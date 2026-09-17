import Foundation
import FirebaseFirestore

enum PlayerCardError: Error, LocalizedError {
    case alreadyGenerated
    case noRetriesLeft
    case generationInProgress
    case missingPhoto
    case missingConsent
    case notWritable

    var errorDescription: String? {
        switch self {
        case .alreadyGenerated:
            "Hai già creato la tua figurina."
        case .noRetriesLeft:
            "Hai già usato tutti e \(PlayerCardJob.maxGenerations) i tentativi."
        case .generationInProgress:
            "La tua figurina è già in lavorazione. Ti avvisiamo appena è pronta."
        case .missingPhoto:
            "Serve una foto per creare la figurina."
        case .missingConsent:
            "Per continuare devi accettare l'invio della foto al servizio di generazione."
        case .notWritable:
            "Non è possibile creare la figurina in questo momento."
        }
    }
}

/// Ponte fra l'app e la coda di generazione delle figurine.
///
/// L'app non sa (e non deve sapere) come l'immagine venga prodotta: scrive un
/// job e osserva `status`. Cambiare motore di generazione non tocca l'app.
final class PlayerCardService {
    private var db: Firestore { Firestore.firestore() }
    private let collection = "playerCardJobs"

    // MARK: - Lettura

    func fetchJob(tournamentId: String, playerId: String) async throws -> PlayerCardJob? {
        let id = PlayerCardJob.documentId(tournamentId: tournamentId, playerId: playerId)
        let snapshot = try await db.collection(collection).document(id).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: PlayerCardJob.self)
    }

    /// Ascolta il job finché non arriva `ready` o `failed`.
    /// Il chiamante tiene la registrazione e la chiude quando lascia la schermata.
    func observeJob(
        tournamentId: String,
        playerId: String,
        onChange: @escaping (PlayerCardJob?) -> Void
    ) -> ListenerRegistration {
        let id = PlayerCardJob.documentId(tournamentId: tournamentId, playerId: playerId)
        return db.collection(collection).document(id).addSnapshotListener { snapshot, _ in
            guard let snapshot, snapshot.exists else {
                onChange(nil)
                return
            }
            onChange(try? snapshot.data(as: PlayerCardJob.self))
        }
    }

    // MARK: - Creazione

    /// Crea il job in modo idempotente.
    ///
    /// La transaction è la barriera vera: se il documento esiste già, la
    /// creazione fallisce qui e non nell'interfaccia. Un doppio tap, un retry di
    /// rete o due dispositivi contemporaneamente non possono produrre due
    /// figurine per lo stesso giocatore. Le regole Firestore rifiutano comunque
    /// una `create` su un documento esistente, quindi il limite regge anche se
    /// qualcuno parlasse col database senza passare dall'app.
    @discardableResult
    func createJob(_ job: PlayerCardJob) async throws -> PlayerCardJob {
        try RuntimeSafety.shared.assertAllowsMutation("creare la figurina del giocatore")
        guard job.aiCardConsent?.accepted == true else { throw PlayerCardError.missingConsent }
        guard !job.playerPhotoURL.isEmpty else { throw PlayerCardError.missingPhoto }

        let ref = db.collection(collection).document(job.jobId)
        var payload = try Firestore.Encoder().encode(job)
        payload["status"] = CardGenerationStatus.pending.rawValue
        payload["attempt"] = 0
        payload["outputImageURL"] = NSNull()
        payload["outputStoragePath"] = NSNull()
        payload["startedAt"] = NSNull()
        payload["completedAt"] = NSNull()
        payload["error"] = NSNull()
        payload["createdAt"] = FieldValue.serverTimestamp()
        payload["generationsUsed"] = 1
        payload["previousImageURL"] = NSNull()

        // La transaction non lancia l'errore tipizzato: attraversando il bridge
        // Objective-C diventerebbe un NSError generico e il chiamante non
        // potrebbe piu' distinguere "gia' pronta" da "in lavorazione".
        // Restituisce lo stato trovato, e l'errore giusto lo si alza qui fuori.
        let outcome = try await db.runTransaction { transaction, errorPointer -> Any? in
            let existing: DocumentSnapshot
            do {
                existing = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }

            guard existing.exists else {
                transaction.setData(payload, forDocument: ref)
                return "created"
            }
            return (existing.data()?["status"] as? String) ?? CardGenerationStatus.pending.rawValue
        }

        if let existingStatus = outcome as? String, existingStatus != "created" {
            switch CardGenerationStatus(rawValue: existingStatus) {
            case .ready: throw PlayerCardError.alreadyGenerated
            case .failed: throw PlayerCardError.notWritable
            default: throw PlayerCardError.generationInProgress
            }
        }

        var created = job
        created.status = .pending
        created.attempt = 0
        return created
    }

    // MARK: - Secondo tentativo

    /// Rimette in coda la figurina con nuova foto e nuove risposte.
    ///
    /// Riprovare dopo un errore non costa un tentativo: quel fallimento non è
    /// stato il giocatore a causarlo. Riprovare dopo una figurina riuscita sì.
    /// La transaction rilegge lo stato: due tap non consumano due tentativi.
    @discardableResult
    func requestRetry(_ job: PlayerCardJob) async throws -> PlayerCardJob {
        try RuntimeSafety.shared.assertAllowsMutation("rigenerare la figurina del giocatore")
        guard job.aiCardConsent?.accepted == true else { throw PlayerCardError.missingConsent }
        guard !job.playerPhotoURL.isEmpty else { throw PlayerCardError.missingPhoto }

        let ref = db.collection(collection).document(job.jobId)

        let outcome = try await db.runTransaction { transaction, errorPointer -> Any? in
            let snap: DocumentSnapshot
            do {
                snap = try transaction.getDocument(ref)
            } catch let error as NSError {
                errorPointer?.pointee = error
                return nil
            }
            guard snap.exists, let data = snap.data() else { return "missing" }

            let status = CardGenerationStatus(rawValue: data["status"] as? String ?? "") ?? .pending
            let used = data["generationsUsed"] as? Int ?? 1
            if status.isInProgress { return "busy" }
            let costs = status == .ready
            if costs && used >= PlayerCardJob.maxGenerations { return "exhausted" }

            var update: [String: Any] = [
                "status": CardGenerationStatus.pending.rawValue,
                "attempt": 0,
                "outputImageURL": NSNull(),
                "outputThumbURL": NSNull(),
                "outputStoragePath": NSNull(),
                "startedAt": NSNull(),
                "completedAt": NSNull(),
                "error": NSNull(),
                "generationsUsed": costs ? used + 1 : used,
                "playerPhotoURL": job.playerPhotoURL,
                "position": job.position.rawValue,
                "overall": job.overall,
                "cardTier": job.cardTier.rawValue,
                "stats": (try? Firestore.Encoder().encode(job.stats)) ?? [:],
                "answers": job.answers ?? [:],
                "retriedAt": FieldValue.serverTimestamp(),
            ]
            // La prima figurina non si butta: resta consultabile.
            if costs, let previous = data["outputImageURL"] as? String {
                update["previousImageURL"] = previous
                update["previousThumbURL"] = data["outputThumbURL"] as? String ?? previous
            }
            transaction.updateData(update, forDocument: ref)
            return "queued"
        }

        switch outcome as? String {
        case "queued": break
        case "exhausted": throw PlayerCardError.noRetriesLeft
        case "busy": throw PlayerCardError.generationInProgress
        default: throw PlayerCardError.notWritable
        }

        var updated = job
        updated.status = .pending
        updated.outputImageURL = nil
        updated.generationsUsed = (job.status == .ready ? job.usedGenerations + 1 : job.usedGenerations)
        return updated
    }
}

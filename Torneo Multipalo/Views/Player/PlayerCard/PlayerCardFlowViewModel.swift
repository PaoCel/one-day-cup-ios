import Foundation
import FirebaseFirestore
import UIKit

/// I passi del flow. `tracking` è l'unico che si può raggiungere anche
/// riaprendo l'app: se esiste già un job, si entra direttamente lì.
enum PlayerCardStep: Equatable {
    case intro
    case photo
    case role
    case quiz(Int)
    case result
    case confirm
    case tracking
}

@Observable
@MainActor
final class PlayerCardFlowViewModel {

    // Dati presi dall'account: non si chiedono al giocatore.
    let player: Player
    let tournamentId: String
    let teamName: String?
    let teamLogoURL: String?
    let tournamentLogoURL: String?

    var step: PlayerCardStep = .intro

    // Foto
    var existingPhotoURL: String?
    var pickedImage: UIImage?
    var isUsingExistingPhoto = true

    // Quiz
    var position: CardPosition?
    /// Per ogni domanda le risposte scelte, **nell'ordine in cui sono state
    /// toccate**: la prima pesa piena, la seconda meno.
    var answers: [String: [String]] = [:]

    // Esito
    var result: PlayerCardScoring.Result?

    // Consensi: entrambi obbligatori prima di poter generare.
    var consentAI = false
    var consentIdentity = false

    // Stato invio
    var isSubmitting = false
    var errorMessage: String?

    // Job
    var job: PlayerCardJob?
    var isLoadingJob = true
    /// Vero quando si sta rifacendo una figurina già esistente: cambia il testo
    /// della conferma e fa aggiornare il job invece di crearne uno nuovo.
    var isRetry = false

    private let service = PlayerCardService()
    private var listener: ListenerRegistration?

    init(
        player: Player,
        tournamentId: String,
        teamName: String?,
        teamLogoURL: String?,
        tournamentLogoURL: String? = nil
    ) {
        self.player = player
        self.tournamentId = tournamentId
        self.teamName = teamName
        self.teamLogoURL = teamLogoURL
        self.tournamentLogoURL = tournamentLogoURL
        // La foto scontornata è quella che rende meglio su una figurina.
        self.existingPhotoURL = player.pictureURLNoBg ?? player.pictureURL
    }

    // Niente `deinit`: il listener e' isolato al main actor e da deinit non si
    // puo' toccare. Lo chiude la view con `stopObserving()` in `onDisappear`,
    // ed e' comunque il ViewModel a spegnerlo appena il job non e' piu' in corso.

    var playerId: String { player.playerId ?? player.id ?? "" }

    var quizIndex: Int {
        if case let .quiz(index) = step { return index }
        return 0
    }

    var canSubmit: Bool { consentAI && consentIdentity && !isSubmitting }

    var hasPhoto: Bool { pickedImage != nil || (existingPhotoURL?.isEmpty == false && isUsingExistingPhoto) }

    /// Progresso mostrato in cima: ruolo + le cinque domande.
    var progress: Double {
        switch step {
        case .intro, .photo: 0
        case .role: 1.0 / Double(PlayerCardQuiz.questions.count + 1)
        case let .quiz(index): Double(index + 2) / Double(PlayerCardQuiz.questions.count + 1)
        case .result, .confirm, .tracking: 1
        }
    }

    // MARK: - Avvio

    /// Se una figurina esiste già (pronta o in lavorazione) il quiz non si apre
    /// nemmeno: si va dritti allo stato. È il limite di una sola generazione
    /// visto dal lato dell'interfaccia; quello vero sta nel database.
    func start() async {
        isLoadingJob = true
        defer { isLoadingJob = false }
        guard !playerId.isEmpty else {
            errorMessage = "Non riesco a identificare il tuo profilo giocatore."
            return
        }
        do {
            if let existing = try await service.fetchJob(tournamentId: tournamentId, playerId: playerId) {
                job = existing
                step = .tracking
                if existing.status.pareInLavorazione { startObserving() }
                return
            }
            step = .intro
        } catch {
            errorMessage = "Non riesco a leggere lo stato della tua figurina. Riprova."
        }
    }

    // MARK: - Navigazione

    func beginFlow() {
        isRetry = false
        step = .photo
    }

    /// Secondo tentativo: si riparte dalla foto tenendo il job esistente.
    /// I consensi si ridanno da capo — è una nuova immagine che parte.
    func beginRetry() {
        guard job?.canRetry == true else { return }
        isRetry = true
        consentAI = false
        consentIdentity = false
        pickedImage = nil
        isUsingExistingPhoto = true
        answers = [:]
        position = nil
        result = nil
        errorMessage = nil
        step = .photo
    }

    /// Quanti tentativi restano dopo quello in corso.
    var retriesLeft: Int {
        guard let job else { return PlayerCardJob.maxGenerations - 1 }
        return max(0, PlayerCardJob.maxGenerations - job.usedGenerations)
    }

    func confirmPhoto() {
        step = .role
    }

    func choose(position: CardPosition) {
        self.position = position
        step = .quiz(0)
    }

    func isSelected(_ option: CardQuizOption, in question: CardQuizQuestion) -> Bool {
        answers[question.id]?.contains(option.id) ?? false
    }

    /// Sulle domande a scelta singola si tocca e si va avanti. Su quelle
    /// multiple si accumula, e a superare il tetto la scelta piu' vecchia
    /// scorre via: meglio che un tap che non fa niente senza spiegare perche'.
    func toggle(_ option: CardQuizOption, in question: CardQuizQuestion) {
        var chosen = answers[question.id] ?? []

        if let existing = chosen.firstIndex(of: option.id) {
            chosen.remove(at: existing)
        } else {
            chosen.append(option.id)
            if chosen.count > question.maxSelections { chosen.removeFirst() }
        }
        answers[question.id] = chosen

        if !question.allowsMultiple, !chosen.isEmpty { advance() }
    }

    func canAdvance(from question: CardQuizQuestion) -> Bool {
        !(answers[question.id] ?? []).isEmpty
    }

    func advance() {
        let next = quizIndex + 1
        if next < PlayerCardQuiz.questions.count {
            step = .quiz(next)
        } else {
            computeResult()
            step = .result
        }
    }

    func back() {
        switch step {
        case .intro, .tracking: break
        case .photo: step = .intro
        case .role: step = .photo
        case let .quiz(index): step = index == 0 ? .role : .quiz(index - 1)
        case .result: step = .quiz(PlayerCardQuiz.questions.count - 1)
        case .confirm: step = .result
        }
    }

    func goToConfirm() { step = .confirm }

    /// "Cambia foto" dalla schermata finale: si torna al passo foto senza
    /// perdere le risposte già date.
    func changePhotoFromConfirm() {
        step = .photo
    }

    func computeResult() {
        guard let position else { return }
        result = PlayerCardScoring.compute(position: position, answers: answers, seedKey: playerId)
    }

    // MARK: - Invio

    func submit(appState: AppState) async {
        guard !isSubmitting else { return }        // doppio tap
        guard let position, let result else { return }
        guard consentAI, consentIdentity else {
            errorMessage = PlayerCardError.missingConsent.errorDescription
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let photoURL = try await resolvePhotoURL(appState: appState)

            let newJob = PlayerCardJob(
                jobId: PlayerCardJob.documentId(tournamentId: tournamentId, playerId: playerId),
                playerId: playerId,
                tournamentId: tournamentId,
                teamId: player.teamId,
                status: .pending,
                playerName: player.nomeCompleto,
                teamName: teamName,
                position: position,
                jerseyNumber: player.numeroMaglia,
                overall: result.overall,
                stats: result.stats,
                cardTier: result.tier,
                answers: answers,
                playerPhotoURL: photoURL,
                teamLogoURL: teamLogoURL,
                tournamentLogoURL: tournamentLogoURL,
                outputImageURL: nil,
                outputStoragePath: nil,
                aiCardConsent: .accepted(),
                attempt: 0
            )

            if isRetry, let existing = job {
                var retry = newJob
                retry.generationsUsed = existing.usedGenerations
                retry.status = existing.status
                job = try await service.requestRetry(retry)
            } else {
                job = try await service.createJob(newJob)
            }
            isRetry = false
            step = .tracking
            startObserving()
        } catch let error as PlayerCardError {
            errorMessage = error.errorDescription
            // Se la figurina esiste già altrove, allineiamo la schermata.
            if case .alreadyGenerated = error { await start() }
        } catch {
            errorMessage = "Non siamo riusciti ad avviare la generazione. Riprova fra poco."
        }
    }

    /// Carica la foto scelta e restituisce l'URL da mandare al generatore.
    /// La foto della figurina è un file a sé: non tocca la foto profilo.
    private func resolvePhotoURL(appState: AppState) async throws -> String {
        if let pickedImage, !isUsingExistingPhoto {
            guard let data = pickedImage.jpegData(compressionQuality: 0.85) else {
                throw PlayerCardError.missingPhoto
            }
            let path = "player-cards/source/\(tournamentId)/\(playerId).jpg"
            let url = try await appState.storageService.uploadImage(data, path: path)
            return url.absoluteString
        }
        guard let existingPhotoURL, !existingPhotoURL.isEmpty else {
            throw PlayerCardError.missingPhoto
        }
        return existingPhotoURL
    }

    // MARK: - Stato

    func startObserving() {
        listener?.remove()
        guard !playerId.isEmpty else { return }
        listener = service.observeJob(tournamentId: tournamentId, playerId: playerId) { [weak self] updated in
            Task { @MainActor in
                guard let self else { return }
                self.job = updated
                // Finito il lavoro non serve più tenere aperto il listener.
                if let updated, !updated.status.isInProgress { self.stopObserving() }
            }
        }
    }

    func stopObserving() {
        listener?.remove()
        listener = nil
    }
}

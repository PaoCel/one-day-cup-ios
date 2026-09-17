import ActivityKit
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit

/// Registra i token ActivityKit del "tabellone live" (fino a 4 partite in
/// griglia sulla lock screen).
///
/// Perché serve un token diverso da quello FCM: una Live Activity NON si può
/// avviare da FCM. Serve una push APNs con `apns-push-type: liveactivity`
/// indirizzata a un token ActivityKit — quello di *push-to-start* per farla
/// comparire, e poi uno per attività per aggiornarla. Il mittente sta in
/// `functions/apns-live-activity.js`.
///
/// Cosa scriviamo in Firestore (`liveActivityTokens/{token}`):
///   { uid, kind: "start" | "update", tournamentId, activityId?, platform,
///     updatedAt }
/// Il server manda lo start ai token `kind == "start"` del torneo, e gli
/// aggiornamenti ai `kind == "update"` finché l'attività è viva.
@MainActor
final class LiveScoreboardService {
    static let shared = LiveScoreboardService()

    private let db = Firestore.firestore()
    private var started = false
    private var currentTournamentId: String?

    private init() {}

    /// Gli stemmi delle squadre di questa edizione, scaricati nel contenitore
    /// condiviso con l'estensione.
    ///
    /// Il widget del tabellone non puo' scaricarseli da solo — una Live Activity
    /// disegna in modo sincrono da uno snapshot, non ha un `AsyncImage` — e nei
    /// 4 KB del payload un'immagine non ci sta. L'unica strada e' che i file
    /// siano gia' sul disco quando il widget si disegna, e a metterceli e' l'app.
    ///
    /// Si fa una volta per edizione e si salta quello che c'e' gia': sono nove
    /// PNG da mezzo schermo, ma su rete di campo anche nove richieste inutili si
    /// sentono. Se una fallisce non importa: al suo posto il widget mette il
    /// monogramma, che e' brutto ma non e' un buco.
    func precaricaStemmi(_ squadre: [(id: String, crest: String?)]) async {
        for s in squadre {
            guard let raw = s.crest, let url = URL(string: raw), !s.id.isEmpty else { continue }
            if let f = SharedLogoStorage.logoURL(filename: "logo_\(s.id).png"),
               FileManager.default.fileExists(atPath: f.path) { continue }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let img = UIImage(data: data) else { continue }
            // Ridotto a 64: nel widget se ne vedono 18 punti, e tenere mezzo mega
            // per stemma nel contenitore condiviso non ha senso.
            //
            // Dentro un quadrato ma **senza deformare**: gli stemmi non sono
            // quadrati (Materos e' largo, King e' alto) e disegnarli a forza in
            // 64×64 li schiaccia. Si scala per il lato lungo e si centra, il
            // resto resta trasparente.
            let lato: CGFloat = 64
            let f = UIGraphicsImageRendererFormat(); f.scale = 2; f.opaque = false
            let scala = min(lato / max(img.size.width, 1), lato / max(img.size.height, 1))
            let dim = CGSize(width: img.size.width * scala, height: img.size.height * scala)
            let origine = CGPoint(x: (lato - dim.width) / 2, y: (lato - dim.height) / 2)
            let piccolo = UIGraphicsImageRenderer(size: CGSize(width: lato, height: lato), format: f).image { _ in
                img.draw(in: CGRect(origin: origine, size: dim))
            }
            if let png = piccolo.pngData() { _ = SharedLogoStorage.saveLogo(data: png, teamId: s.id) }
        }
    }

    /// Da chiamare all'avvio e a ogni cambio torneo.
    func begin(tournamentId: String) {
        currentTournamentId = tournamentId

        guard #available(iOS 17.2, *) else { return }
        // Le build Debug agganciate a Firebase prod non devono scrivere:
        // stessa guardia del resto dell'app.
        guard !RuntimeSafety.shared.protectsRealData else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard !started else {
            Task { await refreshExistingActivities() }
            return
        }
        started = true

        Task { [weak self] in
            for await token in Activity<ScoreboardActivityAttributes>.pushToStartTokenUpdates {
                await self?.save(token: token, kind: "start", activityId: nil)
            }
        }

        Task { [weak self] in
            for await activity in Activity<ScoreboardActivityAttributes>.activityUpdates {
                await self?.observe(activity: activity)
            }
        }

        Task { await refreshExistingActivities() }
    }

    @available(iOS 17.2, *)
    private func refreshExistingActivities() async {
        for activity in Activity<ScoreboardActivityAttributes>.activities {
            await observe(activity: activity)
        }
    }

    @available(iOS 17.2, *)
    private func observe(activity: Activity<ScoreboardActivityAttributes>) async {
        Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                await self?.save(token: token, kind: "update", activityId: activity.id)
            }
        }
        Task { [weak self] in
            for await state in activity.activityStateUpdates {
                if state == .ended || state == .dismissed || state == .stale {
                    await self?.removeTokens(activityId: activity.id)
                }
            }
        }
    }

    // MARK: - Avvio locale (senza server)

    /// Avvia e aggiorna il tabellone **dal telefono**, senza APNs.
    ///
    /// Serve per due motivi: si vede subito (la chiave push del server può
    /// arrivare dopo) e mentre l'app è aperta gli aggiornamenti sono immediati.
    /// Quando l'app va in background senza le push del server l'attività resta
    /// ferma sull'ultimo punteggio: è il limite di ActivityKit, non un bug.
    func syncLocalActivity(tournamentId: String,
                           tournamentName: String,
                           accentHex: String?,
                           edition: Int,
                           matches: [Match]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Se l'admin ha già l'attività della singola partita che sta
        // arbitrando, non gliene impiliamo una seconda sopra — ma il tabellone
        // che c'era va **chiuso**, non lasciato lì.
        //
        // Prima si usciva e basta: dal momento in cui l'admin entrava ad
        // arbitrare, il tabellone restava congelato all'ultimo punteggio visto
        // (in pratica 0-0, perché lo si apre subito dopo il fischio d'inizio) e
        // non si chiudeva nemmeno a partita finita. Sulla schermata di blocco
        // restava un 0-0 fermo su una partita finita 2-2.
        if !Activity<MatchActivityAttributes>.activities.isEmpty {
            if let vecchio = Activity<ScoreboardActivityAttributes>.activities.first {
                Task { await vecchio.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let scoped = matches.filter { $0.edizione == edition }
        // **Solo quelle in campo.** Riempire i buchi con le prossime sembrava
        // utile e sulla lock screen non lo era: uscivano quattro riquadri di cui
        // uno solo vivo, e quattro non entrano nell'altezza che iOS concede —
        // il widget veniva tagliato a meta'. Con due campi in parallelo le
        // partite insieme sono due, e in colonna ci stanno larghe.
        let live = scoped.filter { ($0.started ?? false) && !($0.played ?? false) }
            .sorted { ($0.matchTime ?? "") < ($1.matchTime ?? "") }

        let existing = Activity<ScoreboardActivityAttributes>.activities.first
        if live.isEmpty && existing == nil { return }

        let lines = live.prefix(3).map { match in
            ScoreboardActivityAttributes.MatchLine(
                id: match.id ?? "",
                home: Self.shortName(match.team1Meta.name),
                away: Self.shortName(match.team2Meta.name),
                hi: match.team1,
                ai: match.team2,
                hg: match.team1Goals,
                ag: match.team2Goals,
                minute: nil,
                live: (match.started ?? false) && !(match.played ?? false),
                done: match.played ?? false,
                field: match.campo
            )
        }

        let state = ScoreboardActivityAttributes.ContentState(matches: Array(lines), headline: nil)

        Task {
            if let existing {
                // Niente piu' in campo: l'attivita' ha finito. Prima restava
                // aperta a mostrare le prossime, e restava aperta tutto il giorno.
                if live.isEmpty {
                    await existing.end(.init(state: state, staleDate: nil), dismissalPolicy: .after(.now.addingTimeInterval(900)))
                } else {
                    await existing.update(.init(state: state, staleDate: nil))
                }
                return
            }

            guard !lines.isEmpty else { return }
            let attributes = ScoreboardActivityAttributes(
                tournamentId: tournamentId,
                tournamentName: tournamentName,
                accentHex: accentHex,
                editionLabel: "Edizione \(edition)"
            )
            do {
                // pushType .token: l'attività nasce locale ma chiede comunque
                // il token, così appena il server avrà la chiave APNs potrà
                // aggiornarla anche ad app chiusa.
                _ = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: .token
                )
            } catch {
                print("LiveScoreboardService: avvio locale fallito — \(error.localizedDescription)")
            }
        }
    }

    /// "New Team Since 2017" → "New Team": nella griglia 2×2 ci stanno ~12
    /// caratteri, e tagliare a metà parola si legge peggio.
    private static func shortName(_ name: String, max: Int = 12) -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.count <= max { return clean }
        var out = ""
        for word in clean.split(separator: " ") {
            let candidate = out.isEmpty ? String(word) : out + " " + word
            if candidate.count > max { break }
            out = candidate
        }
        return out.isEmpty ? String(clean.prefix(max)) : out
    }

    private func save(token: Data, kind: String, activityId: String?) async {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        guard !hex.isEmpty else { return }

        var payload: [String: Any] = [
            "uid": Auth.auth().currentUser?.uid ?? "",
            "kind": kind,
            "platform": "ios",
            "token": hex,
            "tournamentId": currentTournamentId ?? "",
            "bundleId": Bundle.main.bundleIdentifier ?? "",
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let activityId { payload["activityId"] = activityId }

        do {
            try await db.collection("liveActivityTokens").document(hex).setData(payload, merge: true)
        } catch {
            print("LiveScoreboardService: registrazione token fallita — \(error.localizedDescription)")
        }
    }

    /// Attività finita o scartata dall'utente: il suo token non vale più e
    /// tenerlo farebbe fallire ogni push successiva (APNs risponde 410).
    private func removeTokens(activityId: String) async {
        do {
            let snap = try await db.collection("liveActivityTokens")
                .whereField("activityId", isEqualTo: activityId)
                .getDocuments()
            for doc in snap.documents {
                try? await doc.reference.delete()
            }
        } catch {
            print("LiveScoreboardService: pulizia token fallita — \(error.localizedDescription)")
        }
    }
}

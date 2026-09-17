import Foundation
import FirebaseFirestore

/// Le partite lette e scritte sulla v2, consegnate all'app nella forma di
/// sempre.
///
/// Sta fra `FirestoreService` e Firestore, e non sale più in alto: le view
/// ricevono `Match` come li hanno sempre ricevuti. Il prezzo della v2 è che le
/// partite non stanno in una collezione piatta ma sotto l'edizione, quindi per
/// avere "tutte le partite di un torneo" bisogna prima sapere quali edizioni
/// esistono. Si paga una lettura in più per edizione e si guadagna che lo
/// storico non cambia quando una squadra cambia logo.
final class V2MatchStore {

    private var db: Firestore { Firestore.firestore() }

    /// Dove sta ogni partita già vista, per quelle il cui id non segue la
    /// convenzione `{edizione}-{n}`. Si riempie leggendo.
    private var percorsi: [String: (tid: String, eid: String)] = [:]

    /// Le iscrizioni per edizione: nome e stemma con cui una squadra ha giocato
    /// quell'edizione. Si rileggono a ogni fetch, non a ogni partita.
    private var entriesCache: [String: [String: V2Entry]] = [:]

    // MARK: - Lettura

    func editionIds(tournamentId: String) async throws -> [String] {
        let snap = try await db.collection("v2_tournaments").document(tournamentId)
            .collection("editions").getDocuments()
        return snap.documents.map(\.documentID)
    }

    func entries(tournamentId: String, editionId: String) async throws -> [String: V2Entry] {
        if let c = entriesCache[editionId] { return c }
        let snap = try await V2Paths.entries(db, tournamentId: tournamentId, editionId: editionId).getDocuments()
        var out: [String: V2Entry] = [:]
        for d in snap.documents {
            if let e = V2Entry(id: d.documentID, data: d.data()) { out[d.documentID] = e }
        }
        entriesCache[editionId] = out
        return out
    }

    /// Tutte le partite di un torneo, tutte le edizioni: il gemello di
    /// `fetchAllMatches`.
    func fetchAllMatches(tournamentId: String) async throws -> [Match] {
        var out: [Match] = []
        for eid in try await editionIds(tournamentId: tournamentId) {
            out.append(contentsOf: try await fetchMatches(tournamentId: tournamentId, editionId: eid))
        }
        return out
    }

    func fetchMatches(tournamentId: String, editionId: String) async throws -> [Match] {
        let iscritte = try await entries(tournamentId: tournamentId, editionId: editionId)
        let snap = try await V2Paths.matches(db, tournamentId: tournamentId, editionId: editionId).getDocuments()
        return snap.documents.compactMap { doc in
            percorsi[doc.documentID] = (tournamentId, editionId)
            return Self.decode(doc.data(), id: doc.documentID,
                               tournamentId: tournamentId, editionId: editionId, entries: iscritte)
        }
    }

    /// Un listener per edizione, uniti in uno solo: chi chiama non deve sapere
    /// che sotto ce ne sono tre.
    func listenToAllMatches(tournamentId: String,
                            onChange: @escaping @Sendable ([Match]) -> Void) async throws -> ListenerRegistration {
        let eids = try await editionIds(tournamentId: tournamentId)
        var perEdizione: [String: [Match]] = [:]
        var registrazioni: [ListenerRegistration] = []

        for eid in eids {
            let iscritte = try await entries(tournamentId: tournamentId, editionId: eid)
            let reg = V2Paths.matches(db, tournamentId: tournamentId, editionId: eid)
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot else { return }
                    perEdizione[eid] = snapshot.documents.compactMap {
                        Self.decode($0.data(), id: $0.documentID,
                                    tournamentId: tournamentId, editionId: eid, entries: iscritte)
                    }
                    onChange(eids.flatMap { perEdizione[$0] ?? [] })
                }
            registrazioni.append(reg)
        }
        return V2CombinedRegistration(registrazioni)
    }

    func listenToMatch(matchId: String,
                       onChange: @escaping @Sendable (Match?) -> Void) -> ListenerRegistration? {
        guard let p = posizione(of: matchId) else { return nil }
        return V2Paths.matches(db, tournamentId: p.tid, editionId: p.eid).document(matchId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot, snapshot.exists, let data = snapshot.data() else { onChange(nil); return }
                let iscritte = self?.entriesCache[p.eid] ?? [:]
                onChange(Self.decode(data, id: matchId, tournamentId: p.tid, editionId: p.eid, entries: iscritte))
            }
    }

    // MARK: - Scrittura

    /// Un evento in coda alla cronaca. L'id lo mette l'app: nella v2 ogni
    /// evento ne ha uno, ed è quello che permette di toglierne uno solo invece
    /// di riscrivere l'array intero.
    func addEvent(matchId: String, event: MatchEvent) async throws {
        let dict = V2Projection.eventToV2(event, id: UUID().uuidString)
        try await ref(matchId).updateData(["events": FieldValue.arrayUnion([dict])])
        try await riallineaPunteggio(matchId)
    }

    func setEvents(matchId: String, eventi: [MatchEvent]) async throws {
        let dicts = eventi.enumerated().map { V2Projection.eventToV2($1, id: "\(matchId)#\(String(format: "%03d", $0))") }
        try await ref(matchId).updateData(["events": dicts])
        try await riallineaPunteggio(matchId)
    }

    /// Fischio d'inizio e fischio finale. Nella v2 non ci sono due booleani ma
    /// uno stato solo, che è anche il motivo per cui non si può avere una
    /// partita "conclusa ma non iniziata".
    func setStarted(matchId: String, started: Bool) async throws {
        var data: [String: Any] = ["status": started ? "live" : "scheduled", "scoreSource": "events"]
        if started {
            data["startedAt"] = FieldValue.serverTimestamp()
            data["pausedAt"] = NSNull()
            data["pausedTotal"] = 0
        }
        try await ref(matchId).updateData(data)
    }

    func setPlayed(matchId: String, played: Bool) async throws {
        try await ref(matchId).updateData(["status": played ? "finished" : "live"])
        try await riallineaPunteggio(matchId)
    }

    func setSchedule(matchId: String, campo: String?, matchTime: String?) async throws {
        var data: [String: Any] = [:]
        if let campo { data["pitch"] = campo }
        if let matchTime, !matchTime.isEmpty { data["kickoffLabel"] = matchTime }
        guard !data.isEmpty else { return }
        try await ref(matchId).updateData(data)
    }

    func setGoalkeeper(matchId: String, side: Int, playerId: String?) async throws {
        let chiave = side == 1 ? "goalkeepers.home" : "goalkeepers.away"
        try await ref(matchId).updateData([chiave: playerId ?? NSNull()])
    }

    func setGoalkeepers(matchId: String, home: String?, away: String?) async throws {
        try await ref(matchId).updateData([
            "goalkeepers.home": home ?? NSNull(), "goalkeepers.away": away ?? NSNull()
        ])
    }

    func setGoalkeeperTimeline(matchId: String, entries: [[String: Any]]) async throws {
        try await ref(matchId).updateData(["goalkeeperTimeline": entries])
    }

    /// Lo spareggio ai tiri, con la sequenza. `winPoints` viaggia sulla partita
    /// e non sul torneo: resta la regola in vigore il giorno in cui si è
    /// giocato.
    func setShootout(matchId: String, home: Int, away: Int,
                     winnerEntryId: String?, winPoints: Int?, lossPoints: Int?,
                     details: [Match.PenaltyKick]) async throws {
        let sequenza = details.map { d -> [String: Any] in
            var k: [String: Any] = ["order": d.order, "entryId": d.teamId, "scored": d.scored]
            k["playerId"] = d.playerId
            k["playerName"] = d.playerName
            k["penaltyMiss"] = d.penaltyMiss?.dictionary
            return k.compactMapValues { $0 }
        }
        // Aggiorniamo i soli campi della sequenza: i punti assegnati allo
        // spareggio appartengono al regolamento della partita e restano intatti.
        var data: [String: Any] = [
            "shootout.home": home, "shootout.away": away,
            "shootout.details": sequenza, "shootout.winnerEntryId": winnerEntryId ?? NSNull()
        ]
        if let winPoints { data["shootout.winPoints"] = winPoints }
        if let lossPoints { data["shootout.lossPoints"] = lossPoints }
        try await ref(matchId).updateData(data)
    }

    // MARK: - Dettagli

    /// Il punteggio dedotto dalla cronaca, tenuto allineato come fa il web
    /// (`riallineaPunteggio` in `store.js`). Senza, il tabellone non avanza:
    /// il trigger che fa passare il vincente legge `scoreFromEvents`.
    private func riallineaPunteggio(_ matchId: String) async throws {
        let r = ref(matchId)
        guard let d = try await r.getDocument().data() else { return }
        let home = d["home"] as? String, away = d["away"] as? String
        var gh = 0, ga = 0
        for e in (d["events"] as? [[String: Any]] ?? []) {
            let t = e["type"] as? String
            let chi = e["entryId"] as? String
            if t == "goal" || t == "pen_scored" {
                if chi == home { gh += 1 } else if chi == away { ga += 1 }
            } else if t == "own_goal" {
                if chi == home { ga += 1 } else if chi == away { gh += 1 }
            }
        }
        let attuale = d["scoreFromEvents"] as? [String: Any]
        if (attuale?["home"] as? Int) != gh || (attuale?["away"] as? Int) != ga {
            try await r.updateData(["scoreFromEvents": ["home": gh, "away": ga]])
        }
    }

    private func posizione(of matchId: String) -> (tid: String, eid: String)? {
        if let p = percorsi[matchId] { return p }
        guard let eid = V2Paths.editionId(fromMatchId: matchId),
              let tid = V2Paths.tournamentId(fromEditionId: eid) else { return nil }
        return (tid, eid)
    }

    private func ref(_ matchId: String) -> DocumentReference {
        guard let p = posizione(of: matchId) else {
            // Non si inventa un percorso: meglio una scrittura che fallisce
            // subito di una che finisce in un documento sbagliato.
            return db.collection("v2_orfane").document(matchId)
        }
        return V2Paths.matches(db, tournamentId: p.tid, editionId: p.eid).document(matchId)
    }

    private static func decode(_ v2: [String: Any], id: String,
                               tournamentId: String, editionId: String,
                               entries: [String: V2Entry]) -> Match? {
        let numero = V2Paths.edizioneNumero(fromEditionId: editionId) ?? 0
        let legacy = V2Projection.matchToLegacy(v2, id: id, tournamentId: tournamentId,
                                                edizione: numero, entries: entries)
        guard let m = try? Firestore.Decoder().decode(Match.self, from: legacy) else { return nil }
        return m.withDocumentID(id)
    }
}

/// Più listener che si spengono insieme. `FirestoreService` ne ha uno uguale
/// ma privato, e duplicarne dieci righe costa meno che aprirlo.
private final class V2CombinedRegistration: NSObject, ListenerRegistration {
    private var registrations: [ListenerRegistration]
    init(_ registrations: [ListenerRegistration]) { self.registrations = registrations }
    func remove() { registrations.forEach { $0.remove() }; registrations.removeAll() }
    deinit { remove() }
}

/// Un listener che arriva dopo.
///
/// Sulla v1 aprire un listener è immediato: c'è una collezione sola e la si
/// ascolta. Sulla v2 bisogna prima sapere quali edizioni esistono, che è una
/// lettura, quindi l'apertura è `async` — ma chi chiama vuole indietro subito
/// qualcosa da poter spegnere. Questo scatola l'attesa: se lo si spegne prima
/// che il listener vero sia pronto, quando arriva viene spento all'istante e
/// non resta appeso.
final class V2DeferredRegistration: NSObject, ListenerRegistration, @unchecked Sendable {
    private let lock = NSLock()
    private var vera: ListenerRegistration?
    private var spento = false

    func adopt(_ reg: ListenerRegistration?) {
        lock.lock(); defer { lock.unlock() }
        if spento { reg?.remove() } else { vera = reg }
    }

    func remove() {
        lock.lock(); defer { lock.unlock() }
        spento = true
        vera?.remove()
        vera = nil
    }

    deinit { remove() }
}

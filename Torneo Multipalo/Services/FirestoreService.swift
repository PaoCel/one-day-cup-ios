import Foundation
import FirebaseFirestore

final class FirestoreListenerToken {
    private var registration: ListenerRegistration?

    func replace(with registration: ListenerRegistration?) {
        self.registration?.remove()
        self.registration = registration
    }

    func cancel() {
        registration?.remove()
        registration = nil
    }

    deinit {
        registration?.remove()
    }
}

private final class CombinedListenerRegistration: NSObject, ListenerRegistration {
    private var registrations: [ListenerRegistration]

    init(_ registrations: [ListenerRegistration]) {
        self.registrations = registrations
    }

    func remove() {
        registrations.forEach { $0.remove() }
        registrations.removeAll()
    }

    deinit {
        remove()
    }
}

@Observable
class FirestoreService {
    struct GroupScheduleAssignment {
        let letter: String
        let teamId: String
        let teamName: String
        let teamLogo: String?
    }

    private var db: Firestore { Firestore.firestore() }

    var currentTournamentId: String = "multipalo"

    /// Da quale versione si legge e si scrive.
    ///
    /// Default `.v1`, e non per prudenza generica: l'app pubblicata deve
    /// continuare a funzionare esattamente come prima finché qualcuno non
    /// decide il contrario. Si gira a runtime, quindi se il giorno del torneo
    /// la v2 facesse una cosa strana si torna indietro senza aspettare Apple.
    var dataSource: ODCDataSource = .v1

    /// Legge l'interruttore da `config/app.dataSource`.
    ///
    /// Si chiama all'avvio, **prima** di caricare qualunque cosa: se cambiasse
    /// sorgente a metà sessione, in memoria resterebbero partite lette da una
    /// parte e squadre dall'altra, che è peggio di tutte e due le versioni.
    ///
    /// Un valore che non si riconosce vale `.v1`: quando l'interruttore non si
    /// capisce si sta dov'era sicuro, non si tira a indovinare. E se la lettura
    /// fallisce (rete assente all'avvio) si resta sul default per lo stesso
    /// motivo — non è il momento di cambiare il pavimento sotto i piedi.
    @discardableResult
    func applyDataSourceFromConfig() async -> ODCDataSource {
        guard let doc = try? await db.collection("config").document("app").getDocument(),
              let data = doc.data() else { return dataSource }
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        dataSource = ODCDataSource.resolve(config: data, build: build)
        return dataSource
    }

    private let v2Matches = V2MatchStore()
    private let v2Entities = V2EntityStore()

    private func tournamentFilter(_ query: Query, tournamentId: String? = nil) -> Query {
        query.whereField("tournamentId", isEqualTo: tournamentId ?? currentTournamentId)
    }

    // MARK: - Matches

    /// Carica partite filtrate per tournament corrente (tutte le edizioni). Il filtro edizione avviene lato client.
    func fetchAllMatches(tournamentId: String? = nil) async throws -> [Match] {
        if dataSource == .v2 {
            return try await v2Matches.fetchAllMatches(tournamentId: tournamentId ?? currentTournamentId)
        }
        return try await tournamentFilter(
            db.collection("partite"),
            tournamentId: tournamentId
        ).getDocumentsAs(Match.self)
    }

    /// Listener real-time su partite del tournament corrente (tutte le edizioni).
    func listenToAllMatches(
        tournamentId: String? = nil,
        onChange: @escaping @Sendable ([Match]) -> Void
    ) -> ListenerRegistration {
        if dataSource == .v2 {
            // Sulla v2 sapere quali edizioni esistono è una lettura, quindi
            // l'apertura è asincrona: si restituisce subito qualcosa da poter
            // spegnere e il listener vero ci entra dentro appena è pronto.
            let differito = V2DeferredRegistration()
            let store = v2Matches
            let tid = tournamentId ?? currentTournamentId
            Task { differito.adopt(try? await store.listenToAllMatches(tournamentId: tid, onChange: onChange)) }
            return differito
        }
        return tournamentFilter(db.collection("partite"), tournamentId: tournamentId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let matches = snapshot.documents.compactMap { try? $0.decodedData(as: Match.self) }
                onChange(matches)
            }
    }

    // MARK: - Ranking generale

    /// Il ranking sta sotto il torneo, non sotto l'edizione: è un coefficiente
    /// che vale su tutte. Se la collezione è vuota la sezione mostra "in
    /// arrivo" — è la condizione normale finché la formula non esiste.
    func fetchRanking(tournamentId: String) async throws -> [RankingEntry] {
        try await db.collection("tournaments")
            .document(tournamentId)
            .collection("ranking")
            .order(by: "position")
            .getDocumentsAs(RankingEntry.self)
    }

    /// Stato e testi del ranking: stanno sul doc del torneo così si possono
    /// cambiare senza pubblicare una versione nuova dell'app.
    func fetchRankingStatus(tournamentId: String) async throws -> RankingStatus? {
        try await db.collection("tournaments")
            .document(tournamentId)
            .getDocumentAs(RankingStatus.self)
    }

    // MARK: - Teams

    func fetchTeams() async throws -> [Team] {
        if dataSource == .v2 { return try await v2Entities.fetchTeams() }
        return try await db.collection("squadre").getDocumentsAs(Team.self)
    }

    func fetchTeam(id: String) async throws -> Team? {
        if dataSource == .v2 { return try await v2Entities.fetchTeam(id: id) }
        return try await db.collection("squadre").document(id).getDocumentAs(Team.self)
    }

    func listenToTeam(teamId: String,
                      onChange: @escaping @Sendable (Team?) -> Void) -> ListenerRegistration {
        if dataSource == .v2 { return v2Entities.listenToTeam(teamId: teamId, onChange: onChange) }
        return db.collection("squadre")
            .document(teamId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                onChange(try? snapshot.decodedData(as: Team.self))
            }
    }

    func updateTeam(_ team: Team) async throws {
        guard let id = team.id else { return }
        try db.collection("squadre").document(id).setData(from: team, merge: true)
    }

    // MARK: - Players

    func fetchPlayers(teamId: String) async throws -> [Player] {
        if dataSource == .v2 { return try await v2Entities.fetchPlayers(teamId: teamId) }
        return try await db.collection("giocatori")
            .whereField("teamId", isEqualTo: teamId)
            .getDocumentsAs(Player.self)
    }

    func fetchPlayer(id: String) async throws -> Player? {
        if dataSource == .v2 { return try await v2Entities.fetchPlayer(id: id) }
        return try await db.collection("giocatori").document(id).getDocumentAs(Player.self)
    }

    func fetchFreeAgents() async throws -> [Player] {
        if dataSource == .v2 { return try await v2Entities.fetchFreeAgents() }
        let players = try await db.collection("giocatori").getDocumentsAs(Player.self)
        return players.filter(\.isFreeAgent)
    }

    // MARK: - Participations

    func fetchAllParticipations(tournamentId: String? = nil) async throws -> [EditionParticipation] {
        if dataSource == .v2 {
            return try await v2Entities.fetchAllParticipations(tournamentId: tournamentId ?? currentTournamentId)
        }
        return try await tournamentFilter(
            db.collection("partecipazioniEdizioni"),
            tournamentId: tournamentId
        ).getDocumentsAs(EditionParticipation.self)
    }

    func fetchParticipations(edizione: Int) async throws -> [EditionParticipation] {
        if dataSource == .v2 {
            return try await v2Entities.fetchParticipations(tournamentId: currentTournamentId, edizione: edizione)
        }
        return try await db.collection("partecipazioniEdizioni")
            .whereField("edizione", isEqualTo: edizione)
            .getDocumentsAs(EditionParticipation.self)
    }

    /// Tutte le partecipazioni di una squadra, SENZA filtro torneo: serve al
    /// selettore stats cross-torneo della scheda squadra (gemello di
    /// loadStatsScopes nella PWA, che interroga per squadraId).
    func fetchParticipations(forTeam teamId: String) async throws -> [EditionParticipation] {
        if dataSource == .v2 {
            // Le iscrizioni della v2 stanno sotto l'edizione, non in una
            // collezione piatta: non si possono interrogare per squadra in una
            // query sola. Si scorrono i tornei e si filtra qui — sono pochi, e
            // questa la chiama solo il selettore stats della scheda squadra.
            let tornei = try await db.collection("v2_tournaments").getDocuments()
            var out: [EditionParticipation] = []
            for t in tornei.documents {
                out.append(contentsOf: try await v2Entities.fetchAllParticipations(tournamentId: t.documentID)
                    .filter { $0.squadraId == teamId })
            }
            return out
        }
        return try await db.collection("partecipazioniEdizioni")
            .whereField("squadraId", isEqualTo: teamId)
            .getDocumentsAs(EditionParticipation.self)
    }

    /// Partite di un torneo esplicito, ignorando il torneo corrente: usato
    /// dalle stats cross-torneo della scheda squadra.
    func fetchMatches(tournamentId: String) async throws -> [Match] {
        if dataSource == .v2 {
            return try await v2Matches.fetchAllMatches(tournamentId: tournamentId)
        }
        return try await db.collection("partite")
            .whereField("tournamentId", isEqualTo: tournamentId)
            .getDocumentsAs(Match.self)
    }

    /// Riassunto rosa di ogni partecipazione, per gli scope stats del profilo
    /// giocatore (gemello della PWA): id+nomi da `giocatoriDettagliati`, con
    /// fallback ai soli nomi delle rose vecchie (`giocatori` /
    /// `legacyRoster.giocatori`). Lettura raw: quei campi legacy non stanno
    /// nel modello EditionParticipation.
    struct ParticipationRoster {
        let tournamentId: String
        let edition: Int
        let teamId: String
        let teamName: String
        let playerIds: Set<String>
        let playerNames: Set<String>   // lowercase, trimmed
        let displayNames: [String]     // come scritti in archivio (per le righe UI)
    }

    func fetchParticipationRosters() async throws -> [ParticipationRoster] {
        let snap = try await db.collection("partecipazioniEdizioni").getDocuments()
        return snap.documents.compactMap { doc in
            let d = doc.data()
            let tidRaw = (d["tournamentId"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
            let tid = tidRaw.isEmpty ? "multipalo" : tidRaw
            guard let ed = (d["edizione"] as? NSNumber)?.intValue else { return nil }
            var ids = Set<String>()
            var names = Set<String>()
            var displayNames: [String] = []
            if let detailed = d["giocatoriDettagliati"] as? [[String: Any]], !detailed.isEmpty {
                for pl in detailed {
                    if let pid = pl["giocatoreId"] as? String, !pid.isEmpty { ids.insert(pid) }
                    if let n = pl["nome"] as? String {
                        names.insert(n.lowercased().trimmingCharacters(in: .whitespaces))
                        displayNames.append(n)
                    }
                }
            } else {
                var raw = d["giocatori"] as? [String]
                if raw == nil, let legacy = d["legacyRoster"] as? [String: Any] {
                    raw = legacy["giocatori"] as? [String]
                }
                for n in raw ?? [] {
                    names.insert(n.lowercased().trimmingCharacters(in: .whitespaces))
                    displayNames.append(n)
                }
            }
            return ParticipationRoster(
                tournamentId: tid,
                edition: ed,
                teamId: (d["squadraId"] as? String) ?? "",
                teamName: (d["nomeSquadra"] as? String) ?? "Squadra",
                playerIds: ids,
                playerNames: names,
                displayNames: displayNames
            )
        }
    }

    // MARK: - Premi d'edizione

    /// Un premio individuale d'edizione, scritto a mano su
    /// `edizioni/{tid}_{ed}.premi`. È l'unico riconoscimento non derivabile:
    /// le partite delle edizioni storiche non hanno eventi mvp e un vincitore
    /// può non avere nemmeno una scheda giocatore (il difensore della Mormon
    /// ed.2 è solo un cognome). Gemello della PWA: `index-tabs.js`
    /// (EDITION_AWARD_TYPES) e `dettagli-giocatore.html` (AWARD_OFFICIAL).
    struct EditionAward {
        let tournamentId: String
        let edition: Int
        let tipo: String            // mvp | capocannoniere | difensore | portiere
        let playerId: String?
        let playerName: String
        let teamName: String
    }

    /// Lettura raw: del doc edizione ci serve solo `premi`, non vale un
    /// modello Codable da tenere allineato al backfill.
    private static func editionAwards(from documentId: String, data: [String: Any]) -> [EditionAward] {
        let tidRaw = (data["tournamentId"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let tid = tidRaw.isEmpty ? String(documentId.prefix(while: { $0 != "_" })) : tidRaw
        guard let ed = (data["numero"] as? NSNumber)?.intValue else { return [] }
        guard let premi = data["premi"] as? [[String: Any]] else { return [] }
        return premi.compactMap { premio in
            guard let tipo = (premio["tipo"] as? String)?.trimmingCharacters(in: .whitespaces),
                  !tipo.isEmpty else { return nil }
            let playerId = (premio["playerId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return EditionAward(
                tournamentId: tid,
                edition: ed,
                tipo: tipo,
                playerId: playerId,
                playerName: (premio["playerName"] as? String) ?? "",
                teamName: (premio["teamName"] as? String) ?? ""
            )
        }
    }

    /// I premi vinti da un giocatore, in qualsiasi torneo: `premiPlayerIds` è
    /// la copia piatta degli id sul doc edizione, quindi basta un
    /// array-contains. Serve perché un premiato può non risultare in nessuna
    /// rosa di quel torneo — delle rose Mormon 1 e 2 non è rimasto niente.
    func fetchEditionAwards(playerId: String) async throws -> [EditionAward] {
        guard !playerId.isEmpty else { return [] }
        let snap = try await db.collection("edizioni")
            .whereField("premiPlayerIds", arrayContains: playerId)
            .getDocuments()
        return snap.documents.flatMap { Self.editionAwards(from: $0.documentID, data: $0.data()) }
    }

    /// I premi di edizioni precise (docId `tid_ed`): dicono se un'edizione ha
    /// un capocannoniere ufficiale anche quando l'ha vinto qualcun altro, così
    /// quello calcolato dai gol non lo contraddice.
    func fetchEditionAwards(editionKeys: [String]) async throws -> [EditionAward] {
        var result: [EditionAward] = []
        for key in Set(editionKeys) where !key.isEmpty {
            guard let snap = try? await db.collection("edizioni").document(key).getDocument(),
                  let data = snap.data() else { continue }
            result.append(contentsOf: Self.editionAwards(from: snap.documentID, data: data))
        }
        return result
    }

    // MARK: - Requests

    func fetchRequests(forTeam teamId: String) async throws -> [TransferRequest] {
        async let canonical = tournamentFilter(db.collection("requests"))
            .whereField("fromTeamId", isEqualTo: teamId)
            .getDocumentsAs(TransferRequest.self)
        async let legacy = fetchLegacyRequestsForTeam(teamId)

        let merged = try await mergeRequests(
            canonical.filter { $0.type == "transfer" || $0.type.isEmpty },
            legacy
        )
        return merged
    }

    func fetchRequests(forPlayerId playerId: String, playerAuthUid: String? = nil) async throws -> [TransferRequest] {
        async let canonicalTarget = tournamentFilter(db.collection("requests"))
            .whereField("toPlayerId", isEqualTo: playerId)
            .getDocumentsAs(TransferRequest.self)
        async let canonicalPlayer = tournamentFilter(db.collection("requests"))
            .whereField("playerId", isEqualTo: playerId)
            .getDocumentsAs(TransferRequest.self)

        let legacy: [TransferRequest]
        if let playerAuthUid, !playerAuthUid.isEmpty {
            legacy = try await fetchLegacyRequestsForPlayer(playerAuthUid: playerAuthUid)
        } else {
            legacy = []
        }

        return try await mergeRequests(canonicalTarget, canonicalPlayer, legacy)
    }

    // MARK: - Config

    /// Finestra iscrizioni + edizione attiva PER-TORNEO, letta da
    /// `config/app.activeTournaments[currentTournamentId]`. Allineata alla PWA
    /// (tm-tournament-state.getActiveEditionInfo). Stato: open/notYet/closed/notConfigured.
    struct RegistrationWindow {
        enum Status { case open, notYet, closed, notConfigured }
        var editionNum: Int?
        var status: Status
        var openFrom: String?   // "YYYY-MM-DD"
        var openTo: String?
        var isOpen: Bool { status == .open }
    }

    func fetchRegistrationWindow(for tournamentId: String? = nil) async throws -> RegistrationWindow {
        let data = (try await db.collection("config").document("app").getDocument()).data() ?? [:]
        let tid = tournamentId ?? currentTournamentId
        let arr = (data["activeTournaments"] as? [[String: Any]]) ?? []
        let entry = arr.first { ($0["tournamentId"] as? String) == tid }

        var editionNum: Int?
        var manualOpen = true
        var openFrom: String?
        var openTo: String?

        if let entry = entry {
            editionNum = entry["activeEditionId"] as? Int
            manualOpen = (entry["teamRegistrationOpen"] as? Bool) ?? true
            openFrom = entry["openFrom"] as? String
            openTo = entry["openTo"] as? String
        } else if tid == "multipalo" {
            editionNum = data["activeEditionId"] as? Int
            manualOpen = (data["teamRegistrationOpen"] as? Bool) ?? true
        } else {
            return RegistrationWindow(editionNum: nil, status: .notConfigured, openFrom: nil, openTo: nil)
        }

        guard let ed = editionNum else {
            return RegistrationWindow(editionNum: nil, status: .notConfigured, openFrom: openFrom, openTo: openTo)
        }
        let status = Self.computeWindowStatus(manualOpen: manualOpen, openFrom: openFrom, openTo: openTo)
        return RegistrationWindow(editionNum: ed, status: status, openFrom: openFrom, openTo: openTo)
    }

    private static func computeWindowStatus(manualOpen: Bool, openFrom: String?, openTo: String?) -> RegistrationWindow.Status {
        if !manualOpen { return .closed }
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone.current
        if let f = openFrom, let fd = df.date(from: f), now < fd { return .notYet }
        if let t = openTo, let td = df.date(from: t) {
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: td) ?? td
            if now >= endOfDay { return .closed }
        }
        return .open
    }

    /// "Concluso": l'edizione attiva ha già partite in `partite`
    /// (query tournamentId+edizione). Allineato alla PWA (editionHasMatches):
    /// distingue "iscrizioni chiuse" (nessuna partita) da "torneo concluso".
    func editionHasMatches(tournamentId: String, edition: Int) async -> Bool {
        do {
            let snap = try await db.collection("partite")
                .whereField("tournamentId", isEqualTo: tournamentId)
                .whereField("edizione", isEqualTo: edition)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            return false
        }
    }

    /// La squadra è già iscritta a QUESTO torneo/edizione? (membership per-torneo,
    /// via partecipazioniEdizioni tournamentId+squadraId+edizione). Usato dal
    /// benvenuto-torneo per decidere se mostrare l'interstitial. Allineato alla
    /// PWA (tm-tournament-membership.getTournamentTeamIds).
    func isTeamRegistered(teamId: String, tournamentId: String, edition: Int) async -> Bool {
        guard !teamId.isEmpty else { return false }
        do {
            let snap = try await db.collection("partecipazioniEdizioni")
                .whereField("tournamentId", isEqualTo: tournamentId)
                .whereField("squadraId", isEqualTo: teamId)
                .whereField("edizione", isEqualTo: edition)
                .limit(to: 1)
                .getDocuments()
            return !snap.documents.isEmpty
        } catch {
            return false
        }
    }

    /// Nome della squadra dal doc GLOBALE `squadre/{id}` (serve al benvenuto
    /// quando la squadra non è tra le `appState.teams` del torneo scelto).
    func fetchTeamName(teamId: String) async -> String? {
        guard !teamId.isEmpty else { return nil }
        do {
            let doc = try await db.collection("squadre").document(teamId).getDocument()
            guard doc.exists, let data = doc.data() else { return nil }
            let name = (data["nomeSquadra"] as? String) ?? (data["name"] as? String)
            let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (trimmed?.isEmpty == false) ? trimmed : nil
        } catch {
            return nil
        }
    }

    func fetchActiveEdition(tournamentId: String? = nil) async throws -> Int {
        // Preferisci l'edizione per-torneo; fallback allo scalare legacy.
        if let ed = try? await fetchRegistrationWindow(for: tournamentId).editionNum { return ed }
        let doc = try await db.collection("config").document("app").getDocument()
        return doc.data()?["activeEditionId"] as? Int ?? 2026
    }

    func fetchManualStandings() async throws -> [String: Any]? {
        let doc = try await db.collection("config").document("manualClassifica").getDocument()
        return doc.data()
    }

    func fetchAwardConfigDocument(edition: Int) async throws -> [String: Any]? {
        let candidateIds = [
            "awardWeights_\(edition)",
            "awards_\(edition)",
            "awardConfig_\(edition)",
            "awardWeights"
        ]

        for candidateId in candidateIds {
            let document = try await db.collection("config").document(candidateId).getDocument()
            if document.exists {
                return document.data()
            }
        }

        return nil
    }

    func fetchAwardConfig(edition: Int) async -> AwardConfig {
        if let document = try? await fetchAwardConfigDocument(edition: edition) {
            return AwardConfig(data: document)
        }
        return AwardConfig()
    }

    func fetchPredictionQuestions(edition: Int) async throws -> [PredictionQuestion] {
        try await db.collection("predictionQuestions")
            .whereField("edition", isEqualTo: edition)
            .getDocumentsAs(PredictionQuestion.self)
    }

    func fetchPredictionEntries(uid: String, edition: Int) async throws -> [PredictionEntry] {
        try await db.collection("predictionEntries")
            .whereField("uid", isEqualTo: uid)
            .whereField("edition", isEqualTo: edition)
            .getDocumentsAs(PredictionEntry.self)
    }

    func listenToManualStandings(
        onChange: @escaping ([String: Any]?) -> Void
    ) -> ListenerRegistration {
        db.collection("config")
            .document("manualClassifica")
            .addSnapshotListener { snapshot, _ in
                onChange(snapshot?.data())
            }
    }

    // MARK: - Real-time listeners (TeamOwner)

    /// Listener real-time sui giocatori di una squadra.
    func listenToPlayers(teamId: String,
                         onChange: @escaping @Sendable ([Player]) -> Void) -> ListenerRegistration {
        if dataSource == .v2 { return v2Entities.listenToPlayers(teamId: teamId, onChange: onChange) }
        return db.collection("giocatori")
            .whereField("teamId", isEqualTo: teamId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let players = snapshot.documents.compactMap { try? $0.decodedData(as: Player.self) }
                onChange(players)
            }
    }

    /// Listener real-time sulle richieste di trasferimento inviate da una squadra.
    func listenToRequests(forTeam teamId: String,
                          onChange: @escaping @Sendable ([TransferRequest]) -> Void) -> ListenerRegistration {
        var canonical: [TransferRequest] = []
        var legacy: [TransferRequest] = []

        let canonicalListener = db.collection("requests")
            .whereField("fromTeamId", isEqualTo: teamId)
            .addSnapshotListener { snapshot, _ in
                canonical = snapshot?.documents.compactMap { try? $0.decodedData(as: TransferRequest.self) } ?? []
                onChange(self.mergeRequestsLocally(canonical.filter { $0.type == "transfer" || $0.type.isEmpty }, legacy))
            }

        let legacyListener = db.collection("playerRequests")
            .whereField("fromTeamId", isEqualTo: teamId)
            .addSnapshotListener { snapshot, error in
                if Self.isPermissionDenied(error) {
                    legacy = []
                    onChange(self.mergeRequestsLocally(canonical.filter { $0.type == "transfer" || $0.type.isEmpty }, legacy))
                    return
                }
                legacy = snapshot?.documents.compactMap { try? $0.decodedData(as: TransferRequest.self) } ?? []
                onChange(self.mergeRequestsLocally(canonical.filter { $0.type == "transfer" || $0.type.isEmpty }, legacy))
            }

        return CombinedListenerRegistration([canonicalListener, legacyListener])
    }

    /// Listener real-time sulle richieste di trasferimento ricevute da un giocatore.
    func listenToRequests(forPlayerId playerId: String,
                          playerAuthUid: String? = nil,
                          onChange: @escaping @Sendable ([TransferRequest]) -> Void) -> ListenerRegistration {
        var canonicalTarget: [TransferRequest] = []
        var canonicalPlayer: [TransferRequest] = []
        var legacy: [TransferRequest] = []

        let listenerTarget = db.collection("requests")
            .whereField("toPlayerId", isEqualTo: playerId)
            .addSnapshotListener { snapshot, _ in
                canonicalTarget = snapshot?.documents.compactMap { try? $0.decodedData(as: TransferRequest.self) } ?? []
                onChange(self.mergeRequestsLocally(canonicalTarget, canonicalPlayer, legacy))
            }

        let listenerPlayer = db.collection("requests")
            .whereField("playerId", isEqualTo: playerId)
            .addSnapshotListener { snapshot, _ in
                canonicalPlayer = snapshot?.documents.compactMap { try? $0.decodedData(as: TransferRequest.self) } ?? []
                onChange(self.mergeRequestsLocally(canonicalTarget, canonicalPlayer, legacy))
            }

        var listeners: [ListenerRegistration] = [listenerTarget, listenerPlayer]

        if let playerAuthUid, !playerAuthUid.isEmpty {
            let legacyListener = db.collection("playerRequests")
                .whereField("toPlayerUid", isEqualTo: playerAuthUid)
                .addSnapshotListener { snapshot, error in
                    if Self.isPermissionDenied(error) {
                        legacy = []
                        onChange(self.mergeRequestsLocally(canonicalTarget, canonicalPlayer, legacy))
                        return
                    }
                    legacy = snapshot?.documents.compactMap { try? $0.decodedData(as: TransferRequest.self) } ?? []
                    onChange(self.mergeRequestsLocally(canonicalTarget, canonicalPlayer, legacy))
                }
            listeners.append(legacyListener)
        }

        return CombinedListenerRegistration(listeners)
    }

    /// Listener real-time su una singola partita (per aggiornamenti live).
    func listenToMatch(matchId: String,
                       onChange: @escaping @Sendable (Match?) -> Void) -> ListenerRegistration {
        if dataSource == .v2, let reg = v2Matches.listenToMatch(matchId: matchId, onChange: onChange) {
            return reg
        }
        return db.collection("partite").document(matchId)
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let match = try? snapshot.decodedData(as: Match.self)
                onChange(match)
            }
    }

    // MARK: - Gestione rosa (TeamOwner)

    /// Aggiunge un giocatore direttamente alla rosa (senza account Auth).
    func addManagedPlayer(nomeCompleto: String, teamId: String,
                          numeroMaglia: Int?, positionPrimary: String?,
                          piedeDominante: String?, pictureURL: String?) async throws -> String {
        try assertWriteAllowed("aggiungere giocatori alla rosa")
        let ref = db.collection("giocatori").document()
        let normalizedPosition = positionPrimary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFoot = piedeDominante?.trimmingCharacters(in: .whitespacesAndNewlines)
        var data: [String: Any] = [
            "playerId": ref.documentID,
            "nomeCompleto": nomeCompleto,
            "teamId": teamId,
            "tesseramentoStatus": "tesserato",
            "playerProfileComplete": true,
            "stats": defaultStatsPayload(),
            "createdAt": FieldValue.serverTimestamp(),
            "lastUpdated": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let n  = numeroMaglia    { data["numeroMaglia"]    = n   }
        if let p = normalizedPosition, !p.isEmpty {
            data["positionPrimary"] = p
            data["position"] = p.lowercased()
        }
        if let pd = normalizedFoot, !pd.isEmpty {
            data["piedeDominante"] = pd
            data["preferredFoot"] = Self.storagePreferredFoot(from: pd)
        }
        if let pic = pictureURL     { data["pictureURL"]      = pic }
        try await ref.setData(data)
        try await syncCurrentEditionParticipationSnapshot(teamId: teamId)
        return ref.documentID
    }

    /// Rimuove un giocatore dalla squadra (diventa free agent).
    func removePlayerFromTeam(playerId: String) async throws {
        try assertWriteAllowed("rimuovere giocatori dalla squadra")
        let currentPlayer = try await fetchPlayer(id: playerId)
        try await db.collection("giocatori").document(playerId).updateData([
            "teamId": FieldValue.delete(),
            "tesseramentoStatus": "libero",
            "updatedAt": FieldValue.serverTimestamp()
        ])
        if let teamId = currentPlayer?.teamId, !teamId.isEmpty {
            try await syncCurrentEditionParticipationSnapshot(teamId: teamId)
        }
    }

    /// Aggiorna il numero di maglia di un giocatore.
    func updatePlayerJerseyNumber(playerId: String, numeroMaglia: Int?) async throws {
        try assertWriteAllowed("aggiornare il numero di maglia del giocatore")
        var data: [String: Any] = [
            "lastUpdated": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let n = numeroMaglia {
            data["numeroMaglia"] = n
        } else {
            data["numeroMaglia"] = FieldValue.delete()
        }
        try await db.collection("giocatori").document(playerId).updateData(data)
    }

    /// Aggiorna l'URL della foto profilo di un giocatore.
    func updatePlayerPicture(playerId: String, pictureURL: String) async throws {
        try assertWriteAllowed("aggiornare la foto profilo del giocatore")
        if dataSource == .v2 { return try await v2Entities.updatePlayerPicture(playerId: playerId, pictureURL: pictureURL) }
        try await db.collection("giocatori").document(playerId).updateData([
            "pictureURL": pictureURL,
            "lastUpdated": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    /// Aggiorna i dati base di un giocatore gestito dal responsabile squadra.
    func updateManagedPlayer(
        playerId: String,
        nomeCompleto: String,
        numeroMaglia: Int?,
        positionPrimary: String?,
        piedeDominante: String?
    ) async throws {
        try assertWriteAllowed("aggiornare i dati del giocatore")

        let normalizedName = nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPosition = positionPrimary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedFoot = piedeDominante?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var data: [String: Any] = [
            "nomeCompleto": normalizedName,
            "lastUpdated": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let numeroMaglia {
            data["numeroMaglia"] = numeroMaglia
        } else {
            data["numeroMaglia"] = FieldValue.delete()
        }

        if normalizedPosition.isEmpty {
            data["positionPrimary"] = FieldValue.delete()
            data["position"] = FieldValue.delete()
        } else {
            data["positionPrimary"] = normalizedPosition
            data["position"] = normalizedPosition.lowercased()
        }

        if normalizedFoot.isEmpty {
            data["piedeDominante"] = FieldValue.delete()
            data["preferredFoot"] = FieldValue.delete()
        } else {
            data["piedeDominante"] = normalizedFoot
            data["preferredFoot"] = Self.storagePreferredFoot(from: normalizedFoot)
        }

        try await db.collection("giocatori").document(playerId).updateData(data)
    }

    /// Capitano o vice. Una carica sola per squadra: darla a uno la toglie a chi
    /// la aveva. Vive in `ruoloSquadra`, da cui lo snapshot dell'edizione deriva
    /// `isCapitano`/`isVice` — lo stesso campo che la PWA scrive dal foglio Rosa
    /// via ponte, così web e iPhone non si sovrascrivono a vicenda. Con `nil` si
    /// toglie solo una carica: un ruolo in campo scritto lì dall'admin resta.
    func assegnaCarica(playerId: String, teamId: String, carica: CaricaSquadra?) async throws {
        try assertWriteAllowed("assegnare capitano e vice")
        let players = try await fetchPlayers(teamId: teamId)
        let batch = db.batch()
        var scritture = 0
        for other in players {
            guard let id = other.id, id != playerId, let carica, other.carica == carica else { continue }
            batch.updateData(["ruoloSquadra": FieldValue.delete(), "updatedAt": FieldValue.serverTimestamp()],
                             forDocument: db.collection("giocatori").document(id))
            scritture += 1
        }
        let mio = players.first { $0.id == playerId }
        if let carica {
            batch.updateData(["ruoloSquadra": carica.rawValue, "updatedAt": FieldValue.serverTimestamp()],
                             forDocument: db.collection("giocatori").document(playerId))
            scritture += 1
        } else if mio?.carica != nil {
            batch.updateData(["ruoloSquadra": FieldValue.delete(), "updatedAt": FieldValue.serverTimestamp()],
                             forDocument: db.collection("giocatori").document(playerId))
            scritture += 1
        }
        guard scritture > 0 else { return }
        try await batch.commit()
        try await syncCurrentEditionParticipationSnapshot(teamId: teamId)
    }

    // MARK: - Gestione squadra (TeamOwner)

    /// Aggiorna i dati principali della squadra (nome, rappresentante, colori).
    func updateTeamDetails(teamId: String, nomeSquadra: String,
                           rappresentanteNome: String, rappresentanteTelefono: String,
                           colorePrincipale: String, coloreSecondario: String) async throws {
        try assertWriteAllowed("aggiornare i dati della squadra")
        if dataSource == .v2 {
            return try await v2Entities.updateTeamDetails(
                teamId: teamId, nomeSquadra: nomeSquadra,
                rappresentanteNome: rappresentanteNome, rappresentanteTelefono: rappresentanteTelefono,
                colorePrincipale: colorePrincipale, coloreSecondario: coloreSecondario)
        }
        try await db.collection("squadre").document(teamId).updateData([
            "nomeSquadra": nomeSquadra,
            "rappresentante.nome": rappresentanteNome,
            "rappresentante.telefono": rappresentanteTelefono,
            "colori.principale": colorePrincipale,
            "colori.secondario": coloreSecondario,
            "lastUpdateAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        try await syncCurrentEditionParticipationSnapshot(teamId: teamId)
    }

    /// Aggiorna il logo della squadra in Firestore.
    func updateTeamLogo(teamId: String, logoURL: String) async throws {
        try assertWriteAllowed("aggiornare il logo della squadra")
        if dataSource == .v2 { return try await v2Entities.updateTeamLogo(teamId: teamId, logoURL: logoURL) }
        try await db.collection("squadre").document(teamId).updateData([
            "logoSquadra": logoURL,
            "logo": logoURL,
            "fotoSquadra": logoURL,
            "lastUpdateAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        try await syncCurrentEditionParticipationSnapshot(teamId: teamId)
    }

    // MARK: - Tutti i giocatori

    func fetchAllPlayers() async throws -> [Player] {
        try await db.collection("giocatori").getDocumentsAs(Player.self)
    }

    func refreshCurrentEditionParticipationSnapshot(teamId: String) async throws {
        try assertWriteAllowed("aggiornare gli snapshot di partecipazione")
        try await syncCurrentEditionParticipationSnapshot(teamId: teamId)
    }

    // MARK: - Admin: Partite

    func updateMatchSchedule(matchId: String, campo: String?, matchTime: String?) async throws {
        try assertWriteAllowed("aggiornare il calendario partite")
        var data: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]
        if let campo { data["campo"] = campo }
        if let matchTime, !matchTime.isEmpty { data["matchTime"] = matchTime }
        try await db.collection("partite").document(matchId).updateData(data)
    }

    func addMatchEvent(matchId: String, event: MatchEvent) async throws {
        try assertWriteAllowed("aggiungere eventi di partita")
        if dataSource == .v2 { return try await v2Matches.addEvent(matchId: matchId, event: event) }
        let eventDict = Self.storageEventDictionary(from: event)
        try await db.collection("partite").document(matchId).updateData([
            "eventi": FieldValue.arrayUnion([eventDict]),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func setEventi(matchId: String, eventi: [MatchEvent]) async throws {
        try assertWriteAllowed("sovrascrivere gli eventi di partita")
        if dataSource == .v2 { return try await v2Matches.setEvents(matchId: matchId, eventi: eventi) }
        let dicts = eventi.map(Self.storageEventDictionary(from:))
        try await db.collection("partite").document(matchId).updateData([
            "eventi": dicts,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func setMatchStarted(_ matchId: String, started: Bool) async throws {
        try assertWriteAllowed("cambiare lo stato avviata della partita")
        if dataSource == .v2 { return try await v2Matches.setStarted(matchId: matchId, started: started) }
        var data: [String: Any] = [
            "started": started,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if started {
            data["startTime"] = FieldValue.serverTimestamp()
        }
        try await db.collection("partite").document(matchId).updateData(data)
    }

    func setMatchPlayed(_ matchId: String, played: Bool) async throws {
        try assertWriteAllowed("cambiare lo stato conclusa della partita")
        if dataSource == .v2 { return try await v2Matches.setPlayed(matchId: matchId, played: played) }
        try await db.collection("partite").document(matchId).updateData([
            "played": played,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Knockout Stage Generation

    func generateKnockoutMatches(
        edition: Int,
        standings: [StandingsEntry],
        format: TournamentEditionFormat,
        existingMatches: [Match]
    ) async throws {
        try assertWriteAllowed("generare le partite della fase a eliminazione")
        if standings.contains(where: { $0.tieBreakExplanation == "draw required" }) {
            throw NSError(
                domain: "FirestoreService",
                code: 1401,
                userInfo: [NSLocalizedDescriptionKey: "Spareggio manuale richiesto prima della fase finale."]
            )
        }

        // Don't create duplicates
        let existingKnockoutIds = Set(
            existingMatches
                .filter { $0.edizione == edition && TournamentPhaseKey.isKnockout($0.fase) }
                .compactMap { $0.idFase }
        )

        let batch = db.batch()
        var createdCount = 0
        let baseGiornata = 10 // knockout matches start at giornata 10+

        for slot in format.knockoutSlots {
            guard !existingKnockoutIds.contains(slot.id) else { continue }

            let homeTeam = resolveKnockoutSource(slot.homeSource, standings: standings, existingMatches: existingMatches, edition: edition)
            let awayTeam = resolveKnockoutSource(slot.awaySource, standings: standings, existingMatches: existingMatches, edition: edition)

            let ref = db.collection("partite").document()
            var matchData: [String: Any] = [
                "edizione": edition,
                "giornata": baseGiornata + slot.matchOrder,
                "fase": slot.phaseKey,
                "idFase": slot.id,
                "started": false,
                "played": false,
                "team1": homeTeam?.teamId ?? "tbd",
                "team2": awayTeam?.teamId ?? "tbd",
                "team1Meta": [
                    "id": homeTeam?.teamId ?? "tbd",
                    "name": homeTeam?.teamName ?? "TBD",
                    "logo": homeTeam?.teamLogo ?? ""
                ] as [String: Any],
                "team2Meta": [
                    "id": awayTeam?.teamId ?? "tbd",
                    "name": awayTeam?.teamName ?? "TBD",
                    "logo": awayTeam?.teamLogo ?? ""
                ] as [String: Any],
                "sortIndex": TournamentPhaseKey.sortRank(slot.phaseKey) * 100 + slot.matchOrder,
                "tournamentId": currentTournamentId,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ]

            batch.setData(matchData, forDocument: ref)
            createdCount += 1
        }

        guard createdCount > 0 else { return }
        try await batch.commit()
    }

    /// Updates knockout matches that have "tbd" teams when a previous round result is known.
    func updateKnockoutAdvancement(
        edition: Int,
        standings: [StandingsEntry],
        format: TournamentEditionFormat,
        allMatches: [Match]
    ) async throws {
        try assertWriteAllowed("aggiornare gli avanzamenti della fase a eliminazione")

        let knockoutMatches = allMatches.filter { $0.edizione == edition && TournamentPhaseKey.isKnockout($0.fase) }

        for slot in format.knockoutSlots {
            guard let match = knockoutMatches.first(where: { $0.idFase == slot.id }),
                  let matchId = match.id else { continue }

            let needsTeam1Update = match.team1.isEmpty || match.team1 == "tbd"
            let needsTeam2Update = match.team2.isEmpty || match.team2 == "tbd"
            guard needsTeam1Update || needsTeam2Update else { continue }

            var updates: [String: Any] = ["updatedAt": FieldValue.serverTimestamp()]

            if needsTeam1Update {
                if let resolved = resolveKnockoutSource(slot.homeSource, standings: standings, existingMatches: allMatches, edition: edition) {
                    updates["team1"] = resolved.teamId
                    updates["team1Meta"] = ["id": resolved.teamId, "name": resolved.teamName, "logo": resolved.teamLogo ?? ""] as [String: Any]
                }
            }

            if needsTeam2Update {
                if let resolved = resolveKnockoutSource(slot.awaySource, standings: standings, existingMatches: allMatches, edition: edition) {
                    updates["team2"] = resolved.teamId
                    updates["team2Meta"] = ["id": resolved.teamId, "name": resolved.teamName, "logo": resolved.teamLogo ?? ""] as [String: Any]
                }
            }

            if updates.count > 1 {
                try await db.collection("partite").document(matchId).updateData(updates)
            }
        }
    }

    private struct ResolvedKnockoutTeam {
        let teamId: String
        let teamName: String
        let teamLogo: String?
    }

    private func resolveKnockoutSource(
        _ source: TournamentEditionFormat.KnockoutParticipantSource,
        standings: [StandingsEntry],
        existingMatches: [Match],
        edition: Int
    ) -> ResolvedKnockoutTeam? {
        switch source {
        case .standing(let position):
            guard position >= 1, position <= standings.count else { return nil }
            let entry = standings[position - 1]
            return ResolvedKnockoutTeam(teamId: entry.teamId, teamName: entry.teamName, teamLogo: entry.teamLogo)

        case .winner(let slotId):
            let match = existingMatches.first { $0.edizione == edition && $0.idFase == slotId && $0.isPlayed }
            guard let match, let winnerId = match.resolvedWinnerTeamId else { return nil }
            let winnerName: String
            let winnerLogo: String?
            if winnerId == match.team1 {
                winnerName = match.team1Meta.name
                winnerLogo = match.team1Meta.logo
            } else {
                winnerName = match.team2Meta.name
                winnerLogo = match.team2Meta.logo
            }
            return ResolvedKnockoutTeam(teamId: winnerId, teamName: winnerName, teamLogo: winnerLogo)

        case .loser(let slotId):
            let match = existingMatches.first { $0.edizione == edition && $0.idFase == slotId && $0.isPlayed }
            guard let match, let winnerId = match.resolvedWinnerTeamId else { return nil }
            let loserId = winnerId == match.team1 ? match.team2 : match.team1
            let loserName: String
            let loserLogo: String?
            if loserId == match.team1 {
                loserName = match.team1Meta.name
                loserLogo = match.team1Meta.logo
            } else {
                loserName = match.team2Meta.name
                loserLogo = match.team2Meta.logo
            }
            return ResolvedKnockoutTeam(teamId: loserId, teamName: loserName, teamLogo: loserLogo)
        }
    }

    // MARK: - Dynamic Scheduling Config

    func fetchDynamicSchedulingEnabled() async throws -> Bool {
        let doc = try await db.collection("config").document("app").getDocument()
        return doc.data()?["dynamicSchedulingEnabled"] as? Bool ?? false
    }

    func setDynamicSchedulingEnabled(_ enabled: Bool) async throws {
        try assertWriteAllowed("aggiornare le impostazioni di scheduling dinamico")
        try await db.collection("config").document("app").setData([
            "dynamicSchedulingEnabled": enabled
        ], merge: true)
    }

    func updateMatchDuration(matchId: String, duration: Int, buffer: Int) async throws {
        try assertWriteAllowed("aggiornare la durata della partita")
        try await db.collection("partite").document(matchId).updateData([
            "matchDuration": duration,
            "bufferMinutes": buffer,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Live Match: Goalkeeper Timeline

    func updateGoalkeeperTimeline(
        matchId: String,
        timeline: [Match.GoalkeeperTimelineEntry]
    ) async throws {
        try assertWriteAllowed("aggiornare la timeline portieri")
        let dicts: [[String: Any]] = timeline.map { entry in
            var dict: [String: Any] = [
                "playerId": entry.playerId,
                "startMinute": entry.startMinute
            ]
            if let name = entry.playerName { dict["playerName"] = name }
            return dict
        }
        if dataSource == .v2 {
            return try await v2Matches.setGoalkeeperTimeline(matchId: matchId, entries: dicts)
        }
        try await db.collection("partite").document(matchId).updateData([
            "goalkeeperTimeline": dicts,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Penalty Shootout

    func savePenaltyDetails(
        matchId: String,
        penalties: [Match.PenaltyKick],
        team1Score: Int,
        team2Score: Int,
        winnerId: String?
    ) async throws {
        try assertWriteAllowed("salvare i rigori")
        if dataSource == .v2 {
            return try await v2Matches.setShootout(
                matchId: matchId, home: team1Score, away: team2Score,
                winnerEntryId: winnerId, winPoints: nil, lossPoints: nil, details: penalties
            )
        }
        let dicts: [[String: Any]] = penalties.map { kick in
            var dict: [String: Any] = [
                "teamId": kick.teamId,
                "scored": kick.scored,
                "order": kick.order
            ]
            if let pid = kick.playerId { dict["playerId"] = pid }
            if let pname = kick.playerName { dict["playerName"] = pname }
            if let miss = kick.penaltyMiss { dict["penaltyMiss"] = miss.dictionary }
            return dict
        }
        var data: [String: Any] = [
            "penaltyShootout": true,
            "penaltyDetails": dicts,
            "penaltyScore": ["team1": team1Score, "team2": team2Score],
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let winnerId {
            data["penaltyWinner"] = winnerId
        }
        try await db.collection("partite").document(matchId).updateData(data)
    }

    func updateMatchGoalkeepers(
        matchId: String,
        team1Goalkeeper: Match.GoalkeeperSelection?,
        team2Goalkeeper: Match.GoalkeeperSelection?
    ) async throws {
        try assertWriteAllowed("aggiornare i portieri di partita")
        if dataSource == .v2 {
            return try await v2Matches.setGoalkeepers(
                matchId: matchId, home: team1Goalkeeper?.playerId, away: team2Goalkeeper?.playerId
            )
        }
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]

        let team1Id = team1Goalkeeper?.playerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let team1Name = team1Goalkeeper?.playerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let team2Id = team2Goalkeeper?.playerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let team2Name = team2Goalkeeper?.playerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        data["team1GoalkeeperPlayerId"] = team1Id.isEmpty ? FieldValue.delete() : team1Id
        data["team1GoalkeeperPlayerName"] = team1Name.isEmpty ? FieldValue.delete() : team1Name
        data["team2GoalkeeperPlayerId"] = team2Id.isEmpty ? FieldValue.delete() : team2Id
        data["team2GoalkeeperPlayerName"] = team2Name.isEmpty ? FieldValue.delete() : team2Name

        try await db.collection("partite").document(matchId).updateData(data)
    }

    func setMatchMvp(matchId: String, mvp: Match.MatchMvp?) async throws {
        try assertWriteAllowed("aggiornare l'MVP della partita")
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let mvp, let dict = Self.storageMvpDictionary(from: mvp) {
            data["mvp"] = dict
        } else {
            data["mvp"] = FieldValue.delete()
        }

        try await db.collection("partite").document(matchId).updateData(data)
    }

    func setMatchBestDefender(matchId: String, bestDefender: Match.MatchMvp?) async throws {
        try assertWriteAllowed("aggiornare il miglior difensore della partita")
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let bestDefender, let dict = Self.storageMvpDictionary(from: bestDefender) {
            data["bestDefender"] = dict
        } else {
            data["bestDefender"] = FieldValue.delete()
        }

        try await db.collection("partite").document(matchId).updateData(data)
    }

    func setMatchGoalkeeper(matchId: String, slot: Int, playerId: String?) async throws {
        try assertWriteAllowed("aggiornare il portiere assegnato alla partita")
        let fieldName: String
        switch slot {
        case 1:
            fieldName = "team1GoalkeeperPlayerId"
        case 2:
            fieldName = "team2GoalkeeperPlayerId"
        default:
            throw NSError(
                domain: "FirestoreService",
                code: 1301,
                userInfo: [NSLocalizedDescriptionKey: "Slot portiere non valido."]
            )
        }

        if dataSource == .v2 {
            let normalized = playerId?.trimmingCharacters(in: .whitespacesAndNewlines)
            return try await v2Matches.setGoalkeeper(
                matchId: matchId, side: slot, playerId: normalized?.isEmpty == false ? normalized : nil
            )
        }

        let normalizedPlayerId = playerId?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let normalizedPlayerId, !normalizedPlayerId.isEmpty {
            data[fieldName] = normalizedPlayerId
        } else {
            data[fieldName] = FieldValue.delete()
        }

        try await db.collection("partite").document(matchId).updateData(data)
    }

    func clearGroupStageSchedule(edition: Int) async throws {
        try assertWriteAllowed("cancellare il calendario dei gironi")
        let snapshot = try await tournamentFilter(db.collection("partite"))
            .whereField("edizione", isEqualTo: edition)
            .getDocuments()

        let groupStageDocuments = snapshot.documents.filter(Self.isGroupStageMatchDocument(_:))
        guard !groupStageDocuments.isEmpty else { return }

        let batch = db.batch()
        groupStageDocuments.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    func replaceGroupStageSchedule(
        edition: Int,
        assignments: [GroupScheduleAssignment]
    ) async throws {
        try assertWriteAllowed("pubblicare il calendario dei gironi")
        let normalizedAssignments = try normalizedGroupScheduleAssignments(assignments)
        let assignmentByLetter = Dictionary(
            uniqueKeysWithValues: normalizedAssignments.map { ($0.letter, $0) }
        )

        let snapshot = try await tournamentFilter(db.collection("partite"))
            .whereField("edizione", isEqualTo: edition)
            .getDocuments()

        let batch = db.batch()
        snapshot.documents
            .filter(Self.isGroupStageMatchDocument(_:))
            .forEach { batch.deleteDocument($0.reference) }

        for match in GroupScheduleTemplate.scheduledMatches {
            guard let team1 = assignmentByLetter[match.homeLetter],
                  let team2 = assignmentByLetter[match.awayLetter] else {
                throw scheduleError("Manca l'associazione tra lettere e squadre.")
            }

            let ref = db.collection("partite").document()
            let team1Meta = Self.groupScheduleTeamMeta(
                teamId: team1.teamId,
                teamName: team1.teamName,
                teamLogo: team1.teamLogo
            )
            let team2Meta = Self.groupScheduleTeamMeta(
                teamId: team2.teamId,
                teamName: team2.teamName,
                teamLogo: team2.teamLogo
            )
            batch.setData([
                "edizione": edition,
                "giornata": match.giornata,
                "matchTime": match.timeLabel,
                "campo": match.fieldNumber,
                "fase": "girone",
                "idFase": "girone",
                "started": false,
                "played": false,
                "team1": team1.teamId,
                "team2": team2.teamId,
                "team1Meta": team1Meta,
                "team2Meta": team2Meta,
                "scheduleTemplate": "group_stage_fixed_ag",
                "sortIndex": match.sortIndex,
                "tournamentId": currentTournamentId,
                "createdAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp()
            ], forDocument: ref)
        }

        try await batch.commit()
    }

    // MARK: - Registrazione

    /// Crea una nuova squadra in Firestore e restituisce il documento ID.
    func createTeam(nomeSquadra: String, email: String, ownerUid: String,
                    rappresentanteNome: String, rappresentanteTelefono: String,
                    colorePrincipale: String, coloreSecondario: String,
                    edizione: Int) async throws -> String {
        try assertWriteAllowed("creare squadre")
        let ref = db.collection("squadre").document()
        try await ref.setData([
            "nomeSquadra": nomeSquadra,
            "email": email,
            "ownerUid": ownerUid,
            "ownerStatus": "assigned",
            "_needsOwnerAssignment": false,
            "ownerAssignedAt": FieldValue.serverTimestamp(),
            "accettazioneRegolamento": true,
            "rappresentante": [
                "nome": rappresentanteNome,
                "telefono": rappresentanteTelefono
            ],
            "colori": [
                "principale": colorePrincipale,
                "secondario": coloreSecondario
            ],
            "playersCount": 0,
            "ultimeEdizioni": [edizione],
            "primaEdizione": edizione,
            "dataCreazione": FieldValue.serverTimestamp(),
            "dataIscrizione": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp(),
            "lastUpdateAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
        return ref.documentID
    }

    // MARK: - Multi-tournament docId helpers
    // ⚠️ DEVONO combaciare con la PWA (dbSchema.js IDS.* / functions/index.js):
    // il torneo di default "multipalo" mantiene gli id NON prefissati
    // (retro-compat con tutti i documenti storici); ogni altro torneo è
    // namespaced per tournamentId, così team ed edizione non collidono mai
    // fra tornei diversi.
    private func participationDocId(_ teamId: String, _ edizione: Int) -> String {
        currentTournamentId == "multipalo"
            ? "\(teamId)_\(edizione)"
            : "\(currentTournamentId)_\(teamId)_\(edizione)"
    }

    private func registrationDocId(_ edizione: Int) -> String {
        currentTournamentId == "multipalo"
            ? "\(edizione)"
            : "\(currentTournamentId)_\(edizione)"
    }

    /// Crea il documento di partecipazione all'edizione per una squadra.
    func createEditionParticipation(squadraId: String, nomeSquadra: String,
                                    edizione: Int) async throws {
        try assertWriteAllowed("creare partecipazioni di edizione")
        let ref = db.collection("partecipazioniEdizioni").document(participationDocId(squadraId, edizione))
        try await ref.setData([
            "squadraId": squadraId,
            "nomeSquadra": nomeSquadra,
            "edizione": edizione,
            "playersCount": 0,
            "tournamentId": currentTournamentId,
            "dataIscrizione": FieldValue.serverTimestamp()
        ], merge: true)
        try? await syncEditionParticipationSnapshot(teamId: squadraId, edizione: edizione)
    }

    func registerTeamToEdition(squadraId: String, nomeSquadra: String, edizione: Int) async throws {
        try assertWriteAllowed("registrare squadre all'edizione")
        let teamRef = db.collection("squadre").document(squadraId)
        let registrationRef = teamRef.collection("registrations").document(registrationDocId(edizione))

        let batch = db.batch()
        batch.updateData([
            "ultimeEdizioni": FieldValue.arrayUnion([edizione]),
            "lastUpdateAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: teamRef)
        batch.setData([
            "edition": edizione,
            "editionId": String(edizione),
            "squadraId": squadraId,
            "nomeSquadra": nomeSquadra,
            "status": "registered",
            // Multi-tournament: la cloud function onRegistrationWriteV2 legge
            // questo campo come sorgente di verità del torneo (prima mancava).
            "tournamentId": currentTournamentId,
            "updatedAt": FieldValue.serverTimestamp(),
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: registrationRef, merge: true)
        batch.setData([
            "squadraId": squadraId,
            "nomeSquadra": nomeSquadra,
            "edizione": edizione,
            "tournamentId": currentTournamentId,
            "dataIscrizione": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: db.collection("partecipazioniEdizioni").document(participationDocId(squadraId, edizione)), merge: true)
        try await batch.commit()
        try? await syncEditionParticipationSnapshot(teamId: squadraId, edizione: edizione)
    }

    func claimExistingTeam(
        uid: String,
        teamId: String,
        email: String,
        rappresentanteNome: String,
        rappresentanteTelefono: String
    ) async throws {
        try assertWriteAllowed("collegare una squadra esistente a un account")
        let teamRef = db.collection("squadre").document(teamId)
        let teamSnapshot = try await teamRef.getDocument()

        guard teamSnapshot.exists else {
            throw NSError(
                domain: "FirestoreService",
                code: 1101,
                userInfo: [NSLocalizedDescriptionKey: "Squadra non trovata."]
            )
        }

        let currentData = teamSnapshot.data() ?? [:]
        let currentOwnerUid = (currentData["ownerUid"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let currentOwnerUid, !currentOwnerUid.isEmpty, currentOwnerUid != uid {
            throw NSError(
                domain: "FirestoreService",
                code: 1102,
                userInfo: [NSLocalizedDescriptionKey: "Questa squadra risulta gia collegata a un altro account."]
            )
        }

        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        try await teamRef.setData([
            "ownerUid": uid,
            "ownerStatus": "assigned",
            "_needsOwnerAssignment": false,
            "ownerAssignedAt": FieldValue.serverTimestamp(),
            "email": normalizedEmail,
            "rappresentante": [
                "nome": rappresentanteNome.trimmingCharacters(in: .whitespacesAndNewlines),
                "telefono": rappresentanteTelefono.trimmingCharacters(in: .whitespacesAndNewlines)
            ],
            "lastUpdateAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        if let activeEdition = try? await fetchActiveEdition(),
           let team = try? await fetchTeam(id: teamId),
           team.hasEdition(activeEdition) {
            try? await syncEditionParticipationSnapshot(teamId: teamId, edizione: activeEdition)
        }
    }

    /// Crea un nuovo giocatore in Firestore e restituisce il documento ID.
    func createPlayer(nomeCompleto: String, playerAuthUid: String,
                      email: String?, numeroMaglia: Int?, positionPrimary: String?,
                      piedeDominante: String?) async throws -> String {
        try assertWriteAllowed("creare profili giocatore")
        let ref = db.collection("giocatori").document()
        let normalizedPosition = positionPrimary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedFoot = piedeDominante?.trimmingCharacters(in: .whitespacesAndNewlines)
        var data: [String: Any] = [
            "playerId": ref.documentID,
            "userId": playerAuthUid,
            "nomeCompleto": nomeCompleto,
            "claimedBy": playerAuthUid,
            "playerAuthUid": playerAuthUid,
            "tesseramentoStatus": "libero",
            "playerProfileComplete": true,
            "stats": defaultStatsPayload(),
            "createdAt": FieldValue.serverTimestamp(),
            "lastUpdated": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let email, !email.isEmpty { data["email"] = email }
        if let numero = numeroMaglia { data["numeroMaglia"] = numero }
        if let pos = normalizedPosition, !pos.isEmpty {
            data["positionPrimary"] = pos
            data["position"] = pos.lowercased()
        }
        if let piede = normalizedFoot, !piede.isEmpty {
            data["piedeDominante"] = piede
            data["preferredFoot"] = Self.storagePreferredFoot(from: piede)
        }
        try await ref.setData(data)
        return ref.documentID
    }

    func createPlayerClaim(uid: String, playerId: String) async throws {
        try assertWriteAllowed("creare claim giocatore")
        try await db.collection("playerClaims").document(uid).setData([
            "playerId": playerId,
            "createdAt": FieldValue.serverTimestamp(),
            "source": "ios"
        ], merge: true)
    }

    func claimExistingPlayer(uid: String, playerId: String) async throws {
        try assertWriteAllowed("collegare un profilo giocatore esistente")
        let claimRef = db.collection("playerClaims").document(uid)
        let playerRef = db.collection("giocatori").document(playerId)

        let existingClaim = try await claimRef.getDocument()
        if existingClaim.exists {
            throw NSError(
                domain: "FirestoreService",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Questo account e gia collegato a un profilo giocatore."]
            )
        }

        let playerSnap = try await playerRef.getDocument()
        guard playerSnap.exists else {
            throw NSError(
                domain: "FirestoreService",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Profilo giocatore non trovato."]
            )
        }

        let data = playerSnap.data() ?? [:]
        let linkedUid = [data["claimedBy"], data["userId"], data["playerAuthUid"]]
            .compactMap { $0 as? String }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if let linkedUid, linkedUid != uid {
            throw NSError(
                domain: "FirestoreService",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Questo profilo e gia collegato a un altro account."]
            )
        }

        let batch = db.batch()
        batch.setData([
            "playerId": playerId,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "source": "ios"
        ], forDocument: claimRef, merge: true)
        batch.updateData([
            "claimedBy": uid,
            "updatedAt": FieldValue.serverTimestamp()
        ], forDocument: playerRef)
        try await batch.commit()
    }

    private func defaultStatsPayload() -> [String: Int] {
        [
            "goals": 0,
            "assists": 0,
            "yellowCards": 0,
            "redCards": 0,
            "matches": 0
        ]
    }

    private func syncCurrentEditionParticipationSnapshot(teamId: String) async throws {
        guard let team = try await fetchTeam(id: teamId) else { return }
        let activeEdition = try await fetchActiveEdition()
        let participationRef = db.collection("partecipazioniEdizioni").document(participationDocId(teamId, activeEdition))
        let hasActiveParticipation = try await participationRef.getDocument().exists
        guard team.hasEdition(activeEdition) || hasActiveParticipation else { return }
        try await upsertEditionParticipationSnapshot(team: team, edizione: activeEdition)
    }

    private func syncEditionParticipationSnapshot(teamId: String, edizione: Int) async throws {
        guard let team = try await fetchTeam(id: teamId) else { return }
        try await upsertEditionParticipationSnapshot(team: team, edizione: edizione)
    }

    private func upsertEditionParticipationSnapshot(team: Team, edizione: Int) async throws {
        guard let teamId = team.id else { return }
        let players = try await fetchPlayers(teamId: teamId)
        let sortedPlayers = players.sorted {
            if ($0.numeroMaglia ?? Int.max) != ($1.numeroMaglia ?? Int.max) {
                return ($0.numeroMaglia ?? Int.max) < ($1.numeroMaglia ?? Int.max)
            }
            return $0.nomeCompleto.localizedCaseInsensitiveCompare($1.nomeCompleto) == .orderedAscending
        }

        let playerSnapshots = sortedPlayers.map { player in
            makePlayerSnapshotDictionary(from: player)
        }
        let legacyPlayerNames = sortedPlayers.map(\.nomeCompleto)
        let legacyPlayerPhotos: [Any] = sortedPlayers.map { player in
            if let pictureURL = normalizedSnapshotString(player.pictureURL) {
                return pictureURL
            }
            return NSNull()
        }
        let legacyPlayerNumbers: [Any] = sortedPlayers.map { player in
            if let numeroMaglia = player.numeroMaglia {
                return String(numeroMaglia)
            }
            return NSNull()
        }
        let legacyCaptainFlags = sortedPlayers.map { player in
            player.carica == .capitano
        }
        let legacyPlayerRoles: [Any] = sortedPlayers.map { player in
            if let role = normalizedSnapshotString(player.positionPrimary)
                ?? (player.carica == nil ? normalizedSnapshotString(player.ruoloSquadra) : nil) {
                return role
            }
            return NSNull()
        }

        var snapshot: [String: Any] = [
            "squadraId": teamId,
            "nomeSquadra": team.nomeSquadra,
            "edizione": edizione,
            "email": team.email,
            "ownerUid": team.ownerUid,
            "rappresentante": [
                "nome": team.rappresentante.nome,
                "telefono": team.rappresentante.telefono
            ],
            "colori": [
                "principale": team.colori.principale,
                "secondario": team.colori.secondario
            ],
            "playersCount": sortedPlayers.count,
            "giocatoriDettagliati": playerSnapshots,
            "giocatori": legacyPlayerNames,
            "fotoGiocatori": legacyPlayerPhotos,
            "numeriMaglia": legacyPlayerNumbers,
            "capitani": legacyCaptainFlags,
            "ruoli": legacyPlayerRoles,
            "tournamentId": currentTournamentId,
            "snapshotSource": "ios",
            "snapshotUpdatedAt": FieldValue.serverTimestamp(),
            "snapshotUpdatedISO": ISO8601DateFormatter().string(from: Date()),
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let logoSquadra = team.logoSquadra, !logoSquadra.isEmpty {
            snapshot["logoSquadra"] = logoSquadra
        }

        try await db.collection("partecipazioniEdizioni").document(participationDocId(teamId, edizione)).setData(snapshot, merge: true)
    }

    private func makePlayerSnapshotDictionary(from player: Player) -> [String: Any] {
        var snapshot: [String: Any] = [
            "nome": player.nomeCompleto,
            "nomeCompleto": player.nomeCompleto
        ]
        if let playerId = player.id, !playerId.isEmpty { snapshot["giocatoreId"] = playerId }
        if let numero = player.numeroMaglia {
            snapshot["numero"] = numero
            snapshot["numeroMaglia"] = String(numero)
        }
        // In `ruoloSquadra` una carica non è un ruolo in campo: nello snapshot va
        // nei flag, non in `ruolo` (la v2 lo leggerebbe come posizione).
        if let ruolo = normalizedSnapshotString(player.positionPrimary)
            ?? (player.carica == nil ? normalizedSnapshotString(player.ruoloSquadra) : nil) {
            snapshot["ruolo"] = ruolo
        }
        if let pictureURL = normalizedSnapshotString(player.pictureURL) {
            snapshot["pictureURL"] = pictureURL
            snapshot["fotoUrl"] = pictureURL
        }
        snapshot["isCapitano"] = player.carica == .capitano
        if player.carica == .vice { snapshot["isVice"] = true }
        return snapshot
    }

    private func normalizedSnapshotString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func mergeRequests(_ groups: [TransferRequest]...) async throws -> [TransferRequest] {
        mergeRequestsLocally(groups.flatMap { $0 })
    }

    private func fetchLegacyRequestsForTeam(_ teamId: String) async throws -> [TransferRequest] {
        do {
            return try await db.collection("playerRequests")
                .whereField("fromTeamId", isEqualTo: teamId)
                .getDocumentsAs(TransferRequest.self)
        } catch {
            if Self.isPermissionDenied(error) {
                return []
            }
            throw error
        }
    }

    private func fetchLegacyRequestsForPlayer(playerAuthUid: String) async throws -> [TransferRequest] {
        do {
            return try await db.collection("playerRequests")
                .whereField("toPlayerUid", isEqualTo: playerAuthUid)
                .getDocumentsAs(TransferRequest.self)
        } catch {
            if Self.isPermissionDenied(error) {
                return []
            }
            throw error
        }
    }

    private func mergeRequestsLocally(_ groups: [TransferRequest]...) -> [TransferRequest] {
        var mergedById: [String: TransferRequest] = [:]
        var anonymous: [TransferRequest] = []

        for request in groups.flatMap({ $0 }) {
            if let id = request.id, !id.isEmpty {
                mergedById[id] = request
            } else {
                anonymous.append(request)
            }
        }

        return (Array(mergedById.values) + anonymous).sorted {
                ($0.createdAt?.dateValue() ?? .distantPast) >
                ($1.createdAt?.dateValue() ?? .distantPast)
            }
    }

    private static func storageEventDictionary(from event: MatchEvent) -> [String: Any] {
        var dict: [String: Any] = ["type": storageEventType(from: event.tipo)]
        if let value = event.giocatoreId, !value.isEmpty { dict["playerId"] = value }
        if let value = event.giocatoreNome, !value.isEmpty { dict["playerName"] = value }
        if let value = event.squadraId, !value.isEmpty { dict["teamId"] = value }
        if let value = event.minuto { dict["minute"] = value }
        if let value = event.assistName, !value.isEmpty { dict["assist"] = value }
        if let value = event.playerOutName, !value.isEmpty { dict["playerOut"] = value }
        if let value = event.doubleYellow { dict["doubleYellow"] = value }
        if let miss = event.penaltyMiss { dict["penaltyMiss"] = miss.dictionary }
        if let value = event.votes { dict["votes"] = value }
        if let value = event.mvpPhoto, !value.isEmpty { dict["mvpPhoto"] = value }
        return dict
    }

    private static func storageMvpDictionary(from mvp: Match.MatchMvp) -> [String: Any]? {
        let playerId = mvp.playerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let playerName = mvp.playerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !playerId.isEmpty || !playerName.isEmpty else {
            return nil
        }

        var dict: [String: Any] = [:]
        if !playerId.isEmpty { dict["playerId"] = playerId }
        if !playerName.isEmpty { dict["playerName"] = playerName }
        if let team = mvp.team { dict["team"] = team }
        if let url = mvp.mvpPhotoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            dict["mvpPhotoURL"] = url
        }
        return dict
    }

    func updateMatchMvpPhoto(matchId: String, photoURL: String?) async throws {
        try assertWriteAllowed("aggiornare la foto MVP")
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let url = photoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            data["mvp.mvpPhotoURL"] = url
        } else {
            data["mvp.mvpPhotoURL"] = FieldValue.delete()
        }
        try await db.collection("partite").document(matchId).updateData(data)
    }

    func updateMatchBestDefenderPhoto(matchId: String, photoURL: String?) async throws {
        try assertWriteAllowed("aggiornare la foto del miglior difensore")
        var data: [String: Any] = [
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let url = photoURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            data["bestDefender.mvpPhotoURL"] = url
        } else {
            data["bestDefender.mvpPhotoURL"] = FieldValue.delete()
        }
        try await db.collection("partite").document(matchId).updateData(data)
    }

    private static func storageEventType(from appValue: String) -> String {
        switch appValue.lowercased() {
        case "gol":
            return "goal"
        case "autogol":
            return "autogol"
        case "ammonizione":
            return "yellow"
        case "espulsione":
            return "red"
        case "rigore_segnato":
            return "penalty"
        case "punizione_segnata":
            return "freekick"
        case "rigore_sbagliato":
            return "penalty_missed"
        case "sostituzione":
            return "substitution"
        case "assist":
            return "assist"
        default:
            return appValue.lowercased()
        }
    }

    private static func storagePreferredFoot(from appValue: String) -> String {
        switch appValue.lowercased() {
        case "destro", "right":
            return "right"
        case "sinistro", "left":
            return "left"
        case "ambidestro", "both":
            return "both"
        default:
            return appValue.lowercased()
        }
    }

    private func normalizedGroupScheduleAssignments(
        _ assignments: [GroupScheduleAssignment]
    ) throws -> [GroupScheduleAssignment] {
        guard assignments.count == GroupScheduleTemplate.letters.count else {
            throw scheduleError(
                "Servono esattamente \(GroupScheduleTemplate.letters.count) squadre associate alle lettere A-G."
            )
        }

        var normalized: [GroupScheduleAssignment] = []
        var seenLetters = Set<String>()
        var seenTeamIds = Set<String>()

        for assignment in assignments {
            let letter = assignment.letter.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let teamId = assignment.teamId.trimmingCharacters(in: .whitespacesAndNewlines)
            let teamName = assignment.teamName.trimmingCharacters(in: .whitespacesAndNewlines)

            guard GroupScheduleTemplate.letters.contains(letter) else {
                throw scheduleError("Le lettere disponibili vanno da A a G.")
            }
            guard !teamId.isEmpty else {
                throw scheduleError("Una delle squadre selezionate non ha un ID valido.")
            }
            guard !teamName.isEmpty else {
                throw scheduleError("Una delle squadre selezionate non ha un nome valido.")
            }
            guard seenLetters.insert(letter).inserted else {
                throw scheduleError("Ogni lettera puo essere usata una sola volta.")
            }
            guard seenTeamIds.insert(teamId).inserted else {
                throw scheduleError("Ogni squadra puo comparire una sola volta.")
            }

            normalized.append(
                GroupScheduleAssignment(
                    letter: letter,
                    teamId: teamId,
                    teamName: teamName,
                    teamLogo: assignment.teamLogo
                )
            )
        }

        return normalized
    }

    private static func isGroupStageMatchDocument(_ document: QueryDocumentSnapshot) -> Bool {
        let data = document.data()
        let fase = (data["fase"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let idFase = (data["idFase"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return fase == "girone" || idFase == "girone"
    }

    private static func groupScheduleTeamMeta(
        teamId: String,
        teamName: String,
        teamLogo: String?
    ) -> [String: Any] {
        var meta: [String: Any] = [
            "id": teamId,
            "name": teamName
        ]
        if let teamLogo, !teamLogo.isEmpty {
            meta["logo"] = teamLogo
        }
        return meta
    }

    private func scheduleError(_ message: String, code: Int = 2000) -> NSError {
        NSError(
            domain: "FirestoreService.Schedule",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    private static func isPermissionDenied(_ error: Error?) -> Bool {
        guard let nsError = error as NSError? else { return false }
        return nsError.domain == FirestoreErrorDomain
            && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    private func assertWriteAllowed(_ operation: String) throws {
        try RuntimeSafety.shared.assertAllowsMutation(operation)
    }
}

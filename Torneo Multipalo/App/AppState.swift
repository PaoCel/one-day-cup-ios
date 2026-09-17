import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Intent di iscrizione impostato dal benvenuto-torneo e consumato dal tab
/// Profilo (MainTabView): apre la registrazione giusta una volta entrati in app.
enum RegistrationIntent: String, Identifiable, Equatable {
    case existingTeam   // "Iscrivi {la mia squadra}" (scelta=esistente)
    case newTeam        // "Crea una squadra nuova" (scelta=nuova)
    case playerRegister // "Partecipa come giocatore"
    var id: String { rawValue }
}

@Observable
@MainActor
class AppState {
    private enum BootstrapTimeoutError: LocalizedError {
        case timedOut(seconds: TimeInterval)

        var errorDescription: String? {
            switch self {
            case let .timedOut(seconds):
                return "Operazione iniziale scaduta dopo \(String(format: "%.1f", seconds)) secondi."
            }
        }
    }

    struct ResolvedTeamInfo {
        var id: String?
        var name: String
        var logo: String?
        var isTbd: Bool
    }

    var activeEdition: Int = 2026
    var selectedEdition: Int = 2026
    let authService = AuthService()
    let firestoreService = FirestoreService()
    let storageService = StorageService()
    let cloudFunctionsService = CloudFunctionsService()
    let notificationService = NotificationService()
    let runtimeSafety = RuntimeSafety.shared

    /// Phase 3c — store del torneo correntemente selezionato dall'utente.
    /// Sorgente di verità per `currentTournamentId`. AppState e FirestoreService
    /// si sincronizzano da qui sia all'init che ogni volta che la store cambia.
    let tournamentSelectionStore = TournamentSelectionStore()

    /// Cache dei giocatori per l'album delle figurine, condivisa fra striscia
    /// in home, album e schede: si carica alla prima occasione e non si
    /// invalida al cambio torneo (la mappa `figurine` è per-torneo sul
    /// documento globale del giocatore).
    let figurineStore = FigurineStore()

    /// Tutte le partite caricate (tutte le edizioni).
    var allMatches: [Match] = []
    var teams: [Team] = []
    var allParticipations: [EditionParticipation] = []
    var standings: [StandingsEntry] = []
    var isLoadingMatches = false
    var isLoadingTeams = false
    var isSwitchingTournament = false
    var dynamicSchedulingEnabled = false

    /// Mirror di `tournamentSelectionStore.currentTournamentId` per compat con
    /// codice esistente che leggeva `appState.currentTournamentId`.
    /// Aggiornato automaticamente all'init e all'evento `.tournamentChanged`.
    var currentTournamentId: String = "multipalo"

    /// Nome leggibile del torneo corrente. La lista arriva dallo store quando
    /// c'e'; finche' non c'e' si mostra l'id, che e' comunque parlante
    /// ("mormon", "multipalo") ed e' meglio di uno spazio vuoto.
    var currentTournamentName: String {
        tournamentSelectionStore.availableTournaments
            .first { $0.id == currentTournamentId }?
            .displayName
            .nonEmpty
            ?? currentTournamentId.capitalized
    }

    /// Branding derivato dal torneo corrente (colore primario + URL logo).
    /// Le View possono leggerlo per applicare overrides minimi.
    /// Nil quando il doc non è ancora caricato (mostra default app).
    var currentBranding: TournamentBranding = .none

    /// Impostato dal benvenuto-torneo quando l'utente sceglie come partecipare;
    /// il tab Profilo (MainTabView) lo consuma per aprire la registrazione.
    var pendingRegistrationIntent: RegistrationIntent?

    private var tournamentChangeObserver: NSObjectProtocol?
    private var tournamentChangeTask: Task<Void, Never>?
    private var tournamentChangeGeneration = 0

    private var manualStandingsOverride: [String: Any]?
    private let matchesListener = FirestoreListenerToken()
    private let manualStandingsListener = FirestoreListenerToken()

    /// Partite filtrate per l'edizione selezionata.
    var matches: [Match] {
        allMatches.filter { $0.edizione == selectedEdition }
    }

    /// Edizioni disponibili, ordinate decrescente.
    var availableEditions: [Int] {
        var editions = Set(allMatches.map(\.edizione))
        editions.formUnion(allParticipations.map(\.edizione))
        editions.insert(activeEdition)
        return editions.sorted(by: >)
    }

    var editionParticipations: [EditionParticipation] {
        deduplicatedParticipations(for: selectedEdition)
    }

    var editionTeams: [EditionTeam] {
        editionTeams(for: selectedEdition)
    }

    func editionTeams(for edition: Int) -> [EditionTeam] {
        let participations = deduplicatedParticipations(for: edition)
        let participationByTeamId: [String: EditionParticipation] = participations.reduce(into: [:]) { result, participation in
            guard !participation.squadraId.isEmpty else { return }
            result[participation.squadraId] = participation
        }
        let teamById: [String: Team] = teams.reduce(into: [:]) { result, team in
            guard let id = team.id else { return }
            result[id] = team
        }

        // ⚠️ `tbd` non e' una squadra. Gli slot di tabellone ancora vuoti sono
        // scritti `team1: "tbd"` con l'etichetta dentro ("Vincente semifinale
        // 1"), e raccogliendoli qui comparivano nell'elenco Squadre come una
        // squadra senza nome — quella che il fallback chiama "Squadra".
        let matchTeamIds = Set(
            allMatches
                .filter { $0.edizione == edition }
                .flatMap { [$0.team1, $0.team2] }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "tbd" }
        )
        let participationTeamIds = Set(participations.map(\.squadraId).filter { !$0.isEmpty })
        // `squadre` è globale: `ultimeEdizioni` è un campo legacy Multipalo e
        // non dimostra l'iscrizione a Mormon o ad altri tornei. Fuori da
        // Multipalo contano solo partecipazioni e partite scoped.
        let teamDocumentIds: Set<String> = currentTournamentId == "multipalo"
            ? Set(teams.compactMap { team -> String? in
                guard let id = team.id, team.hasEdition(edition) else { return nil }
                return id
            })
            : []

        let allTeamIds = participationTeamIds.union(matchTeamIds).union(teamDocumentIds)

        // Edizioni per squadra prese da fonti già filtrate per torneo:
        // `allParticipations` passa da fetchAllParticipations(tournamentId:) e
        // `allMatches` da fetchAllMatches(tournamentId:). Il campo
        // `ultimeEdizioni` sul doc squadra invece è globale e sommava le
        // edizioni degli altri tornei.
        var editionsByTeam: [String: Set<Int>] = [:]
        for participation in allParticipations where !participation.squadraId.isEmpty {
            editionsByTeam[participation.squadraId, default: []].insert(participation.edizione)
        }
        for match in allMatches {
            for teamId in [match.team1, match.team2].map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            where !teamId.isEmpty && teamId.lowercased() != "tbd" {
                editionsByTeam[teamId, default: []].insert(match.edizione)
            }
        }

        return allTeamIds
            .map { teamId in
                EditionTeam(
                    edition: edition,
                    team: teamById[teamId],
                    participation: participationByTeamId[teamId],
                    fallbackParticipation: latestHistoricalParticipation(for: teamId, before: edition),
                    preferLiveTeamData: edition == activeEdition,
                    tournamentEditions: (editionsByTeam[teamId] ?? []).sorted()
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    init() {
        // Phase 3c — sincronizza subito da TournamentSelectionStore così che
        // tutte le query Firestore vedano il tid corretto fin dal primo fetch.
        self.currentTournamentId = tournamentSelectionStore.currentTournamentId
        self.firestoreService.currentTournamentId = tournamentSelectionStore.currentTournamentId
        self.cloudFunctionsService.currentTournamentId = tournamentSelectionStore.currentTournamentId
        self.currentBranding = tournamentSelectionStore.currentBranding
        installTournamentChangeObserver()
    }

    // Nota: AppState vive per tutta la durata dell'app, l'observer viene
    // automaticamente liberato a process exit. Niente deinit esplicito qui
    // per evitare attriti con l'isolation `@MainActor` (Swift 6).

    func loadInitialData() async {
        authService.listenToAuthState()
        let firestoreService = self.firestoreService

        // Da quale versione si legge, PRIMA di leggere qualunque cosa: se
        // cambiasse a metà avvio resterebbero in memoria partite prese da una
        // parte e squadre dall'altra. Se il documento non c'è o non risponde
        // resta `.v1`, che è dove l'app pubblicata ha sempre vissuto.
        await firestoreService.applyDataSourceFromConfig()

        // Phase 3c — carica tornei in parallelo all'edition: ci serve per
        // (a) sapere il branding del torneo corrente,
        // (b) eventuale auto-selezione se utente è admin di un solo torneo.
        async let loadedTournaments: [Tournament] = tournamentSelectionStore.loadAvailableTournaments()

        do {
            activeEdition = try await runBootstrapTask(timeout: 4) {
                try await firestoreService.fetchActiveEdition()
            }
            selectedEdition = activeEdition
        } catch {
            activeEdition = 2026
            selectedEdition = 2026
            print("Bootstrap edition fallback: \(error.localizedDescription)")
        }

        // Aspetta che i tornei siano caricati per aggiornare il branding.
        _ = await loadedTournaments
        if let uid = authService.currentUser?.uid {
            tournamentSelectionStore.autoSelectIfSingleAdminTournament(userUid: uid)
        }
        currentTournamentId = tournamentSelectionStore.currentTournamentId
        firestoreService.currentTournamentId = tournamentSelectionStore.currentTournamentId
        cloudFunctionsService.currentTournamentId = tournamentSelectionStore.currentTournamentId
        currentBranding = tournamentSelectionStore.currentBranding

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadMatches() }
            group.addTask { await self.loadTeams() }
            group.addTask { await self.loadDynamicSchedulingFlag() }
        }
    }

    /// Phase 3c — reagisce ai cambi di torneo: aggiorna i mirror locali e ricarica
    /// matches + teams. Le partite/squadre del torneo precedente vengono scartate.
    private func installTournamentChangeObserver() {
        let observer = NotificationCenter.default.addObserver(
            forName: .tournamentChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Estrazione `tid` non richiede MainActor (solo lettura cast).
            let payloadTid = notification.object as? String
            Task { @MainActor [weak self] in
                guard let self else { return }
                let newTid = payloadTid ?? self.tournamentSelectionStore.currentTournamentId
                self.beginTournamentChange(to: newTid)
            }
        }
        tournamentChangeObserver = observer
    }

    /// Il cambio torneo è una transazione UI: azzera subito TUTTO lo stato
    /// scoped (compresa l'edizione), carica usando un tournamentId immutabile e
    /// pubblica i risultati solo se nel frattempo non è partita un'altra scelta.
    private func beginTournamentChange(to tournamentId: String) {
        tournamentChangeGeneration += 1
        let generation = tournamentChangeGeneration
        let fallbackEdition = tournamentId == "multipalo" ? 2026 : 1

        tournamentChangeTask?.cancel()
        stopListening()

        currentTournamentId = tournamentId
        firestoreService.currentTournamentId = tournamentId
        cloudFunctionsService.currentTournamentId = tournamentId
        currentBranding = tournamentSelectionStore.currentBranding

        allMatches = []
        teams = []
        allParticipations = []
        standings = []
        manualStandingsOverride = nil
        activeEdition = fallbackEdition
        selectedEdition = fallbackEdition
        isLoadingMatches = true
        isLoadingTeams = true
        isSwitchingTournament = true

        tournamentChangeTask = Task { @MainActor [weak self] in
            await self?.reloadTournamentData(
                tournamentId: tournamentId,
                generation: generation
            )
        }
    }

    private func reloadTournamentData(tournamentId: String, generation: Int) async {
        let fallbackEdition = tournamentId == "multipalo" ? 2026 : 1

        async let editionTask: Int = {
            (try? await firestoreService.fetchActiveEdition(tournamentId: tournamentId))
                ?? fallbackEdition
        }()
        async let matchesTask = firestoreService.fetchAllMatches(tournamentId: tournamentId)
        async let teamsTask = firestoreService.fetchTeams()
        async let participationsTask = firestoreService.fetchAllParticipations(tournamentId: tournamentId)
        async let manualStandingsTask: [String: Any]? = tournamentId == "multipalo"
            ? try? firestoreService.fetchManualStandings()
            : nil

        do {
            let edition = await editionTask
            let matches = try await matchesTask
            let loadedTeams = try await teamsTask
            let participations = try await participationsTask
            let manualStandings = await manualStandingsTask

            guard !Task.isCancelled,
                  generation == tournamentChangeGeneration,
                  tournamentId == currentTournamentId else {
                return
            }

            activeEdition = edition
            selectedEdition = edition
            allMatches = matches
            teams = loadedTeams
            allParticipations = participations
            manualStandingsOverride = manualStandings
            recalculateStandings()

            // Gli stemmi nel contenitore condiviso, per il tabellone sulla
            // schermata di blocco: il widget non puo' scaricarli da se'. Si fa
            // qui perche' e' il momento in cui si sa chi gioca; in sottofondo,
            // che nessuna schermata aspetta nove PNG.
            let squadrePerStemma = participations
                .filter { $0.edizione == edition }
                .map { (id: $0.squadraId, crest: $0.logoSquadra) }
            Task { await LiveScoreboardService.shared.precaricaStemmi(squadrePerStemma) }
            startListeningToMatches(
                tournamentId: tournamentId,
                generation: generation
            )
        } catch is CancellationError {
            return
        } catch {
            guard generation == tournamentChangeGeneration else { return }
            print("Errore cambio torneo \(tournamentId): \(error.localizedDescription)")
        }

        guard generation == tournamentChangeGeneration else { return }
        isLoadingMatches = false
        isLoadingTeams = false
        isSwitchingTournament = false
    }

    func loadMatches() async {
        isLoadingMatches = true
        defer { isLoadingMatches = false }
        let firestoreService = self.firestoreService
        let requestedTournamentId = currentTournamentId

        do {
            let loadedMatches = try await runBootstrapTask(timeout: 6) {
                try await firestoreService.fetchAllMatches(tournamentId: requestedTournamentId)
            }
            let loadedManualStandings: [String: Any]? = requestedTournamentId == "multipalo"
                ? try? await runBootstrapTask(timeout: 4) {
                    try await firestoreService.fetchManualStandings()
                }
                : nil
            guard requestedTournamentId == currentTournamentId else { return }
            allMatches = loadedMatches
            manualStandingsOverride = loadedManualStandings
            recalculateStandings()
        } catch {
            print("Errore caricamento partite: \(error)")
        }
    }

    func loadTeams() async {
        isLoadingTeams = true
        defer { isLoadingTeams = false }
        let firestoreService = self.firestoreService
        let requestedTournamentId = currentTournamentId

        do {
            async let teamsTask: [Team] = runBootstrapTask(timeout: 6) {
                try await firestoreService.fetchTeams()
            }
            async let participationsTask: [EditionParticipation] = runBootstrapTask(timeout: 6) {
                try await firestoreService.fetchAllParticipations(tournamentId: requestedTournamentId)
            }
            let loadedTeams = try await teamsTask
            let loadedParticipations = try await participationsTask
            guard requestedTournamentId == currentTournamentId else { return }
            teams = loadedTeams
            allParticipations = loadedParticipations
            recalculateStandings()
        } catch {
            print("Errore caricamento squadre: \(error)")
        }
    }

    func startListeningToMatches(
        tournamentId: String? = nil,
        generation: Int? = nil
    ) {
        let listenerTournamentId = tournamentId ?? currentTournamentId
        matchesListener.replace(with: firestoreService.listenToAllMatches(
            tournamentId: listenerTournamentId
        ) { [weak self] matches in
            Task { @MainActor [weak self, matches] in
                guard let self else { return }
                guard self.currentTournamentId == listenerTournamentId else { return }
                if let generation, generation != self.tournamentChangeGeneration { return }
                self.allMatches = matches
                self.recalculateStandings()
                // Tabellone live: parte e si aggiorna dal telefono appena una
                // partita va in campo. Il server, quando avrà la chiave APNs,
                // aggiornerà la stessa attività anche ad app chiusa.
                let branding = self.tournamentSelectionStore.availableTournaments
                    .first { $0.id == listenerTournamentId }
                LiveScoreboardService.shared.syncLocalActivity(
                    tournamentId: listenerTournamentId,
                    tournamentName: branding?.displayName ?? listenerTournamentId,
                    accentHex: branding?.primaryColor,
                    edition: self.activeEdition,
                    matches: matches
                )
            }
        })

        if listenerTournamentId == "multipalo" {
            manualStandingsListener.replace(with: firestoreService.listenToManualStandings { [weak self] overrides in
                Task { @MainActor [weak self, overrides] in
                    guard let self else { return }
                    guard self.currentTournamentId == listenerTournamentId else { return }
                    if let generation, generation != self.tournamentChangeGeneration { return }
                    self.manualStandingsOverride = overrides
                    self.recalculateStandings()
                }
            })
        } else {
            manualStandingsListener.cancel()
        }
    }

    func stopListening() {
        matchesListener.cancel()
        manualStandingsListener.cancel()
    }

    func loadDynamicSchedulingFlag() async {
        if let doc = try? await firestoreService.fetchDynamicSchedulingEnabled() {
            dynamicSchedulingEnabled = doc
        }
    }

    /// Cambia edizione selezionata e ricalcola classifica.
    func switchEdition(to edition: Int) {
        selectedEdition = edition
        recalculateStandings()
    }

    private func runBootstrapTask<T>(
        timeout: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw BootstrapTimeoutError.timedOut(seconds: timeout)
            }

            guard let result = try await group.next() else {
                throw BootstrapTimeoutError.timedOut(seconds: timeout)
            }

            group.cancelAll()
            return result
        }
    }

    func editionTeam(for teamId: String, edition: Int? = nil) -> EditionTeam? {
        let targetEdition = edition ?? selectedEdition

        if targetEdition == selectedEdition {
            return editionTeams.first { $0.teamId == teamId }
        }

        let participation = bestParticipation(for: teamId, edition: targetEdition)
        let team = teams.first { $0.id == teamId }
        if team == nil && participation == nil {
            return nil
        }
        return EditionTeam(
            edition: targetEdition,
            team: team,
            participation: participation,
            fallbackParticipation: latestHistoricalParticipation(for: teamId, before: targetEdition),
            preferLiveTeamData: targetEdition == activeEdition
        )
    }

    func editions(forTeamId teamId: String) -> [Int] {
        guard !teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var editions = Set(
            allParticipations
                .filter { $0.squadraId == teamId }
                .map(\.edizione)
        )

        editions.formUnion(
            allMatches
                .filter { $0.team1 == teamId || $0.team2 == teamId }
                .map(\.edizione)
        )

        if let team = teams.first(where: { $0.id == teamId }) {
            if let primaEdizione = team.primaEdizione {
                editions.insert(primaEdizione)
            }
            editions.formUnion(team.ultimeEdizioni ?? [])
            if team.hasEdition(activeEdition) {
                editions.insert(activeEdition)
            }
        }

        return editions.sorted(by: >)
    }

    func resolvedTeamInfo(teamId: String?, meta: Match.TeamMeta? = nil, edition: Int? = nil) -> ResolvedTeamInfo {
        let normalizedId = teamId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let metaName = meaningfulTeamName(meta?.name)
        let metaLogo = meaningfulString(meta?.logo)

        if normalizedId.lowercased() == "tbd" {
            return ResolvedTeamInfo(id: nil, name: "TBD", logo: nil, isTbd: true)
        }

        if !normalizedId.isEmpty,
           let editionTeam = editionTeam(for: normalizedId, edition: edition) {
            return ResolvedTeamInfo(
                id: normalizedId,
                name: editionTeam.displayName,
                logo: meaningfulString(editionTeam.logoURL) ?? metaLogo,
                isTbd: false
            )
        }

        if !normalizedId.isEmpty,
           let team = teams.first(where: { $0.id == normalizedId }) {
            return ResolvedTeamInfo(
                id: normalizedId,
                name: meaningfulTeamName(team.nomeSquadra) ?? metaName ?? "Squadra",
                logo: meaningfulString(team.logoSquadra) ?? metaLogo,
                isTbd: false
            )
        }

        if let metaName {
            return ResolvedTeamInfo(
                id: normalizedId.isEmpty ? nil : normalizedId,
                name: metaName,
                logo: metaLogo,
                isTbd: metaName.uppercased() == "TBD"
            )
        }

        return ResolvedTeamInfo(
            id: normalizedId.isEmpty ? nil : normalizedId,
            name: normalizedId.isEmpty ? "TBD" : "Squadra",
            logo: nil,
            isTbd: normalizedId.isEmpty
        )
    }

    /// Doc del torneo corrente, quando la lista è già stata caricata. Nil da
    /// guest o prima del primo load: chi lo legge deve reggere il fallback.
    var currentTournament: Tournament? {
        tournamentSelectionStore.availableTournaments.first { $0.id == currentTournamentId }
    }

    /// Come si chiama il tie-break di questa partita ("rigori" o "shootout").
    /// Le view chiedono qui invece di sapere in che torneo si trovano.
    func shootoutTerminology(for match: Match) -> ShootoutTerminology {
        ShootoutTerminology.resolve(
            tournament: currentTournament,
            tournamentId: currentTournamentId,
            fase: match.fase
        )
    }

    func resolvedTeams(for match: Match) -> (team1: ResolvedTeamInfo, team2: ResolvedTeamInfo) {
        (
            resolvedTeamInfo(teamId: match.team1, meta: match.team1Meta, edition: match.edizione),
            resolvedTeamInfo(teamId: match.team2, meta: match.team2Meta, edition: match.edizione)
        )
    }

    /// Returns estimated delay (new start, delay minutes) if the match will start late vs schedule.
    /// Cascades delay from previous match on same campo. Uses real wall-clock time.
    func scheduleDelayInfo(for match: Match) -> (newStart: String, delayMinutes: Int)? {
        guard dynamicSchedulingEnabled else { return nil }
        guard let campo = match.campo, !campo.isEmpty else { return nil }
        guard let scheduledMinutes = match.scheduledStartMinutesFromMidnight else { return nil }
        if match.isStarted || match.isPlayed { return nil }

        let sameCampoMatches = matches
            .filter { $0.campo == campo && $0.id != match.id }
            .sorted { ($0.scheduledStartMinutesFromMidnight ?? 0) < ($1.scheduledStartMinutesFromMidnight ?? 0) }

        let previousMatch = sameCampoMatches.last {
            ($0.scheduledStartMinutesFromMidnight ?? 0) < scheduledMinutes
        }

        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)

        var projectedEndMinutes: Int? = nil

        if let previousMatch {
            if previousMatch.isLive, let prevStart = previousMatch.startTime {
                let prevStartComp = calendar.dateComponents([.hour, .minute], from: prevStart.dateValue())
                let prevStartMins = (prevStartComp.hour ?? 0) * 60 + (prevStartComp.minute ?? 0)
                let projected = prevStartMins + previousMatch.effectiveDuration
                projectedEndMinutes = max(projected, nowMinutes)
            } else if previousMatch.isPlayed, let endDate = previousMatch.actualEndDate {
                let endComp = calendar.dateComponents([.hour, .minute], from: endDate)
                projectedEndMinutes = (endComp.hour ?? 0) * 60 + (endComp.minute ?? 0)
            } else if !previousMatch.isStarted,
                      nowMinutes > (previousMatch.scheduledStartMinutesFromMidnight ?? 0) {
                projectedEndMinutes = nowMinutes + previousMatch.effectiveDuration
            }
        }

        let candidateNewStart: Int
        if let projectedEndMinutes {
            candidateNewStart = projectedEndMinutes + match.effectiveBuffer
        } else if nowMinutes > scheduledMinutes {
            candidateNewStart = nowMinutes
        } else {
            return nil
        }

        let delay = candidateNewStart - scheduledMinutes
        guard delay > 0 else { return nil }

        let newStart = String(format: "%02d:%02d", candidateNewStart / 60, candidateNewStart % 60)
        return (newStart, delay)
    }

    /// Backward-compat wrapper: returns just the new start string.
    func estimatedStartTime(for match: Match) -> String? {
        scheduleDelayInfo(for: match)?.newStart
    }

    /// Minutes of delay for a match (positive) or nil if on schedule.
    func delayMinutes(for match: Match) -> Int? {
        scheduleDelayInfo(for: match)?.delayMinutes
    }

    private func recalculateStandings() {
        standings = standings(for: selectedEdition)
    }

    func standings(for edition: Int) -> [StandingsEntry] {
        standings(for: edition, girone: nil)
    }

    /// La classifica dell'edizione, o quella di **un solo girone**.
    ///
    /// Con `girone` valorizzato entrano solo le partite di quel girone e solo le
    /// squadre che ci giocano. Serve dove la classifica generale non vuol dire
    /// niente: dentro una partita dei gironi, la tabella giusta è quella del suo
    /// girone, non le nove squadre di tutti e tre — che oltretutto non ci
    /// stanno in larghezza e uscivano coi nomi tagliati.
    ///
    /// ⚠️ Passa sempre da qui: `StandingsView` si calcolava i gironi per conto
    /// suo con `StandingsCalculator.calculate(from:)` **senza regole**, quindi
    /// con 3/1/0 al posto dei punti dell'edizione — e con lo shootout della
    /// Mormon (2/1) le due tabelle non potevano che divergere.
    func standings(for edition: Int, girone: String?) -> [StandingsEntry] {
        let format = TournamentEditionFormat.format(
            for: edition,
            tournamentId: currentTournamentId,
            teamCount: editionTeams(for: edition).count
        )

        let partiteEdizione = allMatches.filter { $0.edizione == edition }
        let chiave = girone?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let partite = chiave.map { g in
            partiteEdizione.filter {
                ($0.group?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "") == g
            }
        } ?? partiteEdizione

        // In un girone la rosa non è quella dell'edizione: sono le squadre che
        // ci giocano dentro, prese dal calendario.
        let squadreDelGirone: Set<String>? = chiave == nil ? nil : Set(
            partite.flatMap { [$0.team1, $0.team2] }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.lowercased() != "tbd" }
        )

        let seededEntries: [StandingsEntry] = editionTeams(for: edition).compactMap { team in
            guard !team.teamId.isEmpty else { return nil }
            if let squadreDelGirone, !squadreDelGirone.contains(team.teamId) { return nil }
            return StandingsEntry(
                teamId: team.teamId,
                teamName: team.displayName,
                teamLogo: team.logoURL,
                pointsForWin: format.standingsRules.winPoints,
                pointsForDraw: format.standingsRules.drawPoints,
                pointsForLoss: format.standingsRules.lossPoints
            )
        }

        return StandingsCalculator.calculate(
            from: partite,
            initialEntries: seededEntries,
            rules: format.standingsRules,
            manualOverrides: edition == activeEdition ? manualStandingsOverride : nil
        ) { [weak self] teamId, meta, matchEdition in
            guard let self else {
                return (meta.name, meta.logo)
            }
            let resolved = self.resolvedTeamInfo(teamId: teamId, meta: meta, edition: matchEdition)
            return (resolved.name, resolved.logo)
        }
    }

    /// I gironi dell'edizione, in ordine: `["A", "B", "C"]`. Vuoto se il torneo
    /// gioca a girone unico.
    func gironi(for edition: Int) -> [String] {
        Set(
            allMatches
                .filter { $0.edizione == edition && TournamentPhaseKey.isGroupStage($0.fase) }
                .compactMap { m -> String? in
                    let v = m.group?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
                    return v.isEmpty ? nil : v
                }
        ).sorted()
    }

    private func deduplicatedParticipations(for edition: Int) -> [EditionParticipation] {
        let grouped = Dictionary(grouping: allParticipations.filter { $0.edizione == edition }) { participation in
            participation.squadraId.isEmpty ? participation.id ?? UUID().uuidString : participation.squadraId
        }

        return grouped.values
            .compactMap { candidates in
                candidates.max { lhs, rhs in
                    let lhsScore = participationScore(lhs)
                    let rhsScore = participationScore(rhs)
                    if lhsScore == rhsScore {
                        return (lhs.dataIscrizione?.dateValue() ?? .distantPast) < (rhs.dataIscrizione?.dateValue() ?? .distantPast)
                    }
                    return lhsScore < rhsScore
                }
            }
            .sorted {
                $0.nomeSquadra.localizedCaseInsensitiveCompare($1.nomeSquadra) == .orderedAscending
            }
    }

    private func bestParticipation(for teamId: String, edition: Int) -> EditionParticipation? {
        deduplicatedParticipations(for: edition).first { $0.squadraId == teamId }
    }

    private func latestHistoricalParticipation(for teamId: String, before edition: Int) -> EditionParticipation? {
        let normalizedTeamId = teamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTeamId.isEmpty else { return nil }

        let candidates = allParticipations.filter {
            $0.squadraId == normalizedTeamId && $0.edizione < edition
        }

        return candidates.max { lhs, rhs in
            if lhs.edizione == rhs.edizione {
                let lhsScore = participationScore(lhs)
                let rhsScore = participationScore(rhs)
                if lhsScore == rhsScore {
                    return (lhs.dataIscrizione?.dateValue() ?? .distantPast) <
                        (rhs.dataIscrizione?.dateValue() ?? .distantPast)
                }
                return lhsScore < rhsScore
            }
            return lhs.edizione < rhs.edizione
        }
    }

    private func participationScore(_ participation: EditionParticipation) -> Int {
        var score = 0
        if let logo = participation.logoSquadra, !logo.isEmpty { score += 2 }
        if let email = participation.email, !email.isEmpty { score += 1 }
        if let ownerUid = participation.ownerUid, !ownerUid.isEmpty { score += 1 }
        if let rappresentante = participation.rappresentante,
           !rappresentante.nome.isEmpty || !rappresentante.telefono.isEmpty { score += 2 }
        if participation.colori != nil { score += 2 }
        if participation.playersCount != nil { score += 1 }
        score += participation.playerSnapshots.count * 3
        score += (participation.legacyPlayerNames ?? []).count
        return score
    }

    private func meaningfulString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func meaningfulTeamName(_ value: String?) -> String? {
        guard let value = meaningfulString(value) else { return nil }
        let lowercased = value.lowercased()
        if ["squadra", "squadra 1", "squadra 2", "team 1", "team 2"].contains(lowercased) {
            return nil
        }
        return value
    }
}

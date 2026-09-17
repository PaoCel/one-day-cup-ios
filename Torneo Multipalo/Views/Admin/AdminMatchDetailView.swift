import SwiftUI
import FirebaseFirestore

// MARK: - ViewModel

@Observable
@MainActor
final class AdminMatchDetailViewModel {
    var match: Match?
    var team1Players: [Player] = []
    var team2Players: [Player] = []
    var isLoading = false
    var errorMessage: String?
    var showAddEventSheet = false
    var goalkeeperStatusMessage: String?
    var mvpStatusMessage: String?
    var defenderStatusMessage: String?
    var scheduleStatusMessage: String?

    // Form aggiunta evento
    var newTipo = "gol"
    var newSquadraId = ""
    var newGiocatoreId = ""
    var newGiocatoreNome = ""
    var newMinuto = ""

    // Portieri
    var selectedTeam1GoalkeeperId = ""
    var selectedTeam2GoalkeeperId = ""
    var team1GoalkeeperHint: String?
    var team2GoalkeeperHint: String?
    /// Teams whose goalkeeper couldn't be auto-assigned (0 or 2+ portieri in roster).
    var goalkeeperWarnings: [String] = []

    // MVP
    var selectedMvpTeamId = ""
    var selectedMvpPlayerId = ""
    var selectedDefenderTeamId = ""
    var selectedDefenderPlayerId = ""

    // Programmazione
    var scheduledCampo = ""
    var scheduledTime = ""

    // MVP photo
    var showMvpPhotoPicker = false
    var mvpPhotoSourceType: UIImagePickerController.SourceType = .photoLibrary
    var mvpPhotoImage: UIImage?
    var isUploadingMvpPhoto = false
    var mvpPhotoSaved = false

    // Social share
    var showMvpShareSheet = false
    var showMatchResultShareSheet = false

    let tipiEvento: [(id: String, label: String)] = [
        ("gol",              "Gol"),
        ("autogol",          "Autogol"),
        ("ammonizione",      "Ammonizione"),
        ("espulsione",       "Espulsione"),
        ("rigore_segnato",   "Rigore segnato"),
        ("rigore_sbagliato", "Rigore sbagliato"),
        ("sostituzione",     "Sostituzione")
    ]

    private let listener = FirestoreListenerToken()
    private var hasPendingGoalkeeperChanges = false
    private var hasPendingMvpChanges = false
    private var hasPendingDefenderChanges = false
    private var hasPendingScheduleChanges = false

    func start(match initialMatch: Match, appState: AppState) {
        self.match = initialMatch
        refreshEditableSelections(allMatches: appState.allMatches, force: true)

        guard let matchId = initialMatch.id else { return }

        listener.replace(with: appState.firestoreService.listenToMatch(matchId: matchId) { [weak self] updated in
            Task { @MainActor [weak self, updated] in
                guard let self, let updated else { return }
                self.match = updated
                self.refreshEditableSelections(allMatches: appState.allMatches, force: false)
            }
        })

        Task {
            async let players1 = appState.firestoreService.fetchPlayers(teamId: initialMatch.team1)
            async let players2 = appState.firestoreService.fetchPlayers(teamId: initialMatch.team2)
            let loadedTeam1 = (try? await players1) ?? []
            let loadedTeam2 = (try? await players2) ?? []

            team1Players = Self.sortedPlayers(loadedTeam1)
            team2Players = Self.sortedPlayers(loadedTeam2)
            refreshEditableSelections(allMatches: appState.allMatches, force: true)
            await autoAssignGoalkeepersIfNeeded(appState: appState)
        }
    }

    func stop() {
        listener.cancel()
    }

    var playersForSquadra: [Player] {
        guard let match else { return [] }
        if newSquadraId == match.team1 { return team1Players }
        if newSquadraId == match.team2 { return team2Players }
        return []
    }

    var mvpPlayersForSelectedTeam: [Player] {
        players(for: selectedMvpTeamId)
    }

    var defenderPlayersForSelectedTeam: [Player] {
        players(for: selectedDefenderTeamId)
    }

    func goalkeeperSummary(for teamId: String) -> String {
        let selection = pendingGoalkeeperSelection(for: teamId)
        return selection?.playerName ?? "Non impostato"
    }

    func updateGoalkeeperSelection(teamId: String, playerId: String, allMatches: [Match]) {
        guard let match else { return }

        switch teamId {
        case match.team1:
            selectedTeam1GoalkeeperId = playerId
        case match.team2:
            selectedTeam2GoalkeeperId = playerId
        default:
            return
        }

        hasPendingGoalkeeperChanges = true
        goalkeeperStatusMessage = nil
        refreshGoalkeeperHints(allMatches: allMatches)
    }

    func updateSelectedMvpTeam(_ teamId: String) {
        selectedMvpTeamId = teamId
        if !mvpPlayersForSelectedTeam.contains(where: { Self.matchesPlayerIdentifier($0, identifier: selectedMvpPlayerId) }) {
            selectedMvpPlayerId = ""
        }
        hasPendingMvpChanges = true
        mvpStatusMessage = nil
    }

    func updateSelectedMvpPlayer(_ playerId: String) {
        selectedMvpPlayerId = playerId
        hasPendingMvpChanges = true
        mvpStatusMessage = nil
    }

    func updateSelectedDefenderTeam(_ teamId: String) {
        selectedDefenderTeamId = teamId
        if !defenderPlayersForSelectedTeam.contains(where: { Self.matchesPlayerIdentifier($0, identifier: selectedDefenderPlayerId) }) {
            selectedDefenderPlayerId = ""
        }
        hasPendingDefenderChanges = true
        defenderStatusMessage = nil
    }

    func updateSelectedDefenderPlayer(_ playerId: String) {
        selectedDefenderPlayerId = playerId
        hasPendingDefenderChanges = true
        defenderStatusMessage = nil
    }

    func updateScheduledCampo(_ value: String) {
        scheduledCampo = value
        hasPendingScheduleChanges = true
        scheduleStatusMessage = nil
    }

    func updateScheduledTime(_ value: String) {
        scheduledTime = value
        hasPendingScheduleChanges = true
        scheduleStatusMessage = nil
    }

    func addEvent(appState: AppState, missOutcome: PenaltyMiss.Outcome? = nil) async {
        guard !isLoading, let match, let matchId = match.id else { return }
        guard newTipo != "rigore_sbagliato" || missOutcome != nil else { return }

        if isSelectedPlayerSuspendedForCurrentMatch(allMatches: appState.allMatches) {
            errorMessage = "Giocatore squalificato per questa partita: evento bloccato."
            return
        }

        let event = MatchEvent(
            tipo: newTipo,
            giocatoreId: newGiocatoreId.isEmpty ? nil : newGiocatoreId,
            giocatoreNome: newGiocatoreNome.isEmpty ? nil : newGiocatoreNome,
            squadraId: newSquadraId.isEmpty ? nil : newSquadraId,
            minuto: Int(newMinuto),
            penaltyMiss: newTipo == "rigore_sbagliato" ? missOutcome.map {
                match.penaltyMiss(outcome: $0, kickingTeamId: newSquadraId, players: team1Players + team2Players)
            } : nil
        )

        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.addMatchEvent(matchId: matchId, event: event)
            resetForm()
            showAddEventSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeEvent(at index: Int, appState: AppState) async {
        guard let match, let matchId = match.id else { return }
        var eventi = match.safeEventi
        guard index < eventi.count else { return }
        eventi.remove(at: index)

        do {
            try await appState.firestoreService.setEventi(matchId: matchId, eventi: eventi)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveGoalkeepers(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        isLoading = true
        defer { isLoading = false }

        let t1Selection = pendingGoalkeeperSelection(for: match.team1)
        let t2Selection = pendingGoalkeeperSelection(for: match.team2)

        do {
            try await appState.firestoreService.updateMatchGoalkeepers(
                matchId: matchId,
                team1Goalkeeper: t1Selection,
                team2Goalkeeper: t2Selection
            )

            // Seed goalkeeperTimeline with startMinute=0 if not yet set
            if match.goalkeeperTimeline == nil || match.goalkeeperTimeline!.isEmpty {
                var timeline: [Match.GoalkeeperTimelineEntry] = []
                if let t1 = t1Selection, let pid = t1.playerId, !pid.isEmpty {
                    timeline.append(Match.GoalkeeperTimelineEntry(playerId: pid, playerName: t1.playerName, startMinute: 0))
                }
                if let t2 = t2Selection, let pid = t2.playerId, !pid.isEmpty {
                    timeline.append(Match.GoalkeeperTimelineEntry(playerId: pid, playerName: t2.playerName, startMinute: 0))
                }
                if !timeline.isEmpty {
                    try? await appState.firestoreService.updateGoalkeeperTimeline(matchId: matchId, timeline: timeline)
                }
            }

            hasPendingGoalkeeperChanges = false
            goalkeeperStatusMessage = "Portieri della partita aggiornati."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveSchedule(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.updateMatchSchedule(
                matchId: matchId,
                campo: scheduledCampo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : scheduledCampo,
                matchTime: scheduledTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : scheduledTime
            )
            hasPendingScheduleChanges = false
            scheduleStatusMessage = "Programmazione partita aggiornata."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveMvp(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        let selectedPlayer = mvpPlayersForSelectedTeam.first {
            Self.matchesPlayerIdentifier($0, identifier: selectedMvpPlayerId)
        }

        let normalizedPlayerId = Self.stablePlayerIdentifier(for: selectedPlayer)
        let normalizedPlayerName = selectedPlayer?.nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedTeamId = selectedMvpTeamId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTeamId.isEmpty, (!normalizedPlayerId.isEmpty || !normalizedPlayerName.isEmpty) else {
            errorMessage = "Seleziona squadra e giocatore per salvare l'MVP."
            return
        }

        let mvp = Match.MatchMvp(
            playerId: normalizedPlayerId.isEmpty ? nil : normalizedPlayerId,
            playerName: normalizedPlayerName.isEmpty ? nil : normalizedPlayerName,
            team: normalizedTeamId == match.team2 ? 2 : 1
        )

        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.setMatchMvp(matchId: matchId, mvp: mvp)
            hasPendingMvpChanges = false
            mvpStatusMessage = "MVP ufficiale salvato."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearMvp(appState: AppState) async {
        guard let matchId = match?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.setMatchMvp(matchId: matchId, mvp: nil)
            selectedMvpTeamId = ""
            selectedMvpPlayerId = ""
            hasPendingMvpChanges = false
            mvpStatusMessage = "MVP rimosso."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveBestDefender(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        let selectedPlayer = defenderPlayersForSelectedTeam.first {
            Self.matchesPlayerIdentifier($0, identifier: selectedDefenderPlayerId)
        }
        let normalizedPlayerId = Self.stablePlayerIdentifier(for: selectedPlayer)
        let normalizedPlayerName = selectedPlayer?.nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedTeamId = selectedDefenderTeamId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedTeamId.isEmpty, (!normalizedPlayerId.isEmpty || !normalizedPlayerName.isEmpty) else {
            errorMessage = "Seleziona squadra e giocatore per salvare il miglior difensore."
            return
        }

        let defender = Match.MatchMvp(
            playerId: normalizedPlayerId.isEmpty ? nil : normalizedPlayerId,
            playerName: normalizedPlayerName.isEmpty ? nil : normalizedPlayerName,
            team: normalizedTeamId == match.team2 ? 2 : 1
        )

        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.setMatchBestDefender(matchId: matchId, bestDefender: defender)
            hasPendingDefenderChanges = false
            defenderStatusMessage = "Miglior difensore salvato."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearBestDefender(appState: AppState) async {
        guard let matchId = match?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.setMatchBestDefender(matchId: matchId, bestDefender: nil)
            selectedDefenderTeamId = ""
            selectedDefenderPlayerId = ""
            hasPendingDefenderChanges = false
            defenderStatusMessage = "Miglior difensore rimosso."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadMvpPhoto(appState: AppState) async {
        guard let match, let matchId = match.id, let image = mvpPhotoImage else { return }
        guard let data = image.jpegData(compressionQuality: 0.75) else { return }

        isUploadingMvpPhoto = true
        defer { isUploadingMvpPhoto = false }

        do {
            let path = "partite/\(matchId)/mvp.jpg"
            let url = try await appState.storageService.uploadImage(data, path: path)
            try await appState.firestoreService.updateMatchMvpPhoto(matchId: matchId, photoURL: url.absoluteString)
            mvpPhotoSaved = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeMvpPhoto(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        do {
            let path = "partite/\(matchId)/mvp.jpg"
            try? await appState.storageService.deleteImage(path: path)
            try await appState.firestoreService.updateMatchMvpPhoto(matchId: matchId, photoURL: nil)
            mvpPhotoImage = nil
            mvpPhotoSaved = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setStarted(_ started: Bool, appState: AppState) async {
        guard let matchId = match?.id else { return }
        do {
            try await appState.firestoreService.setMatchStarted(matchId, started: started)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setPlayed(_ played: Bool, appState: AppState) async {
        guard let matchId = match?.id else { return }
        do {
            try await appState.firestoreService.setMatchPlayed(matchId, played: played)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetForm() {
        newTipo = "gol"
        newSquadraId = ""
        newGiocatoreId = ""
        newGiocatoreNome = ""
        newMinuto = ""
    }

    private func refreshEditableSelections(allMatches: [Match], force: Bool) {
        refreshSchedule(force: force)
        refreshGoalkeeperSelections(allMatches: allMatches, force: force)
        refreshMvpSelection(force: force)
        refreshDefenderSelection(force: force)
    }

    private func refreshSchedule(force: Bool) {
        guard let match else { return }
        guard force || !hasPendingScheduleChanges else { return }
        scheduledCampo = match.campo ?? ""
        scheduledTime = match.matchTime ?? ""
    }

    private func refreshGoalkeeperSelections(allMatches: [Match], force: Bool) {
        guard let match else { return }
        guard force || !hasPendingGoalkeeperChanges else {
            refreshGoalkeeperHints(allMatches: allMatches)
            return
        }

        let team1Seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: match.team1,
            in: match,
            roster: team1Players,
            allMatches: allMatches
        )
        selectedTeam1GoalkeeperId = team1Seed.selection?.playerId ?? ""

        let team2Seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: match.team2,
            in: match,
            roster: team2Players,
            allMatches: allMatches
        )
        selectedTeam2GoalkeeperId = team2Seed.selection?.playerId ?? ""

        refreshGoalkeeperHints(allMatches: allMatches)
    }

    private func refreshGoalkeeperHints(allMatches: [Match]) {
        guard let match else { return }

        let team1Seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: match.team1,
            in: match,
            roster: team1Players,
            allMatches: allMatches
        )
        let team2Seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: match.team2,
            in: match,
            roster: team2Players,
            allMatches: allMatches
        )

        team1GoalkeeperHint = goalkeeperHint(
            currentSelectionId: selectedTeam1GoalkeeperId,
            savedSelection: match.team1Goalkeeper,
            seededSelection: team1Seed
        )
        team2GoalkeeperHint = goalkeeperHint(
            currentSelectionId: selectedTeam2GoalkeeperId,
            savedSelection: match.team2Goalkeeper,
            seededSelection: team2Seed
        )
    }

    private func goalkeeperHint(
        currentSelectionId: String,
        savedSelection: Match.GoalkeeperSelection?,
        seededSelection: MatchStaffSupport.GoalkeeperSeed
    ) -> String? {
        let normalizedCurrentSelectionId = currentSelectionId.trimmingCharacters(in: .whitespacesAndNewlines)

        if savedSelection != nil && !hasPendingGoalkeeperChanges {
            return "Portiere già salvato per questa partita."
        }

        if seededSelection.isInherited,
           let seededPlayerId = seededSelection.selection?.playerId,
           seededPlayerId == normalizedCurrentSelectionId {
            return "Predefinito dall'ultima partita salvata."
        }

        if hasPendingGoalkeeperChanges {
            return "Hai modifiche non ancora salvate."
        }

        return nil
    }

    private func refreshMvpSelection(force: Bool) {
        guard let match else { return }
        guard force || !hasPendingMvpChanges else { return }

        guard let mvp = match.mvp else {
            selectedMvpTeamId = ""
            selectedMvpPlayerId = ""
            return
        }

        let teamId: String
        switch mvp.team {
        case 2:
            teamId = match.team2
        default:
            teamId = match.team1
        }

        selectedMvpTeamId = teamId
        if let resolvedPlayerId = resolvePlayerIdentifier(
            playerId: mvp.playerId,
            playerName: mvp.playerName,
            teamId: teamId
        ) {
            selectedMvpPlayerId = resolvedPlayerId
        } else {
            selectedMvpPlayerId = ""
        }
    }

    private func refreshDefenderSelection(force: Bool) {
        guard let match else { return }
        guard force || !hasPendingDefenderChanges else { return }

        guard let defender = match.bestDefender else {
            selectedDefenderTeamId = ""
            selectedDefenderPlayerId = ""
            return
        }

        let teamId = defender.team == 2 ? match.team2 : match.team1
        selectedDefenderTeamId = teamId
        selectedDefenderPlayerId = resolvePlayerIdentifier(
            playerId: defender.playerId,
            playerName: defender.playerName,
            teamId: teamId
        ) ?? ""
    }

    // MARK: - Auto-assign goalkeeper

    private func autoAssignGoalkeepersIfNeeded(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        var warnings: [String] = []
        var t1Selection: Match.GoalkeeperSelection?
        var t2Selection: Match.GoalkeeperSelection?

        for (teamId, roster) in [(match.team1, team1Players), (match.team2, team2Players)] {
            guard match.goalkeeper(for: teamId) == nil else { continue }
            if let gk = MatchStaffSupport.uniqueGoalkeeper(in: roster) {
                let selection = Match.GoalkeeperSelection(
                    playerId: gk.firestoreIdentifier ?? gk.playerAuthUid,
                    playerName: gk.nomeCompleto
                )
                if teamId == match.team1 { t1Selection = selection }
                else { t2Selection = selection }
            } else {
                let teamName = teamId == match.team1
                    ? (appState.resolvedTeams(for: match).team1.name)
                    : (appState.resolvedTeams(for: match).team2.name)
                warnings.append(teamName)
            }
        }

        goalkeeperWarnings = warnings

        let anyAssignment = t1Selection != nil || t2Selection != nil
        guard anyAssignment else { return }

        do {
            try await appState.firestoreService.updateMatchGoalkeepers(
                matchId: matchId,
                team1Goalkeeper: t1Selection ?? match.team1Goalkeeper,
                team2Goalkeeper: t2Selection ?? match.team2Goalkeeper
            )

            var timeline = match.goalkeeperTimeline ?? []
            if timeline.isEmpty {
                if let t1 = t1Selection, let pid = t1.playerId, !pid.isEmpty {
                    timeline.append(Match.GoalkeeperTimelineEntry(playerId: pid, playerName: t1.playerName, startMinute: 0))
                }
                if let t2 = t2Selection, let pid = t2.playerId, !pid.isEmpty {
                    timeline.append(Match.GoalkeeperTimelineEntry(playerId: pid, playerName: t2.playerName, startMinute: 0))
                }
                if !timeline.isEmpty {
                    try? await appState.firestoreService.updateGoalkeeperTimeline(matchId: matchId, timeline: timeline)
                }
            }

            goalkeeperStatusMessage = "Portiere assegnato automaticamente."
        } catch {
            // Non-fatal: just leave GK unset; warning already shown
        }
    }

    private func players(for teamId: String) -> [Player] {
        guard let match else { return [] }
        if teamId == match.team1 { return team1Players }
        if teamId == match.team2 { return team2Players }
        return []
    }

    private func isSelectedPlayerSuspendedForCurrentMatch(allMatches: [Match]) -> Bool {
        guard let match, !newSquadraId.isEmpty else { return false }

        return MatchSuspensionSupport.isPlayerSuspended(
            playerId: newGiocatoreId.isEmpty ? nil : newGiocatoreId,
            playerName: newGiocatoreNome,
            teamId: newSquadraId,
            in: match,
            within: allMatches
        )
    }

    private func pendingGoalkeeperSelection(for teamId: String) -> Match.GoalkeeperSelection? {
        let selectedPlayerId: String
        let roster: [Player]

        guard let match else { return nil }

        switch teamId {
        case match.team1:
            selectedPlayerId = selectedTeam1GoalkeeperId
            roster = team1Players
        case match.team2:
            selectedPlayerId = selectedTeam2GoalkeeperId
            roster = team2Players
        default:
            return nil
        }

        let normalizedPlayerId = selectedPlayerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPlayerId.isEmpty else { return nil }
        return MatchStaffSupport.goalkeeperSelection(from: normalizedPlayerId, roster: roster)
    }

    private func resolvePlayerIdentifier(playerId: String?, playerName: String?, teamId: String) -> String? {
        let roster: [Player]
        guard let match else { return nil }

        switch teamId {
        case match.team1:
            roster = team1Players
        case match.team2:
            roster = team2Players
        default:
            return nil
        }

        if let playerId = playerId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !playerId.isEmpty,
           let player = roster.first(where: { Self.matchesPlayerIdentifier($0, identifier: playerId) }) {
            return Self.stablePlayerIdentifier(for: player)
        }

        if let normalizedPlayerName = Player.normalizedLookupName(from: playerName),
           let player = roster.first(where: { Player.normalizedLookupName(from: $0.nomeCompleto) == normalizedPlayerName }) {
            return Self.stablePlayerIdentifier(for: player)
        }

        return nil
    }

    private static func sortedPlayers(_ players: [Player]) -> [Player] {
        players.sorted { lhs, rhs in
            let lhsNumber = lhs.numeroMaglia ?? 99
            let rhsNumber = rhs.numeroMaglia ?? 99
            if lhsNumber == rhsNumber {
                return lhs.nomeCompleto.localizedCaseInsensitiveCompare(rhs.nomeCompleto) == .orderedAscending
            }
            return lhsNumber < rhsNumber
        }
    }

    private static func stablePlayerIdentifier(for player: Player?) -> String {
        [player?.firestoreIdentifier, player?.playerAuthUid]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func matchesPlayerIdentifier(_ player: Player, identifier: String) -> Bool {
        let normalizedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedIdentifier.isEmpty else { return false }

        return [player.firestoreIdentifier, player.playerAuthUid]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(normalizedIdentifier)
    }
}

// MARK: - View

struct AdminMatchDetailView: View {
    let match: Match

    @Environment(AppState.self) private var appState
    @State private var viewModel = AdminMatchDetailViewModel()
    @State private var showPenaltyMissChoice = false

    var currentMatch: Match { viewModel.match ?? match }

    private var isAdminOverride: Bool {
        appState.authService.userRole == .admin
    }

    private var resolvedTeams: (team1: AppState.ResolvedTeamInfo, team2: AppState.ResolvedTeamInfo) {
        appState.resolvedTeams(for: currentMatch)
    }

    var body: some View {
        List {
            if currentMatch.isPlayed && isAdminOverride {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Modifica post-fine partita — admin only")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                scoreHeader
            }

            Section("Programmazione partita") {
                TextField("Campo", text: Binding(
                    get: { viewModel.scheduledCampo },
                    set: { viewModel.updateScheduledCampo($0) }
                ))

                TextField("Orario", text: Binding(
                    get: { viewModel.scheduledTime },
                    set: { viewModel.updateScheduledTime($0) }
                ))
                .keyboardType(.numbersAndPunctuation)

                Button {
                    Task { await viewModel.saveSchedule(appState: appState) }
                } label: {
                    Label("Salva orario e campo", systemImage: "calendar.badge.clock")
                }
                .disabled(viewModel.isLoading)

                if let message = viewModel.scheduleStatusMessage {
                    statusMessage(message, tint: TournamentPalette.success)
                }
            }

            Section("Portieri partita") {
                if !viewModel.goalkeeperWarnings.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(TournamentPalette.danger)
                        Text("Portiere non assegnato: \(viewModel.goalkeeperWarnings.joined(separator: ", ")). Imposta manualmente.")
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.danger)
                    }
                }

                goalkeeperPicker(
                    teamId: currentMatch.team1,
                    teamName: resolvedTeams.team1.name,
                    players: viewModel.team1Players,
                    selection: Binding(
                        get: { viewModel.selectedTeam1GoalkeeperId },
                        set: { viewModel.updateGoalkeeperSelection(teamId: currentMatch.team1, playerId: $0, allMatches: appState.allMatches) }
                    ),
                    hint: viewModel.team1GoalkeeperHint
                )

                goalkeeperPicker(
                    teamId: currentMatch.team2,
                    teamName: resolvedTeams.team2.name,
                    players: viewModel.team2Players,
                    selection: Binding(
                        get: { viewModel.selectedTeam2GoalkeeperId },
                        set: { viewModel.updateGoalkeeperSelection(teamId: currentMatch.team2, playerId: $0, allMatches: appState.allMatches) }
                    ),
                    hint: viewModel.team2GoalkeeperHint
                )

                Button {
                    Task { await viewModel.saveGoalkeepers(appState: appState) }
                } label: {
                    Label("Salva portieri", systemImage: "checkmark.circle.fill")
                }
                .disabled(viewModel.isLoading)

                if let message = viewModel.goalkeeperStatusMessage {
                    statusMessage(message, tint: TournamentPalette.success)
                }
            }

            Section("MVP ufficiale") {
                Picker("Squadra", selection: Binding(
                    get: { viewModel.selectedMvpTeamId },
                    set: { viewModel.updateSelectedMvpTeam($0) }
                )) {
                    Text("Seleziona squadra").tag("")
                    Text(resolvedTeams.team1.name).tag(currentMatch.team1)
                    Text(resolvedTeams.team2.name).tag(currentMatch.team2)
                }
                .pickerStyle(.menu)

                Picker("Giocatore", selection: Binding(
                    get: { viewModel.selectedMvpPlayerId },
                    set: { viewModel.updateSelectedMvpPlayer($0) }
                )) {
                    Text("Seleziona giocatore").tag("")
                    ForEach(viewModel.mvpPlayersForSelectedTeam, id: \.stableRosterKey) { player in
                        Text(player.nomeCompleto).tag(player.firestoreIdentifier ?? player.playerAuthUid ?? "")
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.selectedMvpTeamId.isEmpty)

                Button {
                    Task { await viewModel.saveMvp(appState: appState) }
                } label: {
                    Label("Salva MVP", systemImage: "star.circle.fill")
                }
                .disabled(viewModel.isLoading)

                if currentMatch.mvp != nil {
                    Button(role: .destructive) {
                        Task { await viewModel.clearMvp(appState: appState) }
                    } label: {
                        Label("Rimuovi MVP", systemImage: "trash")
                    }
                    .disabled(viewModel.isLoading)
                }

                if let message = viewModel.mvpStatusMessage {
                    statusMessage(message, tint: TournamentPalette.success)
                }

                // MVP Photo
                if currentMatch.mvp != nil {
                    if let photo = viewModel.mvpPhotoImage {
                        HStack {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                            VStack(alignment: .leading) {
                                if viewModel.mvpPhotoSaved {
                                    Text("Foto salvata")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(TournamentPalette.success)
                                } else if viewModel.isUploadingMvpPhoto {
                                    ProgressView()
                                } else {
                                    Button("Salva foto") {
                                        Task { await viewModel.uploadMvpPhoto(appState: appState) }
                                    }
                                }
                                Button("Rimuovi", role: .destructive) {
                                    viewModel.mvpPhotoImage = nil
                                    viewModel.mvpPhotoSaved = false
                                }
                                .font(.caption)
                            }
                        }
                    } else if let existingURL = currentMatch.mvp?.mvpPhotoURL, !existingURL.isEmpty {
                        HStack {
                            CachedAsyncImage(
                                urlString: existingURL,
                                placeholderIcon: "person.fill",
                                placeholderColor: TournamentPalette.warm,
                                contentMode: .fill
                            )
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                            Text("Foto MVP presente")
                                .font(.caption)
                                .foregroundStyle(TournamentPalette.success)
                        }
                    } else {
                        Menu {
                            Button {
                                viewModel.mvpPhotoSourceType = .camera
                                viewModel.showMvpPhotoPicker = true
                            } label: {
                                Label("Scatta foto", systemImage: "camera.fill")
                            }
                            Button {
                                viewModel.mvpPhotoSourceType = .photoLibrary
                                viewModel.showMvpPhotoPicker = true
                            } label: {
                                Label("Scegli dalla galleria", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Label("Aggiungi foto MVP", systemImage: "camera.badge.ellipsis")
                        }
                    }

                }

            }

            Section("Miglior difensore") {
                Picker("Squadra", selection: Binding(
                    get: { viewModel.selectedDefenderTeamId },
                    set: { viewModel.updateSelectedDefenderTeam($0) }
                )) {
                    Text("Seleziona squadra").tag("")
                    Text(resolvedTeams.team1.name).tag(currentMatch.team1)
                    Text(resolvedTeams.team2.name).tag(currentMatch.team2)
                }
                .pickerStyle(.menu)

                Picker("Giocatore", selection: Binding(
                    get: { viewModel.selectedDefenderPlayerId },
                    set: { viewModel.updateSelectedDefenderPlayer($0) }
                )) {
                    Text("Seleziona giocatore").tag("")
                    ForEach(viewModel.defenderPlayersForSelectedTeam, id: \.stableRosterKey) { player in
                        Text(player.nomeCompleto).tag(player.firestoreIdentifier ?? player.playerAuthUid ?? "")
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.selectedDefenderTeamId.isEmpty)

                Button {
                    Task { await viewModel.saveBestDefender(appState: appState) }
                } label: {
                    Label("Salva miglior difensore", systemImage: "shield.lefthalf.filled")
                }
                .disabled(viewModel.isLoading)

                if currentMatch.bestDefender != nil {
                    Button(role: .destructive) {
                        Task { await viewModel.clearBestDefender(appState: appState) }
                    } label: {
                        Label("Rimuovi miglior difensore", systemImage: "trash")
                    }
                    .disabled(viewModel.isLoading)
                }

                if let message = viewModel.defenderStatusMessage {
                    statusMessage(message, tint: TournamentPalette.success)
                }
            }

            Section("Stato") {
                stateButtons
            }

            Section {
                if currentMatch.safeEventi.isEmpty {
                    Text("Nessun evento. Aggiungi gol, cartellini e altro.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(currentMatch.safeEventi.enumerated()), id: \.offset) { index, event in
                        VStack(alignment: .leading, spacing: 4) {
                            EventAdminRow(event: event)
                            if let save = event.penaltySaveEvent {
                                EventAdminRow(event: save).padding(.leading, 20)
                            }
                        }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await viewModel.removeEvent(at: index, appState: appState) }
                                } label: {
                                    Label("Elimina", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                HStack {
                    Text("Eventi")
                    Spacer()
                    Button {
                        viewModel.resetForm()
                        viewModel.showAddEventSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
                    }
                }
            }
        }
        .navigationTitle("\(resolvedTeams.team1.name) vs \(resolvedTeams.team2.name)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { viewModel.showAddEventSheet },
            set: { viewModel.showAddEventSheet = $0 }
        )) {
            addEventSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMvpPhotoPicker },
            set: { viewModel.showMvpPhotoPicker = $0 }
        )) {
            ImagePicker(
                image: Binding(
                    get: { viewModel.mvpPhotoImage },
                    set: { newImage in
                        viewModel.mvpPhotoImage = newImage
                        viewModel.mvpPhotoSaved = false
                        if newImage != nil {
                            Task { await viewModel.uploadMvpPhoto(appState: appState) }
                        }
                    }
                ),
                sourceType: viewModel.mvpPhotoSourceType
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMvpShareSheet },
            set: { viewModel.showMvpShareSheet = $0 }
        )) {
            if let mvp = currentMatch.mvp {
                MVPStoryShareView(
                    match: currentMatch,
                    mvpName: mvp.playerName ?? "",
                    mvpTeam: mvp.team == 2 ? resolvedTeams.team2.name : resolvedTeams.team1.name,
                    mvpPhotoURL: mvp.mvpPhotoURL,
                    team1Name: resolvedTeams.team1.name,
                    team2Name: resolvedTeams.team2.name,
                    team1Logo: resolvedTeams.team1.logo,
                    team2Logo: resolvedTeams.team2.logo
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMatchResultShareSheet },
            set: { viewModel.showMatchResultShareSheet = $0 }
        )) {
            MatchResultStoryShareView(
                match: currentMatch,
                team1Name: resolvedTeams.team1.name,
                team2Name: resolvedTeams.team2.name,
                team1Logo: resolvedTeams.team1.logo,
                team2Logo: resolvedTeams.team2.logo
            )
        }
        .alert("Errore", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onAppear { viewModel.start(match: match, appState: appState) }
        .onDisappear { viewModel.stop() }
    }

    private var scoreHeader: some View {
        HStack {
            VStack {
                Text(resolvedTeams.team1.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("\(currentMatch.team1Goals)")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
            }
            .frame(maxWidth: .infinity)

            Text("–")
                .font(.title)
                .foregroundStyle(.secondary)

            VStack {
                Text(resolvedTeams.team2.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("\(currentMatch.team2Goals)")
                    .font(.system(size: 48, weight: .black))
                    .foregroundStyle(Color(hex: "#1a73e8") ?? .blue)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
    }

    private func isPlayerSuspended(_ player: Player, teamId: String) -> Bool {
        MatchSuspensionSupport.isPlayerSuspended(
            playerId: player.firestoreIdentifier ?? player.playerAuthUid,
            playerName: player.nomeCompleto,
            teamId: teamId,
            in: currentMatch,
            within: appState.allMatches
        )
    }

    @ViewBuilder
    private func goalkeeperPicker(
        teamId: String,
        teamName: String,
        players: [Player],
        selection: Binding<String>,
        hint: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(teamName, selection: selection) {
                Text("Non impostato").tag("")
                ForEach(players, id: \.stableRosterKey) { player in
                    Text(player.nomeCompleto).tag(player.firestoreIdentifier ?? player.playerAuthUid ?? "")
                }
            }
            .pickerStyle(.menu)

            Text(viewModel.goalkeeperSummary(for: teamId))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
    }

    private func statusMessage(_ message: String, tint: Color) -> some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
    }

    @ViewBuilder
    private var stateButtons: some View {
        if !currentMatch.isStarted && !currentMatch.isPlayed && !viewModel.goalkeeperWarnings.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(TournamentPalette.danger)
                Text("Imposta portieri prima di avviare: \(viewModel.goalkeeperWarnings.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.danger)
            }
        }

        if !currentMatch.isStarted && !currentMatch.isPlayed {
            Button {
                Task { await viewModel.setStarted(true, appState: appState) }
            } label: {
                Label("Avvia Partita", systemImage: "play.circle.fill")
                    .foregroundStyle(.green)
            }
        }

        if currentMatch.isStarted && !currentMatch.isPlayed {
            Button {
                Task { await viewModel.setPlayed(true, appState: appState) }
            } label: {
                Label("Termina Partita", systemImage: "flag.checkered.circle.fill")
                    .foregroundStyle(.orange)
            }
        }

        if currentMatch.isPlayed {
            Label("Partita terminata", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

            Button(role: .destructive) {
                Task {
                    await viewModel.setPlayed(false, appState: appState)
                    await viewModel.setStarted(false, appState: appState)
                }
            } label: {
                Label("Riapri partita", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var addEventSheet: some View {
        NavigationStack {
            Form {
                Section("Tipo Evento") {
                    Picker("Tipo", selection: Binding(
                        get: { viewModel.newTipo },
                        set: { viewModel.newTipo = $0 }
                    )) {
                        ForEach(viewModel.tipiEvento, id: \.id) { tipo in
                            if let symbol = MatchEventSymbol.event(type: tipo.id) {
                                Label(tipo.label, image: symbol.rawValue)
                                    .tag(tipo.id)
                            } else {
                                Label(tipo.label, systemImage: "arrow.left.arrow.right")
                                    .tag(tipo.id)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Squadra") {
                    Picker("Squadra", selection: Binding(
                        get: { viewModel.newSquadraId },
                        set: {
                            viewModel.newSquadraId = $0
                            viewModel.newGiocatoreId = ""
                            viewModel.newGiocatoreNome = ""
                        }
                    )) {
                        Text("Seleziona squadra").tag("")
                        Text(resolvedTeams.team1.name).tag(currentMatch.team1)
                        Text(resolvedTeams.team2.name).tag(currentMatch.team2)
                    }
                    .pickerStyle(.menu)
                }

                Section("Giocatore") {
                    let availablePlayers = viewModel.playersForSquadra.filter {
                        !isPlayerSuspended($0, teamId: viewModel.newSquadraId)
                    }

                    if viewModel.playersForSquadra.isEmpty {
                        TextField("Nome giocatore", text: Binding(
                            get: { viewModel.newGiocatoreNome },
                            set: { viewModel.newGiocatoreNome = $0 }
                        ))
                    } else if availablePlayers.isEmpty {
                        Text("Nessun giocatore selezionabile: i giocatori disponibili sono squalificati per questa partita.")
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.danger)
                    } else {
                        Picker("Giocatore", selection: Binding(
                            get: { viewModel.newGiocatoreId },
                            set: { newId in
                                viewModel.newGiocatoreId = newId
                                let player = availablePlayers.first {
                                    ($0.firestoreIdentifier == newId) || ($0.playerAuthUid == newId)
                                }
                                viewModel.newGiocatoreNome = player?.nomeCompleto ?? ""
                            }
                        )) {
                            Text("Nessuno").tag("")
                            ForEach(availablePlayers, id: \.stableRosterKey) { player in
                                Text(player.nomeCompleto).tag(player.firestoreIdentifier ?? player.playerAuthUid ?? "")
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Minuto (opzionale)") {
                    TextField("Minuto", text: Binding(
                        get: { viewModel.newMinuto },
                        set: { viewModel.newMinuto = $0 }
                    ))
                    .keyboardType(.numberPad)
                }
            }
            .navigationTitle("Aggiungi Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.showAddEventSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi") {
                        if viewModel.newTipo == "rigore_sbagliato" {
                            showPenaltyMissChoice = true
                        } else {
                            Task { await viewModel.addEvent(appState: appState) }
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .penaltyMissConfirmation(isPresented: $showPenaltyMissChoice) { outcome in
            Task { await viewModel.addEvent(appState: appState, missOutcome: outcome) }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Riga evento (versione admin)

private struct EventAdminRow: View {
    let event: MatchEvent

    var body: some View {
        HStack(spacing: 12) {
            MatchEventTypeIcon(type: event.tipo, doubleYellow: event.doubleYellow == true, size: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.tipoLabel)
                    .font(.subheadline.bold())
                if let nome = event.giocatoreNome, !nome.isEmpty {
                    Text(nome)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let min = event.minuto {
                Text("\(min)'")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

}

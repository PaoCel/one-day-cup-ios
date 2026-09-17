import SwiftUI
import FirebaseFirestore
import ActivityKit

// MARK: - ViewModel

@Observable
@MainActor
final class LiveMatchAdminViewModel {
    var match: Match?
    var team1Players: [Player] = []
    var team2Players: [Player] = []
    var isLoading = false
    var errorMessage: String?
    var feedbackMessage: String?
    var feedbackTimer: Timer?
    var scheduleStatusMessage: String?

    // Bottom sheet
    var showEventSheet = false
    var selectedPlayer: Player?
    var selectedTeamId: String?

    // Undo
    var lastAddedEvent: MatchEvent?
    var showUndoToast = false

    // Goalkeeper change
    var showGoalkeeperSheet = false
    var goalkeeperTeamId: String?
    var showScheduleSheet = false
    var scheduledCampo = ""
    var scheduledTimeDraft = ""

    // MVP selection
    var showMvpSheet = false
    var mvpSaved = false
    var showBestDefenderSheet = false
    var bestDefenderSaved = false

    // MVP photo
    var showMvpPhotoPicker = false
    var mvpPhotoSourceType: UIImagePickerController.SourceType = .photoLibrary
    var mvpPhotoImage: UIImage?
    var isUploadingMvpPhoto = false
    var mvpPhotoSaved = false

    // Best defender photo
    var showBestDefenderPhotoPicker = false
    var bestDefenderPhotoSourceType: UIImagePickerController.SourceType = .photoLibrary
    var bestDefenderPhotoImage: UIImage?
    var isUploadingBestDefenderPhoto = false
    var bestDefenderPhotoSaved = false

    // Social share
    var showMvpShareSheet = false
    var showBestDefenderShareSheet = false
    var showMatchResultShareSheet = false

    // Cached logo filenames in App Group container
    private var logoFile1: String?
    private var logoFile2: String?
    private var logosReady = false

    // Live Activity auto-update timer
    private var liveActivityTimer: Timer?

    private let listener = FirestoreListenerToken()

    var currentMinute: Int {
        match?.elapsedMinute ?? 0
    }

    var elapsedSeconds: Int {
        guard let startTime = match?.startTime else { return 0 }
        let elapsed = Date().timeIntervalSince(startTime.dateValue())
        return max(0, Int(elapsed))
    }

    var elapsedTimerString: String {
        let total = elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var scheduledTime: String? {
        guard let time = match?.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !time.isEmpty else { return nil }
        let parts = time.components(separatedBy: "-")
        return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start(match initialMatch: Match, appState: AppState) {
        self.match = initialMatch
        scheduledCampo = initialMatch.campo ?? ""
        scheduledTimeDraft = initialMatch.matchTime ?? ""

        guard let matchId = initialMatch.id else { return }

        listener.replace(with: appState.firestoreService.listenToMatch(matchId: matchId) { [weak self] updated in
            Task { @MainActor [weak self, updated] in
                guard let self, let updated else { return }
                self.match = updated
                if !self.showScheduleSheet {
                    self.scheduledCampo = updated.campo ?? ""
                    self.scheduledTimeDraft = updated.matchTime ?? ""
                }
            }
        })

        Task {
            async let players1 = appState.firestoreService.fetchPlayers(teamId: initialMatch.team1)
            async let players2 = appState.firestoreService.fetchPlayers(teamId: initialMatch.team2)
            team1Players = Self.sortedPlayers((try? await players1) ?? [])
            team2Players = Self.sortedPlayers((try? await players2) ?? [])

            // Download logos to shared App Group container
            let resolved = appState.resolvedTeams(for: initialMatch)
            let logo1URL = resolved.team1.logo ?? initialMatch.team1Meta.logo
            let logo2URL = resolved.team2.logo ?? initialMatch.team2Meta.logo
            logoFile1 = await Self.downloadAndSaveLogo(urlString: logo1URL, teamId: initialMatch.team1)
            logoFile2 = await Self.downloadAndSaveLogo(urlString: logo2URL, teamId: initialMatch.team2)
            logosReady = true
        }
    }

    func stop() {
        listener.cancel()
        feedbackTimer?.invalidate()
        liveActivityTimer?.invalidate()
    }

    func openScheduleEditor() {
        scheduledCampo = match?.campo ?? ""
        scheduledTimeDraft = match?.matchTime ?? ""
        scheduleStatusMessage = nil
        showScheduleSheet = true
    }

    func saveSchedule(appState: AppState) async {
        guard let matchId = match?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let trimmedCampo = scheduledCampo.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedTime = scheduledTimeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            try await appState.firestoreService.updateMatchSchedule(
                matchId: matchId,
                campo: trimmedCampo.isEmpty ? nil : trimmedCampo,
                matchTime: trimmedTime.isEmpty ? nil : trimmedTime
            )
            scheduleStatusMessage = "Orario e campo aggiornati."
            showScheduleSheet = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Live Activity

    var liveActivityStatus: String?

    func startLiveActivity() {
        guard let match, let matchId = match.id else {
            liveActivityStatus = "Nessun match ID"
            return
        }

        let authInfo = ActivityAuthorizationInfo()
        guard authInfo.areActivitiesEnabled else {
            liveActivityStatus = "Live Activities disabilitate. Attivale in Impostazioni > Torneo Multipalo."
            return
        }

        let existing = Activity<MatchActivityAttributes>.activities.first {
            $0.attributes.matchId == matchId
        }
        if existing != nil {
            liveActivityStatus = nil
            return
        }

        let attributes = MatchActivityAttributes(
            matchId: matchId,
            team1Name: match.team1Meta.name,
            team2Name: match.team2Meta.name,
            team1LogoFile: logoFile1,
            team2LogoFile: logoFile2,
            campo: match.campo,
            fase: match.fase
        )

        let state = MatchActivityAttributes.ContentState(
            team1Goals: match.team1Goals,
            team2Goals: match.team2Goals,
            elapsedMinutes: currentMinute,
            lastEvent: nil,
            isFinished: false
        )

        do {
            _ = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )

            liveActivityStatus = nil

            startLiveActivityTimer()
        } catch {
            liveActivityStatus = "Errore: \(error.localizedDescription)"
        }
    }

    /// Periodically updates the Live Activity so the timer stays current on the lock screen
    func startLiveActivityTimer() {
        liveActivityTimer?.invalidate()
        liveActivityTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateLiveActivity()
            }
        }
    }

    private static func downloadAndSaveLogo(urlString: String?, teamId: String) async -> String? {
        guard let urlString,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: urlString) else { return nil }

        // Use the app's image pipeline (same cache that CachedAsyncImage uses)
        guard let image = await RemoteImagePipeline.shared.image(for: urlString, url: url) else { return nil }

        // Use PNG to preserve transparency
        let targetSize = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let pngData = renderer.pngData { ctx in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return SharedLogoStorage.saveLogo(data: pngData, teamId: teamId)
    }

    func updateLiveActivity(lastEvent: String? = nil) {
        guard let match, let matchId = match.id else { return }

        let activity = Activity<MatchActivityAttributes>.activities.first {
            $0.attributes.matchId == matchId
        }
        guard let activity else { return }

        let state = MatchActivityAttributes.ContentState(
            team1Goals: match.team1Goals,
            team2Goals: match.team2Goals,
            elapsedMinutes: currentMinute,
            lastEvent: lastEvent,
            isFinished: false
        )

        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    func endLiveActivity() {
        guard let match, let matchId = match.id else { return }

        let activity = Activity<MatchActivityAttributes>.activities.first {
            $0.attributes.matchId == matchId
        }
        guard let activity else { return }

        let finalState = MatchActivityAttributes.ContentState(
            team1Goals: match.team1Goals,
            team2Goals: match.team2Goals,
            elapsedMinutes: currentMinute,
            lastEvent: nil,
            isFinished: true
        )

        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .after(.now + 300))
        }
    }

    // MARK: - Match State

    func startMatch(appState: AppState) async {
        guard let matchId = match?.id else { return }
        do {
            try await appState.firestoreService.setMatchStarted(matchId, started: true)
            TournamentHaptics.success()
            startLiveActivity()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endMatch(appState: AppState) async {
        guard let match, let matchId = match.id else { return }
        do {
            try await appState.firestoreService.setMatchPlayed(matchId, played: true)
            TournamentHaptics.success()
            endLiveActivity()

            // Auto-generate/update knockout matches
            await handleKnockoutProgression(match: match, appState: appState)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleKnockoutProgression(match: Match, appState: AppState) async {
        let edition = match.edizione
        let format = TournamentEditionFormat.format(
            for: edition,
            tournamentId: appState.currentTournamentId,
            teamCount: appState.editionTeams.count
        )
        guard format.hasKnockout else { return }

        let allMatches = appState.allMatches.filter { $0.edizione == edition }
        let standings = appState.standings(for: edition)

        if TournamentPhaseKey.isGroupStage(match.fase) {
            // Check if all group stage matches are done
            let groupMatches = allMatches.filter { TournamentPhaseKey.isGroupStage($0.fase) }
            let allGroupDone = groupMatches.allSatisfy { $0.isPlayed } && groupMatches.count >= format.groupStageMatchCount

            if allGroupDone {
                guard !standings.contains(where: { $0.tieBreakExplanation == "draw required" }) else {
                    errorMessage = "Spareggio manuale richiesto prima di generare la fase finale."
                    return
                }
                let hadKnockoutMatches = allMatches.contains { TournamentPhaseKey.isKnockout($0.fase) }
                do {
                    try await appState.firestoreService.generateKnockoutMatches(
                        edition: edition,
                        standings: standings,
                        format: format,
                        existingMatches: allMatches
                    )
                    feedbackMessage = "Fase a eliminazione generata!"
                    if !hadKnockoutMatches {
                        try? await appState.cloudFunctionsService.sendTestNotification(
                            uid: nil,
                            broadcast: true,
                            title: "Torneo Multipalo",
                            body: "Accoppiamenti fase finale creati, entra a vederli."
                        )
                    }
                } catch {
                    errorMessage = "Errore generazione fasi finali: \(error.localizedDescription)"
                }
            }
        } else if TournamentPhaseKey.isKnockout(match.fase) {
            // A knockout match just ended - update next round teams
            do {
                // Re-fetch latest matches to include the one just ended
                let updatedMatches = try await appState.firestoreService.fetchAllMatches()
                try await appState.firestoreService.updateKnockoutAdvancement(
                    edition: edition,
                    standings: standings,
                    format: format,
                    allMatches: updatedMatches
                )
            } catch {
                // Non-blocking
            }
        }
    }

    // MARK: - Event Actions

    func selectPlayer(_ player: Player, teamId: String) {
        selectedPlayer = player
        selectedTeamId = teamId
        showEventSheet = true
        TournamentHaptics.selection()
    }

    func addEvent(type: String, appState: AppState, missOutcome: PenaltyMiss.Outcome? = nil) async {
        guard !isLoading, type != "rigore_sbagliato" || missOutcome != nil else { return }
        guard let match, let matchId = match.id,
              let player = selectedPlayer,
              let teamId = selectedTeamId else { return }

        if MatchSuspensionSupport.isPlayerSuspended(
            playerId: player.firestoreIdentifier ?? player.playerAuthUid,
            playerName: player.nomeCompleto,
            teamId: teamId,
            in: match,
            within: appState.allMatches
        ) {
            errorMessage = "Giocatore squalificato per questa partita: evento bloccato."
            showEventSheet = false
            return
        }

        let minute = currentMinute
        let event = MatchEvent(
            tipo: type,
            giocatoreId: player.firestoreIdentifier,
            giocatoreNome: player.nomeCompleto,
            squadraId: teamId,
            minuto: minute > 0 ? minute : nil,
            penaltyMiss: type == "rigore_sbagliato" ? missOutcome.map {
                match.penaltyMiss(outcome: $0, kickingTeamId: teamId, players: team1Players + team2Players)
            } : nil
        )

        showEventSheet = false
        isLoading = true
        defer { isLoading = false }

        do {
            try await appState.firestoreService.addMatchEvent(matchId: matchId, event: event)
            lastAddedEvent = event
            let feedbackLabel = eventLabel(type)
            showFeedback(feedbackLabel, minute: minute, playerName: player.nomeCompleto)
            let eventDesc = minute > 0 ? "\(feedbackLabel) - \(player.nomeCompleto) \(minute)'" : "\(feedbackLabel) - \(player.nomeCompleto)"
            updateLiveActivity(lastEvent: eventDesc)
            TournamentHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func undoLastEvent(appState: AppState) async {
        guard let match, let matchId = match.id, lastAddedEvent != nil else { return }
        var eventi = match.safeEventi
        guard !eventi.isEmpty else { return }
        eventi.removeLast()

        do {
            try await appState.firestoreService.setEventi(matchId: matchId, eventi: eventi)
            lastAddedEvent = nil
            showUndoToast = false
            showFeedback("Evento annullato", minute: nil, playerName: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Goalkeeper

    func openGoalkeeperChange(teamId: String) {
        goalkeeperTeamId = teamId
        showGoalkeeperSheet = true
    }

    func setGoalkeeper(player: Player, appState: AppState) async {
        guard let match, let matchId = match.id,
              let teamId = goalkeeperTeamId,
              let playerId = player.firestoreIdentifier else { return }

        let minute = currentMinute
        var timeline = match.goalkeeperTimeline ?? []
        timeline.append(Match.GoalkeeperTimelineEntry(
            playerId: playerId,
            playerName: player.nomeCompleto,
            startMinute: max(minute, 0)
        ))

        showGoalkeeperSheet = false
        do {
            try await appState.firestoreService.updateGoalkeeperTimeline(
                matchId: matchId, timeline: timeline
            )
            let slot = teamId == match.team1 ? 1 : 2
            try await appState.firestoreService.setMatchGoalkeeper(
                matchId: matchId, slot: slot, playerId: playerId
            )
            showFeedback("Portiere: \(player.nomeCompleto)", minute: minute, playerName: nil)
            TournamentHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - MVP

    func saveMvp(player: Player, teamId: String, appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        let mvp = Match.MatchMvp(
            playerId: player.firestoreIdentifier,
            playerName: player.nomeCompleto,
            team: teamId == match.team2 ? 2 : 1
        )

        do {
            try await appState.firestoreService.setMatchMvp(matchId: matchId, mvp: mvp)
            try await appState.firestoreService.updateMatchMvpPhoto(matchId: matchId, photoURL: nil)
            mvpPhotoImage = nil
            mvpPhotoSaved = false
            mvpSaved = true
            showMvpSheet = false
            TournamentHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveBestDefender(player: Player, teamId: String, appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        let defender = Match.MatchMvp(
            playerId: player.firestoreIdentifier,
            playerName: player.nomeCompleto,
            team: teamId == match.team2 ? 2 : 1
        )

        do {
            try await appState.firestoreService.setMatchBestDefender(matchId: matchId, bestDefender: defender)
            try await appState.firestoreService.updateMatchBestDefenderPhoto(matchId: matchId, photoURL: nil)
            bestDefenderPhotoImage = nil
            bestDefenderPhotoSaved = false
            bestDefenderSaved = true
            showBestDefenderSheet = false
            TournamentHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearBestDefender(appState: AppState) async {
        guard let matchId = match?.id else { return }

        do {
            try await appState.firestoreService.setMatchBestDefender(matchId: matchId, bestDefender: nil)
            try await appState.firestoreService.updateMatchBestDefenderPhoto(matchId: matchId, photoURL: nil)
            bestDefenderPhotoImage = nil
            bestDefenderPhotoSaved = false
            bestDefenderSaved = false
            TournamentHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - MVP Photo

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
            TournamentHaptics.success()
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

    func uploadBestDefenderPhoto(appState: AppState) async {
        guard let match, let matchId = match.id, let image = bestDefenderPhotoImage else { return }
        guard let data = image.jpegData(compressionQuality: 0.75) else { return }

        isUploadingBestDefenderPhoto = true
        defer { isUploadingBestDefenderPhoto = false }

        do {
            let path = "partite/\(matchId)/bestDefender.jpg"
            let url = try await appState.storageService.uploadImage(data, path: path)
            try await appState.firestoreService.updateMatchBestDefenderPhoto(matchId: matchId, photoURL: url.absoluteString)
            bestDefenderPhotoSaved = true
            TournamentHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeBestDefenderPhoto(appState: AppState) async {
        guard let match, let matchId = match.id else { return }

        do {
            let path = "partite/\(matchId)/bestDefender.jpg"
            try? await appState.storageService.deleteImage(path: path)
            try await appState.firestoreService.updateMatchBestDefenderPhoto(matchId: matchId, photoURL: nil)
            bestDefenderPhotoImage = nil
            bestDefenderPhotoSaved = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    func playersForTeam(_ teamId: String) -> [Player] {
        guard let match else { return [] }
        if teamId == match.team1 { return team1Players }
        if teamId == match.team2 { return team2Players }
        return []
    }

    private func showFeedback(_ label: String, minute: Int?, playerName: String?) {
        var message = label
        if let minute, minute > 0 { message += " al \(minute)'" }
        if let playerName { message += " - \(playerName)" }
        feedbackMessage = message
        showUndoToast = lastAddedEvent != nil

        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.feedbackMessage = nil
                self?.showUndoToast = false
            }
        }
    }

    private func eventLabel(_ type: String) -> String {
        switch type {
        case "gol": return "Gol registrato"
        case "rigore_segnato": return "Rigore segnato"
        case "rigore_sbagliato": return "Rigore sbagliato"
        case "autogol": return "Autogol registrato"
        case "ammonizione": return "Ammonizione"
        case "espulsione": return "Espulsione"
        default: return "Evento registrato"
        }
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
}

// MARK: - Live Match Admin View

struct LiveMatchAdminView: View {
    let match: Match

    @Environment(AppState.self) private var appState
    @State private var viewModel = LiveMatchAdminViewModel()
    @State private var showPenaltyMissChoice = false

    private var currentMatch: Match { viewModel.match ?? match }

    private var resolvedTeams: (team1: AppState.ResolvedTeamInfo, team2: AppState.ResolvedTeamInfo) {
        appState.resolvedTeams(for: currentMatch)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            liveContent
        }
        .background(TournamentPalette.backgroundTop)
        .navigationTitle("Live Admin")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.openScheduleEditor()
                } label: {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(TournamentPalette.accent)
                }
                .accessibilityLabel("Modifica orario e campo")
            }

            if currentMatch.isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.openScheduleEditor()
                        } label: {
                            Label("Modifica orario / campo", systemImage: "calendar.badge.clock")
                        }
                        Divider()
                        Button {
                            viewModel.openGoalkeeperChange(teamId: currentMatch.team1)
                        } label: {
                            Label("Cambia portiere \(resolvedTeams.team1.name)", systemImage: "person.badge.shield.checkmark")
                        }
                        Button {
                            viewModel.openGoalkeeperChange(teamId: currentMatch.team2)
                        } label: {
                            Label("Cambia portiere \(resolvedTeams.team2.name)", systemImage: "person.badge.shield.checkmark")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task { await viewModel.endMatch(appState: appState) }
                        } label: {
                            Label("Termina partita", systemImage: "flag.checkered")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .foregroundStyle(TournamentPalette.accent)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showEventSheet },
            set: { viewModel.showEventSheet = $0 }
        )) {
            eventActionSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showGoalkeeperSheet },
            set: { viewModel.showGoalkeeperSheet = $0 }
        )) {
            goalkeeperSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showScheduleSheet },
            set: { viewModel.showScheduleSheet = $0 }
        )) {
            scheduleSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMvpSheet },
            set: { viewModel.showMvpSheet = $0 }
        )) {
            mvpSheet
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showBestDefenderSheet },
            set: { viewModel.showBestDefenderSheet = $0 }
        )) {
            bestDefenderSheet
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
            get: { viewModel.showBestDefenderPhotoPicker },
            set: { viewModel.showBestDefenderPhotoPicker = $0 }
        )) {
            ImagePicker(
                image: Binding(
                    get: { viewModel.bestDefenderPhotoImage },
                    set: { newImage in
                        viewModel.bestDefenderPhotoImage = newImage
                        viewModel.bestDefenderPhotoSaved = false
                        if newImage != nil {
                            Task { await viewModel.uploadBestDefenderPhoto(appState: appState) }
                        }
                    }
                ),
                sourceType: viewModel.bestDefenderPhotoSourceType
            )
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showMvpShareSheet },
            set: { viewModel.showMvpShareSheet = $0 }
        )) {
            if let mvp = currentMatch.mvp {
                AwardStoryShareView(
                    kind: .mvp,
                    playerName: mvp.playerName ?? "",
                    teamName: mvp.team == 2 ? resolvedTeams.team2.name : resolvedTeams.team1.name,
                    playerPhotoURL: mvp.mvpPhotoURL,
                    teamLogoURL: mvp.team == 2 ? resolvedTeams.team2.logo : resolvedTeams.team1.logo
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showBestDefenderShareSheet },
            set: { viewModel.showBestDefenderShareSheet = $0 }
        )) {
            if let defender = currentMatch.bestDefender {
                AwardStoryShareView(
                    kind: .bestDefender,
                    playerName: defender.playerName ?? "",
                    teamName: defender.team == 2 ? resolvedTeams.team2.name : resolvedTeams.team1.name,
                    playerPhotoURL: defender.mvpPhotoURL,
                    teamLogoURL: defender.team == 2 ? resolvedTeams.team2.logo : resolvedTeams.team1.logo
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
        .onAppear {
            viewModel.start(match: match, appState: appState)
            if match.isLive {
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    viewModel.startLiveActivity()
                    viewModel.startLiveActivityTimer()
                }
            }
        }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Live Content

    private var liveContent: some View {
        VStack(spacing: 0) {
            // Score header
            liveScoreHeader

            // Timer bar
            if currentMatch.isLive {
                timerBar
            }

            // Live Activity status
            if let status = viewModel.liveActivityStatus {
                Text(status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(status.contains("Errore") || status.contains("disabilitate")
                        ? TournamentPalette.danger : TournamentPalette.success)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

            // Feedback toast
            if let message = viewModel.feedbackMessage {
                feedbackToast(message)
            }

            // Match state controls
            if !currentMatch.isStarted {
                startMatchButton
            } else if currentMatch.isLive {
                playerColumns
            } else if currentMatch.isPlayed {
                matchEndedView
            }
        }
    }

    // MARK: - Score Header

    private var liveScoreHeader: some View {
        VStack(spacing: 4) {
            // Scheduled start time (small, above score)
            if let time = viewModel.scheduledTime {
                Text("Inizio: \(time)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    TournamentTeamLogo(urlString: resolvedTeams.team1.logo, size: 36)
                    Text(resolvedTeams.team1.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    Text("\(currentMatch.team1Goals)")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(TournamentPalette.accent)

                    Text("-")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)

                Text("\(currentMatch.team2Goals)")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(TournamentPalette.accent)
            }

                VStack(spacing: 4) {
                    TournamentTeamLogo(urlString: resolvedTeams.team2.logo, size: 36)
                    Text(resolvedTeams.team2.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }

            // Elapsed timer (below score)
            if currentMatch.isLive {
                Text(viewModel.elapsedTimerString)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(TournamentPalette.success)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TournamentPalette.surfaceStrong)
    }

    // MARK: - Timer Bar

    private var timerBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Text("LIVE")
                .font(.caption2.weight(.black))
                .foregroundStyle(.red)

            if viewModel.currentMinute > 0 {
                Text("\(viewModel.currentMinute)'")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
            }

            Spacer()

            Text("Tocca un giocatore per registrare un evento")
                .font(.caption2)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(TournamentPalette.warm.opacity(0.1))
    }

    private var scheduleSheet: some View {
        NavigationStack {
            Form {
                Section("Programmazione partita") {
                    TextField("Campo", text: Binding(
                        get: { viewModel.scheduledCampo },
                        set: { viewModel.scheduledCampo = $0 }
                    ))

                    TextField("Orario", text: Binding(
                        get: { viewModel.scheduledTimeDraft },
                        set: { viewModel.scheduledTimeDraft = $0 }
                    ))
                    .keyboardType(.numbersAndPunctuation)
                }
            }
            .navigationTitle("Orario e campo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") {
                        viewModel.showScheduleSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        Task { await viewModel.saveSchedule(appState: appState) }
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Player Columns

    private var playerColumns: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                // Team 1 - Left column
                playerColumn(
                    players: viewModel.team1Players,
                    teamId: currentMatch.team1,
                    teamName: resolvedTeams.team1.name,
                    alignment: .leading
                )
                .frame(width: geo.size.width / 2)

                // Team 2 - Right column
                playerColumn(
                    players: viewModel.team2Players,
                    teamId: currentMatch.team2,
                    teamName: resolvedTeams.team2.name,
                    alignment: .trailing
                )
                .frame(width: geo.size.width / 2)
            }
        }
    }

    private func playerColumn(players: [Player], teamId: String, teamName: String, alignment: HorizontalAlignment) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(players, id: \.stableRosterKey) { player in
                    playerRow(player: player, teamId: teamId, alignment: alignment)
                }
            }
        }
        .background(TournamentPalette.surfaceStrong.opacity(0.5))
    }

    private func playerRow(player: Player, teamId: String, alignment: HorizontalAlignment) -> some View {
        let isSuspended = isPlayerSuspended(player, teamId: teamId)

        return VStack(spacing: 0) {
            Button {
                viewModel.selectPlayer(player, teamId: teamId)
            } label: {
                HStack(spacing: 8) {
                    if alignment == .trailing { Spacer(minLength: 4) }

                    if alignment == .leading {
                        numberBadge(player.numeroMaglia)
                        playerInfo(player, teamId: teamId, alignment: .leading)
                        Spacer(minLength: 4)
                        playerEventIcons(player, teamId: teamId)
                    } else {
                        playerEventIcons(player, teamId: teamId)
                        Spacer(minLength: 4)
                        playerInfo(player, teamId: teamId, alignment: .trailing)
                        numberBadge(player.numeroMaglia)
                    }

                    if alignment == .leading { Spacer(minLength: 4) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(TournamentPalette.surfaceStrong)
                .opacity(isSuspended ? 0.48 : 1)
            }
            .buttonStyle(.tournamentPress)
            .disabled(isSuspended)

            Divider().padding(.horizontal, 8)
        }
    }

    private func numberBadge(_ number: Int?) -> some View {
        Text(number.map(String.init) ?? "-")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(TournamentPalette.accent)
            .frame(width: 26, height: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(TournamentPalette.accentSoft)
            )
    }

    private func playerInfo(_ player: Player, teamId: String, alignment: HorizontalAlignment) -> some View {
        let isSuspended = isPlayerSuspended(player, teamId: teamId)

        return VStack(alignment: alignment == .leading ? .leading : .trailing, spacing: 1) {
            Text(player.nomeCompleto)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
                .strikethrough(isSuspended, color: TournamentPalette.danger)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func playerEventIcons(_ player: Player, teamId: String) -> some View {
        let events = currentMatch.safeEventi.flatMap { event in
            [event] + (event.penaltySaveEvent.map { [$0] } ?? [])
        }.filter { player.matches(event: $0) }
        if !events.isEmpty {
            // Nelle due rose affiancate una lunga fila di eventi toglierebbe
            // spazio al nome: dopo tre icone si va a capo.
            let columns = min(events.count, 3)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 2), count: columns), spacing: 2) {
                ForEach(events) { event in
                    MatchEventTypeIcon(type: event.tipo, doubleYellow: event.doubleYellow == true, size: 18)
                }
            }
            .frame(width: CGFloat(columns * 20 - 2))
        }
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

    // MARK: - Start / End

    private var startMatchButton: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(TournamentPalette.success)

            Text("Partita non ancora iniziata")
                .font(.headline)
                .foregroundStyle(TournamentPalette.ink)

            Button {
                Task { await viewModel.startMatch(appState: appState) }
            } label: {
                Text("Avvia Partita")
                    .tournamentButtonChrome(.primary, fullWidth: false)
            }
            .buttonStyle(.tournamentPress)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var matchEndedView: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 20)

                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(TournamentPalette.success)

                Text("Partita terminata")
                    .font(.headline)
                    .foregroundStyle(TournamentPalette.ink)

                Text("\(currentMatch.team1Goals) - \(currentMatch.team2Goals)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(TournamentPalette.accent)

                if currentMatch.team1Goals == currentMatch.team2Goals && currentMatch.penaltyWinner == nil {
                    NavigationLink(destination: PenaltyShootoutView(match: currentMatch)) {
                        Text(appState.shootoutTerminology(for: currentMatch).callToAction)
                            .tournamentButtonChrome(.primary, fullWidth: false)
                    }
                    .buttonStyle(.tournamentPress)
                }

                Divider().padding(.horizontal, 32)

                VStack(spacing: 14) {
                    Text("Premi partita")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)

                    HStack(alignment: .top, spacing: 10) {
                        awardEditorCard(
                            title: "MVP della partita",
                            systemImage: "star.fill",
                            tint: TournamentPalette.warm,
                            selection: currentMatch.mvp,
                            teamName: currentMatch.mvp?.team == 2 ? resolvedTeams.team2.name : resolvedTeams.team1.name,
                            teamLogoURL: currentMatch.mvp?.team == 2 ? resolvedTeams.team2.logo : resolvedTeams.team1.logo,
                            pickedImage: viewModel.mvpPhotoImage,
                            existingPhotoURL: currentMatch.mvp?.mvpPhotoURL,
                            isSaved: viewModel.mvpSaved,
                            photoSaved: viewModel.mvpPhotoSaved,
                            isUploadingPhoto: viewModel.isUploadingMvpPhoto,
                            onChoose: { viewModel.showMvpSheet = true },
                            onCamera: {
                                viewModel.mvpPhotoSourceType = .camera
                                viewModel.showMvpPhotoPicker = true
                            },
                            onGallery: {
                                viewModel.mvpPhotoSourceType = .photoLibrary
                                viewModel.showMvpPhotoPicker = true
                            },
                            onRemovePhoto: {
                                Task { await viewModel.removeMvpPhoto(appState: appState) }
                            },
                            onRemoveAward: nil
                        )

                        awardEditorCard(
                            title: "Miglior difensore",
                            systemImage: "shield.lefthalf.filled",
                            tint: TournamentPalette.accent,
                            selection: currentMatch.bestDefender,
                            teamName: currentMatch.bestDefender?.team == 2 ? resolvedTeams.team2.name : resolvedTeams.team1.name,
                            teamLogoURL: currentMatch.bestDefender?.team == 2 ? resolvedTeams.team2.logo : resolvedTeams.team1.logo,
                            pickedImage: viewModel.bestDefenderPhotoImage,
                            existingPhotoURL: currentMatch.bestDefender?.mvpPhotoURL,
                            isSaved: viewModel.bestDefenderSaved,
                            photoSaved: viewModel.bestDefenderPhotoSaved,
                            isUploadingPhoto: viewModel.isUploadingBestDefenderPhoto,
                            onChoose: { viewModel.showBestDefenderSheet = true },
                            onCamera: {
                                viewModel.bestDefenderPhotoSourceType = .camera
                                viewModel.showBestDefenderPhotoPicker = true
                            },
                            onGallery: {
                                viewModel.bestDefenderPhotoSourceType = .photoLibrary
                                viewModel.showBestDefenderPhotoPicker = true
                            },
                            onRemovePhoto: {
                                Task { await viewModel.removeBestDefenderPhoto(appState: appState) }
                            },
                            onRemoveAward: {
                                Task { await viewModel.clearBestDefender(appState: appState) }
                            }
                        )
                    }

                    NavigationLink(destination: AdminMatchDetailView(match: currentMatch)) {
                        Label("Modifica eventi / risultato", systemImage: "pencil.circle")
                            .tournamentButtonChrome(.neutral, fullWidth: false)
                    }
                    .buttonStyle(.tournamentPress)
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Event Action Sheet

    private var eventActionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let player = viewModel.selectedPlayer {
                        HStack(spacing: 12) {
                            numberBadge(player.numeroMaglia)
                            Text(player.nomeCompleto)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(TournamentPalette.ink)
                            Spacer()
                            if viewModel.currentMinute > 0 {
                                TournamentPill(label: "\(viewModel.currentMinute)'", tone: .neutral)
                            }
                        }
                        .padding(16)
                        .background(TournamentPalette.surfaceMuted)
                    }

                    eventButton(label: "Gol", type: "gol")
                    eventButton(label: "Rigore segnato", type: "rigore_segnato")
                    eventButton(label: "Rigore sbagliato", type: "rigore_sbagliato")
                    eventButton(label: "Autogol", type: "autogol")

                    Divider().padding(.horizontal, 16)

                    eventButton(label: "Ammonizione", type: "ammonizione")
                    eventButton(label: "Espulsione", type: "espulsione")
                }
            }
            .navigationTitle("Azione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.showEventSheet = false }
                }
            }
        }
        .penaltyMissConfirmation(isPresented: $showPenaltyMissChoice) { outcome in
            Task { await viewModel.addEvent(type: "rigore_sbagliato", appState: appState, missOutcome: outcome) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func eventButton(label: String, type: String) -> some View {
        Button {
            if type == "rigore_sbagliato" {
                showPenaltyMissChoice = true
            } else {
                Task { await viewModel.addEvent(type: type, appState: appState) }
            }
        } label: {
            HStack(spacing: 14) {
                MatchEventTypeIcon(type: type, size: 32)
                    .accessibilityHidden(true)
                    .frame(width: 36)

                Text(label)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.tournamentPress)
    }

    // MARK: - Goalkeeper Sheet

    private var goalkeeperSheet: some View {
        NavigationStack {
            let teamId = viewModel.goalkeeperTeamId ?? ""
            let players = viewModel.playersForTeam(teamId)
            let teamName = teamId == currentMatch.team1
                ? resolvedTeams.team1.name
                : resolvedTeams.team2.name

            List {
                Section("Seleziona portiere per \(teamName)") {
                    ForEach(players, id: \.stableRosterKey) { player in
                        Button {
                            Task { await viewModel.setGoalkeeper(player: player, appState: appState) }
                        } label: {
                            HStack(spacing: 12) {
                                numberBadge(player.numeroMaglia)
                                Text(player.nomeCompleto)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(TournamentPalette.ink)
                                Spacer()
                            }
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
            }
            .navigationTitle("Cambia portiere")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.showGoalkeeperSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - MVP Sheet

    private var mvpSheet: some View {
        NavigationStack {
            List {
                Section(resolvedTeams.team1.name) {
                    ForEach(viewModel.team1Players, id: \.stableRosterKey) { player in
                        Button {
                            Task { await viewModel.saveMvp(player: player, teamId: currentMatch.team1, appState: appState) }
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(
                                    urlString: player.displayPhotoURL,
                                    placeholderIcon: "person.fill",
                                    placeholderColor: TournamentPalette.warm.opacity(0.12),
                                    contentAlignment: .top
                                )
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                numberBadge(player.numeroMaglia)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.nomeCompleto)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(TournamentPalette.ink)
                                    Text(resolvedTeams.team1.name)
                                        .font(.caption)
                                        .foregroundStyle(TournamentPalette.inkMuted)
                                }
                                Spacer()
                                if currentMatch.mvp?.playerId == player.firestoreIdentifier {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(TournamentPalette.warm)
                                }
                            }
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }

                Section(resolvedTeams.team2.name) {
                    ForEach(viewModel.team2Players, id: \.stableRosterKey) { player in
                        Button {
                            Task { await viewModel.saveMvp(player: player, teamId: currentMatch.team2, appState: appState) }
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(
                                    urlString: player.displayPhotoURL,
                                    placeholderIcon: "person.fill",
                                    placeholderColor: TournamentPalette.warm.opacity(0.12),
                                    contentAlignment: .top
                                )
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                numberBadge(player.numeroMaglia)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.nomeCompleto)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(TournamentPalette.ink)
                                    Text(resolvedTeams.team2.name)
                                        .font(.caption)
                                        .foregroundStyle(TournamentPalette.inkMuted)
                                }
                                Spacer()
                                if currentMatch.mvp?.playerId == player.firestoreIdentifier {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(TournamentPalette.warm)
                                }
                            }
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
            }
            .navigationTitle("Seleziona MVP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.showMvpSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var bestDefenderSheet: some View {
        NavigationStack {
            List {
                Section(resolvedTeams.team1.name) {
                    ForEach(viewModel.team1Players, id: \.stableRosterKey) { player in
                        Button {
                            Task { await viewModel.saveBestDefender(player: player, teamId: currentMatch.team1, appState: appState) }
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(
                                    urlString: player.displayPhotoURL,
                                    placeholderIcon: "person.fill",
                                    placeholderColor: TournamentPalette.accent.opacity(0.12),
                                    contentAlignment: .top
                                )
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                numberBadge(player.numeroMaglia)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.nomeCompleto)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(TournamentPalette.ink)
                                    Text(resolvedTeams.team1.name)
                                        .font(.caption)
                                        .foregroundStyle(TournamentPalette.inkMuted)
                                }
                                Spacer()
                                if currentMatch.bestDefender?.playerId == player.firestoreIdentifier {
                                    Image(systemName: "shield.lefthalf.filled")
                                        .foregroundStyle(TournamentPalette.accent)
                                }
                            }
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }

                Section(resolvedTeams.team2.name) {
                    ForEach(viewModel.team2Players, id: \.stableRosterKey) { player in
                        Button {
                            Task { await viewModel.saveBestDefender(player: player, teamId: currentMatch.team2, appState: appState) }
                        } label: {
                            HStack(spacing: 12) {
                                CachedAsyncImage(
                                    urlString: player.displayPhotoURL,
                                    placeholderIcon: "person.fill",
                                    placeholderColor: TournamentPalette.accent.opacity(0.12),
                                    contentAlignment: .top
                                )
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                                numberBadge(player.numeroMaglia)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.nomeCompleto)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(TournamentPalette.ink)
                                    Text(resolvedTeams.team2.name)
                                        .font(.caption)
                                        .foregroundStyle(TournamentPalette.inkMuted)
                                }
                                Spacer()
                                if currentMatch.bestDefender?.playerId == player.firestoreIdentifier {
                                    Image(systemName: "shield.lefthalf.filled")
                                        .foregroundStyle(TournamentPalette.accent)
                                }
                            }
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
            }
            .navigationTitle("Miglior difensore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { viewModel.showBestDefenderSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func awardEditorCard(
        title: String,
        systemImage: String,
        tint: Color,
        selection: Match.MatchMvp?,
        teamName: String,
        teamLogoURL: String?,
        pickedImage: UIImage?,
        existingPhotoURL: String?,
        isSaved: Bool,
        photoSaved: Bool,
        isUploadingPhoto: Bool,
        onChoose: @escaping () -> Void,
        onCamera: @escaping () -> Void,
        onGallery: @escaping () -> Void,
        onRemovePhoto: @escaping () -> Void,
        onRemoveAward: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            ZStack(alignment: .topTrailing) {
                Group {
                    if let pickedImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFill()
                    } else if let existingPhotoURL, !existingPhotoURL.isEmpty {
                        CachedAsyncImage(
                            urlString: existingPhotoURL,
                            placeholderIcon: systemImage,
                            placeholderColor: tint,
                            contentMode: .fill
                        )
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [tint.opacity(0.18), TournamentPalette.surfaceStrong],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: systemImage)
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(tint)
                        }
                    }
                }
                .frame(height: 132)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                TournamentTeamLogo(urlString: teamLogoURL, size: 26, placeholderTint: tint)
                    .background(Circle().fill(TournamentPalette.backgroundTop))
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(selection?.playerName?.isEmpty == false ? (selection?.playerName ?? "") : "Nessun giocatore selezionato")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(2)

                Text(selection != nil ? teamName : "Scegli il giocatore e aggiungi una foto se serve.")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .lineLimit(2)

                if isSaved || photoSaved {
                    Text("Aggiornato")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TournamentPalette.success)
                } else if isUploadingPhoto {
                    Text("Caricamento foto...")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }

            VStack(spacing: 8) {
                Button(action: onChoose) {
                    Label(selection != nil ? "Cambia giocatore" : "Scegli giocatore", systemImage: "checkmark.circle")
                        .tournamentButtonChrome(.secondary, fullWidth: true)
                }
                .buttonStyle(.tournamentPress)

                if selection != nil {
                    HStack(spacing: 8) {
                        Button(action: onCamera) {
                            Image(systemName: "camera.fill")
                                .frame(maxWidth: .infinity)
                                .tournamentButtonChrome(.neutral, fullWidth: true)
                        }
                        .buttonStyle(.tournamentPress)

                        Button(action: onGallery) {
                            Image(systemName: "photo.on.rectangle")
                                .frame(maxWidth: .infinity)
                                .tournamentButtonChrome(.neutral, fullWidth: true)
                        }
                        .buttonStyle(.tournamentPress)

                        if pickedImage != nil || (existingPhotoURL?.isEmpty == false) {
                            Button(role: .destructive, action: onRemovePhoto) {
                                Image(systemName: "trash")
                                    .frame(maxWidth: .infinity)
                                    .tournamentButtonChrome(.neutral, fullWidth: true)
                            }
                            .buttonStyle(.tournamentPress)
                        }
                    }

                    if let onRemoveAward {
                        Button(role: .destructive, action: onRemoveAward) {
                            Label("Rimuovi", systemImage: "trash")
                                .tournamentButtonChrome(.neutral, fullWidth: true)
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TournamentPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }

    // MARK: - Feedback Toast

    private func feedbackToast(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TournamentPalette.success)
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
            Spacer()
            if viewModel.showUndoToast {
                Button("Annulla") {
                    Task { await viewModel.undoLastEvent(appState: appState) }
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.danger)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(TournamentPalette.success.opacity(0.12))
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.25), value: message)
    }

    // MARK: - MVP Photo Buttons

    private var mvpPhotoButtons: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.mvpPhotoSourceType = .camera
                viewModel.showMvpPhotoPicker = true
            } label: {
                Label("Scatta foto", systemImage: "camera.fill")
                    .tournamentButtonChrome(.secondary, fullWidth: false)
            }
            .buttonStyle(.tournamentPress)

            Button {
                viewModel.mvpPhotoSourceType = .photoLibrary
                viewModel.showMvpPhotoPicker = true
            } label: {
                Label("Galleria", systemImage: "photo.on.rectangle")
                    .tournamentButtonChrome(.secondary, fullWidth: false)
            }
            .buttonStyle(.tournamentPress)
        }
    }

}

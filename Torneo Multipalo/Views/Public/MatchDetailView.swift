import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

private struct FormationShareContext: Identifiable {
    let id: String
    let teamName: String
    let teamLogoURL: String?
    let players: [Player]
    let primaryHex: String
    let secondaryHex: String
}

private struct AwardShareContext: Identifiable {
    let id: String
    let kind: MatchAwardShareKind
    let playerName: String
    let teamName: String
    let playerPhotoURL: String?
    let teamLogoURL: String?
}

// MARK: - ViewModel

@Observable
@MainActor
final class MatchDetailViewModel {
    var match: Match?
    var team1Players: [Player] = []
    var team2Players: [Player] = []
    var allPlayers: [Player] = []
    var isLoading = true

    private let matchListener = FirestoreListenerToken()

    func start(match initialMatch: Match, firestoreService: FirestoreService) {
        self.match = initialMatch
        isLoading = false

        guard let matchId = initialMatch.id else { return }
        matchListener.replace(with: firestoreService.listenToMatch(matchId: matchId) { [weak self] updated in
            Task { @MainActor [weak self, updated] in
                if let m = updated { self?.match = m }
            }
        })

        Task {
            async let p1 = firestoreService.fetchPlayers(teamId: initialMatch.team1)
            async let p2 = firestoreService.fetchPlayers(teamId: initialMatch.team2)
            let all1 = (try? await p1)?.sorted { ($0.numeroMaglia ?? 99) < ($1.numeroMaglia ?? 99) } ?? []
            let all2 = (try? await p2)?.sorted { ($0.numeroMaglia ?? 99) < ($1.numeroMaglia ?? 99) } ?? []
            team1Players = all1
            team2Players = all2
            allPlayers = all1 + all2
        }
    }

    func stop() { matchListener.cancel() }

    // Giocatori in formazione: usa team1Formation/team2Formation se disponibili, altrimenti fallback rosa
    var team1FormationPlayers: [Player] {
        guard let m = match, let formation = m.team1Formation, !formation.isEmpty else {
            return team1Players
        }
        return formation.compactMap { fId in
            allPlayers.first { $0.id == fId || $0.playerAuthUid == fId }
        }
    }

    var team2FormationPlayers: [Player] {
        guard let m = match, let formation = m.team2Formation, !formation.isEmpty else {
            return team2Players
        }
        return formation.compactMap { fId in
            allPlayers.first { $0.id == fId || $0.playerAuthUid == fId }
        }
    }

    // MVP: usa admin MVP se presente, altrimenti calcola
    var mvpInfo: (nome: String, gol: Int)? {
        guard let m = match else { return nil }
        // Admin-selected MVP
        if let adminMvp = m.mvp, let name = adminMvp.playerName, !name.isEmpty {
            let normalizedName = Player.normalizedLookupName(from: name)
            let golCount = m.safeEventi.filter {
                guard ["gol", "rigore_segnato", "punizione_segnata"].contains($0.tipo) else { return false }
                if let playerId = adminMvp.playerId, !playerId.isEmpty, $0.giocatoreId == playerId {
                    return true
                }
                return normalizedName != nil && Player.normalizedLookupName(from: $0.giocatoreNome) == normalizedName
            }.count
            return (name, golCount)
        }
        // Calcolo automatico
        var contatoreGol: [String: (nome: String, gol: Int)] = [:]
        for evento in m.safeEventi {
            guard ["gol", "rigore_segnato", "punizione_segnata"].contains(evento.tipo),
                  let nome = evento.giocatoreNome, !nome.isEmpty else { continue }
            let key = evento.giocatoreId ?? nome
            contatoreGol[key, default: (nome, 0)].gol += 1
        }
        return contatoreGol.values.max(by: { $0.gol < $1.gol })
    }

    var bestDefenderInfo: String? {
        guard let defender = match?.bestDefender,
              let name = defender.playerName,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return name
    }
}

// MARK: - View principale

struct MatchDetailView: View {
    private struct AwardVisualInfo {
        let playerId: String?
        let playerName: String
        let teamName: String
        let photoURL: String?
        let teamLogoURL: String?
    }

    let match: Match

    @Environment(AppState.self) private var appState
    @State private var vm = MatchDetailViewModel()
    @State private var predictionsViewModel = PredictionsViewModel()
    @State private var selectedTab = 0
    @State private var isTogglingNotifications = false
    @State private var notificationErrorMessage: String?
    @State private var showAuthSheet = false
    @State private var awardShareContext: AwardShareContext?

    private let tabs = ["Cronaca", "Formazioni", "Pronostici", "Info"]

    private var isAdmin: Bool {
        appState.authService.userRole == .admin
    }

    private var hasPersistedMatchRecord: Bool {
        guard let matchId = currentMatch.id else { return false }
        return appState.matches.contains { $0.id == matchId }
    }

    private var ownerEditableTeamId: String? {
        guard case let .teamOwner(teamId) = appState.authService.userRole else {
            return nil
        }
        return [currentMatch.team1, currentMatch.team2].contains(teamId) ? teamId : nil
    }

    private var currentMatch: Match {
        vm.match ?? match
    }

    private var predictionLoadToken: String {
        let uid = appState.authService.currentUser?.uid ?? "guest"
        return "\(currentMatch.id ?? "match")-\(currentMatch.edizione)-\(uid)"
    }

    private var resolvedTeams: (team1: AppState.ResolvedTeamInfo, team2: AppState.ResolvedTeamInfo) {
        appState.resolvedTeams(for: currentMatch)
    }

    private var isFollowingMatchNotifications: Bool {
        appState.notificationService.isSubscribedToMatch(
            matchId: currentMatch.id,
            edition: currentMatch.edizione,
            teamIds: currentMatch.notificationRelevantTeamIds,
            playerIds: currentMatch.notificationRelevantPlayerIds
        )
    }

    private var matchPredictionQuestions: [PredictionQuestion] {
        guard let matchId = currentMatch.id else { return [] }
        return predictionsViewModel.questions
            .filter { $0.matchId == matchId && $0.isMatchOutcome }
            .sorted {
                ($0.sortIndex ?? Int.max) < ($1.sortIndex ?? Int.max)
            }
    }

    private var isLoggedInForPredictions: Bool {
        appState.authService.currentUser != nil
    }

    var body: some View {
        TournamentScreen {
            VStack(spacing: 0) {
                scoreHeader

                Picker("Sezione", selection: $selectedTab) {
                    ForEach(tabs.indices, id: \.self) { Text(tabs[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(10)
                .tournamentCard(padding: 0)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Group {
                    switch selectedTab {
                    case 0: cronacaTab
                    case 1: formazioniTab
                    case 2: pronosticiTab
                    default: infoTab
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(faseLabel)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if currentMatch.isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    TournamentPill(label: "LIVE", tone: .success)
                }
            }
            if hasPersistedMatchRecord {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    TournamentNotificationBellButton(
                        isActive: isFollowingMatchNotifications,
                        isBusy: isTogglingNotifications,
                        accessibilityLabel: isFollowingMatchNotifications
                            ? "Disattiva notifiche partita"
                            : "Attiva notifiche partita"
                    ) {
                        handleMatchNotificationTap()
                    }

                    if isAdmin {
                        NavigationLink(destination: LiveMatchAdminView(match: currentMatch)) {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(TournamentPalette.accent)
                        }
                    } else if let ownerEditableTeamId {
                        NavigationLink(destination: TeamMatchGoalkeeperEditorView(match: currentMatch, managedTeamId: ownerEditableTeamId)) {
                            Image(systemName: "person.text.rectangle")
                        }
                    }
                }
            }
        }
        .onAppear { vm.start(match: match, firestoreService: appState.firestoreService) }
        .onDisappear { vm.stop() }
        .task(id: predictionLoadToken) {
            await predictionsViewModel.load(
                appState: appState,
                edition: currentMatch.edizione
            )
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthRouter()
        }
        .alert("Notifiche partita", isPresented: Binding(
            get: { notificationErrorMessage != nil },
            set: { if !$0 { notificationErrorMessage = nil } }
        )) {
            if appState.notificationService.authorizationState == .denied {
                Button("Impostazioni") { openSettings() }
            }
            Button("OK", role: .cancel) {
                notificationErrorMessage = nil
            }
        } message: {
            Text(notificationErrorMessage ?? "")
        }
    }

    private var faseLabel: String {
        let m = currentMatch
        if TournamentPhaseKey.isGroupStage(m.fase) {
            return "Giornata \(m.giornata)"
        }
        return TournamentPhaseKey.displayName(m.fase)
    }

    // MARK: - Header punteggio

    @ViewBuilder
    private var scoreHeader: some View {
        let m = currentMatch
        let resolved = resolvedTeams

        let headerContent = VStack(spacing: 12) {
            // Top row: phase + campo + status
            HStack(spacing: 8) {
                TournamentPill(label: faseLabel, tone: .accent)
                if let campo = m.campo, !campo.isEmpty {
                    TournamentPill(label: "Campo \(campo)", tone: .neutral)
                }
                Spacer()
                TournamentPill(label: stateLabel, tone: stateTone)
            }

            // Scheduled time
            if let time = m.matchTime, !time.isEmpty, !m.isLive {
                Text(time)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            // Score area
            HStack(spacing: 0) {
                teamHeaderColumn(
                    name: resolved.team1.name,
                    url: resolved.team1.logo,
                    teamId: currentMatch.team1
                )

                VStack(spacing: 6) {
                    if (m.isPlayed || m.isStarted) && m.hasKnownScore {
                        HStack(spacing: 8) {
                            scoreDigit("\(m.team1Goals)")
                            Text("–")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(TournamentPalette.inkMuted)
                            scoreDigit("\(m.team2Goals)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    m.isLive
                                        ? TournamentPalette.success.opacity(0.12)
                                        : TournamentPalette.surfaceMuted
                                )
                        )
                        .animation(.default, value: m.team1Goals)
                        .animation(.default, value: m.team2Goals)

                        // Live timer
                        if m.isLive, let elapsed = m.elapsedMinute, elapsed > 0 {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 6, height: 6)
                                Text("\(elapsed)'")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(TournamentPalette.success)
                            }
                        }
                    } else if m.isPlayed || m.isStarted {
                        Text("Risultato non disponibile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(TournamentPalette.surfaceMuted)
                            )
                    } else {
                        Text("VS")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(TournamentPalette.ink)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(TournamentPalette.surfaceMuted)
                            )
                    }
                }
                .frame(minWidth: 100)

                teamHeaderColumn(
                    name: resolved.team2.name,
                    url: resolved.team2.logo,
                    teamId: currentMatch.team2
                )
            }
        }
        .tournamentCard(padding: 20)
        .padding(.horizontal, 16)
        .padding(.top, 16)

        if m.isLive {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                headerContent
            }
        } else {
            headerContent
        }
    }

    private func toggleMatchNotifications() async {
        guard !isTogglingNotifications else { return }
        isTogglingNotifications = true
        defer { isTogglingNotifications = false }

        do {
            let shouldEnable = !isFollowingMatchNotifications
            _ = try await appState.notificationService.setMatchSubscription(
                enabled: shouldEnable,
                matchId: currentMatch.id,
                edition: currentMatch.edizione,
                teamIds: currentMatch.notificationRelevantTeamIds,
                playerIds: currentMatch.notificationRelevantPlayerIds,
                cloudFunctionsService: appState.cloudFunctionsService
            )
        } catch {
            notificationErrorMessage = error.localizedDescription
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func handleMatchNotificationTap() {
        Task { await toggleMatchNotifications() }
    }

    @ViewBuilder
    private func teamLogoView(url: String?) -> some View {
        TournamentTeamLogo(urlString: url, size: 48)
    }

    @ViewBuilder
    private func teamHeaderColumn(name: String, url: String?, teamId: String) -> some View {
        let content = VStack(spacing: 8) {
            teamLogoView(url: url)
            Text(name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)

        if let team = appState.editionTeam(for: teamId, edition: currentMatch.edizione) {
            NavigationLink(destination: TeamDetailView(team: team)) {
                content
            }
            .buttonStyle(.tournamentPress)
        } else {
            content
        }
    }

    private func scoreDigit(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 36, weight: .bold, design: .rounded))
            .foregroundStyle(currentMatch.isLive ? TournamentPalette.success : TournamentPalette.ink)
            .contentTransition(.numericText())
    }

    // MARK: - Tab Cronaca

    private var cronacaTab: some View {
        let m = currentMatch
        let eventi = m.safeEventi.sorted { ($0.minuto ?? 0) < ($1.minuto ?? 0) }
        let penaltyKicks = m.safePenaltyDetails.sorted { $0.order < $1.order }

        return ScrollView {
            VStack(spacing: 16) {
                if eventi.isEmpty && penaltyKicks.isEmpty && !m.isStarted && !m.isPlayed {
                    EmptyStateView(
                        icon: "clock",
                        title: "Partita non ancora iniziata",
                        message: "Gli eventi appariranno qui in tempo reale."
                    )
                } else {
                    if !eventi.isEmpty || m.isStarted || m.isPlayed {
                        VStack(alignment: .leading, spacing: 12) {
                            TournamentSectionHeader(
                                title: "Cronaca partita",
                                subtitle: "Timeline ordinata degli eventi registrati in campo."
                            )

                            if m.isStarted {
                                phaseMarker("Partita iniziata")
                            }

                            ForEach(eventi) { evento in
                                let isTeam1 = evento.squadraId == m.team1
                                cronacaLaneRow(isTeam1: isTeam1) {
                                    MatchEventRow(event: evento, isTeam1: isTeam1)
                                }
                                .padding(.vertical, 4)
                                if let save = evento.penaltySaveEvent {
                                    let keeperIsTeam1 = save.squadraId == m.team1
                                    cronacaLaneRow(isTeam1: keeperIsTeam1) {
                                        MatchEventRow(event: save, isTeam1: keeperIsTeam1)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }

                            if m.isPlayed {
                                phaseMarker("Partita terminata")
                            }
                        }
                        .tournamentCard()
                    }

                    if !penaltyKicks.isEmpty {
                        penaltyShootoutCronacaCard(kicks: penaltyKicks)
                    }

                    if m.isPlayed {
                        HStack(alignment: .top, spacing: 10) {
                            if let officialMvp = currentMatch.mvp,
                               let visual = awardVisualInfo(
                                playerId: officialMvp.playerId,
                                playerName: officialMvp.playerName,
                                explicitPhotoURL: officialMvp.mvpPhotoURL,
                                teamSlot: officialMvp.team
                               ) {
                                awardVisualCard(
                                    title: "MVP della partita",
                                    shareKind: .mvp,
                                    visual: visual,
                                    systemImage: "star.fill",
                                    tint: TournamentPalette.warm
                                )
                            } else if let mvp = vm.mvpInfo {
                                awardFallbackCard(
                                    title: "MVP della partita",
                                    systemImage: "star.fill",
                                    nome: mvp.nome,
                                    detail: mvp.gol > 0 ? "\(mvp.gol) gol" : nil,
                                    tint: TournamentPalette.warm
                                )
                            }
                            if let defender = currentMatch.bestDefender,
                               let visual = awardVisualInfo(
                                playerId: defender.playerId,
                                playerName: defender.playerName,
                                explicitPhotoURL: defender.mvpPhotoURL,
                                teamSlot: defender.team
                               ) {
                                awardVisualCard(
                                    title: "Miglior difensore",
                                    shareKind: .bestDefender,
                                    visual: visual,
                                    systemImage: "shield.lefthalf.filled",
                                    tint: TournamentPalette.accent
                                )
                            } else if let defender = vm.bestDefenderInfo {
                                awardFallbackCard(
                                    title: "Miglior difensore",
                                    systemImage: "shield.lefthalf.filled",
                                    nome: defender,
                                    detail: nil,
                                    tint: TournamentPalette.accent
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    /// Il taglio è quello nuovo della PWA: intestazione **centrata** con
    /// punteggio grande e "Passa <squadra>", poi i tiri alternati casa/ospiti.
    /// Prima era un `TournamentSectionHeader` allineato a sinistra col
    /// punteggio relegato in sottotitolo, e l'esito si leggeva male.
    private func penaltyShootoutCronacaCard(kicks: [Match.PenaltyKick]) -> some View {
        let m = currentMatch
        let terms = appState.shootoutTerminology(for: m)
        let t1Score = kicks.filter { $0.teamId == m.team1 && $0.scored }.count
        let t2Score = kicks.filter { $0.teamId == m.team2 && $0.scored }.count
        let winnerName: String? = {
            guard let winnerId = m.penaltyWinner else { return nil }
            if winnerId == m.team1 { return resolvedTeams.team1.name }
            if winnerId == m.team2 { return resolvedTeams.team2.name }
            return nil
        }()

        return VStack(spacing: 14) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "soccerball")
                    Text(terms.title.uppercased())
                        .tracking(1.1)
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(TournamentPalette.accent)

                Text("\(t1Score) – \(t2Score)")
                    .font(.system(size: 34, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(TournamentPalette.ink)

                if let winnerName {
                    Text("Passa \(winnerName)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.surfaceStrong)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule(style: .continuous).fill(TournamentPalette.accent))
                }
            }
            .frame(maxWidth: .infinity)

            if !kicks.isEmpty {
                Rectangle()
                    .fill(TournamentPalette.divider)
                    .frame(height: 1)

                VStack(spacing: 6) {
                    ForEach(kicks) { kick in
                        let isTeam1 = kick.teamId == m.team1
                        cronacaLaneRow(isTeam1: isTeam1) {
                            MatchShootoutKickRow(kick: kick, isTeam1: isTeam1)
                        }
                        .padding(.vertical, 2)
                        if let save = kick.penaltySaveEvent {
                            let keeperIsTeam1 = save.squadraId == m.team1
                            cronacaLaneRow(isTeam1: keeperIsTeam1) {
                                MatchEventRow(event: save, isTeam1: keeperIsTeam1, timeLabel: "\(kick.order)°")
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .tournamentCard()
    }

    // MARK: - Layout a corsie per cronaca (team1 sx | centro | team2 dx)

    @ViewBuilder
    private func cronacaLaneRow<Content: View>(
        isTeam1: Bool,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        // **Riga intera.** Qui c'era una corsia per squadra: il contenuto in
        // meta' larghezza e un `Color.clear` a tenere occupata l'altra meta'.
        // Con un nome lungo il taglio era garantito ("M. Nana D…") e la meta'
        // vuota restava vuota comunque, perche' due eventi non finiscono mai
        // sulla stessa riga. Da che parte sta l'evento lo dicono il filo di
        // colore e l'allineamento.
        HStack(spacing: 10) {
            if isTeam1 {
                Rectangle()
                    .fill(TournamentPalette.accent)
                    .frame(width: 3)
                    .clipShape(Capsule())
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Rectangle()
                    .fill(TournamentPalette.danger)
                    .frame(width: 3)
                    .clipShape(Capsule())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func phaseMarker(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(TournamentPalette.border.opacity(0.6))
                .frame(height: 0.5)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(TournamentPalette.inkMuted)
                .textCase(.uppercase)
                .tracking(0.6)
            Rectangle()
                .fill(TournamentPalette.border.opacity(0.6))
                .frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }

    private func awardFallbackCard(title: String, systemImage: String, nome: String, detail: String?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Spacer()
            }

            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Text(nome)
                    .font(.headline)
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let detail {
                    Text("·")
                        .foregroundStyle(TournamentPalette.inkMuted)
                    Text(detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private func awardVisualCard(
        title: String,
        shareKind: MatchAwardShareKind,
        visual: AwardVisualInfo,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Group {
                if let playerId = visual.playerId, !playerId.isEmpty {
                    NavigationLink(destination: PlayerDetailLazyView(playerId: playerId)) {
                        awardVisualBody(visual: visual, systemImage: systemImage, tint: tint)
                    }
                    .buttonStyle(.tournamentPress)
                } else {
                    awardVisualBody(visual: visual, systemImage: systemImage, tint: tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private func awardVisualBody(
        visual: AwardVisualInfo,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(
                    urlString: visual.photoURL,
                    placeholderIcon: systemImage,
                    placeholderColor: tint,
                    contentMode: .fill
                )
                .frame(height: 162)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                TournamentTeamLogo(urlString: visual.teamLogoURL, size: 28, placeholderTint: tint)
                    .background(Circle().fill(TournamentPalette.backgroundTop))
                    .padding(10)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(visual.playerName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(2)
                Text(visual.teamName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Tab Formazioni

    private var formazioniTab: some View {
        let resolved = resolvedTeams

        return ScrollView {
            VStack(spacing: 16) {
                // Two-column layout
                HStack(alignment: .top, spacing: 8) {
                    formazioneColumn(
                        teamId: currentMatch.team1,
                        teamName: resolved.team1.name,
                        logoURL: resolved.team1.logo,
                        players: vm.team1FormationPlayers,
                        alignment: .leading
                    )

                    formazioneColumn(
                        teamId: currentMatch.team2,
                        teamName: resolved.team2.name,
                        logoURL: resolved.team2.logo,
                        players: vm.team2FormationPlayers,
                        alignment: .trailing
                    )
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 24)
        }
    }

    private func formazioneColumn(
        teamId: String,
        teamName: String,
        logoURL: String?,
        players: [Player],
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(spacing: 0) {
            // Team header
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    TournamentTeamLogo(urlString: logoURL, size: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(teamName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                        Text("\(players.count) giocatori")
                            .font(.caption2)
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .background(TournamentPalette.surfaceMuted)

            // Player list
            if players.isEmpty {
                Text("Rosa non disponibile")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                let goalkeeperKey = goalkeeperRosterKey(for: teamId, players: players)
                VStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.offset) { index, player in
                        formazionePlayerRow(
                            player: player,
                            teamId: teamId,
                            alignment: alignment,
                            isGoalkeeper: goalkeeperKey != nil && player.stableRosterKey == goalkeeperKey
                        )

                        if index < players.count - 1 {
                            Divider().padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
        .background(TournamentPalette.surfaceStrong)
        .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }

    /// Quanti gol ha fatto questo giocatore in questa partita.
    ///
    /// Gli autogol non contano: sono un gol per l'altra squadra, e un pallone
    /// accanto al nome di chi l'ha subito si legge come un merito.
    private func golInPartita(_ player: Player) -> Int {
        let chiave = player.id
        return (currentMatch.eventi ?? []).filter { ev in
            guard let id = ev.giocatoreId, !id.isEmpty, id == chiave else { return false }
            return ev.tipo == "gol" || ev.tipo == "rigore_segnato" || ev.tipo == "punizione_segnata"
        }.count
    }

    /// Un pallone per gol, in fila. Chi ne fa quattro ha quattro palloni: sono
    /// piccoli e in una riga di formazione ci stanno.
    @ViewBuilder
    private func palloniGol(_ quanti: Int) -> some View {
        if quanti > 0 {
            HStack(spacing: 1) {
                ForEach(0..<quanti, id: \.self) { _ in
                    MatchEventIcon(.goal, size: 14)
                }
            }
        }
    }

    private func formazionePlayerRow(
        player: Player,
        teamId: String,
        alignment: HorizontalAlignment,
        isGoalkeeper: Bool
    ) -> some View {
        let isSuspended = isPlayerSuspended(player, teamId: teamId)
        let gol = golInPartita(player)

        return HStack(spacing: 6) {
            if alignment == .leading {
                playerNumberBadge(player.numeroMaglia, teamId: teamId)
                Text(compactFormationName(for: player.nomeCompleto))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TournamentPalette.ink)
                    .strikethrough(isSuspended, color: TournamentPalette.danger)
                    .lineLimit(1)
                palloniGol(gol)
                if isGoalkeeper { goalkeeperTag }
                if isSuspended {
                    Image(systemName: "rectangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TournamentPalette.danger)
                }
                Spacer(minLength: 2)
            } else {
                Spacer(minLength: 2)
                if isSuspended {
                    Image(systemName: "rectangle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(TournamentPalette.danger)
                }
                if isGoalkeeper { goalkeeperTag }
                palloniGol(gol)
                Text(compactFormationName(for: player.nomeCompleto))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(TournamentPalette.ink)
                    .strikethrough(isSuspended, color: TournamentPalette.danger)
                    .lineLimit(1)
                playerNumberBadge(player.numeroMaglia, teamId: teamId)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .opacity(isSuspended ? 0.62 : 1)
    }

    /// Il portiere non è un evento: è un ruolo. Lo marchiamo con un tag
    /// testuale invece che con un guanto, perché in questa lista le icone
    /// significano "evento" (pallone = gol) e un guanto verrebbe letto come
    /// un evento anche lui. Stessa scelta fatta sulla PWA.
    private var goalkeeperTag: some View {
        Text("GK")
            .font(.system(size: 8, weight: .black, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(TournamentPalette.accent)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(TournamentPalette.accentSoft)
            )
            .accessibilityLabel("Portiere")
    }

    /// Chiave di roster del portiere di quella squadra, risolta una volta per
    /// colonna. Stesso ordine di priorità della PWA: id esplicito sulla
    /// partita → id ereditato dalle giornate precedenti → confronto sul nome,
    /// che serve per le rose importate senza `playerId`.
    private func goalkeeperRosterKey(for teamId: String, players: [Player]) -> String? {
        let editionMatches = appState.allMatches.filter { $0.edizione == currentMatch.edizione }
        let explicitId = currentMatch.goalkeeper(for: teamId)?.playerId
        let resolvedId = MatchGoalkeeperResolver.goalkeeperPlayerId(
            for: currentMatch,
            teamId: teamId,
            within: editionMatches
        )

        for candidateId in [explicitId, resolvedId].compactMap({ $0 }) {
            let trimmed = candidateId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let hit = players.first(where: { $0.firestoreIdentifier == trimmed || $0.playerAuthUid == trimmed }) {
                return hit.stableRosterKey
            }
        }

        guard let explicitName = Player.normalizedLookupName(from: currentMatch.goalkeeper(for: teamId)?.playerName) else {
            return nil
        }
        return players.first { Player.normalizedLookupName(from: $0.nomeCompleto) == explicitName }?.stableRosterKey
    }

    private func playerNumberBadge(_ number: Int?, teamId: String) -> some View {
        let hexes = teamColorHexes(for: teamId)
        let primary = Color(hex: hexes.primary) ?? TournamentPalette.accent
        let textColor = jerseyNumberTextColor(primaryHex: hexes.primary, preferredHex: hexes.secondary)
        return ZStack {
            Image(systemName: "tshirt.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(primary)

            Text(number.map(String.init) ?? "-")
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(textColor)
                .offset(y: 1)
        }
        .frame(width: 26, height: 24)
    }

    private func compactFormationName(for fullName: String) -> String {
        let components = fullName
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard let firstName = components.first else {
            return fullName
        }
        guard components.count > 1 else {
            return firstName
        }

        let surname = components.dropFirst().joined(separator: " ")
        let initial = firstName.prefix(1).uppercased()
        return "\(initial). \(surname)"
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

    private func makeFormationShareContext(
        teamId: String,
        teamName: String,
        teamLogoURL: String?,
        players: [Player]
    ) -> FormationShareContext {
        let hexes = teamColorHexes(for: teamId)
        return FormationShareContext(
            id: teamId,
            teamName: teamName,
            teamLogoURL: teamLogoURL,
            players: players,
            primaryHex: hexes.primary,
            secondaryHex: hexes.secondary
        )
    }

    // MARK: - Tab Info

    private var infoTab: some View {
        let m = currentMatch
        let resolved = resolvedTeams
        return ScrollView {
            VStack(spacing: 16) {
                matchSummaryCard

                if team1GoalkeeperName != nil || team2GoalkeeperName != nil {
                    infoCard(title: "Portieri") {
                        if let team1GoalkeeperName {
                            infoRow(
                                icon: "person.crop.circle.badge.checkmark",
                                label: resolved.team1.name,
                                valore: team1GoalkeeperName
                            )
                        }
                        if let team2GoalkeeperName {
                            infoRow(
                                icon: "person.crop.circle.badge.checkmark",
                                label: resolved.team2.name,
                                valore: team2GoalkeeperName
                            )
                        }
                    }
                }

                if isGroupStageMatch, !matchStandings.isEmpty {
                    infoCard(title: "Classifica") {
                        standingsHeader

                        ForEach(Array(matchStandings.enumerated()), id: \.element.id) { index, item in
                            standingsRow(position: index + 1, entry: item)

                            if index < matchStandings.count - 1 {
                                Divider().padding(.leading, 42)
                            }
                        }

                    }
                }

                if let ownerEditableTeamId {
                    infoCard(title: "Il tuo portiere") {
                        NavigationLink(
                            destination: TeamMatchGoalkeeperEditorView(
                                match: currentMatch,
                                managedTeamId: ownerEditableTeamId
                            )
                        ) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(TournamentPalette.accent)

                                Text(ownerTeamName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(TournamentPalette.ink)

                                Spacer(minLength: 0)

                                Text(ownerGoalkeeperName ?? "Non impostato")
                                    .font(.subheadline)
                                    .foregroundStyle(
                                        ownerGoalkeeperName == nil
                                            ? TournamentPalette.inkMuted
                                            : TournamentPalette.ink
                                    )

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TournamentPalette.inkMuted)
                            }
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private var matchSummaryCard: some View {
        let m = currentMatch

        return VStack(alignment: .leading, spacing: 12) {
            Text("Giornata \(m.giornata)")
                .font(.title3.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)

            Text(matchPhaseSummaryLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TournamentPalette.inkMuted)

            if let campo = m.campo, !campo.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(TournamentPalette.accent)
                    Text("Campo \(campo)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private var pronosticiTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let feedbackMessage = predictionsViewModel.feedbackMessage {
                    predictionStatusCard(
                        icon: "checkmark.circle.fill",
                        message: feedbackMessage,
                        tint: TournamentPalette.success
                    )
                }

                if let errorMessage = predictionsViewModel.errorMessage {
                    predictionStatusCard(
                        icon: "exclamationmark.triangle.fill",
                        message: errorMessage,
                        tint: TournamentPalette.danger
                    )
                }

                if !isLoggedInForPredictions {
                    predictionAuthPromptCard
                }

                if predictionsViewModel.isSyncingQuestions {
                    predictionStatusCard(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        message: "Aggiorno i pronostici",
                        tint: TournamentPalette.accent
                    )
                }

                if predictionsViewModel.isLoading && matchPredictionQuestions.isEmpty {
                    LoadingView(message: "Carico i pronostici...")
                } else if matchPredictionQuestions.isEmpty {
                    EmptyStateView(
                        icon: "checklist.checked",
                        title: "Pronostici non disponibili",
                        message: ""
                    )
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        TournamentSectionHeader(title: "Pronostici partita")

                        ForEach(matchPredictionQuestions) { question in
                            MatchPredictionCard(
                                question: question,
                                match: currentMatch,
                                edition: currentMatch.edizione,
                                selectedOptionId: predictionsViewModel.selectedOptionId(for: question.id),
                                isSubmitting: predictionsViewModel.isSubmitting(questionId: question.id),
                                isLoggedIn: isLoggedInForPredictions,
                                showsDetailLink: false,
                                onAuthenticate: { showAuthSheet = true },
                                onSubmit: { option in
                                    Task {
                                        await predictionsViewModel.submit(
                                            question: question,
                                            option: option,
                                            appState: appState
                                        )
                                    }
                                }
                            )
                        }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func infoCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(title: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private func infoRow(icon: String, label: String, valore: String) -> some View {
        TournamentInfoRow(icon: icon, label: label, value: valore)
    }

    private var isGroupStageMatch: Bool {
        let fase = currentMatch.fase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return fase.isEmpty || fase == "girone"
    }

    /// La classifica **del girone di questa partita**, non quella generale.
    ///
    /// Prima erano le nove squadre di tutti e tre i gironi messe insieme: una
    /// tabella che non risponde alla domanda ("come sta andando questo
    /// girone?") e che in larghezza non ci sta, tanto che i nomi uscivano
    /// tagliati.
    private var matchStandings: [StandingsEntry] {
        guard isGroupStageMatch else { return [] }
        return appState.standings(for: currentMatch.edizione, girone: gironeDellaPartita)
    }

    /// Le colonne dei numeri, strette al minimo che regge due cifre.
    ///
    /// Erano 28 punti l'una piu' 58 per i gol: 202 punti di numeri su ~330 di
    /// riga, e al nome squadra ne restavano un centinaio — da cui "New T…",
    /// "Salaza…", "Hunter…" su **tutte** le righe. Vittorie, pareggi e sconfitte
    /// si ricavano gia' da partite e punti, quindi le tre colonne V/N/S si
    /// stringono e i gol diventano la sola differenza reti, che e' il criterio
    /// che conta davvero.
    private static let colonnaStretta: CGFloat = 22
    private static let colonnaGol: CGFloat = 42

    private var standingsHeader: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: 20, alignment: .leading)
            Text("Squadra")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("P")
                .frame(width: Self.colonnaStretta, alignment: .center)
            Text("V")
                .frame(width: Self.colonnaStretta, alignment: .center)
            Text("N")
                .frame(width: Self.colonnaStretta, alignment: .center)
            Text("S")
                .frame(width: Self.colonnaStretta, alignment: .center)
            Text("DR")
                .frame(width: Self.colonnaGol, alignment: .center)
            Text("PT")
                .frame(width: 28, alignment: .trailing)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(TournamentPalette.inkMuted)
    }

    private func standingsRow(position: Int, entry: StandingsEntry) -> some View {
        let highlightColor = highlightedStandingColor(for: entry.teamId)
        let isHighlighted = highlightColor != nil

        return HStack(spacing: 0) {
            Text("\(position)")
                .font(.caption.weight(.bold))
                .foregroundStyle(standingsRankColor(for: position))
                .frame(width: 20, alignment: .leading)

            HStack(spacing: 6) {
                TournamentTeamLogo(
                    urlString: entry.teamLogo,
                    size: 20,
                    placeholderTint: TournamentPalette.accent
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.teamName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)
                        // Un nome lungo si stringe invece di sparire: meglio
                        // "New Team Since 2017" un filo piu' piccolo che
                        // "New T…".
                        .minimumScaleFactor(0.7)

                    if entry.isPlaying {
                        Text("In corso")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TournamentPalette.danger)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            standingsValueCell("\(entry.played)", width: Self.colonnaStretta)
            standingsValueCell("\(entry.won)", width: Self.colonnaStretta)
            standingsValueCell("\(entry.drawn)", width: Self.colonnaStretta)
            standingsValueCell("\(entry.lost)", width: Self.colonnaStretta)
            standingsValueCell(scartoReti(entry), width: Self.colonnaGol)

            Text("\(entry.points)")
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.accent)
                .frame(width: 28, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((highlightColor ?? .clear).opacity(isHighlighted ? 0.12 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke((highlightColor ?? .clear).opacity(isHighlighted ? 0.35 : 0), lineWidth: 1)
        )
    }

    private func standingsValueCell(_ value: String, width: CGFloat) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(TournamentPalette.ink)
            .frame(width: width, alignment: .center)
    }

    private func standingsRankColor(for position: Int) -> Color {
        switch position {
        case 1: return TournamentPalette.warm
        case 2: return TournamentPalette.accent
        case 3: return TournamentPalette.success
        default: return TournamentPalette.ink
        }
    }

    /// "+3", "0", "−2": la differenza reti in due caratteri invece di "3-2" in
    /// cinque. Il segno meno e' quello tipografico, che alla stessa dimensione
    /// si distingue dal trattino di separazione.
    private func scartoReti(_ entry: StandingsEntry) -> String {
        let d = entry.goalsFor - entry.goalsAgainst
        if d > 0 { return "+\(d)" }
        if d < 0 { return "\u{2212}\(-d)" }
        return "0"
    }

    private func highlightedStandingColor(for teamId: String) -> Color? {
        // Confronto ripulito da spazi: gli id delle due squadre arrivano dalla
        // partita, quelli della classifica dalle iscrizioni, e uno spazio in
        // coda da una parte sola bastava a **non evidenziare una delle due**.
        let pulito = { (v: String) in v.trimmingCharacters(in: .whitespacesAndNewlines) }
        let inCampo = [pulito(currentMatch.team1), pulito(currentMatch.team2)]
        guard inCampo.contains(pulito(teamId)) else { return nil }

        // Un colore troppo chiaro sparisce: la riga si tinge al 12% su fondo
        // bianco e di una squadra che gioca in bianco non si vedeva niente —
        // sembrava che l'app evidenziasse una sola delle due. Sopra una certa
        // luminosità si usa l'accento del torneo, che si vede sempre.
        let hex = teamColorHexes(for: teamId).primary
        if let luce = relativeLuminance(hex: hex), luce > 0.7 {
            return TournamentPalette.accent
        }
        return teamColors(for: teamId).primary
    }

    private func teamColors(for teamId: String) -> (primary: Color, secondary: Color) {
        let hexes = teamColorHexes(for: teamId)
        return (
            Color(hex: hexes.primary) ?? TournamentPalette.accent,
            Color(hex: hexes.secondary) ?? .white
        )
    }

    private func teamColorHexes(for teamId: String) -> (primary: String, secondary: String) {
        if let editionTeam = appState.editionTeams(for: currentMatch.edizione).first(where: { $0.teamId == teamId }) {
            return (
                editionTeam.colors.principale,
                editionTeam.colors.secondario
            )
        }

        if let team = appState.teams.first(where: { $0.id == teamId }) {
            return (
                team.colori.principale,
                team.colori.secondario
            )
        }

        return ("#0B79F7", "#FFFFFF")
    }

    private func awardVisualInfo(
        playerId: String?,
        playerName: String?,
        explicitPhotoURL: String?,
        teamSlot: Int?
    ) -> AwardVisualInfo? {
        let trimmedName = playerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedName = Player.normalizedLookupName(from: trimmedName)
        let normalizedId = playerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let candidates: [(teamName: String, teamLogoURL: String?, players: [Player])] = {
            switch teamSlot {
            case 1:
                return [(resolvedTeams.team1.name, resolvedTeams.team1.logo, vm.team1Players)]
            case 2:
                return [(resolvedTeams.team2.name, resolvedTeams.team2.logo, vm.team2Players)]
            default:
                return [
                    (resolvedTeams.team1.name, resolvedTeams.team1.logo, vm.team1Players),
                    (resolvedTeams.team2.name, resolvedTeams.team2.logo, vm.team2Players)
                ]
            }
        }()

        for candidate in candidates {
            if let player = candidate.players.first(where: {
                if !normalizedId.isEmpty,
                   [$0.firestoreIdentifier, $0.playerAuthUid]
                    .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                    .contains(normalizedId) {
                    return true
                }
                guard let normalizedName else { return false }
                return Player.normalizedLookupName(from: $0.nomeCompleto) == normalizedName
            }) {
                return AwardVisualInfo(
                    playerId: player.firestoreIdentifier ?? player.playerAuthUid,
                    playerName: player.nomeCompleto,
                    teamName: candidate.teamName,
                    photoURL: explicitPhotoURL?.isEmpty == false ? explicitPhotoURL : player.displayPhotoURL,
                    teamLogoURL: candidate.teamLogoURL
                )
            }
        }

        guard !trimmedName.isEmpty else { return nil }
        let fallbackTeamName = teamSlot == 2 ? resolvedTeams.team2.name : resolvedTeams.team1.name
        let fallbackTeamLogo = teamSlot == 2 ? resolvedTeams.team2.logo : resolvedTeams.team1.logo
        return AwardVisualInfo(
            playerId: normalizedId.isEmpty ? nil : normalizedId,
            playerName: trimmedName,
            teamName: fallbackTeamName,
            photoURL: explicitPhotoURL,
            teamLogoURL: fallbackTeamLogo
        )
    }

    private func jerseyNumberTextColor(primaryHex: String, preferredHex: String) -> Color {
        guard let primaryLum = relativeLuminance(hex: primaryHex) else {
            return Color(hex: preferredHex) ?? .white
        }

        if let preferredLum = relativeLuminance(hex: preferredHex),
           contrastRatio(primaryLum, preferredLum) >= 4.5 {
            return Color(hex: preferredHex) ?? .white
        }

        let blackLum = relativeLuminance(hex: "#000000") ?? 0
        let whiteLum = relativeLuminance(hex: "#FFFFFF") ?? 1
        return contrastRatio(primaryLum, blackLum) >= contrastRatio(primaryLum, whiteLum) ? .black : .white
    }

    private func relativeLuminance(hex: String) -> Double? {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        let red = Double((value & 0xFF0000) >> 16) / 255.0
        let green = Double((value & 0x00FF00) >> 8) / 255.0
        let blue = Double(value & 0x0000FF) / 255.0

        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    private func contrastRatio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Il girone di questa partita, in maiuscolo. `nil` se il torneo gioca a
    /// girone unico o se la partita è del tabellone.
    private var gironeDellaPartita: String? {
        let g = currentMatch.group?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return g.isEmpty ? nil : g
    }

    private var matchPhaseSummaryLabel: String {
        guard isGroupStageMatch else { return "Eliminazione diretta" }
        // Diceva "Fase girone unico" su un torneo con tre gironi. Chi legge
        // vuole sapere in quale sta giocando, non che esiste una fase a gironi.
        if let gironeDellaPartita { return "Girone \(gironeDellaPartita)" }
        return "Fase a gironi"
    }

    private func predictionStatusCard(icon: String, message: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(TournamentPalette.ink)
            Spacer(minLength: 0)
        }
        .tournamentCard()
    }

    private var predictionAuthPromptCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accedi per votare")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                Text("Da ospite vedi solo le percentuali.")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            Spacer(minLength: 0)

            Button("Accedi") {
                showAuthSheet = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(TournamentPalette.accent)
            )
        }
        .tournamentCard()
    }

    private var team1GoalkeeperName: String? {
        goalkeeperName(for: currentMatch.team1, players: vm.team1Players)
    }

    private var team2GoalkeeperName: String? {
        goalkeeperName(for: currentMatch.team2, players: vm.team2Players)
    }

    private var ownerGoalkeeperName: String? {
        guard let ownerEditableTeamId else { return nil }
        if ownerEditableTeamId == currentMatch.team1 {
            return team1GoalkeeperName
        }
        if ownerEditableTeamId == currentMatch.team2 {
            return team2GoalkeeperName
        }
        return nil
    }

    private var ownerTeamName: String {
        guard let ownerEditableTeamId else { return "Squadra" }
        if ownerEditableTeamId == currentMatch.team1 {
            return resolvedTeams.team1.name
        }
        if ownerEditableTeamId == currentMatch.team2 {
            return resolvedTeams.team2.name
        }
        return "Squadra"
    }

    private func goalkeeperName(for teamId: String, players: [Player]) -> String? {
        if let explicitName = currentMatch.goalkeeper(for: teamId)?.playerName,
           !explicitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitName
        }

        let editionMatches = appState.allMatches.filter { $0.edizione == currentMatch.edizione }
        guard let playerId = MatchGoalkeeperResolver.goalkeeperPlayerId(
            for: currentMatch,
            teamId: teamId,
            within: editionMatches
        ) else {
            return nil
        }

        return players.first(where: { ($0.firestoreIdentifier == playerId) || ($0.playerAuthUid == playerId) })?.nomeCompleto
    }

    private var stateLabel: String {
        if currentMatch.isPlayed {
            return "Terminata"
        }
        if currentMatch.isLive {
            return "In corso"
        }
        return "Programmata"
    }

    private var stateTone: TournamentTone {
        if currentMatch.isPlayed {
            return .warning
        }
        if currentMatch.isLive {
            return .success
        }
        return .neutral
    }
}

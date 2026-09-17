import SwiftUI
import FirebaseFirestore

// MARK: - ViewModel

@Observable
@MainActor
final class TeamDashboardViewModel {
    var team: Team?
    var players: [Player] = []
    var requests: [TransferRequest] = []
    var isLoading = true
    var errorMessage: String?

    private let teamListener = FirestoreListenerToken()
    private let playersListener = FirestoreListenerToken()
    private let requestsListener = FirestoreListenerToken()

    func start(teamId: String, firestoreService: FirestoreService, includeRequests: Bool = true) {
        isLoading = true
        errorMessage = nil
        requests = []

        // Mantiene logo e nome aggiornati anche dopo modifiche owner/admin.
        teamListener.replace(with: firestoreService.listenToTeam(teamId: teamId) { [weak self] team in
            Task { @MainActor [weak self, team] in
                self?.team = team
                self?.isLoading = false
            }
        })

        // Carica dati squadra
        Task {
            do {
                team = try await firestoreService.fetchTeam(id: teamId)
            } catch {
                errorMessage = "Errore caricamento squadra: \(error.localizedDescription)"
            }
            isLoading = false
        }

        // Listener real-time giocatori
        playersListener.replace(with: firestoreService.listenToPlayers(teamId: teamId) { [weak self] players in
            Task { @MainActor [weak self, players] in
                self?.players = Self.normalizedRoster(players)
            }
        })

        if includeRequests {
            // Listener real-time richieste
            requestsListener.replace(with: firestoreService.listenToRequests(forTeam: teamId) { [weak self] reqs in
                Task { @MainActor [weak self, reqs] in
                    self?.requests = reqs.sorted {
                        ($0.createdAt?.dateValue() ?? .distantPast) >
                        ($1.createdAt?.dateValue() ?? .distantPast)
                    }
                }
            })
        } else {
            requestsListener.cancel()
        }
    }

    func stop() {
        teamListener.cancel()
        playersListener.cancel()
        requestsListener.cancel()
    }

    private static func normalizedRoster(_ players: [Player]) -> [Player] {
        var uniquePlayers: [String: Player] = [:]

        for player in players {
            uniquePlayers[player.stableRosterKey] = player
        }

        return uniquePlayers.values.sorted {
            let lhsNumber = $0.numeroMaglia ?? 99
            let rhsNumber = $1.numeroMaglia ?? 99
            if lhsNumber == rhsNumber {
                return $0.nomeCompleto.localizedCaseInsensitiveCompare($1.nomeCompleto) == .orderedAscending
            }
            return lhsNumber < rhsNumber
        }
    }
}

// MARK: - View principale

struct TeamDashboardView: View {
    let teamId: String

    @Environment(AppState.self) private var appState
    @State private var vm = TeamDashboardViewModel()
    @State private var selectedTab = 0
    @State private var showTournamentPicker = false
    @State private var availableTournamentsCount = 0

    private let tabs = ["Panoramica", "Rosa", "Gestione"]

    var body: some View {
        NavigationStack {
            TournamentScreen {
                VStack(spacing: 0) {
                    if vm.isLoading {
                        LoadingView(message: "Caricamento squadra...")
                            .frame(maxHeight: .infinity)
                    } else if let team = vm.team {
                        VStack(spacing: 12) {
                            Picker("Sezione", selection: $selectedTab) {
                                ForEach(tabs.indices, id: \.self) { i in
                                    Text(tabs[i]).tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(10)
                            .tournamentCard(padding: 0)
                            .padding(.horizontal, 16)

                            switch selectedTab {
                            case 0:
                                PanoramicaTab(
                                    team: team,
                                    players: vm.players,
                                    teamId: teamId,
                                    onOpenRoster: { selectedTab = 1 }
                                )
                            case 1:
                                RosterView(
                                    teamId: teamId,
                                    team: team,
                                    players: vm.players
                                )
                            default:
                                GestioneTab(
                                    teamId: teamId,
                                    team: team
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Squadra non trovata",
                            message: "Impossibile caricare i dati della squadra."
                        )
                        .frame(maxHeight: .infinity)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Logo+nome fuori dalla capsula Liquid Glass: dentro leggeva
                // come una "bolla" attorno al brand (bocciata dall'owner).
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) {
                        Group {
                            if let team = vm.team {
                                TeamDashboardCompactHeroTitle(team: team)
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Group {
                            if let team = vm.team {
                                TeamDashboardCompactHeroTitle(team: team)
                            }
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Il menu ⋯ c'è sempre: oltre al cambio ruolo ospita il
                    // cambio torneo, che prima viveva solo in fondo a Gestione
                    // e di fatto non si trovava.
                    Menu {
                        if appState.authService.hasMultipleProfileRoles {
                            Section("Entra come") {
                                ForEach(Array(appState.authService.availableRoles.enumerated()), id: \.offset) { item in
                                    let role = item.element
                                    let isCurrent = role == appState.authService.userRole
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            appState.authService.setActiveRole(role)
                                        }
                                    } label: {
                                        Label(role.profileSwitchLabel, systemImage: isCurrent ? "checkmark" : role.profileSwitchIcon)
                                    }
                                }
                            }
                        }

                        if availableTournamentsCount >= 2 {
                            Button {
                                showTournamentPicker = true
                            } label: {
                                Label("Cambia torneo", systemImage: "trophy")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(TournamentPalette.accent)
                    }

                    Button {
                        appState.authService.logout()
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(Color(hex: "#ef4444") ?? .red)
                    }
                }
            }
            .sheet(isPresented: $showTournamentPicker) {
                TournamentPickerView()
                    .environment(appState)
            }
            .task {
                let list = await appState.tournamentSelectionStore.loadAvailableTournaments()
                availableTournamentsCount = list.count
            }
        }
        .onAppear {
            vm.start(teamId: teamId, firestoreService: appState.firestoreService)
            Task {
                guard !appState.runtimeSafety.protectsRealData else { return }
                guard appState.authService.currentUser != nil else { return }
                _ = await appState.notificationService.requestPermissionIfNeeded()
                if let token = appState.notificationService.fcmToken {
                    try? await appState.cloudFunctionsService.registerFcmToken(
                        token: token,
                        installationId: appState.notificationService.installationId
                    )
                }
            }
        }
        .onDisappear {
            vm.stop()
        }
    }
}

// MARK: - Tab Panoramica

private struct PanoramicaTab: View {
    let team: Team
    let players: [Player]
    let teamId: String
    let onOpenRoster: () -> Void
    @Environment(AppState.self) private var appState

    private var standingsEntry: StandingsEntry? {
        appState.standings.first { $0.teamId == teamId }
    }
    private var posizione: Int? {
        guard let entry = standingsEntry else { return nil }
        return (appState.standings.firstIndex { $0.teamId == entry.teamId } ?? -1) + 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                statsGrid

                infoCard

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            Button(action: onOpenRoster) {
                TournamentMetricTile(
                    value: "\(players.count)",
                    label: "Giocatori",
                    icon: "person.2.fill",
                    tint: TournamentPalette.accent
                )
            }
            .buttonStyle(.tournamentPress)
            TournamentMetricTile(value: posizione.map { "#\($0)" } ?? "—", label: "Posizione", icon: "list.number", tint: TournamentPalette.warm)
            TournamentMetricTile(value: "\(standingsEntry?.points ?? 0)", label: "Punti", icon: "star.fill", tint: TournamentPalette.success)
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Informazioni squadra",
                subtitle: "Contatti principali e dati del referente."
            )

            infoRow(icon: "person.fill",     label: "Rappresentante", valore: team.rappresentante.nome)
            infoRow(icon: "phone.fill",      label: "Telefono",        valore: team.rappresentante.telefono)
            infoRow(icon: "envelope.fill",   label: "Email",           valore: team.email)
        }
        .tournamentCard()
    }

    private func infoRow(icon: String, label: String, valore: String) -> some View {
        TournamentInfoRow(icon: icon, label: label, value: valore)
    }
}

// MARK: - Tab Gestione

private struct GestioneTab: View {
    let teamId: String
    let team: Team

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 28) {
                    NavigationLink(destination: TeamManagementView(teamId: teamId, team: team)) {
                        iconButton(icon: "pencil")
                    }
                    .buttonStyle(.tournamentPress)

                    NavigationLink(destination: TransferRequestsView(teamId: teamId, teamName: team.nomeSquadra)) {
                        iconButton(icon: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.tournamentPress)

                    NavigationLink(destination: NotificationPreferencesView()) {
                        iconButton(icon: "bell.badge")
                    }
                    .buttonStyle(.tournamentPress)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)

                // Phase 3c — picker torneo (visibile solo se >= 2 tornei attivi).
                TournamentPickerLinkSection()

                LegalLinksSection()

                HStack {
                    AccountDeletionSection(style: .compact)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private func iconButton(icon: String) -> some View {
        Image(systemName: icon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(TournamentPalette.accent)
            .frame(width: 44, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TournamentPalette.accentSoft)
            )
    }
}

struct TeamDashboardScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TeamDashboardScrollTracker: View {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: TeamDashboardScrollOffsetKey.self,
                    value: max(0, -proxy.frame(in: .named("teamDashboardScroll")).minY)
                )
        }
        .frame(height: 0)
    }
}

struct TeamDashboardScrollHeader: View {
    let team: Team
    let heroProgress: CGFloat

    var body: some View {
        TeamDashboardHeroCard(team: team, progress: heroProgress)
    }
}

private struct TeamDashboardHeroCard: View {
    let team: Team
    let progress: CGFloat

    var body: some View {
        let expandedHeight: CGFloat = 190
        let compactHeight: CGFloat = 76
        let currentHeight = expandedHeight - ((expandedHeight - compactHeight) * progress)

        ZStack {
            heroBackground

            expandedHeroContent
                .opacity(1 - progress)
                .scaleEffect(1 - (0.06 * progress), anchor: .center)
                .offset(y: -10 * progress)

            compactHeroContent
                .opacity(progress)
                .padding(.horizontal, 16)
        }
        .frame(height: currentHeight)
        .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.22), value: progress)
    }

    private var heroBackground: some View {
        HStack(spacing: 0) {
            Color(hex: team.colori.principale) ?? .blue
            Color(hex: team.colori.secondario) ?? .white
        }
    }

    private var expandedHeroContent: some View {
        VStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                heroBackground
                    .frame(height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))

                TournamentTeamLogo(
                    urlString: team.logoSquadra,
                    size: 84,
                    placeholderTint: Color(hex: team.colori.principale) ?? TournamentPalette.accent
                )
                .offset(y: 42)
            }
            .padding(.bottom, 42)

            VStack(spacing: 8) {
                Text(team.nomeSquadra)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .multilineTextAlignment(.center)

                TournamentPill(label: "Area squadra", tone: .accent, systemImage: "shield.fill")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
    }

    private var compactHeroContent: some View {
        HStack(spacing: 12) {
            TournamentTeamLogo(
                urlString: team.logoSquadra,
                size: 42,
                placeholderTint: Color(hex: team.colori.principale) ?? TournamentPalette.accent
            )

            Text(team.nomeSquadra)
                .font(.headline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

private struct TeamDashboardCompactHeroTitle: View {
    let team: Team

    var body: some View {
        HStack(spacing: 8) {
            // 30pt, non 24: fuori dalla capsula glass il logo a 24 spariva.
            TournamentTeamLogo(
                urlString: team.logoSquadra,
                size: 30,
                placeholderTint: Color(hex: team.colori.principale) ?? TournamentPalette.accent
            )

            Text(team.nomeSquadra)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize()
        }
    }
}

import SwiftUI
import FirebaseAuth

private enum MainTabSelection: Hashable {
    case matches
    case rankings
    case predictions
    case teams
    case profile
}

struct MainTabView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: MainTabSelection = .matches
    @State private var didBootstrap = false
    /// Registrazione da aprire dopo il benvenuto-torneo (intent su AppState).
    @State private var registrationSheet: RegistrationIntent?
    @State private var activeLoadingStyle: TournamentRootLoadingStyle? = .overlay
    @State private var activeLoadingMessage = "Stiamo preparando il torneo"
    /// Tinta tab bar per-torneo: in @State così il body ri-renderizza quando
    /// il brand del torneo diventa disponibile (§4.3).
    @State private var brandAccent: Color = TournamentPalette.accent

    /// Torneo attualmente selezionato (per brand del loading, §4.2/§4.3).
    private var currentTournament: Tournament? {
        let store = appState.tournamentSelectionStore
        return store.availableTournaments.first { $0.id == store.currentTournamentId }
    }

    /// §4.3 — applica la tinta del torneo corrente a tutta la chrome in-app.
    private func applyBrandAccent() {
        TournamentPalette.accentOverride = currentTournament?.branding.primaryColor
        brandAccent = TournamentPalette.accent
        TournamentBarTint.apply(brandAccent)
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
            MatchesView()
                .tag(MainTabSelection.matches)
                .tabItem { Label("Partite", systemImage: "sportscourt") }

            RankingsHubView()
                .tag(MainTabSelection.rankings)
                // Dentro non ci sono solo classifiche: anche statistiche
                // individuali e il ranking generale del torneo.
                .tabItem { Label("Torneo", systemImage: "chart.bar.xaxis") }

            PredictionsView()
                .tag(MainTabSelection.predictions)
                .tabItem { Label("Pronostici", systemImage: "checklist.checked") }

            TeamsListView()
                .tag(MainTabSelection.teams)
                .tabItem { Label("Squadre", systemImage: "person.3") }

            profiloTab
                .tag(MainTabSelection.profile)
                .tabItem { Label("Profilo", systemImage: "person.circle") }
        }
            .tint(brandAccent)
            .tournamentTabBarMinimize()

            if let loadingStyle = activeLoadingStyle
                ?? (appState.isSwitchingTournament ? TournamentRootLoadingStyle.overlay : nil) {
                TournamentGlobalLoadingOverlay(
                    style: loadingStyle,
                    message: appState.isSwitchingTournament
                        ? "Stiamo cambiando torneo"
                        : activeLoadingMessage,
                    logoURL: currentTournament?.branding.logoURL,
                    accent: currentTournament?.branding.primaryColor ?? TournamentPalette.accent,
                    // Logo locale dall'id anche prima che il doc torneo sia caricato.
                    localAsset: LocalTournamentLogos.assetName(for: appState.tournamentSelectionStore.currentTournamentId)
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTab)
        .tint(brandAccent)
        .animation(
            .easeInOut(duration: 0.24),
            value: activeLoadingStyle != nil || appState.isSwitchingTournament
        )
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            applyBrandAccent()
            await performBootstrap()
            consumePendingRegistrationIntent()
        }
        .onChange(of: appState.tournamentSelectionStore.currentTournamentId) { _, _ in
            applyBrandAccent()
        }
        .sheet(item: $registrationSheet) { intent in
            NavigationStack {
                registrationDestination(for: intent)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { registrationSheet = nil } label: {
                                Image(systemName: "xmark").font(.body.weight(.semibold))
                            }
                            .accessibilityLabel("Chiudi")
                        }
                    }
            }
            .environment(appState)
        }
    }

    /// Consuma l'intent impostato dal benvenuto-torneo: seleziona Profilo e apre
    /// la registrazione corrispondente.
    private func consumePendingRegistrationIntent() {
        guard let intent = appState.pendingRegistrationIntent else { return }
        appState.pendingRegistrationIntent = nil
        selectedTab = .profile
        registrationSheet = intent
    }

    @ViewBuilder
    private func registrationDestination(for intent: RegistrationIntent) -> some View {
        switch intent {
        case .existingTeam: TeamRegistrationView(preselectExistingTeam: true)
        case .newTeam:      TeamRegistrationView(preselectExistingTeam: false)
        case .playerRegister: PlayerRegistrationView()
        }
    }

    // MARK: - Tab Profilo (routing basato su ruolo)

    @ViewBuilder
    private var profiloTab: some View {
        if appState.authService.isLoading {
            LoadingView(message: "Caricamento...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        } else if appState.authService.currentUser == nil {
            AuthRouter()

        } else {
            switch appState.authService.userRole {

            case .teamOwner(let teamId):
                TeamDashboardView(teamId: teamId)

            case .player(let playerId):
                PlayerDashboardView(playerId: playerId)

            case .admin:
                AdminRouter()

            case .publicUser:
                RuoloPlaceholderView(
                    icon: "person.crop.circle.badge.questionmark",
                    titolo: "Ruolo non assegnato",
                    sottotitolo: "Il tuo account non ha ancora un ruolo associato."
                )
            }
        }
    }

    private func performBootstrap() async {
        await performRootLoading(
            style: .overlay,
            message: "Stiamo preparando il torneo",
            minimumDuration: 1.15
        ) {
            await appState.loadInitialData()
            applyBrandAccent()
            appState.startListeningToMatches()
            await waitForAuthResolution()
            await appState.notificationService.refreshAuthorizationStatus()
            appState.notificationService.registerForRemoteNotificationsIfAuthorized()
        }

    }

    private func performRootLoading(
        style: TournamentRootLoadingStyle,
        message: String,
        minimumDuration: TimeInterval,
        operation: @escaping @MainActor () async -> Void
    ) async {
        let startedAt = Date()

        await MainActor.run {
            activeLoadingStyle = style
            activeLoadingMessage = message
        }

        await operation()

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minimumDuration {
            let remaining = minimumDuration - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            activeLoadingStyle = nil
        }
    }

    private func waitForAuthResolution() async {
        let maxChecks = 36

        for _ in 0..<maxChecks {
            if !appState.authService.isLoading {
                return
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

// MARK: - Placeholder per ruoli pubblici

private struct RuoloPlaceholderView: View {
    @Environment(AppState.self) private var appState

    let icon: String
    let titolo: String
    let sottotitolo: String

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: 18) {
                        TournamentHeroCard(
                            eyebrow: "Profilo torneo",
                            title: titolo,
                            subtitle: sottotitolo,
                            accent: TournamentPalette.accent,
                            systemImage: icon
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        TournamentFormSection(
                            title: "Accesso corrente",
                            subtitle: "Il tuo account è attivo ma non ha ancora un ruolo operativo nel torneo.",
                            icon: "person.crop.circle.badge.questionmark"
                        ) {
                            TournamentInfoRow(icon: "envelope.fill", label: "Email", value: appState.authService.currentUser?.email ?? "—")
                            TournamentInfoRow(icon: "person.text.rectangle.fill", label: "Ruolo", value: ruoloLabel)
                            TournamentInfoRow(icon: "checkmark.shield.fill", label: "Accesso", value: providerLabel)
                        }
                        .padding(.horizontal, 16)

                        TournamentFormSection(
                            title: "Completa il profilo",
                            subtitle: "Scegli il tipo di account da usare nell'app per gestire squadra o giocatore.",
                            icon: "square.and.pencil"
                        ) {
                            NavigationLink(destination: TeamRegistrationView()) {
                                Label("Completa come squadra", systemImage: "shield.fill")
                                    .tournamentButtonChrome(.primary)
                            }
                            .buttonStyle(.tournamentPress)

                            NavigationLink(destination: PlayerRegistrationView()) {
                                Label("Completa come giocatore", systemImage: "person.fill")
                                    .tournamentButtonChrome(.secondary)
                            }
                            .buttonStyle(.tournamentPress)
                        }
                        .padding(.horizontal, 16)

                        Button(role: .destructive) {
                            appState.authService.logout()
                        } label: {
                            Label("Esci dall'account", systemImage: "rectangle.portrait.and.arrow.right")
                                .tournamentButtonChrome(.destructive)
                        }
                        .buttonStyle(.tournamentPress)
                        .padding(.horizontal, 16)

                        NavigationLink(destination: NotificationPreferencesView()) {
                            Label("Notifiche", systemImage: "bell.badge")
                                .tournamentButtonChrome(.neutral)
                        }
                        .buttonStyle(.tournamentPress)
                        .padding(.horizontal, 16)

                        // Phase 3c — picker torneo (auto-hide se solo 1).
                        TournamentPickerLinkSection()
                            .padding(.horizontal, 16)

                        AccountDeletionSection()
                            .padding(.horizontal, 16)

                        LegalLinksSection()
                            .padding(.horizontal, 16)

                        Spacer(minLength: 32)
                    }
                }
            }
            .navigationTitle("Profilo")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var ruoloLabel: String {
        switch appState.authService.userRole {
        case .admin:      return "Amministratore"
        case .teamOwner:  return "Responsabile squadra"
        case .player:     return "Giocatore"
        case .publicUser: return "Utente pubblico"
        }
    }

    private var providerLabel: String {
        if appState.authService.currentUser?.isAnonymous == true {
            return "Ospite anonimo"
        }

        let providerIDs = (appState.authService.currentUser?.providerData ?? [])
            .map(\.providerID)
            .filter { $0 != "firebase" }

        if providerIDs.contains("apple.com") {
            return "Apple"
        }
        if providerIDs.contains("google.com") {
            return "Google"
        }
        if providerIDs.contains("password") {
            return "Email e password"
        }
        return "Autenticato"
    }
}

// Tab bar che si ritira quando non serve (iOS 26): scorrendo il contenuto
// restano solo le icone compatte, niente etichette. Sotto iOS 26 resta com'è.
private extension View {
    @ViewBuilder
    func tournamentTabBarMinimize() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}

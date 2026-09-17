import SwiftUI
import FirebaseAuth

private enum ExternalNavigationTarget: Identifiable {
    case match(Match)
    case team(EditionTeam)
    case player(String)

    var id: String {
        switch self {
        case .match(let match):
            return "match:\(match.id ?? UUID().uuidString)"
        case .team(let team):
            return "team:\(team.id)"
        case .player(let playerId):
            return "player:\(playerId)"
        }
    }
}

struct AppRootView: View {
    @Environment(AppState.self) private var appState

    @State private var enteredAsGuest = false
    @State private var sawAuthenticatedSession = false
    /// Lobby "Scegli il torneo" mostrata una volta per ingresso (come la PWA).
    /// Resettata a ogni cambio sessione auth (login/logout/guest).
    @State private var didChooseTournamentThisSession = false
    /// Interstitial benvenuto-torneo mostrato dopo la lobby (si auto-salta se
    /// non applicabile). Resettato come la lobby a ogni cambio sessione.
    @State private var didWelcomeThisSession = false
    @State private var externalMatchId: String?
    @State private var externalTeamId: String?
    @State private var externalPlayerId: String?

    var body: some View {
        rootContent
        .task {
            appState.authService.listenToAuthState()
            consumePendingNavigationFromAppDelegate()
        }
        .onChange(of: appState.authService.currentUser?.uid) { _, newUid in
            // Ogni cambio identità = nuovo ingresso → rimostra lobby + benvenuto.
            didChooseTournamentThisSession = false
            didWelcomeThisSession = false
            if newUid != nil {
                sawAuthenticatedSession = true
                enteredAsGuest = false
            } else if sawAuthenticatedSession {
                sawAuthenticatedSession = false
                enteredAsGuest = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMatchDetail)) { notification in
            if let matchId = notification.object as? String {
                externalMatchId = matchId
                externalTeamId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTeamDetail)) { notification in
            if let teamId = notification.object as? String {
                externalTeamId = teamId
                externalMatchId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openPlayerDetail)) { notification in
            if let playerId = notification.object as? String {
                externalPlayerId = playerId
                externalMatchId = nil
                externalTeamId = nil
            }
        }
        .sheet(item: externalNavigationBinding) { target in
            navigationDestination(for: target)
                .environment(appState)
        }
    }

    private var externalNavigationBinding: Binding<ExternalNavigationTarget?> {
        Binding(
            get: {
                if let matchId = externalMatchId,
                   let match = appState.allMatches.first(where: { $0.id == matchId }) {
                    return .match(match)
                }

                if let teamId = externalTeamId,
                   let team = resolvedExternalTeam(teamId: teamId) {
                    return .team(team)
                }

                // Il giocatore si carica dentro la vista (PlayerDetailLazyView):
                // dalla push arriva solo l'id, e la cache dell'album puo' non
                // esserci ancora.
                if let playerId = externalPlayerId {
                    return .player(playerId)
                }

                return nil
            },
            set: { newValue in
                if newValue == nil {
                    externalMatchId = nil
                    externalTeamId = nil
                    externalPlayerId = nil
                }
            }
        )
    }

    @ViewBuilder
    private func navigationDestination(for target: ExternalNavigationTarget) -> some View {
        NavigationStack {
            switch target {
            case .match(let match):
                MatchDetailView(match: match)
            case .team(let team):
                TeamDetailView(team: team)
            case .player(let playerId):
                PlayerDetailLazyView(playerId: playerId, apreLente: true)
            }
        }
    }

    private func resolvedExternalTeam(teamId: String) -> EditionTeam? {
        if let activeTeam = appState.editionTeam(for: teamId, edition: appState.activeEdition) {
            return activeTeam
        }

        if let selectedTeam = appState.editionTeam(for: teamId, edition: appState.selectedEdition) {
            return selectedTeam
        }

        let knownEditions = appState.editions(forTeamId: teamId).sorted(by: >)
        for edition in knownEditions {
            if let team = appState.editionTeam(for: teamId, edition: edition) {
                return team
            }
        }

        guard let team = appState.teams.first(where: { $0.id == teamId }) else {
            return nil
        }

        return EditionTeam(
            edition: appState.activeEdition,
            team: team,
            preferLiveTeamData: true
        )
    }

    private func consumePendingNavigationFromAppDelegate() {
        let pending = ExternalNavigationRouter.consumePendingNavigation()
        if let matchId = pending.matchId {
            externalMatchId = matchId
            externalTeamId = nil
        } else if let teamId = pending.teamId {
            externalTeamId = teamId
            externalMatchId = nil
        }
    }

    private var isReadyForMainApp: Bool {
        hasActiveGuestSession || hasAuthenticatedNonAnonymousSession
    }

    private var hasActiveGuestSession: Bool {
        enteredAsGuest && appState.authService.currentUser?.isAnonymous == true
    }

    private var hasAuthenticatedNonAnonymousSession: Bool {
        guard !appState.authService.isLoading,
              let currentUser = appState.authService.currentUser else {
            return false
        }

        return !currentUser.isAnonymous
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--odc-penalty-preview") {
            DebugPenaltyMissView()
        } else if ProcessInfo.processInfo.arguments.contains("--odc-event-icons-preview") {
            DebugMatchEventIconsView()
        } else if ProcessInfo.processInfo.arguments.contains("--odc-playercard-preview") {
            DebugPlayerCardView()
        } else if isKnockoutPreviewMode {
            DebugKnockoutPreviewRoute()
        } else if isLobbyPreviewMode {
            TournamentLobbyView(onChosen: {})
        } else if isWelcomePreviewMode {
            TournamentWelcomeView(onProceed: {}, previewSample: true)
        } else if isAppPreviewMode {
            MainTabView()
        } else {
            mainContent
        }
#else
        mainContent
#endif
    }

    @ViewBuilder
    private var mainContent: some View {
        if isReadyForMainApp {
            if !didChooseTournamentThisSession {
                // Lobby forzata "Scegli il torneo" (porting PWA scegli-torneo).
                // Si auto-salta (onChosen immediato) se c'è <2 tornei attivi.
                TournamentLobbyView(
                    onChosen: { didChooseTournamentThisSession = true }
                )
            } else if !didWelcomeThisSession {
                // Benvenuto-torneo: chiede come partecipare se applicabile,
                // altrimenti (onProceed immediato) prosegue in app.
                TournamentWelcomeView(
                    onProceed: { didWelcomeThisSession = true }
                )
            } else {
                MainTabView()
            }
        } else {
            TournamentLandingView(
                canShowActions: !appState.authService.isLoading,
                onEnterAsGuest: {
                    enteredAsGuest = true
                }
            )
        }
    }

    private var isKnockoutPreviewMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--knockout-preview")
#else
        false
#endif
    }

    private var isLobbyPreviewMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--odc-lobby-preview")
#else
        false
#endif
    }

    private var isWelcomePreviewMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--odc-welcome-preview")
#else
        false
#endif
    }

    private var isAppPreviewMode: Bool {
#if DEBUG
        ProcessInfo.processInfo.arguments.contains("--odc-app-preview")
#else
        false
#endif
    }
}

#if DEBUG
private struct DebugKnockoutPreviewRoute: View {
    @Environment(AppState.self) private var appState
    @State private var didLoad = false
    @State private var didExport = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    TournamentScreen {
                        LoadingView(message: "Carico il tabellone...")
                    }
                } else {
                    KnockoutBracketView(showsNavigation: false)
                }
            }
            .task {
                guard !didLoad else { return }
                didLoad = true
                await appState.loadInitialData()
                appState.startListeningToMatches()
                appState.switchEdition(to: 2026)
                isLoading = false
            }
            .task(id: isLoading) {
                guard !isLoading, shouldExportPreview, !didExport else { return }
                didExport = true
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                exportPreview()
            }
        }
    }

    private var shouldExportPreview: Bool {
        ProcessInfo.processInfo.arguments.contains("--export-knockout-preview")
    }

    @MainActor
    private func exportPreview() {
        let previewView = KnockoutBracketView(
            showsNavigation: false,
            showsScreenBackground: true,
            exportPreview: true
        )
            .environment(appState)
            .frame(width: 520, height: 1500)

        let renderer = ImageRenderer(content: previewView)
        renderer.scale = 2

        guard let image = renderer.uiImage,
              let data = image.pngData() else { return }

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let outputURL = documentsURL?.appendingPathComponent("knockout-bracket-preview.png") else { return }

        try? data.write(to: outputURL, options: .atomic)
        print("Knockout preview exported to \(outputURL.path)")
    }
}
#endif

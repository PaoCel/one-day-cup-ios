import SwiftUI
import FirebaseCore
import FirebaseAuth
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

extension Notification.Name {
    static let openMatchDetail = Notification.Name("OpenMatchDetail")
    static let openTeamDetail = Notification.Name("OpenTeamDetail")
    static let openPlayerDetail = Notification.Name("OpenPlayerDetail")
}

@MainActor
enum ExternalNavigationRouter {
    private static var pendingMatchId: String?
    private static var pendingTeamId: String?

    static func consumePendingNavigation() -> (matchId: String?, teamId: String?) {
        let pending = (pendingMatchId, pendingTeamId)
        pendingMatchId = nil
        pendingTeamId = nil
        return pending
    }

    @discardableResult
    static func handleExternalURL(_ url: URL) -> Bool {
        guard url.scheme == "torneomultipalo" else { return false }

        let routeId = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !routeId.isEmpty else { return false }

        switch url.host {
        case "match":
            queueMatchNavigation(routeId)
            return true
        case "team":
            queueTeamNavigation(routeId)
            return true
        case "player":
            queuePlayerNavigation(routeId)
            return true
        default:
            return false
        }
    }

    static func queueMatchNavigation(_ matchId: String) {
        pendingMatchId = matchId
        NotificationCenter.default.post(name: .openMatchDetail, object: matchId)
    }

    static func queueTeamNavigation(_ teamId: String) {
        pendingTeamId = teamId
        NotificationCenter.default.post(name: .openTeamDetail, object: teamId)
    }

    /// La scheda del giocatore con la figurina gia' aperta: e' dove porta il
    /// tap sulla push "figurina pronta" (al giocatore e all'admin).
    static func queuePlayerNavigation(_ playerId: String) {
        NotificationCenter.default.post(name: .openPlayerDetail, object: playerId)
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do {
            try FirebaseBootstrap.configureApp()
        } catch {
            assertionFailure("Firebase bootstrap failed: \(error.localizedDescription)")
            print("Firebase bootstrap failed: \(error.localizedDescription)")
        }
        configureAppearance()

        // Push notifications setup
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }

        return ExternalNavigationRouter.handleExternalURL(url)
    }

    // MARK: - Appearance

    private func configureAppearance() {
        let accent = UIColor(TournamentPalette.accent)
        let ink = UIColor(TournamentPalette.ink)
        let muted = UIColor(TournamentPalette.inkMuted)
        let surface = UIColor(TournamentPalette.surfaceStrong.opacity(0.94))
        let border = UIColor(TournamentPalette.border)

        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithTransparentBackground()
        navigationAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        navigationAppearance.backgroundColor = surface
        navigationAppearance.shadowColor = border.withAlphaComponent(0.35)
        navigationAppearance.largeTitleTextAttributes = [.foregroundColor: ink]
        navigationAppearance.titleTextAttributes = [.foregroundColor: ink]
        UIBarButtonItem.appearance().tintColor = accent

        UINavigationBar.appearance().standardAppearance = navigationAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navigationAppearance
        UINavigationBar.appearance().compactAppearance = navigationAppearance
        UINavigationBar.appearance().tintColor = accent

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithTransparentBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        tabAppearance.backgroundColor = surface
        tabAppearance.shadowColor = border.withAlphaComponent(0.4)

        let itemAppearance = tabAppearance.stackedLayoutAppearance
        itemAppearance.normal.iconColor = muted
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: muted]
        itemAppearance.selected.iconColor = accent
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: accent]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = muted
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        NotificationCenter.default.post(
            name: Notification.Name("FCMTokenRefreshed"),
            object: token
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let matchId = userInfo["matchId"] as? String, !matchId.isEmpty {
            Task { @MainActor in
                ExternalNavigationRouter.queueMatchNavigation(matchId)
            }
        } else if let teamId = userInfo["teamId"] as? String, !teamId.isEmpty {
            Task { @MainActor in
                ExternalNavigationRouter.queueTeamNavigation(teamId)
            }
        } else if let tipo = userInfo["tipo"] as? String,
                  tipo == "playerCard" || tipo == "playerCardPronta",
                  let playerId = userInfo["playerId"] as? String, !playerId.isEmpty {
            // Solo la figurina pronta: le push "in generazione" e "fallita"
            // portano lo stesso playerId ma vogliono Account, non la scheda.
            Task { @MainActor in
                ExternalNavigationRouter.queuePlayerNavigation(playerId)
            }
        }
        completionHandler()
    }
}

// MARK: - App Entry Point

@main
struct TorneoMultipaloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var appState: AppState

    init() {
        // Firebase is configured by AppDelegate.didFinishLaunchingWithOptions.
        // By the time SwiftUI init runs, AppDelegate has already executed.
        // We do NOT call FirebaseBootstrap here to avoid double-init race conditions.
        _appState = State(initialValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appState)
                // La palette è progettata solo per light mode: forziamo lo schema
                // per evitare contrasti (testo scuro su sfondo scuro) in dark mode.
                .preferredColorScheme(.light)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FCMTokenRefreshed"))) { notification in
                    guard let token = notification.object as? String else { return }
                    appState.notificationService.updateToken(token)
                    guard !appState.runtimeSafety.protectsRealData else { return }
                    Task {
                        do {
                            if appState.authService.currentUser != nil {
                                try await appState.cloudFunctionsService.registerFcmToken(
                                    token: token,
                                    installationId: appState.notificationService.installationId
                                )
                            } else {
                                try await appState.cloudFunctionsService.registerFcmTokenPublic(
                                    token: token,
                                    installationId: appState.notificationService.installationId
                                )
                            }
                            try? await appState.notificationService.syncPreferencesIfPossible(
                                cloudFunctionsService: appState.cloudFunctionsService
                            )
                        } catch {
                            print("FCM token registration failed: \(error.localizedDescription)")
                        }
                    }
                }
                .onChange(of: appState.authService.currentUser?.uid) { _, newUid in
                    guard let token = appState.notificationService.fcmToken else { return }
                    guard !appState.runtimeSafety.protectsRealData else { return }
                    Task {
                        do {
                            if let newUid, !newUid.isEmpty {
                                try await appState.cloudFunctionsService.registerFcmToken(
                                    token: token,
                                    installationId: appState.notificationService.installationId
                                )
                            } else {
                                try await appState.cloudFunctionsService.registerFcmTokenPublic(
                                    token: token,
                                    installationId: appState.notificationService.installationId
                                )
                            }
                            try? await appState.notificationService.syncPreferencesIfPossible(
                                cloudFunctionsService: appState.cloudFunctionsService
                            )
                        } catch {
                            print("FCM token re-registration failed: \(error.localizedDescription)")
                        }
                    }
                }
                .onOpenURL { url in
                    _ = ExternalNavigationRouter.handleExternalURL(url)
                }
                // Tabellone live (fino a 4 partite in griglia sulla lock
                // screen): qui si registra solo il token push-to-start, la
                // Live Activity la avvia il server quando una partita parte.
                .task {
                    LiveScoreboardService.shared.begin(
                        tournamentId: appState.tournamentSelectionStore.currentTournamentId
                    )
                }
                .onChange(of: appState.tournamentSelectionStore.currentTournamentId) { _, newTid in
                    LiveScoreboardService.shared.begin(tournamentId: newTid)
                }
        }
    }
}

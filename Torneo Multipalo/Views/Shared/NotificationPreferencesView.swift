import SwiftUI

struct NotificationPreferencesView: View {
    @Environment(AppState.self) private var appState
    private var notificationService: NotificationService {
        appState.notificationService
    }

    var body: some View {
        TournamentScreen {
            ScrollView {
                VStack(spacing: 16) {
                    authorizationSection
                    if notificationService.permissionGranted {
                        tournamentSection
                        teamSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Notifiche")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await notificationService.refreshAuthorizationStatus()
        }
    }

    @ViewBuilder
    private var authorizationSection: some View {
        TournamentFormSection(
            title: "Stato notifiche",
            icon: "bell.badge"
        ) {
            HStack {
                Image(systemName: authIcon)
                    .foregroundStyle(authColor)
                Text(authLabel)
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.ink)
                Spacer()
                if notificationService.authorizationState == .denied {
                    Button("Impostazioni") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var tournamentSection: some View {
        TournamentFormSection(
            title: "Torneo",
            subtitle: "Ricevi aggiornamenti sulle partite del torneo",
            icon: "trophy"
        ) {
            Toggle(isOn: tournamentBinding) {
                Label("Edizione \(appState.activeEdition)", systemImage: "sportscourt")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.ink)
            }
            .tint(TournamentPalette.accent)
        }
    }

    @ViewBuilder
    private var teamSection: some View {
        let teams = appState.editionTeams.sorted { $0.displayName < $1.displayName }
        if !teams.isEmpty {
            TournamentFormSection(
                title: "Squadre",
                subtitle: "Scegli le squadre di cui vuoi seguire le partite",
                icon: "person.3"
            ) {
                ForEach(teams, id: \.teamId) { team in
                    Toggle(isOn: teamBinding(for: team.teamId)) {
                        HStack(spacing: 10) {
                            TournamentTeamLogo(
                                urlString: team.logoURL,
                                size: 28,
                                placeholderTint: TournamentPalette.accent
                            )
                            Text(team.displayName)
                                .font(.subheadline)
                                .foregroundStyle(TournamentPalette.ink)
                        }
                    }
                    .tint(TournamentPalette.accent)
                }
            }
        }
    }

    private var tournamentBinding: Binding<Bool> {
        Binding(
            get: { notificationService.subscribedEditionIds.contains(appState.activeEdition) },
            set: { newValue in
                Task {
                    try? await notificationService.setTournamentSubscription(
                        enabled: newValue,
                        edition: appState.activeEdition,
                        cloudFunctionsService: appState.cloudFunctionsService
                    )
                }
            }
        )
    }

    private func teamBinding(for teamId: String) -> Binding<Bool> {
        Binding(
            get: { notificationService.subscribedTeamIds.contains(teamId) },
            set: { newValue in
                Task {
                    try? await notificationService.setTeamSubscription(
                        enabled: newValue,
                        teamId: teamId,
                        edition: appState.activeEdition,
                        cloudFunctionsService: appState.cloudFunctionsService
                    )
                }
            }
        )
    }

    private var authIcon: String {
        switch notificationService.authorizationState {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        }
    }

    private var authColor: Color {
        switch notificationService.authorizationState {
        case .authorized: return TournamentPalette.success
        case .denied: return TournamentPalette.danger
        case .notDetermined: return TournamentPalette.warm
        }
    }

    private var authLabel: String {
        switch notificationService.authorizationState {
        case .authorized: return "Notifiche attive"
        case .denied: return "Notifiche disattivate"
        case .notDetermined: return "Permesso non richiesto"
        }
    }
}

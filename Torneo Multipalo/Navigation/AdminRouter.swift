import SwiftUI
import FirebaseAuth

struct AdminRouter: View {
    @Environment(AppState.self) private var appState

    private var partiteDaGiocare: Int {
        appState.matches.filter { !$0.isPlayed && !$0.isStarted }.count
    }

    private var partiteInCorso: Int {
        appState.matches.filter { $0.isStarted && !$0.isPlayed }.count
    }

    private var liveMatches: [Match] {
        appState.matches.filter { $0.isStarted && !$0.isPlayed }
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: 16) {
                        TournamentHeroCard(
                            eyebrow: "Pannello admin",
                            title: "Controllo torneo e operazioni live",
                            subtitle: "Calendario, draw, strumenti e stato torneo sotto una grammatica visiva finalmente coerente con il resto dell'app.",
                            accent: TournamentPalette.accent,
                            systemImage: "gearshape.2.fill"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 16)

                        if let email = appState.authService.currentUser?.email {
                            TournamentFormSection(
                                title: "Profilo amministratore",
                                subtitle: email,
                                icon: "person.crop.circle.badge.checkmark"
                            ) {
                                if let playerId = appState.authService.playerIdIfAdmin {
                                    NavigationLink(destination: PlayerDashboardView(playerId: playerId, isNested: true)) {
                                        Label("Il mio profilo giocatore", systemImage: "person.fill")
                                            .tournamentButtonChrome(.secondary)
                                    }
                                    .buttonStyle(.tournamentPress)
                                }

                                NavigationLink(destination: NotificationPreferencesView()) {
                                    Label("Notifiche", systemImage: "bell.badge")
                                        .tournamentButtonChrome(.neutral)
                                }
                                .buttonStyle(.tournamentPress)

                                // Phase 3c — picker torneo (auto-hide se < 2 tornei).
                                TournamentPickerLinkSection()
                            }
                            .padding(.horizontal, 16)
                        }

                        if partiteInCorso > 0 {
                            sectionCard(title: "Partite in corso", subtitle: "\(partiteInCorso) partite live adesso") {
                                ForEach(liveMatches) { match in
                                    let resolved = appState.resolvedTeams(for: match)
                                    NavigationLink(destination: LiveMatchAdminView(match: match)) {
                                        adminRow(
                                            title: "\(resolved.team1.name) vs \(resolved.team2.name)",
                                            subtitle: "\(match.team1Goals) - \(match.team2Goals)",
                                            icon: "play.circle.fill"
                                        )
                                    }
                                    .buttonStyle(.tournamentPress)
                                }
                            }
                        }

                        sectionCard(title: "Gestione torneo", subtitle: "Calendario, draw e stato live del torneo.") {
                            NavigationLink(destination: AdminCalendarView()) {
                                adminRow(
                                    title: "Calendario partite",
                                    subtitle: partiteInCorso > 0 ? "\(partiteInCorso) partite live adesso" : "Programma e controllo partite",
                                    icon: "calendar"
                                )
                            }
                            .buttonStyle(.tournamentPress)

                            NavigationLink(destination: AdminDrawView()) {
                                adminRow(
                                    title: "Inserisci calendario",
                                    subtitle: "Assegna lettere A-G e pubblica i gironi",
                                    icon: "calendar.badge.plus"
                                )
                            }
                            .buttonStyle(.tournamentPress)
                        }

                        sectionCard(title: "Strumenti", subtitle: "Accesso rapido alle aree di supporto.") {
                            NavigationLink(destination: TeamsListView()) {
                                adminRow(
                                    title: "Lista squadre",
                                    subtitle: "\(appState.teams.count) squadre registrate",
                                    icon: "person.3"
                                )
                            }
                            .buttonStyle(.tournamentPress)

                            NavigationLink(destination: AdminToolsView()) {
                                adminRow(
                                    title: "Strumenti admin",
                                    subtitle: "Push, diagnostica e info ambiente",
                                    icon: "wrench.and.screwdriver"
                                )
                            }
                            .buttonStyle(.tournamentPress)
                        }

                        SimulateTournamentSection()
                            .padding(.horizontal, 16)

                        TournamentFormSection(
                            title: "Stato torneo",
                            subtitle: "\(partiteDaGiocare) partite ancora da giocare",
                            icon: "clock"
                        ) {
                            Button(role: .destructive) {
                                appState.authService.logout()
                            } label: {
                                Label("Esci dall'account", systemImage: "rectangle.portrait.and.arrow.right")
                                    .tournamentButtonChrome(.destructive)
                            }
                            .buttonStyle(.tournamentPress)
                        }
                        .padding(.horizontal, 16)

                        AccountDeletionSection()
                            .padding(.horizontal, 16)

                        LegalLinksSection()
                            .padding(.horizontal, 16)

                        Spacer(minLength: 24)
                    }
                }
            }
            .navigationTitle("Pannello Admin")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func sectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(title: title, subtitle: subtitle)
            content()
        }
        .tournamentCard()
        .padding(.horizontal, 16)
    }

    private func adminRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(TournamentPalette.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TournamentPalette.accentSoft)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .padding(.vertical, 4)
    }
}

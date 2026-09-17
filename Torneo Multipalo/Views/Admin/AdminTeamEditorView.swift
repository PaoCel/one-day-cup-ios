import SwiftUI

struct AdminTeamEditorView: View {
    private enum Section: Int, CaseIterable {
        case rosa
        case squadra

        var title: String {
            switch self {
            case .rosa: return "Gestisci rosa"
            case .squadra: return "Dati squadra"
            }
        }
    }

    let teamId: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var vm = TeamDashboardViewModel()
    @State private var selectedSection: Section = .rosa

    var body: some View {
        NavigationStack {
            TournamentScreen {
                VStack(spacing: 0) {
                    sectionTabs

                    if vm.isLoading {
                        LoadingView(message: "Caricamento strumenti admin...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let team = vm.team {
                        Group {
                            switch selectedSection {
                            case .squadra:
                                squadraTab(team: team)
                            case .rosa:
                                RosterView(teamId: teamId, team: team, players: vm.players)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "Squadra non trovata",
                            message: "Impossibile aprire la modalità modifica per questa squadra."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle(vm.team?.nomeSquadra ?? "Modifica squadra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .onAppear {
            vm.start(teamId: teamId, firestoreService: appState.firestoreService, includeRequests: false)
        }
        .onDisappear {
            vm.stop()
        }
    }

    private var sectionTabs: some View {
        HStack(spacing: 8) {
            ForEach(Section.allCases, id: \.rawValue) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedSection == section ? Color.white : TournamentPalette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    selectedSection == section
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [TournamentPalette.accent, TournamentPalette.accentDeep],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(TournamentPalette.surfaceStrong)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    selectedSection == section ? TournamentPalette.accent : TournamentPalette.border,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(10)
        .tournamentCard(padding: 0)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func squadraTab(team: Team) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                adminSummaryCard(team: team)

                NavigationLink(destination: TeamManagementView(teamId: teamId, team: team)) {
                    editorActionCard(
                        title: "Modifica dati squadra",
                        subtitle: "Aggiorna logo, nome, colori e riferimenti della squadra.",
                        icon: "pencil.line"
                    )
                }
                .buttonStyle(.tournamentPress)

                Button {
                    selectedSection = .rosa
                } label: {
                    editorActionCard(
                        title: "Gestisci rosa",
                        subtitle: "Aggiungi giocatori nuovi e svincola quelli già presenti.",
                        icon: "person.2.fill"
                    )
                }
                .buttonStyle(.tournamentPress)

                infoCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private func adminSummaryCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                TournamentTeamLogo(
                    urlString: team.logoSquadra,
                    size: 72,
                    placeholderTint: Color(hex: team.colori.principale) ?? TournamentPalette.accent
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(team.nomeSquadra)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)

                    Text("Qui l'admin può intervenire come proprietario della squadra sull'edizione corrente.")
                        .font(.subheadline)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                TournamentPill(label: "\(vm.players.count) giocatori", tone: .accent)
                TournamentPill(label: "Edizione \(appState.activeEdition)", tone: .neutral)
            }
        }
        .tournamentCard()
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TournamentSectionHeader(
                title: "Cosa puoi fare qui",
                subtitle: "La rosa si gestisce dalla tab dedicata oppure dal pulsante qui sopra."
            )

            Text("Da questa modalità puoi cambiare il logo, aggiornare le informazioni della squadra, aggiungere giocatori nuovi e svincolare quelli già presenti. L'admin lavora sugli stessi dati live usati dal proprietario squadra.")
                .font(.subheadline)
                .foregroundStyle(TournamentPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tournamentCard()
    }

    private func editorActionCard(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TournamentPalette.accentSoft)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TournamentPalette.accent)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .tournamentCard()
    }
}

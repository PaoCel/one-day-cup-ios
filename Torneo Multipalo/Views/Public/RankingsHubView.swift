import SwiftUI

private enum RankingsSection: String, CaseIterable, Identifiable {
    case standings = "Squadre"
    case statistics = "Individuali"
    case ranking = "Ranking"

    var id: String { rawValue }

    /// Il ranking vale su tutte le edizioni: mostrargli accanto il selettore
    /// edizione farebbe leggere "Ed. 1" sopra un numero che non dipende da
    /// quell'edizione.
    var usesEdition: Bool { self != .ranking }
}

struct RankingsHubView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: RankingsSection = .standings
    @State private var showStandingsShareSheet = false

    var body: some View {
        NavigationStack {
            TournamentScreen {
                VStack(spacing: 12) {
                    sectionPicker
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    currentSection
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .navigationTitle("Torneo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedSection.usesEdition {
                    ToolbarItem(placement: .topBarTrailing) {
                        TournamentEditionMenu()
                    }
                }
            }
            .sheet(isPresented: $showStandingsShareSheet) {
                StandingsStoryShareView(
                    entries: appState.standings,
                    edition: appState.selectedEdition
                )
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 8) {
            ForEach(RankingsSection.allCases) { section in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedSection = section
                    }
                } label: {
                    Text(section.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            selectedSection == section ? Color.white : TournamentPalette.ink
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    selectedSection == section
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [TournamentPalette.accent, TournamentPalette.accentDeep],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(TournamentPalette.surfaceStrong.opacity(0.9))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    selectedSection == section
                                        ? TournamentPalette.accent.opacity(0.08)
                                        : TournamentPalette.border,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TournamentPalette.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var currentSection: some View {
        switch selectedSection {
        case .standings:
            StandingsView(
                showsNavigation: false,
                showsEditionStrip: false,
                showsScreenBackground: false
            )

        case .statistics:
            StatsView(
                showsNavigation: false,
                showsEditionStrip: false,
                showsScreenBackground: false
            )

        case .ranking:
            RankingView(showsScreenBackground: false)
        }
    }
}

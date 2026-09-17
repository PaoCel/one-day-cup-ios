import SwiftUI

struct TeamsListView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            TournamentScreen {
                TeamsListContent(
                    teams: appState.editionTeams,
                    isLoading: appState.isLoadingTeams
                )
            }
            .navigationTitle("Squadre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    TournamentEditionMenu()
                }
            }
            .refreshable {
                await appState.loadTeams()
            }
        }
    }
}

private struct TeamsListContent: View {
    let teams: [EditionTeam]
    let isLoading: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if isLoading && teams.isEmpty {
                    LoadingView()
                } else if teams.isEmpty {
                    EmptyStateView(
                        icon: "person.3",
                        title: "Nessuna squadra",
                        message: "Nessuna squadra trovata per l'edizione selezionata."
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(teams) { team in
                            NavigationLink(destination: TeamDetailView(team: team)) {
                                MinimalTeamRowView(team: team)
                            }
                            .buttonStyle(.tournamentPress)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }
}

#Preview("Squadre Refresh") {
    NavigationStack {
        TournamentScreen {
            TeamsPreviewGrid(teams: previewTeams)
        }
        .navigationTitle("Squadre")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TeamsPreviewGrid: View {
    let teams: [EditionTeam]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(teams) { team in
                    MinimalTeamRowView(team: team)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct MinimalTeamRowView: View {
    let team: EditionTeam

    private var primaryColor: Color {
        Color(hex: team.colors.principale) ?? TournamentPalette.accent
    }

    private var secondaryColor: Color {
        Color(hex: team.colors.secondario) ?? TournamentPalette.surfaceStrong
    }

    var body: some View {
        HStack(spacing: 14) {
            TeamColorSwatches(primary: primaryColor, secondary: secondaryColor)

            TournamentTeamLogo(
                urlString: team.logoURL,
                size: 46,
                placeholderTint: primaryColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(team.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(2)

                if team.playedEditions.count > 0 {
                    Text(team.playedEditions.count == 1 ? "1 edizione" : "\(team.playedEditions.count) edizioni")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TournamentPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }
}

private var previewTeams: [EditionTeam] {
    [
        EditionTeam(
            edition: 2026,
            team: Team(
                id: "lomazzo",
                nomeSquadra: "Lomazzo Team",
                colori: .init(principale: "#0F2D5C", secondario: "#DAB85E"),
                logoSquadra: nil,
                primaEdizione: 2024,
                ultimeEdizioni: [2024, 2025, 2026],
                playersCount: 15
            )
        ),
        EditionTeam(
            edition: 2026,
            team: Team(
                id: "rovers",
                nomeSquadra: "Rovers Granata",
                colori: .init(principale: "#7A1620", secondario: "#182B52"),
                logoSquadra: nil,
                primaEdizione: 2023,
                ultimeEdizioni: [2023, 2024, 2025, 2026],
                playersCount: 17
            )
        ),
        EditionTeam(
            edition: 2026,
            team: Team(
                id: "materos",
                nomeSquadra: "Materos Football Club",
                colori: .init(principale: "#0B4BDB", secondario: "#F6C948"),
                logoSquadra: nil,
                primaEdizione: 2026,
                ultimeEdizioni: [2026],
                playersCount: 14
            )
        ),
        EditionTeam(
            edition: 2026,
            team: Team(
                id: "laghi",
                nomeSquadra: "Laghi FC",
                colori: .init(principale: "#0D5A48", secondario: "#F1F5F9"),
                logoSquadra: nil,
                primaEdizione: 2025,
                ultimeEdizioni: [2025, 2026],
                playersCount: 16
            )
        )
    ]
}

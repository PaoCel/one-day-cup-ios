import SwiftUI

/// Ricerca su TUTTO l'archivio: `squadre` e `giocatori` sono collection
/// GLOBALI, quindi l'identità di una squadra o di un giocatore non ha (e non
/// deve avere) scope di torneo o edizione. Prima si poteva arrivare a una
/// scheda solo passando dalle partite dell'edizione in corso: un giocatore di
/// un'edizione passata, o una squadra che quest'anno non gioca, erano
/// irraggiungibili. Gemello di `renderGlobalSearchResults` nella PWA
/// (`js/features/index-tabs.js`).
@MainActor
@Observable
final class GlobalSearchStore {
    private(set) var teams: [Team] = []
    private(set) var players: [Player] = []
    private(set) var isLoading = false
    private var didLoad = false

    /// L'indice si carica alla prima ricerca vera, non all'avvio dell'app:
    /// sono due letture intere e non servono a chi non cerca.
    func loadIfNeeded(using service: FirestoreService) async {
        guard !didLoad, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        async let teamsTask = try? await service.fetchTeams()
        async let playersTask = try? await service.fetchAllPlayers()

        let loadedTeams = await teamsTask ?? []
        let loadedPlayers = await playersTask ?? []

        teams = loadedTeams.sorted { $0.nomeSquadra.localizedCaseInsensitiveCompare($1.nomeSquadra) == .orderedAscending }
        players = loadedPlayers.sorted { $0.nomeCompleto.localizedCaseInsensitiveCompare($1.nomeCompleto) == .orderedAscending }
        didLoad = true
    }

    func matchingTeams(_ query: String) -> [Team] {
        let q = Self.normalize(query)
        guard q.count >= 2 else { return [] }
        return teams.filter { Self.normalize($0.nomeSquadra).contains(q) }.prefix(6).map { $0 }
    }

    func matchingPlayers(_ query: String) -> [Player] {
        let q = Self.normalize(query)
        guard q.count >= 2 else { return [] }
        return players.filter { Self.normalize($0.nomeCompleto).contains(q) }.prefix(8).map { $0 }
    }

    /// Senza accenti e senza maiuscole: "Nicolò" si deve trovare con "nicolo".
    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct GlobalSearchResultsView: View {
    let query: String
    let store: GlobalSearchStore

    @Environment(AppState.self) private var appState

    private var teams: [Team] { store.matchingTeams(query) }
    private var players: [Player] { store.matchingPlayers(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if store.isLoading && teams.isEmpty && players.isEmpty {
                LoadingView()
                    .frame(maxWidth: .infinity)
            } else if teams.isEmpty && players.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "Nessun risultato",
                    message: "Nessuna squadra o giocatore con questo nome."
                )
            } else {
                if !teams.isEmpty {
                    section(title: "Squadre") {
                        ForEach(teams) { team in
                            NavigationLink {
                                TeamDetailView(team: editionTeam(for: team))
                            } label: {
                                row(
                                    imageURL: team.logoSquadra,
                                    fallbackIcon: "shield.fill",
                                    title: team.nomeSquadra,
                                    subtitle: nil
                                )
                            }
                            .buttonStyle(.tournamentPress)
                        }
                    }
                }

                if !players.isEmpty {
                    section(title: "Giocatori") {
                        ForEach(players) { player in
                            NavigationLink {
                                PlayerDetailView(player: player)
                            } label: {
                                row(
                                    imageURL: player.displayPhotoURL,
                                    fallbackIcon: "person.fill",
                                    title: player.nomeCompleto,
                                    subtitle: teamName(for: player)
                                )
                            }
                            .buttonStyle(.tournamentPress)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.heavy))
                .kerning(1.4)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(imageURL: String?, fallbackIcon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            // Logo e foto nudi, senza cornice: il fondo lo mette solo il
            // placeholder quando l'immagine manca.
            CachedAsyncImage(
                urlString: imageURL,
                placeholderIcon: fallbackIcon,
                placeholderColor: TournamentPalette.accent.opacity(0.12),
                contentMode: .fit,
                contentAlignment: .top
            )
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.07))
        )
    }

    /// La scheda squadra ragiona per edizione: se la squadra partecipa a quella
    /// in corso usiamo quella, altrimenti la partecipazione più recente che
    /// conosciamo — altrimenti si aprirebbe una scheda vuota.
    private func editionTeam(for team: Team) -> EditionTeam {
        if let id = team.id, let existing = appState.editionTeams.first(where: { $0.teamId == id }) {
            return existing
        }
        let participation = appState.allParticipations
            .filter { $0.squadraId == team.id }
            .max { $0.edizione < $1.edizione }
        return EditionTeam(
            edition: participation?.edizione ?? appState.selectedEdition,
            team: team,
            participation: participation,
            preferLiveTeamData: participation == nil
        )
    }

    private func teamName(for player: Player) -> String? {
        guard let teamId = player.teamId, !teamId.isEmpty else { return "Senza squadra" }
        return store.teams.first { $0.id == teamId }?.nomeSquadra ?? "Senza squadra"
    }
}

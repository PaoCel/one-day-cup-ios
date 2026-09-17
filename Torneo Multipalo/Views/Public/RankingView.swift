import SwiftUI

/// Ranking generale del torneo. È **trasversale alle edizioni**: qui il
/// selettore edizione non compare, altrimenti si legge "Ed. 1" sopra un numero
/// che con l'edizione 1 non c'entra.
///
/// Tre stati, decisi dai soli dati: se la collezione ha righe le mostra; se è
/// vuota e il ranking non è mai stato calcolato dice "in arrivo"; se è vuota
/// ma un calcolo c'è già stato dice "non disponibile", che è un guasto, non
/// un'attesa. Non è un placeholder da sostituire: appena la function popola
/// il DB questa stessa schermata si riempie, senza pubblicare nulla.
/// Cosa si guarda dentro "Ranking": il punteggio storico delle squadre oppure
/// le statistiche generali dei giocatori. Non è un secondo punteggio: per i
/// giocatori sono gol, presenze e premi di tutta la storia del torneo.
enum RankingScope: String, CaseIterable, Identifiable {
    case teams = "Squadre"
    case players = "Giocatori"

    var id: String { rawValue }
    var icon: String { self == .teams ? "shield.lefthalf.filled" : "person.fill" }
}

/// Come ordinare la lista giocatori.
enum RankingPlayerSort: String, CaseIterable, Identifiable {
    case goals = "Gol"
    case matches = "Presenze"
    case mvp = "MVP"

    var id: String { rawValue }
}

struct RankingPlayerRowData: Identifiable {
    let id: String
    let name: String
    let pictureURL: String?
    /// Stemma dell'ultima squadra in cui ha giocato. Senza foto la riga restava
    /// spoglia — un cerchio grigio e un nome — e con dieci giocatori senza foto
    /// la classifica non si distingueva una riga dall'altra.
    let teamLogo: String?
    let matches: Int
    let goals: Int
    let mvp: Int

    var goalsPerMatch: Double { matches > 0 ? Double(goals) / Double(matches) : 0 }
}

struct RankingView: View {
    var showsScreenBackground = true

    @Environment(AppState.self) private var appState
    @State private var entries: [RankingEntry] = []
    @State private var status: RankingStatus?
    @State private var isLoading = true
    @State private var scope: RankingScope = .teams
    @State private var playerSort: RankingPlayerSort = .goals
    @State private var players: [RankingPlayerRowData] = []
    @State private var isLoadingPlayers = false

    var body: some View {
        Group {
            if showsScreenBackground {
                TournamentScreen { content }
            } else {
                content
            }
        }
        .task(id: appState.currentTournamentId) {
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                scopePicker

                if scope == .teams {
                    teamsSection
                } else {
                    playersSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    private var scopePicker: some View {
        HStack(spacing: 8) {
            ForEach(RankingScope.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { scope = option }
                } label: {
                    Label(option.rawValue, systemImage: option.icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(scope == option ? TournamentPalette.accent : TournamentPalette.inkMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(scope == option
                                           ? TournamentPalette.accent.opacity(0.14)
                                           : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(scope == option
                                             ? TournamentPalette.accent.opacity(0.45)
                                             : TournamentPalette.inkMuted.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .task(id: scope) {
            if scope == .players && players.isEmpty { await loadPlayers() }
        }
    }

    @ViewBuilder
    private var teamsSection: some View {
        if isLoading {
            LoadingView()
        } else if entries.isEmpty {
            emptyCard
        } else {
            header
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                NavigationLink {
                    TeamDetailLoaderView(teamId: entry.teamId, teamName: entry.teamName)
                } label: {
                    RankingRow(entry: entry, position: index + 1, showsChevron: true)
                }
                .buttonStyle(.tournamentPress)
            }
        }
    }

    @ViewBuilder
    private var playersSection: some View {
        sortPicker

        if isLoadingPlayers {
            LoadingView()
        } else if players.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.largeTitle)
                    .foregroundStyle(TournamentPalette.accent)
                Text("Nessuna statistica")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                Text("Per questo torneo non ci sono ancora partite giocate con giocatori in rosa.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .tournamentCard()
        } else {
            ForEach(Array(sortedPlayers.enumerated()), id: \.element.id) { index, row in
                NavigationLink {
                    PlayerDetailLoaderView(playerId: row.id, displayName: row.name, pictureURL: row.pictureURL)
                } label: {
                    RankingPlayerRow(row: row, position: index + 1, sort: playerSort)
                }
                .buttonStyle(.tournamentPress)
            }

            ArchiveIncompleteNote()
        }
    }

    private var sortPicker: some View {
        HStack(spacing: 8) {
            ForEach(RankingPlayerSort.allCases) { option in
                Button {
                    playerSort = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(playerSort == option ? TournamentPalette.accent : TournamentPalette.inkMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(playerSort == option
                                           ? TournamentPalette.accent.opacity(0.12)
                                           : Color.clear)
                        )
                        .overlay(
                            Capsule().stroke(playerSort == option
                                             ? TournamentPalette.accent.opacity(0.45)
                                             : TournamentPalette.inkMuted.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.tournamentPress)
            }
            Spacer(minLength: 0)
        }
    }

    private var sortedPlayers: [RankingPlayerRowData] {
        players.sorted { a, b in
            switch playerSort {
            case .goals:
                if a.goals != b.goals { return a.goals > b.goals }
            case .matches:
                if a.matches != b.matches { return a.matches > b.matches }
            case .mvp:
                if a.mvp != b.mvp { return a.mvp > b.mvp }
            }
            if a.goals != b.goals { return a.goals > b.goals }
            if a.matches != b.matches { return a.matches > b.matches }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text((status?.title ?? "Ranking").uppercased())
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(TournamentPalette.ink)
            Text(status?.description ?? "")
                .font(.footnote)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    /// Vuoto mai calcolato = attesa. Vuoto dopo un calcolo = qualcosa non ha
    /// funzionato, e dirlo "in arrivo" sarebbe una bugia.
    private var emptyCard: some View {
        let mancante = status?.hasEverComputed == true
        return VStack(spacing: 12) {
            Image(systemName: mancante ? "exclamationmark.triangle" : "chart.line.uptrend.xyaxis")
                .font(.largeTitle)
                .foregroundStyle(mancante ? TournamentPalette.warm : TournamentPalette.accent)

            Text(mancante ? "Ranking non disponibile" : "Ranking in arrivo")
                .font(.headline.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)

            Text(mancante
                 ? "Il punteggio non è raggiungibile in questo momento. Riprova più tardi."
                 : (status?.rankingDescription
                    ?? "Il punteggio generale del torneo, calcolato su tutte le edizioni. Arriva presto."))
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .tournamentCard()
    }

    private func loadPlayers() async {
        isLoadingPlayers = true
        defer { isLoadingPlayers = false }
        let tid = appState.currentTournamentId
        let service = PlayerCareerStatsService()
        guard let rows = try? await service.fetchAllCareerStats(tournamentId: tid) else {
            players = []
            return
        }
        // La foto non sta nell'aggregato carriera: si prende dagli snapshot di
        // rosa già in memoria e, per chi non ce l'ha lì, dai doc giocatore
        // (una lettura sola per tutta la lista, come fa la ricerca globale).
        var photos = Dictionary(
            appState.allParticipations.flatMap { $0.giocatoriDettagliati ?? [] }
                .compactMap { player -> (String, String)? in
                    guard let id = player.giocatoreId, let url = player.pictureURL, !url.isEmpty else { return nil }
                    return (id, url)
                },
            uniquingKeysWith: { first, _ in first }
        )
        if let allPlayers = try? await appState.firestoreService.fetchAllPlayers() {
            for player in allPlayers {
                guard let id = player.firestoreIdentifier ?? player.id else { continue }
                if photos[id] != nil { continue }
                if let url = player.displayPhotoURL, !url.isEmpty { photos[id] = url }
            }
        }
        // Lo stemma per giocatore: ogni iscrizione e' di una squadra, quindi il
        // suo logo vale per tutti i suoi giocatori. A parita' di giocatore vince
        // l'edizione piu' recente, che e' la squadra in cui sta adesso.
        var stemmi: [String: String] = [:]
        for part in appState.allParticipations.sorted(by: { $0.edizione < $1.edizione }) {
            guard let logo = part.logoSquadra, !logo.isEmpty else { continue }
            for player in part.giocatoriDettagliati ?? [] {
                guard let id = player.giocatoreId, !id.isEmpty else { continue }
                stemmi[id] = logo
            }
        }
        players = rows.map { row in
            RankingPlayerRowData(
                id: row.stats.playerId,
                name: row.stats.nomeCompleto ?? "Giocatore",
                pictureURL: photos[row.stats.playerId],
                teamLogo: stemmi[row.stats.playerId],
                matches: row.tournament.matches,
                goals: row.tournament.goals,
                mvp: row.tournament.mvp
            )
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let tid = appState.currentTournamentId
        // lo stato serve solo a scegliere il messaggio quando non c'è niente:
        // sono i dati a decidere se la tabella si popola
        status = try? await appState.firestoreService.fetchRankingStatus(tournamentId: tid)
        entries = (try? await appState.firestoreService.fetchRanking(tournamentId: tid)) ?? []
    }
}

struct RankingRow: View {
    let entry: RankingEntry
    let position: Int
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(positionColor)
                .frame(width: 26, alignment: .center)

            TournamentTeamLogo(
                urlString: entry.logo,
                size: 34,
                placeholderTint: TournamentPalette.accent
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)

                if let played = entry.editionsPlayed, played > 0 {
                    Text(played == 1 ? "1 edizione" : "\(played) edizioni")
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }

            Spacer(minLength: 8)

            Text(entry.scoreLabel)
                .font(.title3.weight(.black))
                .foregroundStyle(TournamentPalette.accent)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted.opacity(0.6))
            }
        }
        .tournamentCard()
    }

    private var positionColor: Color {
        switch position {
        case 1: return TournamentPalette.warm
        case 2, 3: return TournamentPalette.accent
        default: return TournamentPalette.inkMuted
        }
    }
}

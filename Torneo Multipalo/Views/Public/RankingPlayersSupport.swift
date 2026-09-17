import SwiftUI

/// Riga della classifica giocatori del Ranking: foto, nome, e sotto il
/// contesto (presenze, media gol, MVP). Il numero grande a destra è la metrica
/// con cui la lista è ordinata, così l'ordine si spiega da solo.
struct RankingPlayerRow: View {
    let row: RankingPlayerRowData
    let position: Int
    let sort: RankingPlayerSort

    var body: some View {
        HStack(spacing: 12) {
            Text("\(position)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(positionColor)
                .frame(width: 26, alignment: .center)

            CachedAsyncImage(
                urlString: row.pictureURL,
                placeholderIcon: "person.fill",
                placeholderColor: TournamentPalette.accent.opacity(0.15),
                contentMode: .fill,
                fillAnchorY: 0.2
            )
            .frame(width: 40, height: 40)
            .clipShape(Circle())
            // Lo stemma della squadra appoggiato alla foto: quando la foto non
            // c'è è l'unica cosa che distingue una riga dall'altra, e quando
            // c'è dice comunque per chi gioca senza rubare spazio al nome.
            .overlay(alignment: .bottomTrailing) {
                if let logo = row.teamLogo, !logo.isEmpty {
                    TournamentTeamLogo(urlString: logo, size: 18)
                        .background(Circle().fill(TournamentPalette.surfaceStrong))
                        .offset(x: 3, y: 3)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)

                Text(detailLine)
                    .font(.caption2)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(metric)")
                .font(.title3.weight(.black))
                .foregroundStyle(TournamentPalette.accent)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted.opacity(0.6))
        }
        .tournamentCard()
    }

    private var metric: Int {
        switch sort {
        case .goals: return row.goals
        case .matches: return row.matches
        case .mvp: return row.mvp
        }
    }

    private var detailLine: String {
        var parts = ["\(row.matches) pres."]
        if row.matches > 0 {
            parts.append(String(format: "%.2f gol/partita", row.goalsPerMatch).replacingOccurrences(of: ".", with: ","))
        }
        if row.mvp > 0 { parts.append("\(row.mvp) MVP") }
        return parts.joined(separator: " · ")
    }

    private var positionColor: Color {
        switch position {
        case 1: return TournamentPalette.warm
        case 2, 3: return TournamentPalette.accent
        default: return TournamentPalette.inkMuted
        }
    }
}

/// Le edizioni giocate prima dell'app hanno dati parziali (rose perdute, solo
/// i capocannonieri fra i marcatori, partite mai registrate). Senza dirlo, chi
/// legge "4 gol" pensa che l'app sbagli.
struct ArchiveIncompleteNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(TournamentPalette.accent)
            Text("I dati delle edizioni passate non sono completi: alcune partite e alcuni marcatori storici non sono mai stati registrati. Da qui in avanti l'archivio è aggiornato in tempo reale.")
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }
}

/// Apre la scheda squadra partendo dal solo id: il ranking porta id e nome,
/// non l'oggetto `Team`.
struct TeamDetailLoaderView: View {
    let teamId: String
    let teamName: String

    @Environment(AppState.self) private var appState
    @State private var team: EditionTeam?
    @State private var failed = false

    var body: some View {
        Group {
            if let team {
                TeamDetailView(team: team)
            } else if failed {
                TournamentScreen {
                    VStack(spacing: 10) {
                        Image(systemName: "questionmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(TournamentPalette.inkMuted)
                        Text("Scheda non disponibile")
                            .font(.headline)
                            .foregroundStyle(TournamentPalette.ink)
                        Text("La squadra \(teamName) non è più in archivio.")
                            .font(.subheadline)
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }
                    .padding()
                }
            } else {
                LoadingView()
            }
        }
        .task {
            // `editionTeam` sa già mettere insieme squadra viva e snapshot di
            // partecipazione: e' la stessa strada della classifica.
            if let resolved = appState.editionTeam(for: teamId) {
                team = resolved
                return
            }
            // Squadra di un'edizione che questo torneo non ha in memoria
            // (ranking storico): si prende il doc e si costruisce a mano.
            if let fetched = try? await appState.firestoreService.fetchTeam(id: teamId) {
                team = EditionTeam(edition: appState.selectedEdition, team: fetched, preferLiveTeamData: true)
                return
            }
            failed = true
        }
    }
}

/// Stessa cosa per il giocatore: dall'aggregato carriera arriva solo il
/// `playerId`. Se il profilo non esiste più si ripiega sulla scheda storica,
/// che sa vivere di solo nome.
struct PlayerDetailLoaderView: View {
    let playerId: String
    let displayName: String
    var pictureURL: String?

    @Environment(AppState.self) private var appState
    @State private var player: Player?
    @State private var resolved = false

    var body: some View {
        Group {
            if let player {
                PlayerDetailView(player: player)
            } else if resolved {
                HistoricPlayerDetailView(
                    profile: HistoricPlayerProfile(
                        id: playerId,
                        playerId: playerId,
                        displayName: displayName,
                        pictureURL: pictureURL,
                        teamName: "",
                        edition: appState.selectedEdition
                    )
                )
            } else {
                LoadingView()
            }
        }
        .task {
            player = try? await appState.firestoreService.fetchPlayer(id: playerId)
            resolved = true
        }
    }
}

/// Un premio della scheda giocatore. `sort` ordina: prima i titoli (per
/// piazzamento), poi i capocannonieri (per edizione), poi gli MVP.
struct PlayerAward: Identifiable {
    let id: String
    let sort: (Int, Int, Int)
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    struct Podium {
        let label: String
        let icon: String
        let tint: Color
    }

    /// Premio scritto a mano sul doc edizione (`premi`). `order` è l'ordine
    /// con cui il torneo li consegna, non un'importanza.
    struct Official {
        let label: String
        let icon: String
        let order: Int
    }

    static func official(_ tipo: String) -> Official? {
        switch tipo {
        case "mvp": return Official(label: "Miglior giocatore", icon: "star.fill", order: 0)
        case "capocannoniere": return Official(label: "Capocannoniere", icon: "soccerball", order: 1)
        case "difensore": return Official(label: "Miglior difensore", icon: "shield.fill", order: 2)
        case "portiere": return Official(label: "Miglior portiere", icon: "hand.raised.fill", order: 3)
        default: return nil
        }
    }

    static func podium(_ position: Int) -> Podium? {
        switch position {
        case 1: return Podium(label: "Campione", icon: "trophy.fill", tint: TournamentPalette.warm)
        case 2: return Podium(label: "Finalista", icon: "medal.fill", tint: TournamentPalette.inkMuted)
        case 3: return Podium(label: "Terzo posto", icon: "medal.fill", tint: TournamentPalette.accent)
        default: return nil
        }
    }
}

extension String {
    /// Sotto l'etichetta "TORNEO" il prefisso "Torneo " è rumore che fa
    /// troncare il nome vero: "Torneo Multipalo" → "Multipalo".
    var scopeMenuName: String {
        let trimmed = trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("torneo "), trimmed.count > 7 else { return trimmed }
        return String(trimmed.dropFirst(7))
    }
}

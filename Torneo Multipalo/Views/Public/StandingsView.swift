import SwiftUI

struct StandingsView: View {
    var showsNavigation = true
    var showsEditionStrip = true
    var showsScreenBackground = true

    @Environment(AppState.self) private var appState
    @State private var showStandingsShareSheet = false
    @State private var expanded = false
    @State private var mostraCriteri = false

    private var groupedStandings: [(group: String?, entries: [StandingsEntry])] {
        let gironi = appState.gironi(for: appState.selectedEdition)
        guard !gironi.isEmpty else {
            return [(nil, appState.standings)]
        }
        // Passa da `AppState`: qui si chiamava `StandingsCalculator.calculate`
        // a mano, senza regole, e i gironi finivano a 3/1/0 mentre la
        // classifica generale usava il 2/1 dello shootout.
        return gironi.map { ($0, appState.standings(for: appState.selectedEdition, girone: $0)) }
    }

    var body: some View {
        Group {
            if showsNavigation {
                NavigationStack {
                    decoratedContent
                        .navigationTitle("Classifica")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            if showsEditionStrip {
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
            } else {
                decoratedContent
            }
        }
    }

    @ViewBuilder
    private var decoratedContent: some View {
        if showsScreenBackground {
            TournamentScreen { standingsContent }
        } else {
            standingsContent
        }
    }

    private var standingsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsEditionStrip && !showsNavigation {
                    HStack {
                        Spacer()
                        TournamentEditionMenu()
                    }
                    .padding(.horizontal, 16)
                }

                if appState.isLoadingMatches && appState.standings.isEmpty {
                    LoadingView()
                } else if appState.standings.isEmpty {
                    EmptyStateView(
                        icon: "list.number",
                        title: "Classifica non disponibile",
                        message: "La classifica verrà calcolata dopo le prime partite"
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(groupedStandings, id: \.group) { section in
                            standingsTable(
                                entries: section.entries,
                                title: section.group.map { "Girone \($0)" } ?? "Classifica"
                            )
                        }

                        // "E allora chi passa?" e' la domanda che arriva al
                        // campo ogni volta che due squadre finiscono a pari
                        // punti. Sta sotto la classifica, dove nasce.
                        Button {
                            mostraCriteri = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "list.number")
                                    .font(.caption.weight(.bold))
                                Text("Criteri di parità")
                                    .font(.subheadline.weight(.semibold))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(TournamentPalette.inkMuted)
                            }
                            .foregroundStyle(TournamentPalette.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(TournamentPalette.surfaceStrong.opacity(0.94))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(TournamentPalette.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.tournamentPress)

                        NavigationLink(destination: KnockoutBracketView(showsNavigation: false)) {
                            knockoutEntryCard
                        }
                        .buttonStyle(.tournamentPress)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await appState.loadMatches()
        }
        .sheet(isPresented: $mostraCriteri) {
            CriteriParitaView()
        }
    }

    private func standingsTable(entries: [StandingsEntry], title: String) -> some View {
        VStack(spacing: 0) {
            // Titolo e intestazione delle colonne stavano nella stessa riga:
            // il titolo mangiava lo spazio di "#" e "Squadra" e si leggeva
            // "lassifica" sovrapposto alle colonne. Ora sono due righe, e il
            // bottone dice cosa fa invece di essere un chevron muto.
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(TournamentPalette.ink)

                    Spacer(minLength: 8)

                    // "Gol" descriveva la colonna che comparirebbe, non
                    // l'azione: chi legge non sa che il bottone allarga.
                    Text(expanded ? "Mostra meno" : "Mostra più")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TournamentPalette.accent)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(TournamentPalette.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tournamentPress)

            StandingsTableHeader(expanded: expanded)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let row = StandingsTableRow(position: index + 1, entry: entry, expanded: expanded)

                if let team = appState.editionTeam(for: entry.teamId) {
                    NavigationLink(destination: TeamDetailView(team: team)) {
                        row
                    }
                    .buttonStyle(.tournamentPress)
                } else {
                    row
                }

                if index < entries.count - 1 {
                    Divider()
                        .background(TournamentPalette.divider)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
        .tournamentCard(padding: 0)
    }

    private var knockoutEntryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(TournamentPalette.warm)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TournamentPalette.warm.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Tabellone finale")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                Text("Percorso verso la finale")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .tournamentCard()
    }
}

/// Larghezze condivise da intestazione e righe: se divergono le colonne si
/// disallineano e la tabella diventa illeggibile.
private enum StandingsColumn {
    static let rank: CGFloat = 30
    static let points: CGFloat = 34
    static let stat: CGFloat = 26
    static let diff: CGFloat = 30
}

private struct StandingsTableHeader: View {
    let expanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("#")
                .frame(width: StandingsColumn.rank, alignment: .center)
            Text("SQUADRA")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PT")
                .frame(width: StandingsColumn.points, alignment: .center)
            // "P" stava per "partite giocate", ma in italiano si legge "perse":
            // le giocate sono "G" e la P è la colonna delle sconfitte, che
            // prima non c'era proprio.
            Text("G")
                .frame(width: StandingsColumn.stat, alignment: .center)
            // Nove colonne su un telefono lasciavano al nome una settantina di
            // punti: "Roma Impero" diventava "Roma I…". I gol prendono il posto
            // di V/N/P invece di aggiungersi.
            if expanded {
                Text("GF")
                    .frame(width: StandingsColumn.stat, alignment: .center)
                Text("GS")
                    .frame(width: StandingsColumn.stat, alignment: .center)
                Text("DR")
                    .frame(width: StandingsColumn.diff, alignment: .center)
            } else {
                Text("V")
                    .frame(width: StandingsColumn.stat, alignment: .center)
                Text("N")
                    .frame(width: StandingsColumn.stat, alignment: .center)
                Text("P")
                    .frame(width: StandingsColumn.stat, alignment: .center)
            }
        }
        .font(.system(size: 10, weight: .bold))
        .tracking(0.5)
        .foregroundStyle(TournamentPalette.inkMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TournamentPalette.surfaceMuted)
    }
}

private struct StandingsTableRow: View {
    let position: Int
    let entry: StandingsEntry
    let expanded: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(position)")
                .font(.caption.weight(.bold))
                .foregroundStyle(rankColor)
                .frame(width: StandingsColumn.rank, alignment: .center)

            HStack(spacing: 6) {
                TournamentTeamLogo(
                    urlString: entry.teamLogo,
                    size: 26,
                    placeholderTint: TournamentPalette.accent
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.teamName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if entry.isPlaying {
                        Text("In corso")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(TournamentPalette.danger)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(entry.points)")
                .font(.subheadline.weight(.black))
                .foregroundStyle(TournamentPalette.accent)
                .frame(width: StandingsColumn.points, alignment: .center)

            valueCell("\(entry.played)", width: StandingsColumn.stat)
            if expanded {
                valueCell("\(entry.goalsFor)", width: StandingsColumn.stat)
                valueCell("\(entry.goalsAgainst)", width: StandingsColumn.stat)
                valueCell(entry.goalDifference > 0 ? "+\(entry.goalDifference)" : "\(entry.goalDifference)", width: StandingsColumn.diff)
            } else {
                valueCell("\(entry.won)", width: StandingsColumn.stat)
                valueCell("\(entry.drawn)", width: StandingsColumn.stat)
                valueCell("\(entry.lost)", width: StandingsColumn.stat)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(position.isMultiple(of: 2) ? TournamentPalette.surfaceStrong : TournamentPalette.surface)
    }

    private func valueCell(_ value: String, width: CGFloat, weight: Font.Weight = .semibold) -> some View {
        Text(value)
            .font(.caption.weight(weight))
            .foregroundStyle(TournamentPalette.ink)
            .frame(width: width, alignment: .center)
    }

    private var rankColor: Color {
        switch position {
        case 1: return TournamentPalette.warm
        case 2: return TournamentPalette.accent
        case 3: return TournamentPalette.success
        default: return TournamentPalette.ink
        }
    }
}

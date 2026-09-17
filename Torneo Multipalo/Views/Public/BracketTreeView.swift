import SwiftUI

/// Il tabellone disegnato come un tabellone: colonne da sinistra a destra,
/// spareggio → quarti → semifinali → finale, con le forcelle che collegano ogni
/// coppia al turno dopo.
///
/// Prima era un elenco di card in due colonne "lato sinistro / lato destro" con
/// **una sola partita per fase**: con quattro quarti ne mostrava due, le
/// forcelle non c'erano e non si capiva chi incrocia chi. Non sembrava un
/// tabellone perché non lo era.
///
/// La geometria è fissa apposta, niente `GeometryReader`: le posizioni si
/// calcolano dai conteggi (`4 / n` righe per colonna) e il disegno delle linee
/// deve poter usare le stesse coordinate delle card. Con un layout elastico le
/// due cose divergono e le linee finiscono a mezz'aria.
///
/// Le colonne sono costruite dalle **partite vere**, non dagli slot del
/// formato: gli slot ne conoscono uno per lato e basta.
struct BracketTreeView: View {
    let colonne: [Colonna]
    /// Finale 3°/4° e simili: non stanno nell'albero, si giocano a lato.
    let piazzamenti: [Match]

    @Environment(AppState.self) private var appState

    struct Colonna: Identifiable {
        let id: String
        let titolo: String
        let partite: [Match]
        /// Lo spareggio non è un turno dell'albero: è un innesto che porta a un
        /// solo quarto, e va allineato a quello invece che centrato sulla colonna.
        var innesto = false
    }

    // Misure: cambiarle qui cambia tutto, card e linee insieme.
    private let larghezzaCard: CGFloat = 158
    private let altezzaCard: CGFloat = 62
    private let passoColonna: CGFloat = 34
    private let unita: CGFloat = 78

    /// Quante righe alte è l'albero: le decide la colonna più affollata.
    private var righe: Int {
        max(colonne.filter { !$0.innesto }.map(\.partite.count).max() ?? 1, 1)
    }

    private var altezzaTotale: CGFloat { CGFloat(righe) * unita }

    private func x(_ indice: Int) -> CGFloat {
        CGFloat(indice) * (larghezzaCard + passoColonna)
    }

    /// Centro verticale della partita `j` in una colonna di `n`: le colonne più
    /// corte si allargano in proporzione, così la semifinale cade esattamente a
    /// metà fra i due quarti che la alimentano.
    private func y(_ j: Int, su n: Int, innesto: Bool) -> CGFloat {
        if innesto { return unita * 0.5 }
        let passo = CGFloat(righe) / CGFloat(max(n, 1))
        return unita * passo * (CGFloat(j) + 0.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    intestazioni
                    ZStack(alignment: .topLeading) {
                        forcelle
                        card
                    }
                    .frame(
                        width: x(colonne.count - 1) + larghezzaCard,
                        height: altezzaTotale
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            if !piazzamenti.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    etichettaColonna("Piazzamenti")
                    ForEach(piazzamenti, id: \.id) { m in
                        NavigationLink(destination: MatchDetailView(match: m)) {
                            BracketMatchTile(match: m, larghezza: nil)
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var intestazioni: some View {
        HStack(spacing: passoColonna) {
            ForEach(colonne) { colonna in
                etichettaColonna(colonna.titolo)
                    .frame(width: larghezzaCard, alignment: .leading)
            }
        }
    }

    private func etichettaColonna(_ testo: String) -> some View {
        Text(testo.uppercased())
            .font(.caption2.weight(.black))
            .tracking(0.9)
            .foregroundStyle(TournamentPalette.inkMuted)
    }

    private var card: some View {
        ForEach(Array(colonne.enumerated()), id: \.element.id) { c, colonna in
            ForEach(Array(colonna.partite.enumerated()), id: \.element.id) { j, partita in
                NavigationLink(destination: MatchDetailView(match: partita)) {
                    BracketMatchTile(match: partita, larghezza: larghezzaCard)
                        .frame(width: larghezzaCard, height: altezzaCard)
                }
                .buttonStyle(.tournamentPress)
                .offset(
                    x: x(c),
                    y: y(j, su: colonna.partite.count, innesto: colonna.innesto) - altezzaCard / 2
                )
            }
        }
    }

    /// Le linee a gomito fra una colonna e la successiva.
    private var forcelle: some View {
        Path { p in
            for c in 0..<max(colonne.count - 1, 0) {
                let da = colonne[c]
                let a = colonne[c + 1]
                guard !a.partite.isEmpty, !da.partite.isEmpty else { continue }

                let xPartenza = x(c) + larghezzaCard
                let xArrivo = x(c + 1)
                let xMezzo = (xPartenza + xArrivo) / 2

                for (j, _) in da.partite.enumerated() {
                    // Dove sbuca questa partita nel turno dopo: due partite
                    // confluiscono in una, tranne l'innesto dello spareggio che
                    // ne alimenta una sola.
                    let destinazione = da.innesto ? 0 : j * a.partite.count / max(da.partite.count, 1)
                    let y1 = y(j, su: da.partite.count, innesto: da.innesto)
                    let y2 = y(destinazione, su: a.partite.count, innesto: a.innesto)

                    p.move(to: CGPoint(x: xPartenza, y: y1))
                    p.addLine(to: CGPoint(x: xMezzo, y: y1))
                    p.addLine(to: CGPoint(x: xMezzo, y: y2))
                    p.addLine(to: CGPoint(x: xArrivo, y: y2))
                }
            }
        }
        .stroke(TournamentPalette.border, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }
}

/// Una partita nel tabellone: due righe, stemma + nome + gol.
struct BracketMatchTile: View {
    let match: Match
    var larghezza: CGFloat?

    @Environment(AppState.self) private var appState

    private var vincente: String? { match.resolvedWinnerTeamId }

    var body: some View {
        let squadre = appState.resolvedTeams(for: match)

        return VStack(spacing: 0) {
            riga(nome: squadre.team1.name, logo: squadre.team1.logo,
                 gol: match.team1Goals, teamId: match.team1)
            Divider().background(TournamentPalette.divider)
            riga(nome: squadre.team2.name, logo: squadre.team2.logo,
                 gol: match.team2Goals, teamId: match.team2)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TournamentPalette.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(match.isLive ? TournamentPalette.success : TournamentPalette.border,
                        lineWidth: match.isLive ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(width: larghezza)
    }

    private func riga(nome: String, logo: String?, gol: Int, teamId: String) -> some View {
        // Chi ha vinto resta in nero pieno, chi ha perso sbiadisce: a colpo
        // d'occhio il percorso del vincitore si legge senza contare i gol.
        let haPerso = vincente != nil && vincente != teamId && !teamId.isEmpty

        return HStack(spacing: 6) {
            TournamentTeamLogo(urlString: logo, size: 18)
            Text(nome)
                .font(.system(size: 11, weight: haPerso ? .medium : .bold))
                .foregroundStyle(haPerso ? TournamentPalette.inkMuted : TournamentPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if match.isStarted || match.isPlayed {
                Text("\(gol)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(haPerso ? TournamentPalette.inkMuted : TournamentPalette.accent)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
    }
}

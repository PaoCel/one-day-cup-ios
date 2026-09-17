import SwiftUI

/// Come si sciolgono le parità in classifica.
///
/// È la domanda che al campo arriva sempre, e sempre nel momento peggiore: due
/// squadre a pari punti e qualcuno che chiede "e allora chi passa?". Averla
/// scritta dentro l'app evita la discussione.
///
/// ⚠️ **Questo elenco deve restare uguale a `StandingsCalculator`**, che è il
/// codice che ordina davvero. Un elenco che promette un criterio che il motore
/// non applica è peggio che non averlo: qui si scrive quello che il codice fa,
/// non quello che dice il regolamento — che su questo punto è sbagliato e
/// l'owner lo correggerà.
struct CriteriParitaView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Nella Mormon il pareggio dei gironi si risolve allo shootout, e i punti
    /// non sono 3/0: chi vince ne prende 2, chi perde 1. La domanda la fa
    /// `ShootoutTerminology`, che conosce anche il ripiego per torneo.
    private var terminologia: ShootoutTerminology {
        ShootoutTerminology.resolve(
            tournament: appState.currentTournament,
            tournamentId: appState.currentTournamentId,
            fase: "girone"
        )
    }

    private var haShootout: Bool { terminologia.shortTitle == "Shootout" }

    private var criteri: [(String, String)] {
        [
            ("Punti", "Vittoria 3, pareggio 1, sconfitta 0."),
            ("Scontri diretti · punti", "Conta solo quello che le squadre in parità hanno fatto fra loro."),
            ("Scontri diretti · differenza reti", "Sempre nella mini-classifica fra loro."),
            ("Scontri diretti · gol fatti", "Chi ne ha segnati di più negli incroci diretti."),
            ("Differenza reti", "Su tutte le partite del girone."),
            ("Gol fatti", "Su tutte le partite del girone."),
            ("Meno cartellini rossi", "Il fair play conta, e conta in negativo."),
            ("Meno cartellini gialli", "Ultimo criterio sportivo."),
            ("Sorteggio", "Se è ancora parità, decide la monetina dell'organizzazione.")
        ]
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("A parità di punti l'ordine si decide così, un criterio alla volta: si passa al successivo solo se il precedente non separa.")
                            .font(.subheadline)
                            .foregroundStyle(TournamentPalette.inkMuted)

                        VStack(spacing: 0) {
                            ForEach(Array(criteri.enumerated()), id: \.offset) { indice, c in
                                rigaCriterio(numero: indice + 1, titolo: c.0, dettaglio: c.1)
                                if indice < criteri.count - 1 {
                                    Divider().padding(.leading, 46)
                                }
                            }
                        }
                        .tournamentCard()

                        if haShootout {
                            nota(
                                terminologia.shortTitle,
                                "Nei gironi il pareggio si risolve allo shootout: 2 punti a chi vince, 1 a chi perde. I gol dello shootout non entrano né nella classifica marcatori né nella differenza reti."
                            )
                        }

                        nota(
                            "Se sono più di due",
                            "La mini-classifica degli scontri diretti si ricalcola solo fra le squadre ancora in parità. Se una si stacca, le altre ripartono dal primo criterio fra loro."
                        )
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Criteri di parità")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    private func rigaCriterio(numero: Int, titolo: String, dettaglio: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(numero)")
                .font(.caption.weight(.black).monospacedDigit())
                .foregroundStyle(TournamentPalette.accent)
                .frame(width: 26, height: 26)
                .background(Circle().fill(TournamentPalette.accentSoft))

            VStack(alignment: .leading, spacing: 3) {
                Text(titolo)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                Text(dettaglio)
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }

    private func nota(_ titolo: String, _ testo: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titolo.uppercased())
                .font(.caption2.weight(.black))
                .tracking(0.8)
                .foregroundStyle(TournamentPalette.accent)
            Text(testo)
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TournamentPalette.surfaceMuted)
        )
    }
}

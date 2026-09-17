#if DEBUG
import SwiftUI

// Usa le righe della cronaca vera e dati locali: la verifica grafica non
// richiede di registrare gol o cartellini su partite del torneo.
struct DebugMatchEventIconsView: View {
    private let events = [
        MatchEvent(tipo: "gol", giocatoreNome: "Marco Rossi", minuto: 4),
        MatchEvent(tipo: "rigore_segnato", giocatoreNome: "Luca Bianchi", minuto: 9),
        MatchEvent(tipo: "rigore_sbagliato", giocatoreNome: "Paolo Verdi", minuto: 14),
        MatchEvent(tipo: "rigore_parato", giocatoreNome: "Andrea Neri", minuto: 19),
        MatchEvent(tipo: "autogol", giocatoreNome: "Matteo Riva", minuto: 24),
        MatchEvent(tipo: "ammonizione", giocatoreNome: "Davide Conti", minuto: 28),
        MatchEvent(tipo: "espulsione", giocatoreNome: "Simone Galli", minuto: 32),
        MatchEvent(tipo: "espulsione", giocatoreNome: "Federico Costa", minuto: 36, doubleYellow: true)
    ]

    private var isMormon: Bool {
        ProcessInfo.processInfo.arguments.contains("--odc-event-icons-mormon")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isMormon ? "MORMON LEAGUE" : "TORNEO MULTIPALO")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isMormon ? TournamentPalette.warm : TournamentPalette.accent)
                    Text("Cronaca")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)
                    Text("Anteprima icone · dati dimostrativi")
                        .font(.caption)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }

                VStack(spacing: 4) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        MatchEventRow(event: event, isTeam1: index.isMultiple(of: 2))
                    }
                }
                .tournamentCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("SHOOTOUT")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                    MatchShootoutKickRow(
                        kick: Match.PenaltyKick(playerName: "Marco Rossi", teamId: "demo-1", scored: true, order: 1),
                        isTeam1: true
                    )
                    MatchShootoutKickRow(
                        kick: Match.PenaltyKick(playerName: "Luca Bianchi", teamId: "demo-2", scored: false, order: 2),
                        isTeam1: false
                    )
                }
                .tournamentCard()

                HStack(spacing: 6) {
                    ForEach(MatchEventSymbol.allCases, id: \.self) { symbol in
                        MatchEventIcon(symbol, size: 24)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(TournamentPalette.ink, in: RoundedRectangle(cornerRadius: 18))
            }
            .padding(16)
        }
        .background(TournamentPalette.backgroundTop)
    }
}
#endif

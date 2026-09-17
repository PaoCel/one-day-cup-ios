import ActivityKit
import Foundation

/// Live Activity "tabellone": UNA attività per tutte le partite **in campo**,
/// invece di una attività per partita — iOS le impilerebbe e in una giornata di
/// torneo, con due campi in parallelo, la lock screen diventa illeggibile.
///
/// Solo quelle in campo, e sono al massimo due: prima si riempivano i buchi con
/// le prossime in programma e usciva una griglia 2×2 di cui un riquadro solo
/// vivo, troppo alta per lo spazio che iOS concede — veniva tagliata a metà.
///
/// Gemello identico in `Torneo Multipalo/Models/ScoreboardActivityAttributes.swift`:
/// i due target sono moduli diversi e il file dev'essere in entrambi (stessa
/// convenzione già usata da MatchActivityAttributes).
///
/// ⚠️ Il payload di una push ActivityKit sta in 4 KB: i nomi squadra arrivano
/// già accorciati dal server (`home`/`away`), e le chiavi sono corte apposta.
struct ScoreboardActivityAttributes: ActivityAttributes {
    /// Dati fissi per tutta la vita dell'attività: il torneo.
    var tournamentId: String
    var tournamentName: String
    var accentHex: String?
    var editionLabel: String?

    struct MatchLine: Codable, Hashable, Identifiable {
        var id: String        // matchId
        var home: String
        var away: String
        /// Id delle due squadre: servono a trovare lo stemma sul disco
        /// condiviso (`logo_{teamId}.png`). L'immagine nei 4 KB del payload non
        /// ci sta, il nome del file sì.
        var hi: String?
        var ai: String?
        var hg: Int
        var ag: Int
        var minute: Int?      // nil = non ancora iniziata
        var live: Bool
        var done: Bool
        var field: String?

        var statusLabel: String {
            if done { return "FT" }
            if live { return minute.map { "\($0)'" } ?? "LIVE" }
            return field.map { "Campo \($0)" } ?? "—"
        }
    }

    struct ContentState: Codable, Hashable {
        /// Al massimo tre, e in pratica due: tanti sono i campi.
        var matches: [MatchLine]
        /// Ultimo evento in una riga sola ("⚽ Alfa 2-1 Bravo"), opzionale.
        var headline: String?
    }
}

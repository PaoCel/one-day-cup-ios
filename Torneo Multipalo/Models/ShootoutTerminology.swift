import Foundation

/// Nomenclatura del tie-break, per-torneo e per-fase.
///
/// Nel Multipalo il pareggio si risolve ai calci di rigore. Nei **gironi** della
/// Mormon League no: si va allo *shootout* — tot secondi per segnare in 1v1 col
/// portiere. La meccanica dei dati è identica (`penaltyDetails` resta una
/// sequenza di tentativi con esito), quindi qui cambiano **solo le parole**:
/// nessuna view deve sapere in che torneo si trova, chiede l'etichetta e basta.
///
/// La sorgente è il campo `groupTieBreak` del doc `tournaments/{id}`. Finché il
/// backend non lo popola vale la mappa di fallback qui sotto, altrimenti la
/// Mormon continuerebbe a dire "rigori" nei gironi anche dopo il rilascio.
struct ShootoutTerminology {
    /// Intestazione lunga della card in Cronaca.
    let title: String
    /// Titolo corto, per navigation bar e pill.
    let shortTitle: String
    /// CTA che porta l'admin alla sequenza da "partita terminata".
    let callToAction: String
    /// Come si chiama il singolo tentativo ("Tiro #3" vs "Tentativo #3").
    let attemptNoun: String
    /// Etichetta sopra la rosa, nel pannello admin.
    let shooterPickerTitle: String
    /// Coda della frase del vincitore, senza il nome squadra.
    let winsSuffix: String

    func winnerSentence(team: String) -> String {
        "\(team) vince \(winsSuffix)!"
    }

    static let penalties = ShootoutTerminology(
        title: "Calci di rigore",
        shortTitle: "Rigori",
        callToAction: "Vai ai rigori",
        attemptNoun: "Tiro",
        shooterPickerTitle: "Chi tira il rigore",
        winsSuffix: "ai rigori"
    )

    static let shootout = ShootoutTerminology(
        title: "Shootout",
        shortTitle: "Shootout",
        callToAction: "Vai allo shootout",
        attemptNoun: "Tentativo",
        shooterPickerTitle: "Chi va allo shootout",
        winsSuffix: "allo shootout"
    )

    /// Valori ammessi per `tournaments/{id}.groupTieBreak`.
    private static let shootoutMode = "shootout"

    /// La regola vale **solo nei gironi**: la fase a eliminazione resta ai
    /// rigori anche in Mormon (backlog §8a.4, deciso dall'owner il 2026-07-23).
    static func resolve(tournament: Tournament?, tournamentId: String, fase: String?) -> ShootoutTerminology {
        guard TournamentPhaseKey.isGroupStage(fase) else { return .penalties }

        let configured = normalized(tournament?.groupTieBreak)
        let mode = configured ?? fallbackMode(forTournamentId: tournamentId)
        return mode == shootoutMode ? .shootout : .penalties
    }

    /// Ponte finché `groupTieBreak` non è sui doc torneo: la Mormon nasce già
    /// con lo shootout nei gironi, tutti gli altri con i rigori.
    private static func fallbackMode(forTournamentId tournamentId: String) -> String {
        switch normalized(tournamentId) {
        case "mormon":
            return shootoutMode
        default:
            return "rigori"
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

struct StandingsEntry: Identifiable {
    var id: String { teamId }
    var teamId: String
    var teamName: String
    var teamLogo: String?
    var pointsForWin: Int = 3
    var pointsForDraw: Int = 1
    var pointsForLoss: Int = 0
    var played: Int = 0
    var won: Int = 0
    var drawn: Int = 0
    var lost: Int = 0
    var goalsFor: Int = 0
    var goalsAgainst: Int = 0
    var redCards: Int = 0
    var yellowCards: Int = 0
    var tieBreakExplanation: String?
    var manualPointsAdjustment: Int = 0
    /// Quanto lo shootout si scosta dalla vittoria (o dalla sconfitta) piena.
    ///
    /// Il regolamento Mormon 2026 dà **2 punti a chi vince lo shootout e 1 a
    /// chi lo perde**: non è una vittoria piena e non è un pareggio. In tabella
    /// resta una V e una P — è così che la si legge — ma i punti no, e con la
    /// sola formula `vinte × 3` non c'era modo di dirlo.
    ///
    /// È uno scarto e non un totale perché i due valori viaggiano **sulla
    /// partita**: resta la regola in vigore il giorno in cui si è giocato, e
    /// una partita che non dichiara niente vale zero di scarto, cioè si
    /// comporta come prima.
    var shootoutPointsDelta: Int = 0
    var isPlaying: Bool = false
    var points: Int {
        (won * pointsForWin) + (drawn * pointsForDraw) + (lost * pointsForLoss)
            + shootoutPointsDelta + manualPointsAdjustment
    }
    var goalDifference: Int { goalsFor - goalsAgainst }
}

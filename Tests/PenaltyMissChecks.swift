import Foundation

@main
struct PenaltyMissChecks {
    static func main() throws {
        let homeKeeper = PenaltyMiss.Goalkeeper(playerId: "home-gk", playerName: "Portiere casa", entryId: "home")
        let awayKeeper = PenaltyMiss.Goalkeeper(playerId: "away-gk", playerName: "Portiere ospite", entryId: "away")
        func attempt(_ outcome: PenaltyMiss.Outcome, team: String? = "home", away: PenaltyMiss.Goalkeeper? = awayKeeper) -> PenaltyMiss {
            PenaltyMiss.resolve(outcome: outcome, kickingEntryId: team, home: "home", away: "away",
                                homeGoalkeeper: homeKeeper, awayGoalkeeper: away)
        }
        let saved = attempt(.saved)
        precondition(saved.goalkeeper == awayKeeper, "La parata deve andare al portiere avversario")
        precondition(attempt(.saved, team: "away").goalkeeper == homeKeeper)
        precondition(attempt(.offTarget).goalkeeper == nil, "Un tiro fuori non è una parata")
        precondition(attempt(.saved, away: nil).goalkeeper == nil, "Non inventare un portiere")
        precondition(attempt(.saved, team: nil).goalkeeper == nil)
        precondition(attempt(.saved, team: "altra-squadra").goalkeeper == nil)
        precondition(attempt(.saved, away: homeKeeper).goalkeeper == nil, "Non attribuire la parata al tiratore")
        let blank = PenaltyMiss.Goalkeeper(playerId: "  ", playerName: "Solo nome", entryId: "away")
        precondition(attempt(.saved, away: blank).goalkeeper == nil)
        precondition(saved.savedGoalkeeper(against: "home") == awayKeeper)
        precondition(saved.savedGoalkeeper(against: "away") == nil)
        precondition(attempt(.offTarget).savedGoalkeeper(against: "home") == nil)
        let roundTrip = try JSONDecoder().decode(PenaltyMiss.self, from: JSONSerialization.data(withJSONObject: saved.dictionary))
        precondition(roundTrip == saved, "Il salvataggio deve conservare il portiere del momento del tiro")
        let noKeeper = try JSONDecoder().decode(PenaltyMiss.self, from: Data(#"{"outcome":"saved"}"#.utf8))
        precondition(noKeeper.goalkeeper == nil)
        var attempts = [saved, attempt(.offTarget)]
        attempts.removeFirst()
        precondition(attempts.compactMap { $0.savedGoalkeeper(against: "home") }.isEmpty,
                     "Annullando il tiro non deve restare una parata indipendente")
        print("14 controlli superati: direzione, tiro fuori, portiere assente, persistenza e annullamento.")
    }
}

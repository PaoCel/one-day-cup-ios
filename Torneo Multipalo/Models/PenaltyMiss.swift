import Foundation

/// L'esito e il portiere sono una fotografia del tiro, non del portiere
/// attuale: cambiare portiere in seguito non deve spostare una vecchia parata.
struct PenaltyMiss: Codable, Equatable {
    enum Outcome: String, Codable {
        case saved
        case offTarget = "off_target"
    }

    struct Goalkeeper: Codable, Equatable {
        var playerId: String
        var playerName: String?
        var entryId: String
    }

    var outcome: Outcome
    var goalkeeper: Goalkeeper?

    static func resolve(
        outcome: Outcome, kickingEntryId: String?, home: String, away: String,
        homeGoalkeeper: Goalkeeper?, awayGoalkeeper: Goalkeeper?
    ) -> Self {
        var miss = Self(outcome: outcome)
        guard outcome == .saved, home != away,
              !home.isEmpty, !away.isEmpty else { return miss }
        let opponent: String
        let assigned: Goalkeeper?
        if kickingEntryId == home { opponent = away; assigned = awayGoalkeeper }
        else if kickingEntryId == away { opponent = home; assigned = homeGoalkeeper }
        else { return miss }
        guard var assigned, assigned.entryId == opponent else { return miss }
        assigned.playerId = assigned.playerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !assigned.playerId.isEmpty else { return miss }
        miss.goalkeeper = assigned
        return miss
    }

    func savedGoalkeeper(against kickingEntryId: String?) -> Goalkeeper? {
        guard outcome == .saved, let goalkeeper,
              let kickingEntryId, !kickingEntryId.isEmpty,
              !goalkeeper.entryId.isEmpty, goalkeeper.entryId != kickingEntryId,
              !goalkeeper.playerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return goalkeeper
    }

    var dictionary: [String: Any] {
        var data: [String: Any] = ["outcome": outcome.rawValue]
        if outcome == .saved, let goalkeeper {
            var keeper: [String: Any] = ["playerId": goalkeeper.playerId, "entryId": goalkeeper.entryId]
            keeper["playerName"] = goalkeeper.playerName
            data["goalkeeper"] = keeper
        }
        return data
    }
}

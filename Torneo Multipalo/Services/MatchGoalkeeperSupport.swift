import Foundation

enum MatchTeamSlot: String, Identifiable {
    case team1
    case team2

    var id: String { rawValue }

    var goalkeeperFieldName: String {
        switch self {
        case .team1:
            return "team1GoalkeeperPlayerId"
        case .team2:
            return "team2GoalkeeperPlayerId"
        }
    }
}

enum MatchGoalkeeperSupport {
    static func slot(for teamId: String, in match: Match) -> MatchTeamSlot? {
        let normalizedTeamId = normalizedNonEmpty(teamId)
        guard let normalizedTeamId else { return nil }
        if normalizedTeamId == match.team1 { return .team1 }
        if normalizedTeamId == match.team2 { return .team2 }
        return nil
    }

    static func explicitGoalkeeperId(for slot: MatchTeamSlot, in match: Match) -> String? {
        switch slot {
        case .team1:
            return normalizedNonEmpty(match.team1GoalkeeperPlayerId)
        case .team2:
            return normalizedNonEmpty(match.team2GoalkeeperPlayerId)
        }
    }

    static func suggestedGoalkeeperId(
        for teamId: String,
        currentMatch: Match,
        matches: [Match]
    ) -> String? {
        guard let normalizedTeamId = normalizedNonEmpty(teamId) else { return nil }

        let previousMatches = matches
            .filter {
                $0.edizione == currentMatch.edizione
                    && $0.id != currentMatch.id
                    && ($0.team1 == normalizedTeamId || $0.team2 == normalizedTeamId)
                    && sortKey(for: $0) < sortKey(for: currentMatch)
            }
            .sorted { sortKey(for: $0) < sortKey(for: $1) }

        for match in previousMatches.reversed() {
            if match.team1 == normalizedTeamId,
               let goalkeeperId = normalizedNonEmpty(match.team1GoalkeeperPlayerId) {
                return goalkeeperId
            }
            if match.team2 == normalizedTeamId,
               let goalkeeperId = normalizedNonEmpty(match.team2GoalkeeperPlayerId) {
                return goalkeeperId
            }
        }

        return nil
    }

    private static func sortKey(for match: Match) -> (Int, Int, String, String) {
        (
            phasePriority(match.fase),
            match.giornata,
            match.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            match.id ?? ""
        )
    }

    private static func phasePriority(_ fase: String) -> Int {
        switch AwardConfig.normalizePhaseKey(fase) {
        case "girone":
            return 0
        case "ottavi":
            return 1
        case "quarti":
            return 2
        case "semifinali":
            return 3
        case "finale":
            return 4
        default:
            return 5
        }
    }

    private static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

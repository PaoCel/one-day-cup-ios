import Foundation
import FirebaseFirestore

enum MatchGoalkeeperResolver {
    struct Assignment {
        var team1PlayerId: String?
        var team2PlayerId: String?
    }

    static func effectiveAssignments(for matches: [Match]) -> [String: Assignment] {
        var defaultsByTeam: [String: String] = [:]
        var assignments: [String: Assignment] = [:]

        for match in sortedMatches(matches) {
            guard let matchId = match.id else { continue }

            let team1PlayerId = normalizedPlayerId(match.team1GoalkeeperPlayerId) ?? defaultsByTeam[match.team1]
            let team2PlayerId = normalizedPlayerId(match.team2GoalkeeperPlayerId) ?? defaultsByTeam[match.team2]

            assignments[matchId] = Assignment(
                team1PlayerId: team1PlayerId,
                team2PlayerId: team2PlayerId
            )

            if let team1PlayerId {
                defaultsByTeam[match.team1] = team1PlayerId
            }
            if let team2PlayerId {
                defaultsByTeam[match.team2] = team2PlayerId
            }
        }

        return assignments
    }

    static func goalkeeperPlayerId(
        for match: Match,
        teamId: String,
        within matches: [Match]
    ) -> String? {
        guard let matchId = match.id else {
            return normalizedPlayerId(match.goalkeeperPlayerId(for: teamId))
        }

        let assignments = effectiveAssignments(for: matches)
        guard let assignment = assignments[matchId] else {
            return normalizedPlayerId(match.goalkeeperPlayerId(for: teamId))
        }

        switch teamId {
        case match.team1:
            return assignment.team1PlayerId
        case match.team2:
            return assignment.team2PlayerId
        default:
            return nil
        }
    }

    static func sortedMatches(_ matches: [Match]) -> [Match] {
        matches.sorted { lhs, rhs in
            let lhsKey = sortKey(for: lhs)
            let rhsKey = sortKey(for: rhs)

            if lhsKey.edizione != rhsKey.edizione {
                return lhsKey.edizione < rhsKey.edizione
            }
            if lhsKey.phaseRank != rhsKey.phaseRank {
                return lhsKey.phaseRank < rhsKey.phaseRank
            }
            if lhsKey.giornata != rhsKey.giornata {
                return lhsKey.giornata < rhsKey.giornata
            }
            if lhsKey.matchTimeMinutes != rhsKey.matchTimeMinutes {
                return lhsKey.matchTimeMinutes < rhsKey.matchTimeMinutes
            }
            if lhsKey.createdAt != rhsKey.createdAt {
                return lhsKey.createdAt < rhsKey.createdAt
            }
            return (lhs.id ?? "") < (rhs.id ?? "")
        }
    }

    static func normalizedPhase(_ rawPhase: String) -> String {
        TournamentPhaseKey.normalize(rawPhase)
    }

    private struct SortKey {
        var edizione: Int
        var phaseRank: Int
        var giornata: Int
        var matchTimeMinutes: Int
        var createdAt: Date
    }

    private static func sortKey(for match: Match) -> SortKey {
        SortKey(
            edizione: match.edizione,
            phaseRank: phaseRank(for: match.fase),
            giornata: match.giornata,
            matchTimeMinutes: matchTimeToMinutes(match.matchTime),
            createdAt: match.createdAt?.dateValue() ?? .distantPast
        )
    }

    private static func phaseRank(for rawPhase: String) -> Int {
        TournamentPhaseKey.sortRank(rawPhase)
    }

    private static func matchTimeToMinutes(_ rawValue: String?) -> Int {
        guard let rawValue else { return Int.max }
        let trimmed = rawValue
            .components(separatedBy: "-")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawValue
        guard !trimmed.isEmpty else { return Int.max }

        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else {
            return Int.max
        }
        return (hours * 60) + minutes
    }

    private static func normalizedPlayerId(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

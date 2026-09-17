import Foundation
import FirebaseFirestore

enum MatchStaffSupport {
    struct GoalkeeperSeed {
        var selection: Match.GoalkeeperSelection?
        var isInherited: Bool
    }

    static func seededGoalkeeperSelection(
        for teamId: String,
        in currentMatch: Match,
        roster: [Player],
        allMatches: [Match]
    ) -> GoalkeeperSeed {
        if let savedSelection = currentMatch.goalkeeper(for: teamId) {
            return GoalkeeperSeed(
                selection: normalizedGoalkeeperSelection(savedSelection, roster: roster),
                isInherited: false
            )
        }

        guard let inheritedSelection = latestInheritedGoalkeeper(
            for: teamId,
            before: currentMatch,
            roster: roster,
            allMatches: allMatches
        ) else {
            return GoalkeeperSeed(selection: nil, isInherited: false)
        }

        return GoalkeeperSeed(selection: inheritedSelection, isInherited: true)
    }

    /// Returns the single goalkeeper in the roster when exactly one player has `ruoloSquadra`
    /// containing "ortier" (covers "Portiere", "portiere", "PORTIERE", "Portièri", etc.).
    /// Returns nil when there are zero or two-or-more candidates — caller must show a warning.
    static func uniqueGoalkeeper(in roster: [Player]) -> Player? {
        let candidates = roster.filter { player in
            guard let role = player.ruoloSquadra else { return false }
            return role.range(of: "ortier", options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    static func goalkeeperSelection(
        from playerId: String,
        roster: [Player]
    ) -> Match.GoalkeeperSelection? {
        guard let player = roster.first(where: { playerMatchesIdentifier($0, identifier: playerId) }) else {
            return nil
        }
        return Match.GoalkeeperSelection(
            playerId: stablePlayerIdentifier(for: player),
            playerName: player.nomeCompleto
        )
    }

    static func normalizedGoalkeeperSelection(
        _ selection: Match.GoalkeeperSelection,
        roster: [Player]
    ) -> Match.GoalkeeperSelection? {
        if let playerId = normalizedString(selection.playerId),
           let player = roster.first(where: { playerMatchesIdentifier($0, identifier: playerId) }) {
            return Match.GoalkeeperSelection(
                playerId: stablePlayerIdentifier(for: player) ?? playerId,
                playerName: player.nomeCompleto
            )
        }

        if let normalizedName = Player.normalizedLookupName(from: selection.playerName),
           let player = roster.first(where: { Player.normalizedLookupName(from: $0.nomeCompleto) == normalizedName }) {
            return Match.GoalkeeperSelection(
                playerId: stablePlayerIdentifier(for: player),
                playerName: player.nomeCompleto
            )
        }

        guard let playerName = normalizedString(selection.playerName) else {
            return nil
        }

        return Match.GoalkeeperSelection(
            playerId: normalizedString(selection.playerId),
            playerName: playerName
        )
    }

    private static func latestInheritedGoalkeeper(
        for teamId: String,
        before currentMatch: Match,
        roster: [Player],
        allMatches: [Match]
    ) -> Match.GoalkeeperSelection? {
        let currentKey = sortKey(for: currentMatch)

        let candidates = allMatches
            .filter { match in
                match.edizione == currentMatch.edizione
                    && match.id != currentMatch.id
                    && (match.team1 == teamId || match.team2 == teamId)
                    && sortKey(for: match) < currentKey
            }
            .sorted { sortKey(for: $0) > sortKey(for: $1) }

        for candidate in candidates {
            guard let selection = candidate.goalkeeper(for: teamId),
                  let normalized = normalizedGoalkeeperSelection(selection, roster: roster) else {
                continue
            }
            return normalized
        }

        return nil
    }

    private static func stablePlayerIdentifier(for player: Player) -> String? {
        let candidates = [player.firestoreIdentifier, player.playerAuthUid]
            .compactMap(normalizedString(_:))
        return candidates.first
    }

    private static func playerMatchesIdentifier(_ player: Player, identifier: String) -> Bool {
        let normalizedIdentifier = normalizedString(identifier)
        guard let normalizedIdentifier else { return false }

        return [player.firestoreIdentifier, player.playerAuthUid]
            .compactMap(normalizedString(_:))
            .contains(normalizedIdentifier)
    }

    nonisolated private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sortKey(for match: Match) -> MatchSortKey {
        MatchSortKey(
            phaseOrder: phaseOrder(for: match.fase),
            giornata: match.giornata,
            matchTimeMinutes: minutes(from: match.matchTime),
            createdAtSeconds: match.createdAt?.dateValue().timeIntervalSince1970 ?? 0
        )
    }

    private static func phaseOrder(for fase: String) -> Int {
        TournamentPhaseKey.sortRank(fase)
    }

    private static func minutes(from matchTime: String?) -> Int {
        guard let matchTime = normalizedString(matchTime) else { return 0 }
        let startTime = matchTime
            .components(separatedBy: "-")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? matchTime
        let parts = startTime.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return 0
        }
        return (hour * 60) + minute
    }
}

enum MatchSuspensionSupport {
    static func isPlayerSuspended(
        playerId: String?,
        playerName: String?,
        teamId: String,
        in currentMatch: Match,
        within matches: [Match]
    ) -> Bool {
        guard let currentMatchId = currentMatch.id else { return false }
        var pendingSuspension = false
        let teamMatches = MatchGoalkeeperResolver.sortedMatches(
            matches.filter { match in
                match.edizione == currentMatch.edizione
                    && (match.team1 == teamId || match.team2 == teamId)
            }
        )

        for match in teamMatches {
            if match.id == currentMatchId {
                return pendingSuspension
            }

            if pendingSuspension {
                pendingSuspension = false
                continue
            }

            if playerReceivedRedCard(
                playerId: playerId,
                playerName: playerName,
                teamId: teamId,
                in: match
            ) {
                pendingSuspension = true
            }
        }

        return pendingSuspension
    }

    private static func playerReceivedRedCard(
        playerId: String?,
        playerName: String?,
        teamId: String,
        in match: Match
    ) -> Bool {
        let normalizedPlayerId = normalizedString(playerId)
        let normalizedPlayerName = Player.normalizedLookupName(from: playerName)

        return match.safeEventi.contains { event in
            guard isRedCard(event.tipo) else { return false }
            guard normalizedString(event.squadraId) == normalizedString(teamId) else { return false }

            if let normalizedPlayerId,
               normalizedString(event.giocatoreId) == normalizedPlayerId {
                return true
            }

            guard let normalizedPlayerName else { return false }
            return Player.normalizedLookupName(from: event.giocatoreNome) == normalizedPlayerName
        }
    }

    private static func isRedCard(_ rawType: String) -> Bool {
        switch rawType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "red", "red_card", "redcard", "rosso", "cartellino_rosso", "espulsione":
            return true
        default:
            return false
        }
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct MatchSortKey: Comparable {
    let phaseOrder: Int
    let giornata: Int
    let matchTimeMinutes: Int
    let createdAtSeconds: TimeInterval

    static func < (lhs: MatchSortKey, rhs: MatchSortKey) -> Bool {
        if lhs.phaseOrder != rhs.phaseOrder { return lhs.phaseOrder < rhs.phaseOrder }
        if lhs.giornata != rhs.giornata { return lhs.giornata < rhs.giornata }
        if lhs.matchTimeMinutes != rhs.matchTimeMinutes { return lhs.matchTimeMinutes < rhs.matchTimeMinutes }
        return lhs.createdAtSeconds < rhs.createdAtSeconds
    }
}

import Foundation

enum AwardStandingsBuilder {
    struct Entry: Identifiable {
        var id: String
        var playerDocumentId: String?
        var nome: String
        var teamId: String?
        var teamName: String
        var pictureURL: String?
        var jerseyNumber: Int?
        var position: String?
        var rawValue: Int
        var weightedValue: Double
        var matchesCount: Int
        var goalsConceded: Int
        var cleanSheets: Int
        var goalkeeperIndex: Double?
        var eligible: Bool
        var phaseBreakdown: [String: Int]
    }

    struct Result {
        var topScorers: [Entry]
        var mvps: [Entry]
        var defenders: [Entry]
        var goalkeepers: [Entry]
    }

    private struct ResolvedPlayer {
        var id: String
        var playerDocumentId: String?
        var nome: String
        var teamId: String?
        var teamName: String
        var pictureURL: String?
        var jerseyNumber: Int?
        var position: String?
    }

    private struct LookupContext {
        var teamNameById: [String: String]
        var playersById: [String: Player]
        var playersByAuthUid: [String: Player]
        var playersByTeamAndName: [String: Player]
        var playersByName: [String: [Player]]
        var snapshotByTeamAndName: [String: EditionParticipation.PlayerSnapshot]
    }

    private static let rankingTieBreakPhases = ["finale", "semifinali", "quarti", "ottavi", "girone"]

    static func build(
        matches: [Match],
        players: [Player],
        editionTeams: [EditionTeam],
        config: AwardConfig
    ) -> Result {
        let eligibleMatches = matches.filter { $0.isPlayed || $0.isStarted }
        let lookup = makeLookupContext(players: players, editionTeams: editionTeams)

        var topScorers: [String: Entry] = [:]
        var mvps: [String: Entry] = [:]
        var defenders: [String: Entry] = [:]
        var goalkeepers: [String: Entry] = [:]
        var totalGoalkeeperAppearances = 0
        var totalGoalsConcededByGoalkeepers = 0

        for match in eligibleMatches {
            let phaseKey = AwardConfig.normalizePhaseKey(match.fase)

            for event in match.safeEventi where isScoringEvent(event.tipo) {
                guard let player = resolveEventPlayer(event: event, lookup: lookup) else { continue }
                var entry = topScorers[player.id] ?? makeEntry(from: player)
                entry.rawValue += 1
                entry.weightedValue += config.topScorerWeight(for: phaseKey)
                entry.phaseBreakdown[phaseKey, default: 0] += 1
                topScorers[player.id] = entry
            }

            if let mvp = match.mvp,
               let player = resolveMatchMvp(mvp, match: match, lookup: lookup) {
                var entry = mvps[player.id] ?? makeEntry(from: player)
                entry.rawValue += 1
                entry.weightedValue += config.mvpWeight(for: phaseKey)
                entry.matchesCount += 1
                entry.phaseBreakdown[phaseKey, default: 0] += 1
                mvps[player.id] = entry
            }

            if let defender = match.bestDefender,
               let player = resolveMatchMvp(defender, match: match, lookup: lookup) {
                var entry = defenders[player.id] ?? makeEntry(from: player)
                entry.rawValue += 1
                entry.weightedValue += config.mvpWeight(for: phaseKey)
                entry.matchesCount += 1
                entry.phaseBreakdown[phaseKey, default: 0] += 1
                defenders[player.id] = entry
            }

            for teamId in [match.team1, match.team2] {
                guard let goalkeeperPlayerId = MatchGoalkeeperResolver.goalkeeperPlayerId(
                    for: match,
                    teamId: teamId,
                    within: eligibleMatches
                ),
                let goalkeeper = resolvePlayer(
                    playerId: goalkeeperPlayerId,
                    playerName: match.goalkeeper(for: teamId)?.playerName,
                    teamId: teamId,
                    lookup: lookup
                ) else {
                    continue
                }

                let concededGoals = teamId == match.team1 ? match.team2Goals : match.team1Goals
                var entry = goalkeepers[goalkeeper.id] ?? makeEntry(from: goalkeeper)
                entry.rawValue += concededGoals
                entry.goalsConceded += concededGoals
                if concededGoals == 0 {
                    entry.cleanSheets += 1
                }
                entry.matchesCount += 1
                entry.eligible = true
                entry.phaseBreakdown[phaseKey, default: 0] += 1
                goalkeepers[goalkeeper.id] = entry
                totalGoalkeeperAppearances += 1
                totalGoalsConcededByGoalkeepers += concededGoals
            }
        }

        let tournamentAverage = totalGoalkeeperAppearances > 0
            ? Double(totalGoalsConcededByGoalkeepers) / Double(totalGoalkeeperAppearances)
            : 0
        let indexedGoalkeepers = goalkeepers.mapValues { entry -> Entry in
            var copy = entry
            copy.goalkeeperIndex = goalkeeperIndex(
                goalsConceded: copy.goalsConceded,
                matchesPlayed: copy.matchesCount,
                tournamentAverage: tournamentAverage
            )
            copy.weightedValue = copy.goalkeeperIndex ?? .greatestFiniteMagnitude
            return copy
        }

        return Result(
            topScorers: sortedDescending(Array(topScorers.values)),
            mvps: sortedDescending(Array(mvps.values)),
            defenders: sortedDescending(Array(defenders.values)),
            goalkeepers: sortedGoalkeepers(Array(indexedGoalkeepers.values))
        )
    }

    private static func makeLookupContext(players: [Player], editionTeams: [EditionTeam]) -> LookupContext {
        let teamNameById = editionTeams.reduce(into: [String: String]()) { result, team in
            guard !team.teamId.isEmpty else { return }
            result[team.teamId] = team.displayName
        }

        let playersById = players.reduce(into: [String: Player]()) { result, player in
            guard let id = player.id else { return }
            result[id] = player
        }

        let playersByAuthUid = players.reduce(into: [String: Player]()) { result, player in
            guard let authUid = player.playerAuthUid else { return }
            result[authUid] = player
        }

        let playersByTeamAndName = Dictionary(
            players.compactMap { player -> (String, Player)? in
                guard let teamId = player.teamId,
                      let normalizedName = Player.normalizedLookupName(from: player.nomeCompleto) else {
                    return nil
                }
                return ("\(teamId)|\(normalizedName)", player)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let snapshotByTeamAndName = Dictionary(
            editionTeams.flatMap { team in
                team.rosterSnapshots.compactMap { snapshot -> (String, EditionParticipation.PlayerSnapshot)? in
                    guard !team.teamId.isEmpty,
                          let normalizedName = Player.normalizedLookupName(from: snapshot.nome) else {
                        return nil
                    }
                    return ("\(team.teamId)|\(normalizedName)", snapshot)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )

        let playersByName = Dictionary(grouping: players) { player in
            Player.normalizedLookupName(from: player.nomeCompleto) ?? player.nomeCompleto
        }

        return LookupContext(
            teamNameById: teamNameById,
            playersById: playersById,
            playersByAuthUid: playersByAuthUid,
            playersByTeamAndName: playersByTeamAndName,
            playersByName: playersByName,
            snapshotByTeamAndName: snapshotByTeamAndName
        )
    }

    private static func resolveMatchMvp(
        _ mvp: Match.MatchMvp,
        match: Match,
        lookup: LookupContext
    ) -> ResolvedPlayer? {
        let teamId: String?
        switch mvp.team {
        case 2:
            teamId = match.team2
        case 1:
            teamId = match.team1
        default:
            teamId = nil
        }

        return resolvePlayer(
            playerId: mvp.playerId,
            playerName: mvp.playerName,
            teamId: teamId,
            lookup: lookup
        )
    }

    private static func resolvePlayer(
        playerId: String?,
        playerName: String?,
        teamId: String?,
        lookup: LookupContext
    ) -> ResolvedPlayer? {
        let teamName = teamId.flatMap { lookup.teamNameById[$0] } ?? "Squadra"

        if let playerId,
           let normalizedPlayerId = normalizedString(playerId),
           let player = lookup.playersById[normalizedPlayerId] ?? lookup.playersByAuthUid[normalizedPlayerId] {
            return resolvedPlayer(from: player, fallbackTeamId: teamId, fallbackTeamName: teamName)
        }

        guard let normalizedName = Player.normalizedLookupName(from: playerName),
              let originalName = normalizedString(playerName) else {
            return nil
        }

        if let teamId,
           let player = lookup.playersByTeamAndName["\(teamId)|\(normalizedName)"] {
            return resolvedPlayer(from: player, fallbackTeamId: teamId, fallbackTeamName: teamName)
        }

        if let teamId,
           let snapshot = lookup.snapshotByTeamAndName["\(teamId)|\(normalizedName)"] {
            return ResolvedPlayer(
                id: snapshot.giocatoreId ?? "\(teamId)|\(normalizedName)",
                playerDocumentId: snapshot.giocatoreId,
                nome: snapshot.nome ?? originalName,
                teamId: teamId,
                teamName: lookup.teamNameById[teamId] ?? teamName,
                pictureURL: snapshot.pictureURL,
                jerseyNumber: snapshot.numero,
                position: snapshot.ruolo
            )
        }

        if let player = lookup.playersByName[normalizedName]?.first {
            return resolvedPlayer(from: player, fallbackTeamId: teamId, fallbackTeamName: teamName)
        }

        return ResolvedPlayer(
            id: "\(teamId ?? "_")|\(normalizedName)",
            playerDocumentId: nil,
            nome: originalName,
            teamId: teamId,
            teamName: teamName,
            pictureURL: nil,
            jerseyNumber: nil,
            position: nil
        )
    }

    private static func resolvedPlayer(
        from player: Player,
        fallbackTeamId: String?,
        fallbackTeamName: String
    ) -> ResolvedPlayer {
        let resolvedId = player.id ?? player.playerAuthUid ?? "\(fallbackTeamId ?? "_")|\(player.nomeCompleto)"
        let resolvedTeamId = player.teamId ?? fallbackTeamId

        return ResolvedPlayer(
            id: resolvedId,
            playerDocumentId: player.id ?? player.playerAuthUid,
            nome: player.nomeCompleto,
            teamId: resolvedTeamId,
            teamName: fallbackTeamName,
            pictureURL: player.pictureURL,
            jerseyNumber: player.numeroMaglia,
            position: player.positionPrimary
        )
    }

    private static func resolveEventPlayer(
        event: MatchEvent,
        lookup: LookupContext
    ) -> ResolvedPlayer? {
        resolvePlayer(
            playerId: event.giocatoreId,
            playerName: event.giocatoreNome,
            teamId: event.squadraId,
            lookup: lookup
        )
    }

    private static func makeEntry(from player: ResolvedPlayer) -> Entry {
        Entry(
            id: player.id,
            playerDocumentId: player.playerDocumentId,
            nome: player.nome,
            teamId: player.teamId,
            teamName: player.teamName,
            pictureURL: player.pictureURL,
            jerseyNumber: player.jerseyNumber,
            position: player.position,
            rawValue: 0,
            weightedValue: 0,
            matchesCount: 0,
            goalsConceded: 0,
            cleanSheets: 0,
            goalkeeperIndex: nil,
            eligible: false,
            phaseBreakdown: [:]
        )
    }

    private static func isScoringEvent(_ eventType: String) -> Bool {
        ["gol", "rigore_segnato", "punizione_segnata"].contains(eventType)
    }

    private static func sortedDescending(_ entries: [Entry]) -> [Entry] {
        entries
            .filter { $0.rawValue > 0 }
            .sorted { lhs, rhs in
                if lhs.weightedValue != rhs.weightedValue {
                    return lhs.weightedValue > rhs.weightedValue
                }
                if lhs.rawValue != rhs.rawValue {
                    return lhs.rawValue > rhs.rawValue
                }
                let phaseComparison = comparePhaseBreakdown(lhs.phaseBreakdown, rhs.phaseBreakdown)
                if phaseComparison != .orderedSame {
                    return phaseComparison == .orderedDescending
                }
                return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
            }
    }

    private static func sortedGoalkeepers(_ entries: [Entry]) -> [Entry] {
        entries
            .filter { $0.eligible && $0.matchesCount > 0 }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.goalkeeperIndex ?? .greatestFiniteMagnitude
                let rhsIndex = rhs.goalkeeperIndex ?? .greatestFiniteMagnitude
                if lhsIndex != rhsIndex {
                    return lhsIndex < rhsIndex
                }
                if lhs.matchesCount != rhs.matchesCount {
                    return lhs.matchesCount > rhs.matchesCount
                }
                if lhs.cleanSheets != rhs.cleanSheets {
                    return lhs.cleanSheets > rhs.cleanSheets
                }
                if lhs.goalsConceded != rhs.goalsConceded {
                    return lhs.goalsConceded < rhs.goalsConceded
                }
                return lhs.nome.localizedCaseInsensitiveCompare(rhs.nome) == .orderedAscending
            }
    }

    private static func goalkeeperIndex(
        goalsConceded: Int,
        matchesPlayed: Int,
        tournamentAverage: Double
    ) -> Double {
        guard matchesPlayed >= 0 else { return .greatestFiniteMagnitude }
        return (Double(goalsConceded) + 3 * tournamentAverage) / (Double(matchesPlayed) + 3)
    }

    private static func comparePhaseBreakdown(
        _ lhs: [String: Int],
        _ rhs: [String: Int]
    ) -> ComparisonResult {
        for phase in rankingTieBreakPhases {
            let lhsValue = lhs[phase, default: 0]
            let rhsValue = rhs[phase, default: 0]
            if lhsValue != rhsValue {
                return lhsValue > rhsValue ? .orderedDescending : .orderedAscending
            }
        }
        return .orderedSame
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

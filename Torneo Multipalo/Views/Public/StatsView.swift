import SwiftUI

@Observable
@MainActor
final class StatsViewModel {
    struct PlayerStatEntry: Identifiable {
        var id: String
        var playerDocumentId: String?
        var nome: String
        var teamId: String?
        var teamName: String
        var pictureURL: String?
        var jerseyNumber: Int?
        var position: String?
        var gol: Int
        var assist: Int
        var ammonizioni: Int
        var espulsioni: Int
        var presenze: Int
    }

    struct AwardStandingEntry: Identifiable {
        var id: String
        var playerDocumentId: String?
        var nome: String
        var teamId: String?
        var teamName: String
        var pictureURL: String?
        var jerseyNumber: Int?
        var position: String?
        var primaryValue: String
        var secondaryValue: String?
    }

    private struct ResolvedEventPlayer {
        var id: String
        var playerDocumentId: String?
        var nome: String
        var teamId: String?
        var teamName: String
        var pictureURL: String?
        var jerseyNumber: Int?
        var position: String?
    }

    private struct ResolutionContext {
        var teamNameById: [String: String]
        var playersById: [String: Player]
        var playersByAuthUid: [String: Player]
        var playersByTeam: [String: [Player]]
        var playersByTeamAndName: [String: Player]
        var playersByName: [String: [Player]]
        var snapshotsByTeam: [String: [EditionParticipation.PlayerSnapshot]]
        var snapshotByTeamAndName: [String: EditionParticipation.PlayerSnapshot]
        var snapshotById: [String: EditionParticipation.PlayerSnapshot]
    }

    private struct AwardConfig {
        static let defaultGoalWeights: [String: Double] = [
            "girone": 1,
            "ottavi": 1,
            "quarti": 1,
            "semifinali": 1,
            "finale": 1
        ]

        static let defaultMvpOrder = ["finale", "semifinali", "quarti", "ottavi", "girone"]

        let goalWeights: [String: Double]
        let goalkeeperConcededWeights: [String: Double]
        let mvpTieBreakOrder: [String]

        init(documentData: [String: Any]?) {
            let nestedWeights = documentData?["weights"] as? [String: Any]
            goalWeights = Self.phaseWeights(
                from: (documentData?["goalWeights"] as? [String: Any])
                    ?? (documentData?["scorerWeights"] as? [String: Any])
                    ?? (nestedWeights?["goals"] as? [String: Any]),
                fallback: Self.defaultGoalWeights
            )
            goalkeeperConcededWeights = Self.phaseWeights(
                from: (documentData?["goalkeeperConcededWeights"] as? [String: Any])
                    ?? (documentData?["concededGoalWeights"] as? [String: Any])
                    ?? (nestedWeights?["concededGoals"] as? [String: Any]),
                fallback: Self.defaultGoalWeights
            )
            mvpTieBreakOrder = Self.phaseArray(from: documentData?["mvpTieBreakOrder"]) ?? Self.defaultMvpOrder
        }

        var usesCustomWeights: Bool {
            goalWeights != Self.defaultGoalWeights || goalkeeperConcededWeights != Self.defaultGoalWeights
        }

        func goalWeight(for phase: String) -> Double {
            goalWeights[MatchGoalkeeperResolver.normalizedPhase(phase)] ?? 1
        }

        func goalkeeperConcededWeight(for phase: String) -> Double {
            goalkeeperConcededWeights[MatchGoalkeeperResolver.normalizedPhase(phase)] ?? 1
        }

        func scoreLabel(for value: Double) -> String {
            if abs(value.rounded() - value) < 0.001 {
                return "\(Int(value.rounded())) pt"
            }
            return String(format: "%.2f pt", value)
        }

        private static func phaseWeights(from rawMap: [String: Any]?, fallback: [String: Double]) -> [String: Double] {
            guard let rawMap else { return fallback }
            var result = fallback

            for (key, value) in rawMap {
                let normalizedKey = MatchGoalkeeperResolver.normalizedPhase(key)
                if let doubleValue = value as? Double {
                    result[normalizedKey] = doubleValue
                } else if let intValue = value as? Int {
                    result[normalizedKey] = Double(intValue)
                } else if let stringValue = value as? String, let doubleValue = Double(stringValue) {
                    result[normalizedKey] = doubleValue
                }
            }

            return result
        }

        private static func phaseArray(from rawValue: Any?) -> [String]? {
            guard let rawValues = rawValue as? [String], !rawValues.isEmpty else { return nil }
            return rawValues.map(MatchGoalkeeperResolver.normalizedPhase(_:))
        }
    }

    private struct ScorerAwardAccumulator {
        var player: ResolvedEventPlayer
        var pureGoals = 0
        var weightedGoals = 0.0
        var phaseBreakdown: [String: Int] = [:]
    }

    private struct MvpAwardAccumulator {
        var player: ResolvedEventPlayer
        var count = 0
        var phaseBreakdown: [String: Int] = [:]
    }

    private struct GoalkeeperAwardAccumulator {
        var player: ResolvedEventPlayer
        var appearances = 0
        var rawGoalsConceded = 0
        var cleanSheets = 0
        var goalkeeperIndex = Double.greatestFiniteMagnitude
        var phaseBreakdown: [String: Int] = [:]
    }

    var marcatori: [PlayerStatEntry] = []
    var assistman: [PlayerStatEntry] = []
    var cartelliniPlayers: [PlayerStatEntry] = []
    var capocannonieriPremio: [AwardStandingEntry] = []
    var mvpLeaders: [AwardStandingEntry] = []
    var bestDefenderLeaders: [AwardStandingEntry] = []
    var migliorPortiereLeaders: [AwardStandingEntry] = []
    var premiNote = ""
    var missingGoalkeeperAssignments = 0

    private var allPlayers: [Player] = []
    var isLoading = false
    var errorMessage: String?

    func load(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let players = try await appState.firestoreService.fetchAllPlayers()
            let awardConfigDocument = try? await appState.firestoreService.fetchAwardConfigDocument(
                edition: appState.selectedEdition
            )

            allPlayers = players

            let context = makeResolutionContext(players: players, editionTeams: appState.editionTeams)
            var eventEntries = buildEventEntries(matches: appState.matches, context: context)
            applyActiveEditionFallbackStats(
                to: &eventEntries,
                players: players,
                editionTeams: appState.editionTeams,
                includeFallback: appState.selectedEdition == appState.activeEdition
            )

            let entries = Array(eventEntries.values)
            marcatori = entries
                .filter { $0.gol > 0 }
                .sorted { lhs, rhs in
                    if lhs.gol == rhs.gol { return lhs.nome < rhs.nome }
                    return lhs.gol > rhs.gol
                }

            cartelliniPlayers = entries
                .filter { $0.ammonizioni + $0.espulsioni > 0 }
                .sorted { lhs, rhs in
                    let lhsScore = lhs.espulsioni * 2 + lhs.ammonizioni
                    let rhsScore = rhs.espulsioni * 2 + rhs.ammonizioni
                    if lhsScore == rhsScore { return lhs.nome < rhs.nome }
                    return lhsScore > rhsScore
                }

            assistman = entries
                .filter { $0.assist > 0 }
                .sorted { lhs, rhs in
                    if lhs.assist == rhs.assist { return lhs.nome < rhs.nome }
                    return lhs.assist > rhs.assist
                }

            let awardConfig = AwardConfig(documentData: awardConfigDocument ?? nil)
            let awards = buildAwards(matches: appState.matches, context: context, config: awardConfig)
            capocannonieriPremio = awards.capocannonieri
            mvpLeaders = awards.mvp
            bestDefenderLeaders = awards.bestDefenders
            migliorPortiereLeaders = awards.migliorPortiere
            missingGoalkeeperAssignments = awards.missingGoalkeeperAssignments
            premiNote = ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func makeResolutionContext(players: [Player], editionTeams: [EditionTeam]) -> ResolutionContext {
        let teamNameById: [String: String] = editionTeams.reduce(into: [:]) { result, team in
            guard !team.teamId.isEmpty else { return }
            result[team.teamId] = team.displayName
        }

        let playersById: [String: Player] = players.reduce(into: [:]) { result, player in
            guard let id = player.id else { return }
            result[id] = player
        }
        let playersByAuthUid: [String: Player] = players.reduce(into: [:]) { result, player in
            guard let authUid = player.playerAuthUid else { return }
            result[authUid] = player
        }
        let playersByTeam = Dictionary(grouping: players.filter { $0.teamId != nil }) { $0.teamId ?? "" }

        let playersByTeamAndName = Dictionary(
            players.compactMap { player -> (String, Player)? in
                guard let teamId = player.teamId,
                      let normalizedName = Player.normalizedLookupName(from: player.nomeCompleto) else { return nil }
                return ("\(teamId)|\(normalizedName)", player)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let snapshotByTeamAndName = Dictionary(
            editionTeams.flatMap { team in
                team.rosterSnapshots.compactMap { snapshot -> (String, EditionParticipation.PlayerSnapshot)? in
                    guard !team.teamId.isEmpty,
                          let normalizedName = Player.normalizedLookupName(from: snapshot.nome) else { return nil }
                    return ("\(team.teamId)|\(normalizedName)", snapshot)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let snapshotsByTeam = Dictionary(grouping: editionTeams.flatMap { team in
            team.rosterSnapshots.map { (team.teamId, $0) }
        }) { $0.0 }
            .mapValues { values in values.map(\.1) }

        let snapshotById = Dictionary(
            editionTeams.flatMap { team in
                team.rosterSnapshots.compactMap { snapshot -> (String, EditionParticipation.PlayerSnapshot)? in
                    guard let snapshotId = snapshot.giocatoreId,
                          !snapshotId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        return nil
                    }
                    return (snapshotId, snapshot)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )

        let playersByName = Dictionary(grouping: players) { player in
            Player.normalizedLookupName(from: player.nomeCompleto) ?? player.nomeCompleto
        }

        return ResolutionContext(
            teamNameById: teamNameById,
            playersById: playersById,
            playersByAuthUid: playersByAuthUid,
            playersByTeam: playersByTeam,
            playersByTeamAndName: playersByTeamAndName,
            playersByName: playersByName,
            snapshotsByTeam: snapshotsByTeam,
            snapshotByTeamAndName: snapshotByTeamAndName,
            snapshotById: snapshotById
        )
    }

    private func buildEventEntries(
        matches: [Match],
        context: ResolutionContext
    ) -> [String: PlayerStatEntry] {
        var entries: [String: PlayerStatEntry] = [:]
        var pendingSuspensionsByTeam: [String: Set<String>] = [:]

        for match in MatchGoalkeeperResolver.sortedMatches(matches).filter({ $0.isPlayed || $0.isStarted }) {
            let suspendedTeam1 = pendingSuspensionsByTeam[match.team1, default: []]
            let suspendedTeam2 = pendingSuspensionsByTeam[match.team2, default: []]

            addRosterAppearances(
                teamId: match.team1,
                suspendedIds: suspendedTeam1,
                entries: &entries,
                context: context
            )
            addRosterAppearances(
                teamId: match.team2,
                suspendedIds: suspendedTeam2,
                entries: &entries,
                context: context
            )

            pendingSuspensionsByTeam[match.team1] = []
            pendingSuspensionsByTeam[match.team2] = []

            for event in match.safeEventi {
                guard let resolved = resolveEventPlayer(event: event, context: context) else { continue }
                if let teamId = event.squadraId {
                    let suspended = teamId == match.team1 ? suspendedTeam1 : suspendedTeam2
                    if suspended.contains(resolved.id) {
                        continue
                    }
                }

                var entry = entries[resolved.id] ?? makeStatEntry(from: resolved)

                switch event.tipo {
                case "gol", "rigore_segnato", "punizione_segnata":
                    entry.gol += 1
                case "assist":
                    entry.assist += 1
                case "ammonizione":
                    entry.ammonizioni += 1
                case "espulsione":
                    entry.espulsioni += 1
                default:
                    break
                }

                entries[resolved.id] = entry

                if event.tipo == "espulsione", let teamId = event.squadraId {
                    pendingSuspensionsByTeam[teamId, default: []].insert(resolved.id)
                }

                if let assistName = event.assistName,
                   !assistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   ["gol", "rigore_segnato", "punizione_segnata"].contains(event.tipo),
                   let assistPlayer = resolveEventPlayer(
                    event: MatchEvent(
                        tipo: "assist",
                        giocatoreId: event.assistPlayerId,
                        giocatoreNome: assistName,
                        squadraId: event.squadraId,
                        minuto: event.minuto
                    ),
                    context: context
                   ) {
                    var assistEntry = entries[assistPlayer.id] ?? makeStatEntry(from: assistPlayer)
                    assistEntry.assist += 1
                    entries[assistPlayer.id] = assistEntry
                }
            }
        }

        return entries
    }

    private func addRosterAppearances(
        teamId: String,
        suspendedIds: Set<String>,
        entries: inout [String: PlayerStatEntry],
        context: ResolutionContext
    ) {
        let teamName = context.teamNameById[teamId] ?? "Squadra"

        var roster = (context.playersByTeam[teamId] ?? []).map {
            resolvedPlayer(from: $0, teamId: teamId, teamName: teamName)
        }

        let liveIds = Set(roster.map(\.id))
        let snapshotRoster = (context.snapshotsByTeam[teamId] ?? []).compactMap { snapshot -> ResolvedEventPlayer? in
            let id = snapshot.giocatoreId ?? "\(teamId)|\(Player.normalizedLookupName(from: snapshot.nome) ?? snapshot.nome ?? "")"
            guard !id.isEmpty, !liveIds.contains(id) else { return nil }
            return ResolvedEventPlayer(
                id: id,
                playerDocumentId: snapshot.giocatoreId,
                nome: snapshot.nome ?? "Giocatore",
                teamId: teamId,
                teamName: teamName,
                pictureURL: snapshot.pictureURL,
                jerseyNumber: snapshot.numero,
                position: snapshot.ruolo
            )
        }
        roster.append(contentsOf: snapshotRoster)

        for player in roster where !suspendedIds.contains(player.id) {
            var entry = entries[player.id] ?? makeStatEntry(from: player)
            entry.presenze += 1
            entries[player.id] = entry
        }
    }

    private func buildAwards(
        matches: [Match],
        context: ResolutionContext,
        config: AwardConfig
    ) -> (
        capocannonieri: [AwardStandingEntry],
        mvp: [AwardStandingEntry],
        bestDefenders: [AwardStandingEntry],
        migliorPortiere: [AwardStandingEntry],
        missingGoalkeeperAssignments: Int
    ) {
        var scorerAccumulators: [String: ScorerAwardAccumulator] = [:]
        var mvpAccumulators: [String: MvpAwardAccumulator] = [:]
        var defenderAccumulators: [String: MvpAwardAccumulator] = [:]
        var goalkeeperAccumulators: [String: GoalkeeperAwardAccumulator] = [:]
        var missingGoalkeeperAssignments = 0
        var totalGoalkeeperAppearances = 0
        var totalGoalsConcededByGoalkeepers = 0

        let playedMatches = MatchGoalkeeperResolver.sortedMatches(matches.filter(\.isPlayed))

        for match in playedMatches {
            let phase = MatchGoalkeeperResolver.normalizedPhase(match.fase)
            let goalWeight = config.goalWeight(for: phase)

            for event in match.safeEventi where ["gol", "rigore_segnato", "punizione_segnata"].contains(event.tipo) {
                guard let resolved = resolveEventPlayer(event: event, context: context) else { continue }

                var accumulator = scorerAccumulators[resolved.id] ?? ScorerAwardAccumulator(player: resolved)
                accumulator.player = mergeResolvedPlayer(accumulator.player, with: resolved)
                accumulator.pureGoals += 1
                accumulator.weightedGoals += goalWeight
                accumulator.phaseBreakdown[phase, default: 0] += 1
                scorerAccumulators[resolved.id] = accumulator
            }

            if let mvpPlayer = resolveMvpPlayer(for: match, context: context) {
                var accumulator = mvpAccumulators[mvpPlayer.id] ?? MvpAwardAccumulator(player: mvpPlayer)
                accumulator.player = mergeResolvedPlayer(accumulator.player, with: mvpPlayer)
                accumulator.count += 1
                accumulator.phaseBreakdown[phase, default: 0] += 1
                mvpAccumulators[mvpPlayer.id] = accumulator
            }

            if let defenderPlayer = resolveBestDefenderPlayer(for: match, context: context) {
                var accumulator = defenderAccumulators[defenderPlayer.id] ?? MvpAwardAccumulator(player: defenderPlayer)
                accumulator.player = mergeResolvedPlayer(accumulator.player, with: defenderPlayer)
                accumulator.count += 1
                accumulator.phaseBreakdown[phase, default: 0] += 1
                defenderAccumulators[defenderPlayer.id] = accumulator
            }

            let team1GoalkeeperId = MatchGoalkeeperResolver.goalkeeperPlayerId(
                for: match,
                teamId: match.team1,
                within: playedMatches
            )
            let team2GoalkeeperId = MatchGoalkeeperResolver.goalkeeperPlayerId(
                for: match,
                teamId: match.team2,
                within: playedMatches
            )

            if let team1GoalkeeperId,
               let resolvedKeeper = resolvePlayerById(team1GoalkeeperId, teamId: match.team1, context: context) {
                var accumulator = goalkeeperAccumulators[resolvedKeeper.id] ?? GoalkeeperAwardAccumulator(player: resolvedKeeper)
                accumulator.player = mergeResolvedPlayer(accumulator.player, with: resolvedKeeper)
                accumulator.appearances += 1
                accumulator.rawGoalsConceded += match.team2Goals
                if match.team2Goals == 0 {
                    accumulator.cleanSheets += 1
                }
                accumulator.phaseBreakdown[phase, default: 0] += 1
                goalkeeperAccumulators[resolvedKeeper.id] = accumulator
                totalGoalkeeperAppearances += 1
                totalGoalsConcededByGoalkeepers += match.team2Goals
            } else {
                missingGoalkeeperAssignments += 1
            }

            if let team2GoalkeeperId,
               let resolvedKeeper = resolvePlayerById(team2GoalkeeperId, teamId: match.team2, context: context) {
                var accumulator = goalkeeperAccumulators[resolvedKeeper.id] ?? GoalkeeperAwardAccumulator(player: resolvedKeeper)
                accumulator.player = mergeResolvedPlayer(accumulator.player, with: resolvedKeeper)
                accumulator.appearances += 1
                accumulator.rawGoalsConceded += match.team1Goals
                if match.team1Goals == 0 {
                    accumulator.cleanSheets += 1
                }
                accumulator.phaseBreakdown[phase, default: 0] += 1
                goalkeeperAccumulators[resolvedKeeper.id] = accumulator
                totalGoalkeeperAppearances += 1
                totalGoalsConcededByGoalkeepers += match.team1Goals
            } else {
                missingGoalkeeperAssignments += 1
            }
        }

        let tournamentAverage = totalGoalkeeperAppearances > 0
            ? Double(totalGoalsConcededByGoalkeepers) / Double(totalGoalkeeperAppearances)
            : 0
        for key in goalkeeperAccumulators.keys {
            guard let accumulator = goalkeeperAccumulators[key] else { continue }
            goalkeeperAccumulators[key]?.goalkeeperIndex =
                (Double(accumulator.rawGoalsConceded) + 3 * tournamentAverage) / (Double(accumulator.appearances) + 3)
        }

        let capocannonieri = scorerAccumulators.values
            .sorted { lhs, rhs in
                if lhs.weightedGoals != rhs.weightedGoals {
                    return lhs.weightedGoals > rhs.weightedGoals
                }
                let comparison = comparePhaseBreakdown(
                    lhs.phaseBreakdown,
                    rhs.phaseBreakdown,
                    order: config.mvpTieBreakOrder,
                    descending: true
                )
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                if lhs.pureGoals != rhs.pureGoals {
                    return lhs.pureGoals > rhs.pureGoals
                }
                return lhs.player.nome < rhs.player.nome
            }
            .map { accumulator in
                makeAwardEntry(
                    from: accumulator.player,
                    primaryValue: config.scoreLabel(for: accumulator.weightedGoals),
                    secondaryValue: "\(accumulator.pureGoals) gol registrati"
                )
            }

        let mvp = mvpAccumulators.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                let comparison = comparePhaseBreakdown(
                    lhs.phaseBreakdown,
                    rhs.phaseBreakdown,
                    order: config.mvpTieBreakOrder,
                    descending: true
                )
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.player.nome < rhs.player.nome
            }
            .map { accumulator in
                makeAwardEntry(
                    from: accumulator.player,
                    primaryValue: "\(accumulator.count) MVP",
                    secondaryValue: phaseBreakdownLabel(accumulator.phaseBreakdown, order: config.mvpTieBreakOrder)
                )
            }

        let bestDefenders = defenderAccumulators.values
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                let comparison = comparePhaseBreakdown(
                    lhs.phaseBreakdown,
                    rhs.phaseBreakdown,
                    order: config.mvpTieBreakOrder,
                    descending: true
                )
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return lhs.player.nome < rhs.player.nome
            }
            .map { accumulator in
                makeAwardEntry(
                    from: accumulator.player,
                    primaryValue: "\(accumulator.count) DIF",
                    secondaryValue: phaseBreakdownLabel(accumulator.phaseBreakdown, order: config.mvpTieBreakOrder)
                )
            }

        let migliorPortiere = goalkeeperAccumulators.values
            .sorted { lhs, rhs in
                if lhs.goalkeeperIndex != rhs.goalkeeperIndex {
                    return lhs.goalkeeperIndex < rhs.goalkeeperIndex
                }
                if lhs.appearances != rhs.appearances {
                    return lhs.appearances > rhs.appearances
                }
                if lhs.cleanSheets != rhs.cleanSheets {
                    return lhs.cleanSheets > rhs.cleanSheets
                }
                if lhs.rawGoalsConceded != rhs.rawGoalsConceded {
                    return lhs.rawGoalsConceded < rhs.rawGoalsConceded
                }
                return lhs.player.nome < rhs.player.nome
            }
            .map { accumulator in
                makeAwardEntry(
                    from: accumulator.player,
                    primaryValue: String(format: "%.2f idx", accumulator.goalkeeperIndex),
                    secondaryValue: "\(accumulator.appearances) pres. · \(accumulator.rawGoalsConceded) subiti · \(accumulator.cleanSheets) clean sheets"
                )
            }

        return (capocannonieri, mvp, bestDefenders, migliorPortiere, missingGoalkeeperAssignments)
    }

    private func applyActiveEditionFallbackStats(
        to entries: inout [String: PlayerStatEntry],
        players: [Player],
        editionTeams: [EditionTeam],
        includeFallback: Bool
    ) {
        guard includeFallback else { return }

        let teamNameById: [String: String] = editionTeams.reduce(into: [:]) { result, team in
            guard !team.teamId.isEmpty else { return }
            result[team.teamId] = team.displayName
        }
        let eligibleTeamIds = Set(editionTeams.map(\.teamId).filter { !$0.isEmpty })

        for player in players {
            guard let id = player.id,
                  let teamId = player.teamId,
                  eligibleTeamIds.contains(teamId) else {
                continue
            }

            var entry = entries[id] ?? PlayerStatEntry(
                id: id,
                playerDocumentId: id,
                nome: player.nomeCompleto,
                teamId: teamId,
                teamName: teamNameById[teamId] ?? "Squadra",
                pictureURL: player.displayPhotoURL,
                jerseyNumber: player.numeroMaglia,
                position: player.positionPrimary,
                gol: 0,
                assist: 0,
                ammonizioni: 0,
                espulsioni: 0,
                presenze: 0
            )

            entry.assist = max(entry.assist, player.stats?.assist ?? 0)
            entry.gol = max(entry.gol, player.stats?.gol ?? 0)
            entry.ammonizioni = max(entry.ammonizioni, player.stats?.ammonizioni ?? 0)
            entry.espulsioni = max(entry.espulsioni, player.stats?.espulsioni ?? 0)
            entry.presenze = max(entry.presenze, player.stats?.presenze ?? 0)
            entries[id] = entry
        }
    }

    private func makeStatEntry(from resolved: ResolvedEventPlayer) -> PlayerStatEntry {
        PlayerStatEntry(
            id: resolved.id,
            playerDocumentId: resolved.playerDocumentId,
            nome: resolved.nome,
            teamId: resolved.teamId,
            teamName: resolved.teamName,
            pictureURL: resolved.pictureURL,
            jerseyNumber: resolved.jerseyNumber,
            position: resolved.position,
            gol: 0,
            assist: 0,
            ammonizioni: 0,
            espulsioni: 0,
            presenze: 0
        )
    }

    private func makeAwardEntry(
        from resolved: ResolvedEventPlayer,
        primaryValue: String,
        secondaryValue: String?
    ) -> AwardStandingEntry {
        AwardStandingEntry(
            id: resolved.id,
            playerDocumentId: resolved.playerDocumentId,
            nome: resolved.nome,
            teamId: resolved.teamId,
            teamName: resolved.teamName,
            pictureURL: resolved.pictureURL,
            jerseyNumber: resolved.jerseyNumber,
            position: resolved.position,
            primaryValue: primaryValue,
            secondaryValue: secondaryValue
        )
    }

    private func resolveEventPlayer(
        event: MatchEvent,
        context: ResolutionContext
    ) -> ResolvedEventPlayer? {
        let teamId = event.squadraId
        let teamName = teamId.flatMap { context.teamNameById[$0] } ?? "Squadra"

        if let playerId = event.giocatoreId, !playerId.isEmpty,
           let resolved = resolvePlayerById(playerId, teamId: teamId, context: context) {
            return resolved
        }

        guard let normalizedName = Player.normalizedLookupName(from: event.giocatoreNome),
              let originalName = event.giocatoreNome, !originalName.isEmpty else {
            return nil
        }

        if let teamId,
           let player = context.playersByTeamAndName["\(teamId)|\(normalizedName)"] {
            return resolvedPlayer(
                from: player,
                teamId: teamId,
                teamName: context.teamNameById[teamId] ?? teamName
            )
        }

        if let teamId,
           let snapshot = context.snapshotByTeamAndName["\(teamId)|\(normalizedName)"] {
            return ResolvedEventPlayer(
                id: snapshot.giocatoreId ?? "\(teamId)|\(normalizedName)",
                playerDocumentId: snapshot.giocatoreId,
                nome: snapshot.nome ?? originalName,
                teamId: teamId,
                teamName: context.teamNameById[teamId] ?? teamName,
                pictureURL: snapshot.pictureURL,
                jerseyNumber: snapshot.numero,
                position: snapshot.ruolo
            )
        }

        if let player = context.playersByName[normalizedName]?.first {
            let resolvedTeamId = player.teamId ?? teamId
            let resolvedTeamName = resolvedTeamId.flatMap { context.teamNameById[$0] } ?? teamName
            return resolvedPlayer(from: player, teamId: resolvedTeamId, teamName: resolvedTeamName)
        }

        return ResolvedEventPlayer(
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

    private func resolveMvpPlayer(
        for match: Match,
        context: ResolutionContext
    ) -> ResolvedEventPlayer? {
        guard let mvp = match.mvp else { return nil }

        let teamId: String? = {
            switch mvp.team {
            case 2:
                return match.team2
            case 1:
                return match.team1
            default:
                return nil
            }
        }()

        if let playerId = mvp.playerId, !playerId.isEmpty,
           let resolved = resolvePlayerById(playerId, teamId: teamId, context: context) {
            return resolved
        }

        if let playerName = mvp.playerName, !playerName.isEmpty {
            return resolveEventPlayer(
                event: MatchEvent(
                    tipo: "mvp",
                    giocatoreNome: playerName,
                    squadraId: teamId
                ),
                context: context
            )
        }

        return nil
    }

    private func resolveBestDefenderPlayer(
        for match: Match,
        context: ResolutionContext
    ) -> ResolvedEventPlayer? {
        guard let defender = match.bestDefender else { return nil }

        let teamId: String? = {
            switch defender.team {
            case 2:
                return match.team2
            case 1:
                return match.team1
            default:
                return nil
            }
        }()

        if let playerId = defender.playerId, !playerId.isEmpty,
           let resolved = resolvePlayerById(playerId, teamId: teamId, context: context) {
            return resolved
        }

        if let playerName = defender.playerName, !playerName.isEmpty {
            return resolveEventPlayer(
                event: MatchEvent(
                    tipo: "best_defender",
                    giocatoreNome: playerName,
                    squadraId: teamId
                ),
                context: context
            )
        }

        return nil
    }

    private func resolvePlayerById(
        _ playerId: String,
        teamId: String?,
        context: ResolutionContext
    ) -> ResolvedEventPlayer? {
        if let player = context.playersById[playerId] ?? context.playersByAuthUid[playerId] {
            let resolvedTeamId = player.teamId ?? teamId
            let teamName = resolvedTeamId.flatMap { context.teamNameById[$0] } ?? "Squadra"
            return resolvedPlayer(from: player, teamId: resolvedTeamId, teamName: teamName)
        }

        if let snapshot = context.snapshotById[playerId] {
            let resolvedTeamId = teamId
            let teamName = resolvedTeamId.flatMap { context.teamNameById[$0] } ?? "Squadra"
            return ResolvedEventPlayer(
                id: snapshot.giocatoreId ?? playerId,
                playerDocumentId: snapshot.giocatoreId ?? playerId,
                nome: snapshot.nome ?? "Giocatore",
                teamId: resolvedTeamId,
                teamName: teamName,
                pictureURL: snapshot.pictureURL,
                jerseyNumber: snapshot.numero,
                position: snapshot.ruolo
            )
        }

        return nil
    }

    private func resolvedPlayer(from player: Player, teamId: String?, teamName: String) -> ResolvedEventPlayer {
        ResolvedEventPlayer(
            id: player.id ?? player.playerAuthUid ?? "\(teamId ?? "_")|\(player.nomeCompleto)",
            playerDocumentId: player.id ?? player.playerAuthUid,
            nome: player.nomeCompleto,
            teamId: teamId,
            teamName: teamName,
            pictureURL: player.displayPhotoURL,
            jerseyNumber: player.numeroMaglia,
            position: player.positionPrimary
        )
    }

    private func mergeResolvedPlayer(
        _ current: ResolvedEventPlayer,
        with candidate: ResolvedEventPlayer
    ) -> ResolvedEventPlayer {
        ResolvedEventPlayer(
            id: current.id,
            playerDocumentId: current.playerDocumentId ?? candidate.playerDocumentId,
            nome: current.nome.isEmpty ? candidate.nome : current.nome,
            teamId: current.teamId ?? candidate.teamId,
            teamName: current.teamName == "Squadra" ? candidate.teamName : current.teamName,
            pictureURL: current.pictureURL ?? candidate.pictureURL,
            jerseyNumber: current.jerseyNumber ?? candidate.jerseyNumber,
            position: current.position ?? candidate.position
        )
    }

    private func comparePhaseBreakdown(
        _ lhs: [String: Int],
        _ rhs: [String: Int],
        order: [String],
        descending: Bool
    ) -> ComparisonResult {
        for phase in order {
            let lhsValue = lhs[phase, default: 0]
            let rhsValue = rhs[phase, default: 0]

            if lhsValue == rhsValue { continue }

            if descending {
                return lhsValue > rhsValue ? .orderedAscending : .orderedDescending
            }
            return lhsValue < rhsValue ? .orderedAscending : .orderedDescending
        }

        return .orderedSame
    }

    private func phaseBreakdownLabel(_ breakdown: [String: Int], order: [String]) -> String? {
        let chunks = order.compactMap { phase -> String? in
            let value = breakdown[phase, default: 0]
            guard value > 0 else { return nil }
            return "\(phaseLabel(phase)) \(value)"
        }
        return chunks.isEmpty ? nil : chunks.joined(separator: " · ")
    }

    private func phaseLabel(_ phase: String) -> String {
        switch MatchGoalkeeperResolver.normalizedPhase(phase) {
        case "ottavi":
            return "Ottavi"
        case "quarti":
            return "Quarti"
        case "semifinali":
            return "Semi"
        case "finale":
            return "Finale"
        default:
            return "Girone"
        }
    }

    func player(for entry: PlayerStatEntry) -> Player? {
        resolvePlayer(documentId: entry.playerDocumentId, name: entry.nome, teamId: entry.teamId)
    }

    func player(for entry: AwardStandingEntry) -> Player? {
        resolvePlayer(documentId: entry.playerDocumentId, name: entry.nome, teamId: entry.teamId)
    }

    private func resolvePlayer(documentId: String?, name: String, teamId: String?) -> Player? {
        if let documentId, !documentId.isEmpty,
           let exact = allPlayers.first(where: { $0.id == documentId || $0.playerAuthUid == documentId }) {
            return exact
        }

        guard let normalizedName = Player.normalizedLookupName(from: name) else {
            return nil
        }

        return allPlayers.first { player in
            let sameTeam = teamId == nil || player.teamId == teamId
            return sameTeam && Player.normalizedLookupName(from: player.nomeCompleto) == normalizedName
        }
    }
}

struct StatsView: View {
    var showsNavigation = true
    var showsEditionStrip = true
    var showsScreenBackground = true

    @Environment(AppState.self) private var appState
    @State private var viewModel = StatsViewModel()
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if showsNavigation {
                NavigationStack {
                    decoratedContent
                        .navigationTitle("Statistiche")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            if showsEditionStrip {
                                ToolbarItem(placement: .topBarTrailing) {
                                    TournamentEditionMenu()
                                }
                            }
                        }
                }
            } else {
                decoratedContent
            }
        }
    }

    @ViewBuilder
    private var decoratedContent: some View {
        if showsScreenBackground {
            TournamentScreen { statsContent }
        } else {
            statsContent
        }
    }

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if showsEditionStrip && !showsNavigation {
                    HStack {
                        Spacer()
                        TournamentEditionMenu()
                    }
                    .padding(.horizontal, 16)
                }

                statsTabs

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(TournamentPalette.danger)
                        .padding(.horizontal, 16)
                }

                if viewModel.isLoading {
                    LoadingView(message: "Ricostruzione statistiche...")
                } else {
                    currentList
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await viewModel.load(appState: appState) }
        .task(id: appState.selectedEdition) {
            await viewModel.load(appState: appState)
        }
    }

    private var statsTabs: some View {
        HStack(spacing: 8) {
            statsTabButton(title: "Marcatori", tag: 0, tint: TournamentPalette.accent)
            statsTabButton(title: "Cartellini", tag: 1, tint: TournamentPalette.warm)
            statsTabButton(title: "Premi", tag: 2, tint: TournamentPalette.danger)
        }
        .padding(.horizontal, 16)
    }

    private func statsTabButton(title: String, tag: Int, tint: Color) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tag
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selectedTab == tag ? Color.white : TournamentPalette.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(selectedTab == tag ? tint : TournamentPalette.surfaceStrong)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(selectedTab == tag ? tint : TournamentPalette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.tournamentPress)
    }

    @ViewBuilder
    private var currentList: some View {
        switch selectedTab {
        case 0:
            if viewModel.marcatori.isEmpty {
                EmptyStateView(
                    icon: "soccerball",
                    title: "Nessun marcatore",
                    message: "Per questa edizione non risultano gol registrati."
                )
                .padding(.top, 40)
            } else {
                statCard {
                    ForEach(Array(viewModel.marcatori.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(destination: playerDestination(for: entry)) {
                            StatRow(
                                position: index + 1,
                                entry: entry,
                                valueLabel: "\(entry.gol)",
                                valueIcon: "soccerball.fill",
                                tint: TournamentPalette.accent
                            )
                        }
                        .buttonStyle(.tournamentPress)
                        if index < viewModel.marcatori.count - 1 {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }

        case 1:
            if viewModel.cartelliniPlayers.isEmpty {
                EmptyStateView(
                    icon: "rectangle.fill",
                    title: "Nessun cartellino",
                    message: "Per questa edizione non risultano ammonizioni o espulsioni."
                )
                .padding(.top, 40)
            } else {
                statCard {
                    ForEach(Array(viewModel.cartelliniPlayers.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink(destination: playerDestination(for: entry)) {
                            CartelliniRow(position: index + 1, entry: entry)
                        }
                        .buttonStyle(.tournamentPress)
                        if index < viewModel.cartelliniPlayers.count - 1 {
                            Divider().padding(.leading, 74)
                        }
                    }
                }
            }

        default:
            awardsList
        }
    }

    private var awardsList: some View {
        VStack(spacing: 16) {
            awardSectionCard(
                title: "Capocannoniere",
                subtitle: "Gol segnati in partita.",
                entries: viewModel.capocannonieriPremio,
                emptyTitle: "Nessun capocannoniere",
                emptyMessage: "Appena verranno registrati i gol, la classifica premio apparirà qui.",
                tint: TournamentPalette.accent
            )

            awardSectionCard(
                title: "MVP del torneo",
                subtitle: "Più MVP ufficiali.",
                entries: viewModel.mvpLeaders,
                emptyTitle: "Nessun MVP disponibile",
                emptyMessage: "Gli MVP appariranno qui quando saranno assegnati ufficialmente nelle partite.",
                tint: TournamentPalette.warm
            )

            awardSectionCard(
                title: "Miglior difensore",
                subtitle: "Più riconoscimenti difensore della partita.",
                entries: viewModel.bestDefenderLeaders,
                emptyTitle: "Nessun difensore disponibile",
                emptyMessage: "I migliori difensori appariranno qui quando saranno assegnati ufficialmente.",
                tint: TournamentPalette.accentDeep
            )

            awardSectionCard(
                title: "Miglior portiere",
                subtitle: "Partite, gol subiti, clean sheets e index.",
                entries: viewModel.migliorPortiereLeaders,
                emptyTitle: "Nessun portiere classificato",
                emptyMessage: "Serve assegnare il portiere nelle partite per popolare questa classifica premio.",
                tint: TournamentPalette.success
            )
        }
    }

    private func awardSectionCard(
        title: String,
        subtitle: String,
        entries: [StatsViewModel.AwardStandingEntry],
        emptyTitle: String,
        emptyMessage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TournamentSectionHeader(title: title, subtitle: subtitle)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, entries.isEmpty ? 16 : 8)

            if entries.isEmpty {
                EmptyStateView(icon: "trophy.fill", title: emptyTitle, message: emptyMessage)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(destination: playerDestination(for: entry)) {
                        AwardRow(position: index + 1, entry: entry, tint: tint)
                    }
                    .buttonStyle(.tournamentPress)
                    if index < entries.count - 1 {
                        Divider().padding(.leading, 74)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .tournamentCard(padding: 0)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func playerDestination(for entry: StatsViewModel.PlayerStatEntry) -> some View {
        if let player = viewModel.player(for: entry) {
            PlayerDetailView(player: player)
        } else {
            HistoricPlayerDetailView(profile: HistoricPlayerProfile(entry: entry, edition: appState.selectedEdition))
        }
    }

    @ViewBuilder
    private func playerDestination(for entry: StatsViewModel.AwardStandingEntry) -> some View {
        if let player = viewModel.player(for: entry) {
            PlayerDetailView(player: player)
        } else {
            HistoricPlayerDetailView(
                profile: HistoricPlayerProfile(
                    id: entry.playerDocumentId ?? entry.id,
                    playerId: entry.playerDocumentId ?? entry.id,
                    displayName: entry.nome,
                    pictureURL: entry.pictureURL,
                    teamId: entry.teamId,
                    teamName: entry.teamName,
                    edition: appState.selectedEdition,
                    jerseyNumber: entry.jerseyNumber,
                    position: entry.position
                )
            )
        }
    }

    private func statCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .tournamentCard(padding: 0)
            .padding(.horizontal, 16)
    }
}

private struct StatRow: View {
    @Environment(AppState.self) private var appState

    /// Lo stemma della squadra del giocatore, dall'edizione in corso.
    private var stemmaSquadra: String? {
        guard let id = entry.teamId, !id.isEmpty else { return nil }
        return appState.editionTeams.first { $0.teamId == id }?.logoURL
    }

    let position: Int
    let entry: StatsViewModel.PlayerStatEntry
    let valueLabel: String
    let valueIcon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text("\(position)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }

            CachedAsyncImage(
                urlString: entry.pictureURL,
                placeholderIcon: "person.fill",
                contentAlignment: .top
            )
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nome)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)
                // Lo stemma **prima** del nome squadra: senza foto del
                // giocatore la riga era un cerchio grigio e due scritte, e a
                // colpo d'occhio non si distingueva una riga dall'altra.
                HStack(spacing: 5) {
                    if let logo = stemmaSquadra {
                        TournamentTeamLogo(urlString: logo, size: 14)
                    }
                    Text(entry.teamName)
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: valueIcon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(valueLabel)
                        .font(.title3.bold())
                        .foregroundStyle(TournamentPalette.ink)
                }
                if entry.presenze > 0 {
                    Text("\(entry.presenze) pres.")
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct AwardRow: View {
    @Environment(AppState.self) private var appState

    /// Lo stemma della squadra del giocatore, dall'edizione in corso.
    private var stemmaSquadra: String? {
        guard let id = entry.teamId, !id.isEmpty else { return nil }
        return appState.editionTeams.first { $0.teamId == id }?.logoURL
    }

    let position: Int
    let entry: StatsViewModel.AwardStandingEntry
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text("\(position)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
            }

            CachedAsyncImage(
                urlString: entry.pictureURL,
                placeholderIcon: "person.fill",
                contentAlignment: .top
            )
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nome)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)
                // Lo stemma **prima** del nome squadra: senza foto del
                // giocatore la riga era un cerchio grigio e due scritte, e a
                // colpo d'occhio non si distingueva una riga dall'altra.
                HStack(spacing: 5) {
                    if let logo = stemmaSquadra {
                        TournamentTeamLogo(urlString: logo, size: 14)
                    }
                    Text(entry.teamName)
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.primaryValue)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                if let secondaryValue = entry.secondaryValue, !secondaryValue.isEmpty {
                    Text(secondaryValue)
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct CartelliniRow: View {
    @Environment(AppState.self) private var appState

    /// Lo stemma della squadra del giocatore, dall'edizione in corso.
    private var stemmaSquadra: String? {
        guard let id = entry.teamId, !id.isEmpty else { return nil }
        return appState.editionTeams.first { $0.teamId == id }?.logoURL
    }

    let position: Int
    let entry: StatsViewModel.PlayerStatEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.12))
                    .frame(width: 34, height: 34)
                Text("\(position)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusTint)
            }

            CachedAsyncImage(
                urlString: entry.pictureURL,
                placeholderIcon: "person.fill",
                contentAlignment: .top
            )
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.nome)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)
                // Lo stemma **prima** del nome squadra: senza foto del
                // giocatore la riga era un cerchio grigio e due scritte, e a
                // colpo d'occhio non si distingueva una riga dall'altra.
                HStack(spacing: 5) {
                    if let logo = stemmaSquadra {
                        TournamentTeamLogo(urlString: logo, size: 14)
                    }
                    Text(entry.teamName)
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                if entry.ammonizioni > 0 {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TournamentPalette.warm)
                            .frame(width: 10, height: 14)
                        Text("\(entry.ammonizioni)")
                            .font(.caption.bold())
                            .foregroundStyle(TournamentPalette.warm)
                    }
                }
                if entry.espulsioni > 0 {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(TournamentPalette.danger)
                            .frame(width: 10, height: 14)
                        Text("\(entry.espulsioni)")
                            .font(.caption.bold())
                            .foregroundStyle(TournamentPalette.danger)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusTint: Color {
        entry.espulsioni > 0 ? TournamentPalette.danger : TournamentPalette.warm
    }
}

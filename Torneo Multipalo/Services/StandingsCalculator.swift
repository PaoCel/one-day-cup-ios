import Foundation

class StandingsCalculator {
    private struct HeadToHeadEntry {
        var points = 0
        var goalsFor = 0
        var goalsAgainst = 0

        var goalDifference: Int { goalsFor - goalsAgainst }
    }

    /// Vincitore ai rigori che conta anche in classifica, o nil.
    ///
    /// Gemello di `TMH.shootoutStandingsWin` (PWA, tm-helpers.js) e di
    /// `shootoutStandingsWin` in functions/career-stats-core.js. La regola
    /// viaggia sul match e non sulla config del torneo: così resta quella in
    /// vigore il giorno in cui si è giocato.
    private static func shootoutStandingsWinner(_ match: Match) -> String? {
        guard match.penaltyShootout == true,
              let points = match.shootoutWinPoints, points > 0,
              let winner = match.penaltyWinner?.trimmingCharacters(in: .whitespacesAndNewlines),
              !winner.isEmpty else { return nil }
        return winner
    }

    /// Lo scarto fra quello che la tabella conta (V/P piene) e quello che il
    /// regolamento dà davvero allo shootout. Una partita che non dichiara i
    /// punti lascia lo scarto a zero, e si comporta come prima.
    private static func applyShootoutPoints(_ match: Match,
                                            winner: String,
                                            loser: String,
                                            to entries: inout [String: StandingsEntry]) {
        guard let win = match.shootoutWinPoints else { return }
        let loss = match.shootoutLossPoints ?? 0
        if let e = entries[winner] {
            entries[winner]?.shootoutPointsDelta += win - e.pointsForWin
        }
        if let e = entries[loser] {
            entries[loser]?.shootoutPointsDelta += loss - e.pointsForLoss
        }
    }

    static func calculate(
        from matches: [Match],
        initialEntries: [StandingsEntry] = [],
        rules: TournamentEditionFormat.StandingsRules = .standard,
        manualOverrides: [String: Any]? = nil,
        teamResolver: ((String, Match.TeamMeta, Int) -> (name: String, logo: String?))? = nil
    ) -> [StandingsEntry] {
        var entries: [String: StandingsEntry] = initialEntries.reduce(into: [:]) { result, entry in
            guard !entry.teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result[entry.teamId] = entry
        }

        let gironeMatches = matches.filter { TournamentPhaseKey.isGroupStage($0.fase) }

        for match in gironeMatches {
            let normalizedTeam1 = normalizeTeamId(match.team1)
            let normalizedTeam2 = normalizeTeamId(match.team2)

            guard !normalizedTeam1.isEmpty,
                  !normalizedTeam2.isEmpty,
                  normalizedTeam1 != normalizedTeam2,
                  normalizedTeam1.lowercased() != "tbd",
                  normalizedTeam2.lowercased() != "tbd" else {
                continue
            }

            let resolvedTeam1 = teamResolver?(match.team1, match.team1Meta, match.edizione)
                ?? (name: match.team1Meta.name, logo: match.team1Meta.logo)
            let resolvedTeam2 = teamResolver?(match.team2, match.team2Meta, match.edizione)
                ?? (name: match.team2Meta.name, logo: match.team2Meta.logo)

            if entries[normalizedTeam1] == nil {
                entries[normalizedTeam1] = StandingsEntry(
                    teamId: normalizedTeam1,
                    teamName: resolvedTeam1.name,
                    teamLogo: resolvedTeam1.logo,
                    pointsForWin: rules.winPoints,
                    pointsForDraw: rules.drawPoints,
                    pointsForLoss: rules.lossPoints
                )
            }
            if entries[normalizedTeam2] == nil {
                entries[normalizedTeam2] = StandingsEntry(
                    teamId: normalizedTeam2,
                    teamName: resolvedTeam2.name,
                    teamLogo: resolvedTeam2.logo,
                    pointsForWin: rules.winPoints,
                    pointsForDraw: rules.drawPoints,
                    pointsForLoss: rules.lossPoints
                )
            }

            let isLive = match.isStarted && !match.isPlayed

            if isLive {
                entries[normalizedTeam1]?.isPlaying = true
                entries[normalizedTeam2]?.isPlaying = true
            }

            guard match.isPlayed || isLive else { continue }

            let g1 = match.team1Goals
            let g2 = match.team2Goals

            entries[normalizedTeam1]?.goalsFor += g1
            entries[normalizedTeam1]?.goalsAgainst += g2
            entries[normalizedTeam2]?.goalsFor += g2
            entries[normalizedTeam2]?.goalsAgainst += g1
            entries[normalizedTeam1]?.played += 1
            entries[normalizedTeam2]?.played += 1

            if g1 > g2 {
                entries[normalizedTeam1]?.won += 1
                entries[normalizedTeam2]?.lost += 1
            } else if g1 < g2 {
                entries[normalizedTeam1]?.lost += 1
                entries[normalizedTeam2]?.won += 1
            } else if let shootoutWinner = shootoutStandingsWinner(match),
                      normalizeTeamId(shootoutWinner) == normalizedTeam1 {
                // Pari nei regolamentari, deciso allo shootout. In tabella è
                // una V e una P; i punti però li dice la partita — Mormon 2026
                // vuole 2 a chi vince e 1 a chi perde, non 3 e 0.
                entries[normalizedTeam1]?.won += 1
                entries[normalizedTeam2]?.lost += 1
                applyShootoutPoints(match, winner: normalizedTeam1, loser: normalizedTeam2, to: &entries)
            } else if let shootoutWinner = shootoutStandingsWinner(match),
                      normalizeTeamId(shootoutWinner) == normalizedTeam2 {
                entries[normalizedTeam2]?.won += 1
                entries[normalizedTeam1]?.lost += 1
                applyShootoutPoints(match, winner: normalizedTeam2, loser: normalizedTeam1, to: &entries)
            } else {
                entries[normalizedTeam1]?.drawn += 1
                entries[normalizedTeam2]?.drawn += 1
            }

            for event in match.safeEventi {
                switch normalizedEventType(event.tipo) {
                case "red":
                    if let teamId = event.squadraId {
                        entries[teamId]?.redCards += 1
                    }
                case "yellow":
                    if let teamId = event.squadraId {
                        entries[teamId]?.yellowCards += 1
                    }
                default:
                    break
                }
            }
        }

        let pairOverrides = manualPairOverrides(from: manualOverrides)
        let orderedByPoints = Dictionary(grouping: Array(entries.values)) { $0.points }
            .keys
            .sorted(by: >)
            .flatMap { points -> [StandingsEntry] in
                let group = entries.values.filter { $0.points == points }
                return resolveTieGroup(
                    group,
                    matches: gironeMatches.filter(\.isPlayed),
                    pairOverrides: pairOverrides,
                    criterionIndex: 0
                )
            }

        return orderedByPoints
    }

    private static func normalizedEventType(_ rawValue: String) -> String {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "red", "red_card", "redcard", "rosso", "cartellino_rosso", "espulsione":
            return "red"
        case "yellow", "yellow_card", "yellowcard", "giallo", "cartellino_giallo", "ammonizione":
            return "yellow"
        default:
            return rawValue
        }
    }

    private static func manualPairOverrides(from rawOverrides: [String: Any]?) -> [String: String] {
        guard let rawOverrides else { return [:] }

        return rawOverrides.reduce(into: [:]) { result, pair in
            guard pair.key.contains("_") else { return }
            guard let winnerId = pair.value as? String,
                  !winnerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            result[pair.key] = winnerId
        }
    }

    private static func normalizeTeamId(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveTieGroup(
        _ group: [StandingsEntry],
        matches: [Match],
        pairOverrides: [String: String],
        criterionIndex: Int
    ) -> [StandingsEntry] {
        guard group.count > 1 else { return group }

        // Gli indici 5 e 6 sono i cartellini (rossi, poi gialli): il sorteggio
        // arriva solo dopo, all'indice 7.
        if criterionIndex >= 7 {
            return resolveByDraw(group, pairOverrides: pairOverrides)
        }

        let teamIds = Set(group.map(\.teamId))
        let h2hMatches = matches.filter { teamIds.contains($0.team1) && teamIds.contains($0.team2) }

        // Senza scontri diretti fra loro non si applicano i tre criteri che li
        // guardano: si salta dritti alla differenza reti generale (indice 3).
        if criterionIndex <= 2, h2hMatches.isEmpty {
            return resolveTieGroup(group, matches: matches, pairOverrides: pairOverrides, criterionIndex: 3)
        }

        let h2hTable = makeHeadToHeadTable(group: group, matches: h2hMatches)
        let criterion = criterionValues(
            group: group,
            h2hTable: h2hTable,
            criterionIndex: criterionIndex
        )

        let buckets = Dictionary(grouping: group) { criterion.values[$0.teamId] ?? 0 }
        guard buckets.count > 1 else {
            return resolveTieGroup(group, matches: matches, pairOverrides: pairOverrides, criterionIndex: criterionIndex + 1)
        }

        return buckets.keys.sorted(by: criterion.higherIsBetter ? (>) : (<)).flatMap { value in
            var bucket = buckets[value] ?? []
            if bucket.count == 1 {
                bucket[0].tieBreakExplanation = criterion.explanation
                return bucket
            }
            return resolveTieGroup(bucket, matches: matches, pairOverrides: pairOverrides, criterionIndex: criterionIndex + 1)
        }
    }

    private static func makeHeadToHeadTable(
        group: [StandingsEntry],
        matches: [Match]
    ) -> [String: HeadToHeadEntry] {
        var table = Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, HeadToHeadEntry()) })

        for match in matches {
            guard table[match.team1] != nil, table[match.team2] != nil else { continue }

            let g1 = match.team1Goals
            let g2 = match.team2Goals

            table[match.team1]?.goalsFor += g1
            table[match.team1]?.goalsAgainst += g2
            table[match.team2]?.goalsFor += g2
            table[match.team2]?.goalsAgainst += g1

            if g1 > g2 {
                table[match.team1]?.points += 3
            } else if g2 > g1 {
                table[match.team2]?.points += 3
            } else if let shootoutWinner = shootoutStandingsWinner(match),
                      shootoutWinner == match.team1 {
                // Stessa regola della classifica generale: se il torneo dà
                // punti a chi vince ai rigori, lo scontro diretto deve
                // saperlo, altrimenti i due criteri si contraddicono.
                table[match.team1]?.points += match.shootoutWinPoints ?? 3
                // Anche il punto di chi perde allo shootout: col 2/1 del
                // regolamento Mormon, darne 2 al vincitore e 0 al perdente
                // falsava lo scontro diretto rispetto alla classifica generale.
                table[match.team2]?.points += match.shootoutLossPoints ?? 0
            } else if let shootoutWinner = shootoutStandingsWinner(match),
                      shootoutWinner == match.team2 {
                table[match.team2]?.points += match.shootoutWinPoints ?? 3
                table[match.team1]?.points += match.shootoutLossPoints ?? 0
            } else {
                table[match.team1]?.points += 1
                table[match.team2]?.points += 1
            }
        }

        return table
    }

    private static func criterionValues(
        group: [StandingsEntry],
        h2hTable: [String: HeadToHeadEntry],
        criterionIndex: Int
    ) -> (values: [String: Int], higherIsBetter: Bool, explanation: String) {
        switch criterionIndex {
        case 0:
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, h2hTable[$0.teamId]?.points ?? 0) }),
                true,
                "ahead on head-to-head points"
            )
        case 1:
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, h2hTable[$0.teamId]?.goalDifference ?? 0) }),
                true,
                "ahead on head-to-head goal difference"
            )
        case 2:
            // Gol fatti negli scontri diretti: mancava, e la v2 ce l'ha. Due
            // motori di classifica che ordinano diversamente la stessa parita'
            // e' il genere di differenza che si scopre davanti a tutti.
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, h2hTable[$0.teamId]?.goalsFor ?? 0) }),
                true,
                "ahead on head-to-head goals scored"
            )
        case 3:
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, $0.goalDifference) }),
                true,
                "ahead on overall goal difference"
            )
        case 4:
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, $0.goalsFor) }),
                true,
                "ahead on goals scored"
            )
        case 5:
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, $0.redCards) }),
                false,
                "ahead on fewer red cards"
            )
        default:
            return (
                Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, $0.yellowCards) }),
                false,
                "ahead on fewer yellow cards"
            )
        }
    }

    private static func resolveByDraw(
        _ group: [StandingsEntry],
        pairOverrides: [String: String]
    ) -> [StandingsEntry] {
        var manualScores = Dictionary(uniqueKeysWithValues: group.map { ($0.teamId, 0) })

        for left in group {
            for right in group where left.teamId != right.teamId {
                let key = "\(left.teamId)_\(right.teamId)"
                let reverseKey = "\(right.teamId)_\(left.teamId)"
                if pairOverrides[key] == left.teamId || pairOverrides[reverseKey] == left.teamId {
                    manualScores[left.teamId, default: 0] += 1
                }
            }
        }

        let hasManualDecision = manualScores.values.contains { $0 > 0 }

        return group.sorted { lhs, rhs in
            let lhsScore = manualScores[lhs.teamId, default: 0]
            let rhsScore = manualScores[rhs.teamId, default: 0]
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            return lhs.teamName.localizedCaseInsensitiveCompare(rhs.teamName) == .orderedAscending
        }
        .map { entry in
            var copy = entry
            copy.tieBreakExplanation = hasManualDecision ? "manual coin toss decision" : "draw required"
            return copy
        }
    }
}

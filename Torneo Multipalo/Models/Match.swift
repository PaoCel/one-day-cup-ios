import Foundation
import FirebaseFirestore

struct Match: Decodable, Identifiable {
    @DocumentID var id: String?
    var edizione: Int
    var giornata: Int
    var fase: String
    var group: String?
    var idFase: String?
    /// "principale" o "consolazione". I due tabelloni usano le stesse `fase`
    /// (quarti, semifinale, finale…), quindi senza questo campo i quarti di
    /// consolazione finirebbero mescolati a quelli del tabellone principale.
    /// Assente sulle edizioni precedenti al configuratore: vale "principale".
    var tabellone: String?
    var campo: String?
    var matchTime: String?
    var team1: String
    var team2: String
    var team1Meta: TeamMeta
    var team2Meta: TeamMeta
    var started: Bool?
    var played: Bool?
    var eventi: [MatchEvent]?
    var team1Formation: [String]?
    var team2Formation: [String]?
    var team1GoalkeeperPlayerId: String?
    var team1GoalkeeperPlayerName: String?
    var team2GoalkeeperPlayerId: String?
    var team2GoalkeeperPlayerName: String?
    var mvp: MatchMvp?
    var bestDefender: MatchMvp?
    var penaltyShootout: Bool?
    var penaltyScore: PenaltyScore?
    var penaltyWinner: String?
    var penaltyDetails: [PenaltyKick]?
    /// Punti che il torneo assegna a chi vince ai rigori in fase a girone
    /// (Mormon: 3). Viaggia sul match e non sulla config del torneo, così
    /// resta la regola in vigore il giorno in cui si è giocato.
    var shootoutWinPoints: Int?
    /// Quanti punti prende chi **perde** allo shootout. Mormon 2026: 1.
    /// Assente sulle partite vecchie, e lì vale 0 — cioè come si è sempre
    /// contato, e il passato non si riscrive da sé.
    var shootoutLossPoints: Int?
    var scoreKnown: Bool?
    var regulationScore: RegulationScore?
    var winnerTeamId: String?
    var resultStatus: String?
    var startTime: Timestamp?
    var matchDuration: Int?
    var bufferMinutes: Int?
    var goalkeeperTimeline: [GoalkeeperTimelineEntry]?
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
    var tournamentId: String?

    struct TeamMeta: Decodable {
        var id: String?
        var name: String
        var logo: String?

        enum CodingKeys: String, CodingKey {
            case id, name, logo
            case teamId, squadraId, nomeSquadra, logoSquadra
        }

        init(id: String? = nil, name: String = "Squadra", logo: String? = nil) {
            self.id = id
            self.name = name
            self.logo = logo
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = Match.decodeFirstString(in: c, keys: [.id, .teamId, .squadraId])
            name = Match.decodeFirstNonEmptyString(in: c, keys: [.name, .nomeSquadra]) ?? "Squadra"
            logo = Match.decodeFirstNonEmptyString(in: c, keys: [.logo, .logoSquadra])
        }
    }

    struct MatchMvp: Decodable {
        var playerId: String?
        var playerName: String?
        var team: Int?
        var mvpPhotoURL: String?

        enum CodingKeys: String, CodingKey {
            case playerId, playerName, team, mvpPhotoURL
        }

        init(playerId: String? = nil, playerName: String? = nil, team: Int? = nil, mvpPhotoURL: String? = nil) {
            self.playerId = playerId
            self.playerName = playerName
            self.team = team
            self.mvpPhotoURL = mvpPhotoURL
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            playerId = try c.decodeIfPresent(String.self, forKey: .playerId)
            playerName = try c.decodeIfPresent(String.self, forKey: .playerName)
            team = try c.decodeIfPresent(Int.self, forKey: .team)
            mvpPhotoURL = try c.decodeIfPresent(String.self, forKey: .mvpPhotoURL)
        }
    }

    struct GoalkeeperSelection {
        var playerId: String?
        var playerName: String?
    }

    struct PenaltyScore: Decodable {
        var team1: Int
        var team2: Int
    }

    struct RegulationScore: Decodable {
        var team1: Int
        var team2: Int
    }

    struct PenaltyKick: Decodable, Identifiable {
        var id: String { "\(teamId)_\(order)" }
        var playerId: String?
        var playerName: String?
        var teamId: String
        var scored: Bool
        var order: Int
        var penaltyMiss: PenaltyMiss?

        enum CodingKeys: String, CodingKey {
            case playerId, playerName, teamId, scored, order, penaltyMiss
        }

        init(playerId: String? = nil, playerName: String? = nil,
             teamId: String, scored: Bool, order: Int, penaltyMiss: PenaltyMiss? = nil) {
            self.playerId = playerId
            self.playerName = playerName
            self.teamId = teamId
            self.scored = scored
            self.order = order
            self.penaltyMiss = scored ? nil : penaltyMiss
        }
    }

    struct GoalkeeperTimelineEntry: Decodable {
        var playerId: String
        var playerName: String?
        var startMinute: Int

        enum CodingKeys: String, CodingKey {
            case playerId, playerName, startMinute
        }

        init(playerId: String, playerName: String? = nil, startMinute: Int) {
            self.playerId = playerId
            self.playerName = playerName
            self.startMinute = startMinute
        }
    }

    var isPlayed: Bool { played ?? false }
    var isStarted: Bool { started ?? false }
    var isLive: Bool { isStarted && !isPlayed }
    var safeEventi: [MatchEvent] { eventi ?? [] }
    var hasGoalkeeperAssignments: Bool {
        team1Goalkeeper != nil || team2Goalkeeper != nil
    }
    var resolvedWinnerTeamId: String? {
        if let winnerTeamId = winnerTeamId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !winnerTeamId.isEmpty {
            return winnerTeamId
        }
        if team1Goals > team2Goals { return team1 }
        if team2Goals > team1Goals { return team2 }
        return penaltyWinner
    }
    var hasKnownScore: Bool {
        if scoreKnown == false { return false }
        return true
    }
    var safePenaltyDetails: [PenaltyKick] { penaltyDetails ?? [] }

    var effectiveDuration: Int { matchDuration ?? 25 }
    var effectiveBuffer: Int { bufferMinutes ?? 5 }

    /// Parse the scheduled start time from matchTime string (e.g. "09:00" from "09:00 - 09:25")
    var scheduledStartMinutesFromMidnight: Int? {
        guard let time = matchTime?.trimmingCharacters(in: .whitespacesAndNewlines),
              !time.isEmpty else { return nil }
        let parts = time.components(separatedBy: "-")
        guard let startPart = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let timeParts = startPart.components(separatedBy: ":")
        guard timeParts.count == 2,
              let hours = Int(timeParts[0]),
              let minutes = Int(timeParts[1]) else { return nil }
        return hours * 60 + minutes
    }

    /// The actual end time (when match was marked as played), or estimated end if still live
    var actualEndDate: Date? {
        guard let startTime else { return nil }
        if isPlayed {
            return updatedAt?.dateValue() ?? startTime.dateValue().addingTimeInterval(TimeInterval(effectiveDuration * 60))
        }
        if isLive {
            return Date() // still going
        }
        return nil
    }

    var elapsedMinute: Int? {
        guard let startTime else { return nil }
        let elapsed = Date().timeIntervalSince(startTime.dateValue())
        guard elapsed > 0 else { return nil }
        return Int(ceil(elapsed / 60.0))
    }

    func goalkeeperAtMinute(_ minute: Int) -> GoalkeeperTimelineEntry? {
        guard let entries = goalkeeperTimeline, !entries.isEmpty else { return nil }
        let sorted = entries.sorted { $0.startMinute < $1.startMinute }
        var active: GoalkeeperTimelineEntry?
        for entry in sorted {
            if entry.startMinute <= minute {
                active = entry
            }
        }
        return active
    }

    var notificationRelevantTeamIds: [String] {
        Self.sanitizedNotificationIds([team1, team2])
    }
    var notificationRelevantPlayerIds: [String] {
        Self.sanitizedNotificationIds(
            (team1Formation ?? []).map(Optional.some)
            + (team2Formation ?? []).map(Optional.some)
            + [
                team1GoalkeeperPlayerId,
                team2GoalkeeperPlayerId,
                mvp?.playerId,
                bestDefender?.playerId,
            ]
            + safeEventi.flatMap { [$0.giocatoreId, $0.assistPlayerId] }
        )
    }

    var team1Goalkeeper: GoalkeeperSelection? {
        Self.makeGoalkeeperSelection(
            playerId: team1GoalkeeperPlayerId,
            playerName: team1GoalkeeperPlayerName
        )
    }

    var team2Goalkeeper: GoalkeeperSelection? {
        Self.makeGoalkeeperSelection(
            playerId: team2GoalkeeperPlayerId,
            playerName: team2GoalkeeperPlayerName
        )
    }

    func goalkeeperPlayerId(for teamId: String) -> String? {
        switch teamId {
        case team1:
            return team1GoalkeeperPlayerId
        case team2:
            return team2GoalkeeperPlayerId
        default:
            return nil
        }
    }

    func goalkeeper(for teamId: String) -> GoalkeeperSelection? {
        switch teamId {
        case team1:
            return team1Goalkeeper
        case team2:
            return team2Goalkeeper
        default:
            return nil
        }
    }

    var team1Goals: Int {
        if scoreKnown != false, let regulationScore {
            return regulationScore.team1
        }
        return safeEventi.filter {
            $0.squadraId == team1 && ($0.tipo == "gol" || $0.tipo == "rigore_segnato" || $0.tipo == "punizione_segnata")
        }.count
        + safeEventi.filter { $0.squadraId == team2 && $0.tipo == "autogol" }.count
    }

    var team2Goals: Int {
        if scoreKnown != false, let regulationScore {
            return regulationScore.team2
        }
        return safeEventi.filter {
            $0.squadraId == team2 && ($0.tipo == "gol" || $0.tipo == "rigore_segnato" || $0.tipo == "punizione_segnata")
        }.count
        + safeEventi.filter { $0.squadraId == team1 && $0.tipo == "autogol" }.count
    }

    enum CodingKeys: String, CodingKey {
        case edizione, giornata, fase, group, idFase, campo, matchTime
        case team1, team2, team1Meta, team2Meta
        case started, played, eventi, team1Formation, team2Formation
        case team1GoalkeeperPlayerId, team2GoalkeeperPlayerId
        case team1GoalkeeperPlayerName, team2GoalkeeperPlayerName
        case team1GoalkeeperId, team2GoalkeeperId
        case mvp, bestDefender
        case penaltyShootout, penaltyScore, penaltyWinner, penaltyDetails, shootoutWinPoints, shootoutLossPoints
        case scoreKnown, regulationScore, winnerTeamId, resultStatus
        case startTime, matchDuration, bufferMinutes, goalkeeperTimeline
        case createdAt, updatedAt, tournamentId
    }

    init(
        id: String? = nil,
        edizione: Int,
        giornata: Int,
        fase: String,
        group: String? = nil,
        idFase: String? = nil,
        campo: String? = nil,
        matchTime: String? = nil,
        team1: String,
        team2: String,
        team1Meta: TeamMeta,
        team2Meta: TeamMeta,
        started: Bool? = nil,
        played: Bool? = nil,
        eventi: [MatchEvent]? = nil,
        team1Formation: [String]? = nil,
        team2Formation: [String]? = nil,
        team1GoalkeeperPlayerId: String? = nil,
        team1GoalkeeperPlayerName: String? = nil,
        team2GoalkeeperPlayerId: String? = nil,
        team2GoalkeeperPlayerName: String? = nil,
        mvp: MatchMvp? = nil,
        bestDefender: MatchMvp? = nil,
        penaltyShootout: Bool? = nil,
        penaltyScore: PenaltyScore? = nil,
        penaltyWinner: String? = nil,
        penaltyDetails: [PenaltyKick]? = nil,
        shootoutWinPoints: Int? = nil,
        shootoutLossPoints: Int? = nil,
        scoreKnown: Bool? = nil,
        regulationScore: RegulationScore? = nil,
        winnerTeamId: String? = nil,
        resultStatus: String? = nil,
        startTime: Timestamp? = nil,
        matchDuration: Int? = nil,
        bufferMinutes: Int? = nil,
        goalkeeperTimeline: [GoalkeeperTimelineEntry]? = nil,
        createdAt: Timestamp? = nil,
        updatedAt: Timestamp? = nil,
        tournamentId: String? = nil
    ) {
        self.id = id
        self.edizione = edizione
        self.giornata = giornata
        self.fase = fase
        self.group = group
        self.idFase = idFase
        self.campo = campo
        self.matchTime = matchTime
        self.team1 = team1
        self.team2 = team2
        self.team1Meta = team1Meta
        self.team2Meta = team2Meta
        self.started = started
        self.played = played
        self.eventi = eventi
        self.team1Formation = team1Formation
        self.team2Formation = team2Formation
        self.team1GoalkeeperPlayerId = team1GoalkeeperPlayerId
        self.team1GoalkeeperPlayerName = team1GoalkeeperPlayerName
        self.team2GoalkeeperPlayerId = team2GoalkeeperPlayerId
        self.team2GoalkeeperPlayerName = team2GoalkeeperPlayerName
        self.mvp = mvp
        self.bestDefender = bestDefender
        self.penaltyShootout = penaltyShootout
        self.penaltyScore = penaltyScore
        self.penaltyWinner = penaltyWinner
        self.penaltyDetails = penaltyDetails
        self.shootoutWinPoints = shootoutWinPoints
        self.shootoutLossPoints = shootoutLossPoints
        self.scoreKnown = scoreKnown
        self.regulationScore = regulationScore
        self.winnerTeamId = winnerTeamId
        self.resultStatus = resultStatus
        self.startTime = startTime
        self.matchDuration = matchDuration
        self.bufferMinutes = bufferMinutes
        self.goalkeeperTimeline = goalkeeperTimeline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tournamentId = tournamentId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        edizione = Self.decodeInt(in: c, keys: [.edizione]) ?? 2026
        giornata = Self.decodeInt(in: c, keys: [.giornata]) ?? 0
        fase = Self.decodeFirstNonEmptyString(in: c, keys: [.fase]) ?? "girone"
        group = Self.decodeFirstNonEmptyString(in: c, keys: [.group])
        idFase = Self.decodeFirstNonEmptyString(in: c, keys: [.idFase])
        campo = Self.decodeFirstNonEmptyString(in: c, keys: [.campo])
        matchTime = Self.decodeFirstNonEmptyString(in: c, keys: [.matchTime])

        let fallbackTeam1 = try? c.decode(TeamMeta.self, forKey: .team1)
        let fallbackTeam2 = try? c.decode(TeamMeta.self, forKey: .team2)
        let explicitTeam1Meta = try? c.decode(TeamMeta.self, forKey: .team1Meta)
        let explicitTeam2Meta = try? c.decode(TeamMeta.self, forKey: .team2Meta)

        team1 = Self.decodeFirstNonEmptyString(in: c, keys: [.team1]) ?? fallbackTeam1?.id ?? explicitTeam1Meta?.id ?? ""
        team2 = Self.decodeFirstNonEmptyString(in: c, keys: [.team2]) ?? fallbackTeam2?.id ?? explicitTeam2Meta?.id ?? ""

        team1Meta = explicitTeam1Meta ?? Self.makeTeamMeta(from: fallbackTeam1, fallbackId: team1, fallbackName: "Squadra 1")
        team2Meta = explicitTeam2Meta ?? Self.makeTeamMeta(from: fallbackTeam2, fallbackId: team2, fallbackName: "Squadra 2")

        started = Self.decodeBool(in: c, keys: [.started])
        played = Self.decodeBool(in: c, keys: [.played])
        let decodedEvents = (try? c.decodeIfPresent([MatchEvent].self, forKey: .eventi)) ?? []
        let legacyMvpEvent = decodedEvents.first(where: { $0.tipo == "mvp" })
        eventi = decodedEvents.filter { $0.tipo != "mvp" }
        team1Formation = try? c.decodeIfPresent([String].self, forKey: .team1Formation)
        team2Formation = try? c.decodeIfPresent([String].self, forKey: .team2Formation)
        team1GoalkeeperPlayerId = Self.decodeFirstNonEmptyString(in: c, keys: [.team1GoalkeeperPlayerId, .team1GoalkeeperId])
        team1GoalkeeperPlayerName = Self.decodeFirstNonEmptyString(in: c, keys: [.team1GoalkeeperPlayerName])
        team2GoalkeeperPlayerId = Self.decodeFirstNonEmptyString(in: c, keys: [.team2GoalkeeperPlayerId, .team2GoalkeeperId])
        team2GoalkeeperPlayerName = Self.decodeFirstNonEmptyString(in: c, keys: [.team2GoalkeeperPlayerName])
        mvp = (try? c.decodeIfPresent(MatchMvp.self, forKey: .mvp))
            ?? Self.makeMvp(from: legacyMvpEvent, team1Id: team1, team2Id: team2)
        bestDefender = try? c.decodeIfPresent(MatchMvp.self, forKey: .bestDefender)
        penaltyShootout = Self.decodeBool(in: c, keys: [.penaltyShootout])
        penaltyScore = try? c.decodeIfPresent(PenaltyScore.self, forKey: .penaltyScore)
        penaltyWinner = Self.decodeFirstNonEmptyString(in: c, keys: [.penaltyWinner])
        penaltyDetails = try? c.decodeIfPresent([PenaltyKick].self, forKey: .penaltyDetails)
        shootoutWinPoints = Self.decodeInt(in: c, keys: [.shootoutWinPoints])
        shootoutLossPoints = Self.decodeInt(in: c, keys: [.shootoutLossPoints])
        scoreKnown = Self.decodeBool(in: c, keys: [.scoreKnown])
        regulationScore = try? c.decodeIfPresent(RegulationScore.self, forKey: .regulationScore)
        winnerTeamId = Self.decodeFirstNonEmptyString(in: c, keys: [.winnerTeamId])
        resultStatus = Self.decodeFirstNonEmptyString(in: c, keys: [.resultStatus])
        startTime = try? c.decodeIfPresent(Timestamp.self, forKey: .startTime)
        matchDuration = Self.decodeInt(in: c, keys: [.matchDuration])
        bufferMinutes = Self.decodeInt(in: c, keys: [.bufferMinutes])
        goalkeeperTimeline = try? c.decodeIfPresent([GoalkeeperTimelineEntry].self, forKey: .goalkeeperTimeline)
        createdAt = try? c.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Timestamp.self, forKey: .updatedAt)
        tournamentId = try? c.decodeIfPresent(String.self, forKey: .tournamentId)
    }

    private static func makeTeamMeta(from source: TeamMeta?, fallbackId: String, fallbackName: String) -> TeamMeta {
        guard let source else {
            return TeamMeta(id: fallbackId.isEmpty ? nil : fallbackId, name: fallbackName, logo: nil)
        }
        return TeamMeta(
            id: source.id ?? (fallbackId.isEmpty ? nil : fallbackId),
            name: source.name.isEmpty ? fallbackName : source.name,
            logo: source.logo
        )
    }

    private static func makeMvp(from event: MatchEvent?, team1Id: String, team2Id: String) -> MatchMvp? {
        guard let event else { return nil }
        let team: Int?
        switch event.squadraId {
        case team1Id:
            team = 1
        case team2Id:
            team = 2
        default:
            team = nil
        }
        return MatchMvp(playerId: event.giocatoreId, playerName: event.giocatoreNome, team: team)
    }

    private static func makeGoalkeeperSelection(playerId: String?, playerName: String?) -> GoalkeeperSelection? {
        let normalizedPlayerId = playerId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPlayerName = playerName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let normalizedPlayerId, !normalizedPlayerId.isEmpty {
            return GoalkeeperSelection(
                playerId: normalizedPlayerId,
                playerName: normalizedPlayerName
            )
        }

        if let normalizedPlayerName, !normalizedPlayerName.isEmpty {
            return GoalkeeperSelection(
                playerId: nil,
                playerName: normalizedPlayerName
            )
        }

        return nil
    }

    private static func sanitizedNotificationIds(_ rawValues: [String?]) -> [String] {
        Array(
            Set(
                rawValues.compactMap { rawValue in
                    guard let rawValue else { return nil }
                    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            )
        )
        .sorted()
    }

    private static func decodeFirstNonEmptyString<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> String? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(String.self, forKey: key),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func decodeFirstString<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> String? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(String.self, forKey: key) {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func decodeInt<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> Int? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                    return value
                }
            } catch {}
            do {
                if let stringValue = try container.decodeIfPresent(String.self, forKey: key),
                   let value = Int(stringValue) {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func decodeBool<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> Bool? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(Bool.self, forKey: key) {
                    return value
                }
            } catch {}
            do {
                if let stringValue = try container.decodeIfPresent(String.self, forKey: key) {
                    switch stringValue.lowercased() {
                    case "true", "1":
                        return true
                    case "false", "0":
                        return false
                    default:
                        break
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

struct MatchEvent: Decodable, Identifiable {
    let id: String

    var tipo: String
    var giocatoreId: String?
    var giocatoreNome: String?
    var squadraId: String?
    var minuto: Int?
    var assistName: String?
    var assistPlayerId: String?
    var playerOutName: String?
    var doubleYellow: Bool?
    var penaltyMiss: PenaltyMiss?
    var votes: Int?
    var mvpPhoto: String?

    enum CodingKeys: String, CodingKey {
        case tipo, giocatoreId, giocatoreNome, squadraId, minuto
        case type, playerId, playerName, teamId, minute
        case assist, assistName, assistPlayerName, assistId, assistPlayerId
        case playerOut, playerOutName, doubleYellow, votes, mvpPhoto, penaltyMiss
    }

    init(id: String = UUID().uuidString, tipo: String, giocatoreId: String? = nil, giocatoreNome: String? = nil,
         squadraId: String? = nil, minuto: Int? = nil, assistName: String? = nil,
         assistPlayerId: String? = nil, playerOutName: String? = nil,
         doubleYellow: Bool? = nil, votes: Int? = nil, mvpPhoto: String? = nil, penaltyMiss: PenaltyMiss? = nil) {
        self.id = id
        self.tipo = tipo
        self.giocatoreId = giocatoreId
        self.giocatoreNome = giocatoreNome
        self.squadraId = squadraId
        self.minuto = minuto
        self.assistName = assistName
        self.assistPlayerId = assistPlayerId
        self.playerOutName = playerOutName
        self.doubleYellow = doubleYellow
        self.penaltyMiss = tipo == "rigore_sbagliato" ? penaltyMiss : nil
        self.votes = votes
        self.mvpPhoto = mvpPhoto
    }

    init(from decoder: Decoder) throws {
        self.id = UUID().uuidString
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawType = Self.decodeFirstNonEmptyString(in: c, keys: [.tipo, .type]) ?? "evento"
        tipo = Self.normalizedEventType(rawType)
        giocatoreId = Self.decodeFirstNonEmptyString(in: c, keys: [.giocatoreId, .playerId])
        giocatoreNome = Self.decodeFirstNonEmptyString(in: c, keys: [.giocatoreNome, .playerName])
        squadraId = Self.decodeFirstNonEmptyString(in: c, keys: [.squadraId, .teamId])
        minuto = Self.decodeInt(in: c, keys: [.minuto, .minute])
        assistName = Self.decodeFirstNonEmptyString(in: c, keys: [.assist, .assistName, .assistPlayerName])
        assistPlayerId = Self.decodeFirstNonEmptyString(in: c, keys: [.assistId, .assistPlayerId])
        playerOutName = Self.decodeFirstNonEmptyString(in: c, keys: [.playerOut, .playerOutName])
        doubleYellow = Self.decodeBool(in: c, keys: [.doubleYellow])
        penaltyMiss = try? c.decodeIfPresent(PenaltyMiss.self, forKey: .penaltyMiss)
        votes = Self.decodeInt(in: c, keys: [.votes])
        mvpPhoto = Self.decodeFirstNonEmptyString(in: c, keys: [.mvpPhoto])
    }

    private static func normalizedEventType(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "goal", "gol":
            return "gol"
        case "freekick", "free_kick", "punizione", "punizione_segnata":
            return "punizione_segnata"
        case "own_goal", "owngoal", "autogol":
            return "autogol"
        case "yellow", "yellow_card", "yellowcard", "ammonizione":
            return "ammonizione"
        case "red", "red_card", "redcard", "espulsione":
            return "espulsione"
        case "penalty", "penalty_scored", "rigore_segnato":
            return "rigore_segnato"
        case "penalty_missed", "rigore_sbagliato":
            return "rigore_sbagliato"
        case "substitution", "sostituzione":
            return "sostituzione"
        case "assist":
            return "assist"
        case "mvp":
            return "mvp"
        default:
            return rawValue.lowercased()
        }
    }

    private static func decodeFirstNonEmptyString<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> String? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(String.self, forKey: key),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func decodeInt<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> Int? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                    return value
                }
            } catch {}
            do {
                if let stringValue = try container.decodeIfPresent(String.self, forKey: key),
                   let value = Int(stringValue) {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func decodeBool<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> Bool? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(Bool.self, forKey: key) {
                    return value
                }
            } catch {}
            do {
                if let stringValue = try container.decodeIfPresent(String.self, forKey: key) {
                    switch stringValue.lowercased() {
                    case "true", "1":
                        return true
                    case "false", "0":
                        return false
                    default:
                        break
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

extension Match: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> Match {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        return copy
    }
}

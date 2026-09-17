import Foundation
import FirebaseFirestore

/// Phase 4b — modello cross-torneo del documento `playerCareerStats/{playerId}`.
///
/// I documenti vengono scritti dalle Cloud Functions (`onMatchPlayedUpdateCareerStats`
/// trigger e `recomputeAllCareerStats` callable, deployate in Phase 4a).
/// L'app legge solo (rules: read isSignedIn, write false).
struct PlayerCareerStats: Codable {
    let playerId: String
    let nomeCompleto: String?
    let totalMatches: Int
    let totalGoals: Int
    let totalMvp: Int
    let totalYellowCards: Int
    let totalRedCards: Int
    let byTournament: [String: PlayerTournamentStats]
    let lastUpdated: Date?
    let schemaVersion: Int

    enum CodingKeys: String, CodingKey {
        case playerId
        case nomeCompleto
        case totalMatches
        case totalGoals
        case totalMvp
        case totalYellowCards
        case totalRedCards
        case byTournament
        case lastUpdated
        case schemaVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.playerId = (try? container.decode(String.self, forKey: .playerId)) ?? ""
        self.nomeCompleto = try? container.decodeIfPresent(String.self, forKey: .nomeCompleto)
        self.totalMatches = (try? container.decodeIfPresent(Int.self, forKey: .totalMatches)) ?? 0
        self.totalGoals = (try? container.decodeIfPresent(Int.self, forKey: .totalGoals)) ?? 0
        self.totalMvp = (try? container.decodeIfPresent(Int.self, forKey: .totalMvp)) ?? 0
        self.totalYellowCards = (try? container.decodeIfPresent(Int.self, forKey: .totalYellowCards)) ?? 0
        self.totalRedCards = (try? container.decodeIfPresent(Int.self, forKey: .totalRedCards)) ?? 0
        self.byTournament = (try? container.decodeIfPresent([String: PlayerTournamentStats].self, forKey: .byTournament)) ?? [:]

        // `lastUpdated` può arrivare come Firestore Timestamp.
        if let ts = try? container.decodeIfPresent(Timestamp.self, forKey: .lastUpdated) {
            self.lastUpdated = ts.dateValue()
        } else if let date = try? container.decodeIfPresent(Date.self, forKey: .lastUpdated) {
            self.lastUpdated = date
        } else {
            self.lastUpdated = nil
        }

        self.schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playerId, forKey: .playerId)
        try container.encodeIfPresent(nomeCompleto, forKey: .nomeCompleto)
        try container.encode(totalMatches, forKey: .totalMatches)
        try container.encode(totalGoals, forKey: .totalGoals)
        try container.encode(totalMvp, forKey: .totalMvp)
        try container.encode(totalYellowCards, forKey: .totalYellowCards)
        try container.encode(totalRedCards, forKey: .totalRedCards)
        try container.encode(byTournament, forKey: .byTournament)
        if let lastUpdated {
            try container.encode(Timestamp(date: lastUpdated), forKey: .lastUpdated)
        }
        try container.encode(schemaVersion, forKey: .schemaVersion)
    }

    init(
        playerId: String,
        nomeCompleto: String?,
        totalMatches: Int,
        totalGoals: Int,
        totalMvp: Int,
        totalYellowCards: Int,
        totalRedCards: Int,
        byTournament: [String: PlayerTournamentStats],
        lastUpdated: Date?,
        schemaVersion: Int
    ) {
        self.playerId = playerId
        self.nomeCompleto = nomeCompleto
        self.totalMatches = totalMatches
        self.totalGoals = totalGoals
        self.totalMvp = totalMvp
        self.totalYellowCards = totalYellowCards
        self.totalRedCards = totalRedCards
        self.byTournament = byTournament
        self.lastUpdated = lastUpdated
        self.schemaVersion = schemaVersion
    }
}

struct PlayerTournamentStats: Codable {
    let matches: Int
    let goals: Int
    let mvp: Int
    let yellowCards: Int
    let redCards: Int

    enum CodingKeys: String, CodingKey {
        case matches, goals, mvp, yellowCards, redCards
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.matches = (try? container.decodeIfPresent(Int.self, forKey: .matches)) ?? 0
        self.goals = (try? container.decodeIfPresent(Int.self, forKey: .goals)) ?? 0
        self.mvp = (try? container.decodeIfPresent(Int.self, forKey: .mvp)) ?? 0
        self.yellowCards = (try? container.decodeIfPresent(Int.self, forKey: .yellowCards)) ?? 0
        self.redCards = (try? container.decodeIfPresent(Int.self, forKey: .redCards)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(matches, forKey: .matches)
        try container.encode(goals, forKey: .goals)
        try container.encode(mvp, forKey: .mvp)
        try container.encode(yellowCards, forKey: .yellowCards)
        try container.encode(redCards, forKey: .redCards)
    }

    init(matches: Int, goals: Int, mvp: Int, yellowCards: Int, redCards: Int) {
        self.matches = matches
        self.goals = goals
        self.mvp = mvp
        self.yellowCards = yellowCards
        self.redCards = redCards
    }
}

/// Riepilogo restituito dalla callable `recomputeAllCareerStats` (Phase 4a).
struct RecomputeCareerStatsSummary {
    let processedMatches: Int
    let processedPlayers: Int
    let durationMs: Int
    let raw: [String: Any]

    init(raw: [String: Any]) {
        self.processedMatches = (raw["processedMatches"] as? Int)
            ?? Int((raw["processedMatches"] as? NSNumber)?.intValue ?? 0)
        self.processedPlayers = (raw["processedPlayers"] as? Int)
            ?? Int((raw["processedPlayers"] as? NSNumber)?.intValue ?? 0)
        self.durationMs = (raw["durationMs"] as? Int)
            ?? Int((raw["durationMs"] as? NSNumber)?.intValue ?? 0)
        self.raw = raw
    }
}

import XCTest
import FirebaseFirestore
@testable import TorneoMultipaloLogic

final class MatchModelLogicTests: XCTestCase {
    func testResolvedWinnerFallsBackToPenaltyWinnerAfterDrawnRegularTime() {
        let match = Match(
            id: "final-1",
            edizione: 2026,
            giornata: 7,
            fase: "finale",
            campo: "A",
            matchTime: "18:00",
            team1: "A",
            team2: "B",
            team1Meta: Match.TeamMeta(id: "A", name: "Alpha", logo: nil),
            team2Meta: Match.TeamMeta(id: "B", name: "Beta", logo: nil),
            started: true,
            played: true,
            eventi: [
                MatchEvent(tipo: "gol", giocatoreId: "a1", giocatoreNome: "Alpha 1", squadraId: "A"),
                MatchEvent(tipo: "gol", giocatoreId: "b1", giocatoreNome: "Beta 1", squadraId: "B")
            ],
            penaltyShootout: true,
            penaltyScore: Match.PenaltyScore(team1: 3, team2: 4),
            penaltyWinner: "B"
        )

        XCTAssertEqual(match.team1Goals, 1)
        XCTAssertEqual(match.team2Goals, 1)
        XCTAssertEqual(match.resolvedWinnerTeamId, "B")
    }

    func testScheduledStartMinutesParsesSingleTimeAndRange() {
        let singleTime = Match(
            edizione: 2026,
            giornata: 1,
            fase: "girone",
            matchTime: "09:05",
            team1: "A",
            team2: "B",
            team1Meta: Match.TeamMeta(id: "A", name: "Alpha", logo: nil),
            team2Meta: Match.TeamMeta(id: "B", name: "Beta", logo: nil)
        )
        let rangedTime = Match(
            edizione: 2026,
            giornata: 1,
            fase: "girone",
            matchTime: "11:00 - 11:25",
            team1: "A",
            team2: "C",
            team1Meta: Match.TeamMeta(id: "A", name: "Alpha", logo: nil),
            team2Meta: Match.TeamMeta(id: "C", name: "Gamma", logo: nil)
        )

        XCTAssertEqual(singleTime.scheduledStartMinutesFromMidnight, 545)
        XCTAssertEqual(rangedTime.scheduledStartMinutesFromMidnight, 660)
    }

    func testNotificationRelevantPlayerIdsCollectsUniqueIdsAcrossSources() {
        let match = Match(
            edizione: 2026,
            giornata: 2,
            fase: "girone",
            matchTime: "10:00",
            team1: "A",
            team2: "B",
            team1Meta: Match.TeamMeta(id: "A", name: "Alpha", logo: nil),
            team2Meta: Match.TeamMeta(id: "B", name: "Beta", logo: nil),
            eventi: [
                MatchEvent(
                    tipo: "gol",
                    giocatoreId: " scorer ",
                    giocatoreNome: "Mario Rossi",
                    squadraId: "A",
                    assistName: "Assist Man",
                    assistPlayerId: "assist-1"
                ),
                MatchEvent(
                    tipo: "ammonizione",
                    giocatoreId: "p2",
                    giocatoreNome: "Luca Bianchi",
                    squadraId: "B"
                )
            ],
            team1Formation: ["p1", "p2", " "],
            team2Formation: ["p3", "p2"],
            team1GoalkeeperPlayerId: "gk-1",
            team2GoalkeeperPlayerId: "gk-2",
            mvp: Match.MatchMvp(playerId: "p1", playerName: "Mario Rossi", team: 1)
        )

        XCTAssertEqual(
            match.notificationRelevantPlayerIds,
            ["assist-1", "gk-1", "gk-2", "p1", "p2", "p3", "scorer"]
        )
    }

    func testLegacyEventAliasesNormalizeAndAffectMatchScore() throws {
        let payload: [String: Any] = [
            "edizione": 2026,
            "giornata": 4,
            "fase": "girone",
            "team1": "A",
            "team2": "B",
            "team1Meta": ["id": "A", "name": "Alpha"],
            "team2Meta": ["id": "B", "name": "Beta"],
            "played": true,
            "eventi": [
                ["type": "freekick", "teamId": "A", "playerId": "a1"],
                ["type": "penalty_scored", "teamId": "A", "playerId": "a2"],
                ["type": "own_goal", "teamId": "A", "playerId": "a3"]
            ]
        ]

        let match = try Firestore.Decoder().decode(Match.self, from: payload)

        XCTAssertEqual(match.safeEventi.map(\.tipo), ["punizione_segnata", "rigore_segnato", "autogol"])
        XCTAssertEqual(match.team1Goals, 2)
        XCTAssertEqual(match.team2Goals, 1)
    }
}

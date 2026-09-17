import XCTest
@testable import TorneoMultipaloLogic

final class AwardStandingsBuilderTests: XCTestCase {
    func testAwardStandingsApplyPhaseWeightsAndGoalkeeperResolution() {
        let players = [
            TestFixtures.player(id: "striker-a", name: "Luca Bianchi", teamId: "A", number: 9, position: "Attaccante"),
            TestFixtures.player(id: "keeper-a", name: "Marco Porta", teamId: "A", number: 1, position: "Portiere"),
            TestFixtures.player(id: "keeper-b", name: "Paolo Muro", teamId: "B", number: 1, position: "Portiere")
        ]
        let editionTeams = [
            TestFixtures.editionTeam(id: "A", name: "Alfa"),
            TestFixtures.editionTeam(id: "B", name: "Beta")
        ]
        let semifinal = TestFixtures.match(
            id: "sf1",
            giornata: 5,
            phase: "semifinali",
            team1: "A",
            team2: "B",
            played: true,
            events: [
                TestFixtures.event("gol", teamId: "A", playerId: "striker-a", playerName: "Luca Bianchi")
            ],
            team1Goalkeeper: Match.GoalkeeperSelection(playerId: "keeper-a", playerName: "Marco Porta"),
            team2Goalkeeper: Match.GoalkeeperSelection(playerId: "keeper-b", playerName: "Paolo Muro"),
            mvp: Match.MatchMvp(playerId: "striker-a", playerName: "Luca Bianchi", team: 1)
        )
        let config = AwardConfig(
            data: [
                "topScorerWeightsByPhase": ["semifinali": 2.0],
                "mvpWeightsByPhase": ["semifinali": 3.0],
                "goalkeeperConcededWeightsByPhase": ["semifinali": 1.5]
            ]
        )

        let result = AwardStandingsBuilder.build(
            matches: [semifinal],
            players: players,
            editionTeams: editionTeams,
            config: config
        )

        XCTAssertEqual(result.topScorers.first?.id, "striker-a")
        XCTAssertEqual(result.topScorers.first?.rawValue, 1)
        XCTAssertEqual(result.topScorers.first?.weightedValue ?? -1, 2.0, accuracy: 0.001)

        XCTAssertEqual(result.mvps.first?.id, "striker-a")
        XCTAssertEqual(result.mvps.first?.weightedValue ?? -1, 3.0, accuracy: 0.001)

        XCTAssertEqual(result.goalkeepers.first?.id, "keeper-a")
        XCTAssertEqual(result.goalkeepers.first?.weightedValue ?? -1, 0.375, accuracy: 0.001)
        XCTAssertEqual(result.goalkeepers.first?.matchesCount, 1)
        XCTAssertEqual(result.goalkeepers.first?.goalsConceded, 0)
        XCTAssertEqual(result.goalkeepers.first?.cleanSheets, 1)
        XCTAssertTrue(result.goalkeepers.first?.eligible ?? false)
        XCTAssertEqual(result.goalkeepers.last?.id, "keeper-b")
        XCTAssertEqual(result.goalkeepers.last?.weightedValue ?? -1, 0.625, accuracy: 0.001)
    }
}

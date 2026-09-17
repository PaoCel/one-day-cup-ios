import XCTest
@testable import TorneoMultipaloLogic

final class StandingsCalculatorTests: XCTestCase {
    func testCompletedMatchesProduceExpectedRanking() {
        let matches = [
            TestFixtures.match(
                id: "m1",
                giornata: 1,
                team1: "A",
                team2: "B",
                played: true,
                events: [
                    TestFixtures.event("gol", teamId: "A"),
                    TestFixtures.event("gol", teamId: "A")
                ]
            ),
            TestFixtures.match(
                id: "m2",
                giornata: 2,
                team1: "A",
                team2: "C",
                played: true,
                events: [
                    TestFixtures.event("gol", teamId: "A")
                ]
            ),
            TestFixtures.match(
                id: "m3",
                giornata: 3,
                team1: "B",
                team2: "C",
                played: true,
                events: [
                    TestFixtures.event("gol", teamId: "B"),
                    TestFixtures.event("gol", teamId: "B"),
                    TestFixtures.event("gol", teamId: "C")
                ]
            )
        ]

        let standings = StandingsCalculator.calculate(from: matches)

        XCTAssertEqual(standings.map(\.teamId), ["A", "B", "C"])
        XCTAssertEqual(standings.map(\.points), [6, 3, 0])
        XCTAssertEqual(standings.first?.goalsFor, 3)
        XCTAssertEqual(standings.first?.goalsAgainst, 0)
    }

    func testManualOverridesCanReorderPerfectTie() {
        let matches = [
            TestFixtures.match(
                id: "m1",
                giornata: 1,
                team1: "A",
                team2: "B",
                played: true,
                events: [TestFixtures.event("gol", teamId: "A")]
            ),
            TestFixtures.match(
                id: "m2",
                giornata: 2,
                team1: "B",
                team2: "C",
                played: true,
                events: [TestFixtures.event("gol", teamId: "B")]
            ),
            TestFixtures.match(
                id: "m3",
                giornata: 3,
                team1: "C",
                team2: "A",
                played: true,
                events: [TestFixtures.event("gol", teamId: "C")]
            )
        ]

        let standings = StandingsCalculator.calculate(
            from: matches,
            manualOverrides: ["A_B": "B"]
        )

        XCTAssertEqual(standings.map(\.teamId), ["B", "A", "C"])
        XCTAssertEqual(standings.map(\.points), [3, 3, 3])
    }

    func testCalculatorIgnoresTbdTeamsAndMarksLiveMatches() {
        let matches = [
            TestFixtures.match(
                id: "m1",
                giornata: 1,
                team1: "A",
                team2: "B",
                played: true,
                events: [TestFixtures.event("gol", teamId: "A")]
            ),
            TestFixtures.match(
                id: "m2",
                giornata: 2,
                team1: "TBD",
                team2: "A",
                started: true,
                played: false
            ),
            TestFixtures.match(
                id: "m3",
                giornata: 3,
                team1: "B",
                team2: "C",
                started: true,
                played: false
            )
        ]

        let standings = StandingsCalculator.calculate(from: matches)

        XCTAssertEqual(standings.map(\.teamId), ["A", "C", "B"])
        XCTAssertEqual(standings.first?.points, 3)
        XCTAssertFalse(standings.first?.isPlaying ?? true)
        XCTAssertTrue(standings.first(where: { $0.teamId == "B" })?.isPlaying ?? false)
        XCTAssertTrue(standings.first(where: { $0.teamId == "C" })?.isPlaying ?? false)
    }

    func testTwoTeamTieResolvesByHeadToHeadPointsBeforeOverallGoalDifference() {
        let matches = [
            TestFixtures.match(
                id: "ab",
                giornata: 1,
                team1: "A",
                team2: "B",
                played: true,
                events: [TestFixtures.event("gol", teamId: "A")]
            ),
            TestFixtures.match(
                id: "bc",
                giornata: 2,
                team1: "B",
                team2: "C",
                played: true,
                events: [TestFixtures.event("gol", teamId: "B")]
            )
        ]

        let standings = StandingsCalculator.calculate(from: matches)

        XCTAssertEqual(standings.map(\.teamId), ["A", "B", "C"])
        XCTAssertEqual(standings[0].tieBreakExplanation, "ahead on head-to-head points")
    }

    func testEqualFootballCriteriaResolveByFewerRedThenFewerYellowCards() {
        let redTie = [
            TestFixtures.match(id: "ab", giornata: 1, team1: "A", team2: "B", played: true),
            TestFixtures.match(
                id: "ac",
                giornata: 2,
                team1: "A",
                team2: "C",
                played: true,
                events: [
                    TestFixtures.event("gol", teamId: "A"),
                    TestFixtures.event("rosso", teamId: "A")
                ]
            ),
            TestFixtures.match(
                id: "bc",
                giornata: 3,
                team1: "B",
                team2: "C",
                played: true,
                events: [TestFixtures.event("gol", teamId: "B")]
            )
        ]

        var standings = StandingsCalculator.calculate(from: redTie)
        XCTAssertEqual(standings.map(\.teamId), ["B", "A", "C"])
        XCTAssertEqual(standings[0].tieBreakExplanation, "ahead on fewer red cards")

        let yellowTie = [
            TestFixtures.match(id: "ab", giornata: 1, team1: "A", team2: "B", played: true),
            TestFixtures.match(
                id: "ac",
                giornata: 2,
                team1: "A",
                team2: "C",
                played: true,
                events: [
                    TestFixtures.event("gol", teamId: "A"),
                    TestFixtures.event("giallo", teamId: "A")
                ]
            ),
            TestFixtures.match(
                id: "bc",
                giornata: 3,
                team1: "B",
                team2: "C",
                played: true,
                events: [TestFixtures.event("gol", teamId: "B")]
            )
        ]

        standings = StandingsCalculator.calculate(from: yellowTie)
        XCTAssertEqual(standings.map(\.teamId), ["B", "A", "C"])
        XCTAssertEqual(standings[0].tieBreakExplanation, "ahead on fewer yellow cards")
    }

    func testThreeTeamTieUsesMiniTableAndPerfectTieRequiresDraw() {
        let miniTable = [
            TestFixtures.match(
                id: "ab",
                giornata: 1,
                team1: "A",
                team2: "B",
                played: true,
                events: [
                    TestFixtures.event("gol", teamId: "A"),
                    TestFixtures.event("gol", teamId: "A")
                ]
            ),
            TestFixtures.match(
                id: "bc",
                giornata: 2,
                team1: "B",
                team2: "C",
                played: true,
                events: [TestFixtures.event("gol", teamId: "B")]
            ),
            TestFixtures.match(
                id: "ca",
                giornata: 3,
                team1: "C",
                team2: "A",
                played: true,
                events: [TestFixtures.event("gol", teamId: "C")]
            )
        ]

        var standings = StandingsCalculator.calculate(from: miniTable)
        XCTAssertEqual(standings.map(\.teamId), ["A", "C", "B"])
        XCTAssertEqual(standings[0].tieBreakExplanation, "ahead on head-to-head goal difference")

        standings = StandingsCalculator.calculate(from: [
            TestFixtures.match(id: "ab", giornata: 1, team1: "A", team2: "B", played: true)
        ])

        XCTAssertEqual(standings.map(\.teamId), ["A", "B"])
        XCTAssertEqual(standings.map(\.tieBreakExplanation), ["draw required", "draw required"])
    }
}

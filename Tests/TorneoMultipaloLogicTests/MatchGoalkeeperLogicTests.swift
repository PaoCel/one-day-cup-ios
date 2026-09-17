import XCTest
@testable import TorneoMultipaloLogic

final class MatchGoalkeeperLogicTests: XCTestCase {
    func testResolverOrdersRangeTimesChronologicallyForInheritedAssignments() {
        let matches = [
            TestFixtures.match(
                id: "morning",
                giornata: 1,
                matchTime: "09:00 - 09:25",
                team1: "A",
                team2: "B",
                team1Goalkeeper: Match.GoalkeeperSelection(playerId: "gk-a-1", playerName: "Portiere A1"),
                createdAt: Date(timeIntervalSince1970: 200)
            ),
            TestFixtures.match(
                id: "noon",
                giornata: 1,
                matchTime: "11:00 - 11:25",
                team1: "C",
                team2: "A",
                team2Goalkeeper: Match.GoalkeeperSelection(playerId: "gk-a-2", playerName: "Portiere A2"),
                createdAt: Date(timeIntervalSince1970: 100)
            ),
            TestFixtures.match(
                id: "future",
                giornata: 1,
                matchTime: "12:00 - 12:25",
                team1: "A",
                team2: "D",
                createdAt: Date(timeIntervalSince1970: 50)
            )
        ]

        let assignments = MatchGoalkeeperResolver.effectiveAssignments(for: matches)

        XCTAssertEqual(assignments["future"]?.team1PlayerId, "gk-a-2")
    }

    func testResolverInheritsLatestGoalkeeperAssignmentAcrossMatches() {
        let matches = [
            TestFixtures.match(
                id: "m1",
                giornata: 1,
                team1: "A",
                team2: "B",
                team1Goalkeeper: Match.GoalkeeperSelection(playerId: "gk-a-1", playerName: "Portiere A1")
            ),
            TestFixtures.match(
                id: "m2",
                giornata: 2,
                team1: "C",
                team2: "A"
            ),
            TestFixtures.match(
                id: "m3",
                giornata: 3,
                team1: "A",
                team2: "D",
                team1Goalkeeper: Match.GoalkeeperSelection(playerId: "gk-a-2", playerName: "Portiere A2")
            ),
            TestFixtures.match(
                id: "m4",
                giornata: 4,
                team1: "E",
                team2: "A"
            )
        ]

        let assignments = MatchGoalkeeperResolver.effectiveAssignments(for: matches)

        XCTAssertEqual(assignments["m2"]?.team2PlayerId, "gk-a-1")
        XCTAssertEqual(assignments["m4"]?.team2PlayerId, "gk-a-2")
    }

    func testStaffSupportNormalizesSavedSelectionAgainstRoster() {
        let roster = [
            TestFixtures.player(
                id: "doc-keeper",
                name: "Mario Rossi",
                teamId: "A",
                authUID: "auth-keeper",
                number: 1,
                position: "Portiere"
            )
        ]
        let currentMatch = TestFixtures.match(
            id: "m1",
            giornata: 1,
            team1: "A",
            team2: "B",
            team1Goalkeeper: Match.GoalkeeperSelection(playerId: "auth-keeper", playerName: "Nome vecchio")
        )

        let seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: "A",
            in: currentMatch,
            roster: roster,
            allMatches: [currentMatch]
        )

        XCTAssertFalse(seed.isInherited)
        XCTAssertEqual(seed.selection?.playerId, "doc-keeper")
        XCTAssertEqual(seed.selection?.playerName, "Mario Rossi")
    }

    func testStaffSupportInheritsSelectionByNameWhenCurrentMatchIsUnset() {
        let roster = [
            TestFixtures.player(
                id: "doc-keeper",
                name: "Mario Rossi",
                teamId: "A",
                authUID: "auth-keeper",
                number: 1,
                position: "Portiere"
            )
        ]
        let previousMatch = TestFixtures.match(
            id: "m1",
            giornata: 1,
            team1: "A",
            team2: "B",
            team1Goalkeeper: Match.GoalkeeperSelection(playerId: nil, playerName: "Mario Rossi")
        )
        let currentMatch = TestFixtures.match(
            id: "m2",
            giornata: 2,
            team1: "C",
            team2: "A"
        )

        let seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: "A",
            in: currentMatch,
            roster: roster,
            allMatches: [previousMatch, currentMatch]
        )

        XCTAssertTrue(seed.isInherited)
        XCTAssertEqual(seed.selection?.playerId, "doc-keeper")
        XCTAssertEqual(seed.selection?.playerName, "Mario Rossi")
    }

    func testStaffSupportUsesRangeStartTimeWhenResolvingInheritedGoalkeeper() {
        let roster = [
            TestFixtures.player(
                id: "doc-keeper-1",
                name: "Mario Rossi",
                teamId: "A",
                authUID: "auth-keeper-1",
                number: 1,
                position: "Portiere"
            ),
            TestFixtures.player(
                id: "doc-keeper-2",
                name: "Luca Neri",
                teamId: "A",
                authUID: "auth-keeper-2",
                number: 12,
                position: "Portiere"
            )
        ]
        let morningMatch = TestFixtures.match(
            id: "morning",
            giornata: 1,
            matchTime: "09:00 - 09:25",
            team1: "A",
            team2: "B",
            team1Goalkeeper: Match.GoalkeeperSelection(playerId: "doc-keeper-1", playerName: "Mario Rossi"),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let noonMatch = TestFixtures.match(
            id: "noon",
            giornata: 1,
            matchTime: "11:00 - 11:25",
            team1: "C",
            team2: "A",
            team2Goalkeeper: Match.GoalkeeperSelection(playerId: "doc-keeper-2", playerName: "Luca Neri"),
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let currentMatch = TestFixtures.match(
            id: "current",
            giornata: 1,
            matchTime: "12:00 - 12:25",
            team1: "A",
            team2: "D",
            createdAt: Date(timeIntervalSince1970: 50)
        )

        let seed = MatchStaffSupport.seededGoalkeeperSelection(
            for: "A",
            in: currentMatch,
            roster: roster,
            allMatches: [morningMatch, noonMatch, currentMatch]
        )

        XCTAssertTrue(seed.isInherited)
        XCTAssertEqual(seed.selection?.playerId, "doc-keeper-2")
        XCTAssertEqual(seed.selection?.playerName, "Luca Neri")
    }
}

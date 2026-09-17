import XCTest
@testable import TorneoMultipaloLogic

final class GoalkeeperAutoAssignTests: XCTestCase {

    // MARK: - uniqueGoalkeeper

    func testUniqueGoalkeeperReturnsNilForEmptyRoster() {
        XCTAssertNil(MatchStaffSupport.uniqueGoalkeeper(in: []))
    }

    func testUniqueGoalkeeperReturnsNilWhenNoPortiere() {
        let roster = [
            TestFixtures.player(id: "p1", name: "Mario Rossi", ruoloSquadra: "Attaccante"),
            TestFixtures.player(id: "p2", name: "Luigi Bianchi", ruoloSquadra: "Centrocampista"),
        ]
        XCTAssertNil(MatchStaffSupport.uniqueGoalkeeper(in: roster))
    }

    func testUniqueGoalkeeperReturnsSinglePortiere() {
        let roster = [
            TestFixtures.player(id: "p1", name: "Mario Rossi", ruoloSquadra: "Attaccante"),
            TestFixtures.player(id: "gk1", name: "Carlo Verdi", ruoloSquadra: "Portiere"),
        ]
        let result = MatchStaffSupport.uniqueGoalkeeper(in: roster)
        XCTAssertEqual(result?.id, "gk1")
    }

    func testUniqueGoalkeeperReturnsNilForTwoPortieri() {
        let roster = [
            TestFixtures.player(id: "gk1", name: "Carlo Verdi", ruoloSquadra: "Portiere"),
            TestFixtures.player(id: "gk2", name: "Sergio Neri", ruoloSquadra: "portiere"),
        ]
        XCTAssertNil(MatchStaffSupport.uniqueGoalkeeper(in: roster))
    }

    func testUniqueGoalkeeperMatchesCaseInsensitive() {
        let roster = [
            TestFixtures.player(id: "gk1", name: "Carlo Verdi", ruoloSquadra: "PORTIERE"),
        ]
        XCTAssertNotNil(MatchStaffSupport.uniqueGoalkeeper(in: roster))
    }

    func testUniqueGoalkeeperMatchesDiacriticInsensitive() {
        let roster = [
            TestFixtures.player(id: "gk1", name: "Carlo Verdi", ruoloSquadra: "Portièri"),
        ]
        XCTAssertNotNil(MatchStaffSupport.uniqueGoalkeeper(in: roster))
    }

    func testUniqueGoalkeeperIgnoresNilRuoloSquadra() {
        let roster = [
            TestFixtures.player(id: "p1", name: "Mario Rossi", ruoloSquadra: nil),
            TestFixtures.player(id: "gk1", name: "Carlo Verdi", ruoloSquadra: "Portiere"),
        ]
        let result = MatchStaffSupport.uniqueGoalkeeper(in: roster)
        XCTAssertEqual(result?.id, "gk1")
    }

    func testUniqueGoalkeeperReturnsNilForMixedValidAndNilRoles() {
        let roster = [
            TestFixtures.player(id: "gk1", name: "Carlo Verdi", ruoloSquadra: "Portiere"),
            TestFixtures.player(id: "gk2", name: "Antonio Gialli", ruoloSquadra: "Portiere"),
            TestFixtures.player(id: "p1", name: "Mario Rossi", ruoloSquadra: nil),
        ]
        XCTAssertNil(MatchStaffSupport.uniqueGoalkeeper(in: roster))
    }
}

// Extend TestFixtures to support ruoloSquadra
extension TestFixtures {
    static func player(
        id: String,
        name: String,
        ruoloSquadra: String?
    ) -> Player {
        Player(
            id: id,
            nomeCompleto: name,
            ruoloSquadra: ruoloSquadra,
            playerId: id
        )
    }
}

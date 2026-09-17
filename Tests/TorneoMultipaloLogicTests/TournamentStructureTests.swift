import XCTest
@testable import TorneoMultipaloLogic

final class TournamentStructureTests: XCTestCase {
    func testPhaseNormalizationRecognizesAliases() {
        XCTAssertEqual(TournamentPhaseKey.normalize("group_stage"), "girone")
        XCTAssertEqual(TournamentPhaseKey.normalize("preliminary"), "spareggio")
        XCTAssertEqual(TournamentPhaseKey.normalize("semi_final"), "semifinali")
        XCTAssertEqual(TournamentPhaseKey.displayName("quarter_final"), "Quarto di finale")
    }

    func testEdition2026FormatContainsExpectedBracket() {
        let format = TournamentEditionFormat.format(for: 2026, teamCount: 7)

        XCTAssertTrue(format.hasKnockout)
        XCTAssertEqual(format.groupStageMatchCount, 14)
        XCTAssertEqual(format.matchesPerTeam, 4)
        XCTAssertEqual(format.knockoutColumns.count, 7)
        XCTAssertEqual(format.knockoutSlots.count, 7)
        XCTAssertEqual(format.knockoutSlots.first?.phaseKey, "spareggio")
        XCTAssertEqual(format.knockoutSlots.last?.phaseKey, "finale")
    }
}

import XCTest
import FirebaseFirestore
@testable import TorneoMultipaloLogic

final class LegacyDataCompatibilityTests: XCTestCase {
    func testPlayerDecodesLegacyFieldsAndNormalizesSharedSchema() throws {
        let payload: [String: Any] = [
            "nome": "Mario Rossi",
            "numeroMaglia": "10",
            "userId": "uid-player-1",
            "teamId": "",
            "position": "goalkeeper",
            "preferredFoot": "left",
            "fotoUrl": "https://example.com/mario.png",
            "stats": [
                "goals": 2,
                "yellowCards": "3",
                "matches": 5
            ]
        ]

        let player = try Firestore.Decoder().decode(Player.self, from: payload)

        XCTAssertEqual(player.nomeCompleto, "Mario Rossi")
        XCTAssertEqual(player.numeroMaglia, 10)
        XCTAssertEqual(player.identityUid, "uid-player-1")
        XCTAssertTrue(player.isFreeAgent)
        XCTAssertEqual(player.positionPrimary, "Portiere")
        XCTAssertEqual(player.piedeDominante, "Sinistro")
        XCTAssertEqual(player.pictureURL, "https://example.com/mario.png")
        XCTAssertEqual(player.tesseramentoStatus, "libero")
        XCTAssertEqual(player.stats?.gol, 2)
        XCTAssertEqual(player.stats?.ammonizioni, 3)
        XCTAssertEqual(player.stats?.presenze, 5)
    }

    func testTeamDecodesLegacyNameLogoAndRosterCount() throws {
        let payload: [String: Any] = [
            "nome": "Atletico QA",
            "logo": "https://example.com/logo.png",
            "legacyRoster": [
                "giocatori": ["A", "B", "C"]
            ]
        ]

        let team = try Firestore.Decoder().decode(Team.self, from: payload)

        XCTAssertEqual(team.nomeSquadra, "Atletico QA")
        XCTAssertEqual(team.logoSquadra, "https://example.com/logo.png")
        XCTAssertEqual(team.playersCount, 3)
    }

    func testEditionParticipationBuildsSnapshotsFromLegacyArrays() throws {
        let payload: [String: Any] = [
            "squadraId": "team-a",
            "nomeSquadra": "Alpha",
            "edizione": 2026,
            "giocatori": ["Mario Rossi", "Luca Bianchi"],
            "fotoGiocatori": ["https://example.com/mario.png", "https://example.com/luca.png"],
            "numeriMaglia": ["1", "9"],
            "capitani": [true, false],
            "ruoli": ["Portiere", "Attaccante"]
        ]

        let participation = try Firestore.Decoder().decode(EditionParticipation.self, from: payload)
        let snapshots = participation.playerSnapshots

        XCTAssertEqual(participation.safePlayersCount, 2)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].nome, "Mario Rossi")
        XCTAssertEqual(snapshots[0].numero, 1)
        XCTAssertEqual(snapshots[0].ruolo, "Portiere")
        XCTAssertEqual(snapshots[0].pictureURL, "https://example.com/mario.png")
        XCTAssertEqual(snapshots[0].isCapitano, true)
        XCTAssertEqual(snapshots[1].nome, "Luca Bianchi")
        XCTAssertEqual(snapshots[1].numero, 9)
        XCTAssertEqual(snapshots[1].ruolo, "Attaccante")
    }

    func testMatchDecodesLegacyNestedTeamsAndLegacyMvpEvent() throws {
        let payload: [String: Any] = [
            "edizione": 2026,
            "giornata": "3",
            "fase": "group_stage",
            "started": "true",
            "played": true,
            "team1": [
                "teamId": "A",
                "nomeSquadra": "Alpha",
                "logoSquadra": "https://example.com/a.png"
            ],
            "team2": [
                "squadraId": "B",
                "nomeSquadra": "Beta"
            ],
            "team1GoalkeeperId": "keeper-a",
            "eventi": [
                [
                    "type": "goal",
                    "teamId": "A",
                    "playerId": "striker-a",
                    "playerName": "Luca Bianchi"
                ],
                [
                    "type": "autogol",
                    "teamId": "A"
                ],
                [
                    "type": "mvp",
                    "teamId": "A",
                    "playerId": "striker-a",
                    "playerName": "Luca Bianchi"
                ]
            ]
        ]

        let match = try Firestore.Decoder().decode(Match.self, from: payload)

        XCTAssertEqual(match.team1, "A")
        XCTAssertEqual(match.team2, "B")
        XCTAssertEqual(match.team1Meta.name, "Alpha")
        XCTAssertEqual(match.team2Meta.name, "Beta")
        XCTAssertEqual(match.team1Meta.logo, "https://example.com/a.png")
        XCTAssertEqual(match.team1Goalkeeper?.playerId, "keeper-a")
        XCTAssertEqual(match.safeEventi.count, 2)
        XCTAssertEqual(match.team1Goals, 1)
        XCTAssertEqual(match.team2Goals, 1)
        XCTAssertEqual(match.mvp?.playerId, "striker-a")
        XCTAssertEqual(match.mvp?.team, 1)
        XCTAssertTrue(match.isStarted)
        XCTAssertTrue(match.isPlayed)
    }
}

import Foundation
import FirebaseFirestore
@testable import TorneoMultipaloLogic

enum TestFixtures {
    static func team(id: String, name: String, primary: String = "#0044cc") -> Team {
        Team(
            id: id,
            nomeSquadra: name,
            email: "\(id.lowercased())@qa.local",
            ownerUid: "owner-\(id)",
            rappresentante: Team.Rappresentante(nome: "QA \(name)", telefono: "0000000000"),
            colori: Team.TeamColors(principale: primary, secondario: "#ffffff"),
            primaEdizione: 2026,
            ultimeEdizioni: [2026],
            playersCount: 0
        )
    }

    static func editionTeam(id: String, name: String) -> EditionTeam {
        EditionTeam(
            edition: 2026,
            team: team(id: id, name: name),
            participation: nil,
            fallbackParticipation: nil,
            preferLiveTeamData: true
        )
    }

    static func player(
        id: String,
        name: String,
        teamId: String? = nil,
        authUID: String? = nil,
        number: Int? = nil,
        position: String? = nil
    ) -> Player {
        Player(
            id: id,
            nomeCompleto: name,
            numeroMaglia: number,
            teamId: teamId,
            playerAuthUid: authUID,
            positionPrimary: position,
            playerId: id
        )
    }

    static func event(
        _ type: String,
        teamId: String,
        playerId: String? = nil,
        playerName: String? = nil
    ) -> MatchEvent {
        MatchEvent(
            tipo: type,
            giocatoreId: playerId,
            giocatoreNome: playerName,
            squadraId: teamId
        )
    }

    static func match(
        id: String,
        edition: Int = 2026,
        giornata: Int,
        phase: String = "girone",
        matchTime: String = "09:00",
        team1: String,
        team2: String,
        team1Name: String? = nil,
        team2Name: String? = nil,
        started: Bool = true,
        played: Bool = false,
        events: [MatchEvent] = [],
        team1Goalkeeper: Match.GoalkeeperSelection? = nil,
        team2Goalkeeper: Match.GoalkeeperSelection? = nil,
        mvp: Match.MatchMvp? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> Match {
        Match(
            id: id,
            edizione: edition,
            giornata: giornata,
            fase: phase,
            idFase: phase,
            campo: "A",
            matchTime: matchTime,
            team1: team1,
            team2: team2,
            team1Meta: Match.TeamMeta(id: team1, name: team1Name ?? team1, logo: nil),
            team2Meta: Match.TeamMeta(id: team2, name: team2Name ?? team2, logo: nil),
            started: started,
            played: played,
            eventi: events,
            team1GoalkeeperPlayerId: team1Goalkeeper?.playerId,
            team1GoalkeeperPlayerName: team1Goalkeeper?.playerName,
            team2GoalkeeperPlayerId: team2Goalkeeper?.playerId,
            team2GoalkeeperPlayerName: team2Goalkeeper?.playerName,
            mvp: mvp,
            createdAt: Timestamp(date: createdAt)
        )
    }
}

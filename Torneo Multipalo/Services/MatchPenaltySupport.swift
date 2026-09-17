import Foundation

extension Match {
    func penaltyMiss(outcome: PenaltyMiss.Outcome, kickingTeamId: String?, players: [Player]) -> PenaltyMiss {
        func assignedKeeper(teamId: String) -> PenaltyMiss.Goalkeeper? {
            guard let selection = goalkeeper(for: teamId), let id = selection.playerId else { return nil }
            let player = players.first { $0.firestoreIdentifier == id || $0.playerAuthUid == id }
            return PenaltyMiss.Goalkeeper(
                playerId: id, playerName: player?.nomeCompleto ?? selection.playerName, entryId: teamId
            )
        }
        return PenaltyMiss.resolve(
            outcome: outcome, kickingEntryId: kickingTeamId, home: team1, away: team2,
            homeGoalkeeper: assignedKeeper(teamId: team1), awayGoalkeeper: assignedKeeper(teamId: team2)
        )
    }
}

extension MatchEvent {
    // La riga è derivata dal tiro: cancellarlo o annullarlo elimina anche la
    // parata. Non aggiungiamo un secondo evento Firestore che possa restare orfano.
    var penaltySaveEvent: MatchEvent? {
        guard tipo == "rigore_sbagliato",
              let keeper = penaltyMiss?.savedGoalkeeper(against: squadraId) else { return nil }
        return MatchEvent(
            id: "\(id):save", tipo: "rigore_parato", giocatoreId: keeper.playerId,
            giocatoreNome: keeper.playerName ?? "Portiere", squadraId: keeper.entryId, minuto: minuto
        )
    }
}

extension Match.PenaltyKick {
    var penaltySaveEvent: MatchEvent? {
        guard !scored, let keeper = penaltyMiss?.savedGoalkeeper(against: teamId) else { return nil }
        return MatchEvent(
            id: "\(id):save", tipo: "rigore_parato", giocatoreId: keeper.playerId,
            giocatoreNome: keeper.playerName ?? "Portiere", squadraId: keeper.entryId
        )
    }
}

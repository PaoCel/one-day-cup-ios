import Foundation
import FirebaseFunctions

// MARK: - Safe callable wrapper (avoids async let crash in Firebase SDK)

private extension HTTPSCallable {
    func safeCall(_ data: Any? = nil) async throws -> HTTPSCallableResult {
        try await withCheckedThrowingContinuation { continuation in
            self.call(data) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "CloudFunctionsService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No result or error from callable"]
                    ))
                }
            }
        }
    }
}

class CloudFunctionsService {
    private var functions: Functions { Functions.functions() }

    /// Torneo corrente, mirrorato da `AppState` (come `FirestoreService.currentTournamentId`).
    /// Allineato alla PWA: le callable tournament-aware ricevono `tournamentId`
    /// dal client; le functions usano `tidOrDefault` (fallback "multipalo").
    var currentTournamentId: String = "multipalo"

    func generateSchedule(edition: Int, perTeamMatches: Int = 4, matchDuration: Int = 20,
                           bufferMinutes: Int = 5, startTime: String = "09:00",
                           fieldsCount: Int = 2) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("generare un calendario di test")
        let fields = (0..<fieldsCount).map { String(UnicodeScalar(65 + $0)!) }
        _ = try await functions.httpsCallable("adminGenerateTestSchedule").safeCall([
            "edition": edition,
            "perTeamMatches": perTeamMatches,
            "matchDuration": matchDuration,
            "bufferMinutes": bufferMinutes,
            "startTime": startTime,
            "fields": fields,
            "clearExistingTest": true
        ] as [String: Any])
    }

    func sendPlayerRequest(playerId: String) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("inviare richieste giocatore")
        _ = try await functions.httpsCallable("sendPlayerRequest").safeCall([
            "playerId": playerId,
            "tournamentId": currentTournamentId
        ] as [String: Any])
    }

    func respondPlayerRequest(requestId: String, accept: Bool) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("rispondere a richieste giocatore")
        _ = try await functions.httpsCallable("respondPlayerRequest").safeCall([
            "requestId": requestId,
            "action": accept ? "accept" : "reject"
        ] as [String: Any])
    }

    func adminUpdatePlayer(playerId: String, data: [String: Any]) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("aggiornare dati giocatore via Cloud Functions")
        var params: [String: Any] = ["playerId": playerId]
        params.merge(data) { _, new in new }
        _ = try await functions.httpsCallable("adminUpdatePlayer").safeCall(params)
    }

    func adminAssignPlayerToTeam(playerId: String, teamId: String) async throws {
        try await adminUpdatePlayer(
            playerId: playerId,
            data: [
                "teamId": teamId,
                "tesseramentoStatus": "tesserato"
            ]
        )
    }

    func adminRemovePlayerFromTeam(playerId: String) async throws {
        try await adminUpdatePlayer(
            playerId: playerId,
            data: [
                "teamId": "",
                "tesseramentoStatus": "libero"
            ]
        )
    }

    func registerFcmToken(token: String, installationId: String? = nil) async throws {
        guard !RuntimeSafety.shared.protectsRealData else { return }
        var payload: [String: Any] = [
            "token": token,
            "platform": "ios"
        ]

        if let installationId, !installationId.isEmpty {
            payload["installationId"] = installationId
        }

        _ = try await functions.httpsCallable("registerFcmToken").safeCall(payload)
    }

    func registerFcmTokenPublic(token: String, installationId: String? = nil) async throws {
        guard !RuntimeSafety.shared.protectsRealData else { return }
        var payload: [String: Any] = [
            "token": token,
            "platform": "ios"
        ]

        if let installationId, !installationId.isEmpty {
            payload["installationId"] = installationId
        }

        _ = try await functions.httpsCallable("registerFcmTokenPublic").safeCall(payload)
    }

    func syncNotificationPreferences(
        installationId: String,
        subscribedEditionIds: [Int],
        subscribedMatchIds: [String],
        mutedMatchIds: [String],
        subscribedTeamIds: [String],
        mutedTeamIds: [String],
        subscribedPlayerIds: [String],
        mutedPlayerIds: [String]
    ) async throws {
        guard !RuntimeSafety.shared.protectsRealData else { return }
        _ = try await functions.httpsCallable("syncNotificationPreferences").safeCall([
            "installationId": installationId,
            "platform": "ios",
            "subscribedEditionIds": subscribedEditionIds,
            "subscribedMatchIds": subscribedMatchIds,
            "mutedMatchIds": mutedMatchIds,
            "subscribedTeamIds": subscribedTeamIds,
            "mutedTeamIds": mutedTeamIds,
            "subscribedPlayerIds": subscribedPlayerIds,
            "mutedPlayerIds": mutedPlayerIds
        ])
    }

    func submitPrediction(questionId: String, selectionId: String) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("inviare pronostici")
        _ = try await functions.httpsCallable("submitPrediction").safeCall([
            "questionId": questionId,
            "selectionId": selectionId
        ])
    }

    func adminSyncPredictionQuestions(edition: Int) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("sincronizzare le domande pronostici")
        _ = try await functions.httpsCallable("adminSyncPredictionQuestions").safeCall([
            "edition": edition
        ])
    }

    func ensurePredictionQuestions(edition: Int) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("creare domande pronostici mancanti")
        _ = try await functions.httpsCallable("ensurePredictionQuestions").safeCall([
            "edition": edition
        ])
    }

    func setMatchGoalkeeperSelection(
        matchId: String,
        teamSlot: MatchTeamSlot,
        playerId: String?
    ) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("salvare il portiere della partita")
        var payload: [String: Any] = [
            "matchId": matchId,
            "teamSlot": teamSlot.rawValue
        ]

        if let playerId, !playerId.isEmpty {
            payload["playerId"] = playerId
        }

        _ = try await functions.httpsCallable("setMatchGoalkeeperSelection").safeCall(payload)
    }

    func sendTestNotification(uid: String?, broadcast: Bool, title: String, body: String) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("inviare notifiche di test")
        var params: [String: Any] = [
            "broadcast": broadcast,
            "title": title,
            "body": body
        ]
        if let uid { params["uid"] = uid }
        _ = try await functions.httpsCallable("adminSendTestNotification").safeCall(params)
    }

    func sendTeamFieldCall(teamId: String) async throws {
        try RuntimeSafety.shared.assertAllowsMutation("notificare squadra per campo")
        _ = try await functions.httpsCallable("adminSendTeamFieldCall").safeCall([
            "teamId": teamId
        ] as [String: Any])
    }

    func checkIsAdmin() async throws -> Bool {
        let result = try await functions.httpsCallable("isAdmin").safeCall()
        return (result.data as? [String: Any])?["isAdmin"] as? Bool ?? false
    }

    @discardableResult
    func deleteCurrentAccount() async throws -> [String: Any] {
        try RuntimeSafety.shared.assertAllowsMutation("eliminare account e collegamenti dati")
        let result = try await functions.httpsCallable("deleteUserAccount").safeCall()
        return result.data as? [String: Any] ?? [:]
    }

    @discardableResult
    func adminSimulateTournament(edition: Int = 2026, matchDurationMs: Int = 40000, delayBetweenMatchesMs: Int = 3000) async throws -> [String: Any] {
        try RuntimeSafety.shared.assertAllowsMutation("simulare torneo")
        let result = try await functions.httpsCallable("adminSimulateTournament").safeCall([
            "edition": edition,
            "matchDurationMs": matchDurationMs,
            "delayBetweenMatchesMs": delayBetweenMatchesMs
        ] as [String: Any])
        return result.data as? [String: Any] ?? [:]
    }
}

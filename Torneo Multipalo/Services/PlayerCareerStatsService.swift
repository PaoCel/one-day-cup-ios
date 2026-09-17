import Foundation
import FirebaseFirestore
import FirebaseFunctions

/// Phase 4b — accesso (read-only) ai dati cross-torneo aggregati nella collection
/// `playerCareerStats/{playerId}`. Le scritture avvengono solo dalle Cloud
/// Functions deployate in Phase 4a (`onMatchPlayedUpdateCareerStats` trigger,
/// `recomputeAllCareerStats` callable per super-admin).
final class PlayerCareerStatsService {

    private var db: Firestore { Firestore.firestore() }
    private var functions: Functions { Functions.functions() }

    /// Carica il documento aggregato per un singolo giocatore.
    /// - Returns: nil se il documento non esiste (empty state UI).
    func fetchCareerStats(playerId: String) async throws -> PlayerCareerStats? {
        let trimmed = playerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let snapshot = try await db.collection("playerCareerStats").document(trimmed).getDocument()
        guard snapshot.exists else { return nil }
        // Decoding tollerante: se lo schema cambia, evitiamo crash.
        return try? snapshot.decodedData(as: PlayerCareerStats.self)
    }

    /// Tutte le carriere di un torneo, per la classifica giocatori del Ranking.
    ///
    /// La collection è piccola (~150 doc) e si legge in un colpo: filtrare
    /// lato server vorrebbe un campo indicizzato per torneo, che l'aggregato
    /// non ha (le chiavi stanno dentro `byTournament`).
    func fetchAllCareerStats(tournamentId: String) async throws -> [(stats: PlayerCareerStats, tournament: PlayerTournamentStats)] {
        let snapshot = try await db.collection("playerCareerStats").getDocuments()
        return snapshot.documents.compactMap { doc in
            guard let stats = try? doc.decodedData(as: PlayerCareerStats.self) else { return nil }
            guard let bucket = stats.byTournament[tournamentId] else { return nil }
            guard bucket.matches > 0 || bucket.goals > 0 else { return nil }
            return (stats, bucket)
        }
    }

    /// Wrapper della callable `recomputeAllCareerStats` (super-admin only,
    /// enforcement lato Cloud Function).
    @discardableResult
    func recomputeAll() async throws -> RecomputeCareerStatsSummary {
        try RuntimeSafety.shared.assertAllowsMutation("ricalcolare statistiche carriera")
        let result = try await functions.httpsCallable("recomputeAllCareerStats").safeCallVoid()
        let raw = (result.data as? [String: Any]) ?? [:]
        return RecomputeCareerStatsSummary(raw: raw)
    }
}

// MARK: - Local helper to mirror the safe call pattern used in CloudFunctionsService

private extension HTTPSCallable {
    func safeCallVoid() async throws -> HTTPSCallableResult {
        try await withCheckedThrowingContinuation { continuation in
            self.call { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "PlayerCareerStatsService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "No result or error from callable"]
                    ))
                }
            }
        }
    }
}

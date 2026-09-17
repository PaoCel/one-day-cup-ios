import Foundation
import FirebaseFirestore

@MainActor
class TournamentSimulator {
    let db = Firestore.firestore()
    var onProgress: ((String) -> Void)?

    struct SimulationConfig {
        var edition: Int = 2026
        var matchDurationSeconds: Double = 40
        var delayBetweenRoundsSeconds: Double = 3
        var eventsPerMatch: Int = 5
    }

    func simulate(config: SimulationConfig = .init()) async throws -> Int {
        // Load unplayed group matches
        let snapshot = try await db.collection("partite")
            .whereField("tournamentId", isEqualTo: "multipalo")
            .whereField("edizione", isEqualTo: config.edition)
            .getDocuments()

        let groupMatches = snapshot.documents.filter { doc in
            let data = doc.data()
            let fase = (data["fase"] as? String ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let isGroup = fase.isEmpty || fase == "girone" || fase == "group" || fase == "group_stage"
            let isPlayed = data["played"] as? Bool ?? false
            return isGroup && !isPlayed
        }.sorted { a, b in
            let aG = a.data()["giornata"] as? Int ?? 0
            let bG = b.data()["giornata"] as? Int ?? 0
            if aG != bG { return aG < bG }
            let aT = a.data()["matchTime"] as? String ?? ""
            let bT = b.data()["matchTime"] as? String ?? ""
            return aT < bT
        }

        guard !groupMatches.isEmpty else {
            onProgress?("Tutte le partite sono già giocate")
            return 0
        }

        // Load players per team
        let playerSnapshot = try await db.collection("giocatori").getDocuments()
        var playersByTeam: [String: [(id: String, nome: String)]] = [:]
        for doc in playerSnapshot.documents {
            let data = doc.data()
            let teamId = (data["teamId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !teamId.isEmpty else { continue }
            let nome = data["nomeCompleto"] as? String ?? data["nome"] as? String ?? "Giocatore"
            playersByTeam[teamId, default: []].append((id: doc.documentID, nome: nome))
        }

        // Group matches by giornata
        var rounds: [Int: [QueryDocumentSnapshot]] = [:]
        for doc in groupMatches {
            let g = doc.data()["giornata"] as? Int ?? 0
            rounds[g, default: []].append(doc)
        }

        var roundsPlayed = 0
        let sortedRounds = rounds.keys.sorted()
        let eventInterval = config.matchDurationSeconds / Double(config.eventsPerMatch)

        for giornata in sortedRounds {
            let roundDocs = rounds[giornata]!
            onProgress?("Giornata \(giornata): \(roundDocs.count) partite...")

            // Start all matches
            let startBatch = db.batch()
            for doc in roundDocs {
                startBatch.updateData([
                    "started": true,
                    "played": false,
                    "eventi": [] as [Any],
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: doc.reference)
            }
            try await startBatch.commit()

            // Simulate events over time
            for tick in 0..<config.eventsPerMatch {
                try await Task.sleep(nanoseconds: UInt64(eventInterval * 1_000_000_000))

                let eventBatch = db.batch()
                for doc in roundDocs {
                    let data = doc.data()
                    let team1 = (data["team1"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let team2 = (data["team2"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let t1Players = playersByTeam[team1] ?? []
                    let t2Players = playersByTeam[team2] ?? []

                    let event = generateEvent(
                        team1: team1, team2: team2,
                        t1Players: t1Players, t2Players: t2Players,
                        tick: tick, totalTicks: config.eventsPerMatch
                    )

                    eventBatch.updateData([
                        "eventi": FieldValue.arrayUnion([event]),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: doc.reference)
                }
                try await eventBatch.commit()
            }

            // Finish all matches
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let endBatch = db.batch()
            for doc in roundDocs {
                endBatch.updateData([
                    "played": true,
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: doc.reference)
            }
            try await endBatch.commit()

            roundsPlayed += 1
            onProgress?("Giornata \(giornata) completata")

            // Delay between rounds
            if giornata != sortedRounds.last {
                try await Task.sleep(nanoseconds: UInt64(config.delayBetweenRoundsSeconds * 1_000_000_000))
            }
        }

        onProgress?("Simulazione completata: \(roundsPlayed) giornate")
        return roundsPlayed
    }

    private func generateEvent(
        team1: String, team2: String,
        t1Players: [(id: String, nome: String)],
        t2Players: [(id: String, nome: String)],
        tick: Int, totalTicks: Int
    ) -> [String: Any] {
        let eventTypes = ["gol", "gol", "gol", "gol", "ammonizione", "ammonizione", "punizione_segnata"]
        let tipo = eventTypes.randomElement()!

        // Teams with players score more
        let t1Weight = t1Players.isEmpty ? 1 : 3
        let t2Weight = t2Players.isEmpty ? 1 : 3
        let scoringTeamId = Int.random(in: 0..<(t1Weight + t2Weight)) < t1Weight ? team1 : team2
        let scoringPlayers = scoringTeamId == team1 ? t1Players : t2Players

        let minuto = min(1 + tick * (20 / max(totalTicks, 1)) + Int.random(in: 0...3), 20)

        var event: [String: Any] = [
            "id": UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(20).description,
            "tipo": tipo,
            "squadraId": scoringTeamId,
            "minuto": minuto
        ]

        if let player = scoringPlayers.randomElement() {
            event["giocatoreId"] = player.id
            event["giocatoreNome"] = player.nome

            // Add assist for goals
            if (tipo == "gol" || tipo == "punizione_segnata") && scoringPlayers.count > 1 {
                let assistCandidates = scoringPlayers.filter { $0.id != player.id }
                if let assister = assistCandidates.randomElement() {
                    event["assistPlayerId"] = assister.id
                    event["assistName"] = assister.nome
                }
            }
        } else {
            event["giocatoreNome"] = "Giocatore"
        }

        return event
    }
}

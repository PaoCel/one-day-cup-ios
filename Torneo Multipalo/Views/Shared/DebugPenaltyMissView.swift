#if DEBUG
import SwiftUI
import FirebaseFirestore

struct DebugPenaltyMissView: View {
    @State private var showPrompt = false
    @State private var selectedOutcome: PenaltyMiss.Outcome?

    private func shot(_ outcome: PenaltyMiss.Outcome, withKeeper: Bool = true) -> MatchEvent {
        let match = Match(edizione: 1, giornata: 1, fase: "girone", team1: "home", team2: "away",
                          team1Meta: .init(name: "Casa"), team2Meta: .init(name: "Ospiti"),
                          team2GoalkeeperPlayerId: withKeeper ? "keeper" : nil,
                          team2GoalkeeperPlayerName: withKeeper ? "Luca Neri" : nil)
        return MatchEvent(tipo: "rigore_sbagliato", giocatoreNome: "Marco Rossi", squadraId: "home", minuto: 12,
                          penaltyMiss: match.penaltyMiss(outcome: outcome, kickingTeamId: "home", players: []))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("RIGORI · VERSIONE 2").font(.caption.bold()).foregroundStyle(TournamentPalette.accent)
                    Text("Sbagliato o parato?").font(.largeTitle.bold()).foregroundStyle(TournamentPalette.ink)
                    Text("Verifica locale · nessuna partita modificata").font(.caption).foregroundStyle(TournamentPalette.inkMuted)
                    scenario("PARATO · PORTIERE ASSEGNATO", event: shot(.saved))
                    scenario("TIRATO FUORI", event: shot(.offTarget))
                    scenario("PARATO · NESSUN PORTIERE ASSEGNATO", event: shot(.saved, withKeeper: false))
                    Button {
                        showPrompt = true
                    } label: {
                        Label("Registra rigore sbagliato", image: MatchEventSymbol.penaltyMissed.rawValue)
                            .tournamentButtonChrome(.primary)
                    }
                    .buttonStyle(.tournamentPress)
                    if let selectedOutcome {
                        Text(selectedOutcome == .saved ? "Scelta: parato" : "Scelta: tirato fuori")
                    }
                }.padding(16)
            }
            .background(TournamentPalette.backgroundTop)
            .penaltyMissConfirmation(isPresented: $showPrompt) { selectedOutcome = $0 }
            .task {
                assert(shot(.saved).penaltySaveEvent?.squadraId == "away")
                assert(shot(.offTarget).penaltySaveEvent == nil)
                assert(shot(.saved, withKeeper: false).penaltySaveEvent == nil)
                verifyProjection()
                if ProcessInfo.processInfo.arguments.contains("--odc-penalty-dialog") { showPrompt = true }
            }
        }
    }

    private func scenario(_ title: String, event: MatchEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.caption2.bold()).foregroundStyle(TournamentPalette.inkMuted)
            MatchEventRow(event: event, isTeam1: true)
            if let save = event.penaltySaveEvent {
                MatchEventRow(event: save, isTeam1: false)
            }
        }.tournamentCard()
    }

    private func verifyProjection() {
        let saved = shot(.saved)
        let event = V2Projection.eventToV2(saved, id: "test-shot")
        let document: [String: Any] = [
            "home": "home", "away": "away", "status": "finished", "events": [event],
            "shootout": ["home": 0, "away": 0, "details": [[
                "entryId": "home", "order": 1, "scored": false,
                "penaltyMiss": saved.penaltyMiss!.dictionary
            ]]]
        ]
        let legacy = V2Projection.matchToLegacy(document, id: "demo_1-1", tournamentId: "demo", edizione: 1, entries: [:])
        guard let match = try? Firestore.Decoder().decode(Match.self, from: legacy) else {
            assertionFailure("Il modello non legge la proiezione del rigore"); return
        }
        assert(match.safeEventi.first?.penaltySaveEvent?.giocatoreId == "keeper")
        assert(match.safePenaltyDetails.first?.penaltySaveEvent?.giocatoreId == "keeper")
        assert(match.team1Goals == 0 && match.team2Goals == 0)
        print("ODC_PENALTY_CHECKS_OK: proiezione v2, parata, fuori, portiere assente e punteggio")
    }
}
#endif

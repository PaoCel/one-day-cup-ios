import SwiftUI

struct TeamMatchGoalkeeperEditorView: View {
    let match: Match
    let managedTeamId: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var currentMatch: Match
    @State private var teamPlayers: [Player] = []
    @State private var selectedGoalkeeperId = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    init(match: Match, managedTeamId: String) {
        self.match = match
        self.managedTeamId = managedTeamId
        _currentMatch = State(initialValue: match)
    }

    private var teamId: String {
        managedTeamId
    }

    private var teamSlot: MatchTeamSlot? {
        MatchGoalkeeperSupport.slot(for: managedTeamId, in: currentMatch)
    }

    private var resolvedTeams: (team1: AppState.ResolvedTeamInfo, team2: AppState.ResolvedTeamInfo) {
        appState.resolvedTeams(for: currentMatch)
    }

    private var teamName: String {
        switch teamSlot {
        case .team1:
            return resolvedTeams.team1.name
        case .team2:
            return resolvedTeams.team2.name
        case nil:
            return "Squadra"
        }
    }

    private var suggestedGoalkeeperId: String? {
        MatchGoalkeeperSupport.suggestedGoalkeeperId(
            for: teamId,
            currentMatch: currentMatch,
            matches: appState.allMatches
        )
    }

    private var currentExplicitGoalkeeperId: String? {
        guard let teamSlot else { return nil }
        return MatchGoalkeeperSupport.explicitGoalkeeperId(for: teamSlot, in: currentMatch)
    }

    private var selectedGoalkeeperName: String {
        goalkeeperName(for: selectedGoalkeeperId) ?? "Nessun portiere"
    }

    private var selectablePlayers: [Player] {
        teamPlayers.filter { player in
            player.firestoreIdentifier != nil && !isPlayerSuspended(player)
        }
    }

    var body: some View {
        Form {
            Section("Partita") {
                TournamentInfoRow(icon: "flag.fill", label: "Match", value: "\(resolvedTeams.team1.name) vs \(resolvedTeams.team2.name)")
                TournamentInfoRow(icon: "calendar", label: "Fase", value: faseLabel)
                if let time = currentMatch.matchTime, !time.isEmpty {
                    TournamentInfoRow(icon: "clock.fill", label: "Orario", value: time)
                }
            }

            if teamSlot == nil {
                Section {
                    Text("Questa partita non appartiene alla tua squadra.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if isLoading {
                Section {
                    LoadingView(message: "Carico la rosa...")
                }
            } else {
                Section("Portiere \(teamName)") {
                    if selectablePlayers.isEmpty {
                        Text(teamPlayers.isEmpty ? "Rosa non disponibile" : "Nessun giocatore disponibile: i giocatori selezionabili risultano squalificati per questa partita.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Giocatore", selection: $selectedGoalkeeperId) {
                            Text("Nessun portiere").tag("")
                            ForEach(selectablePlayers, id: \.stableRosterKey) { player in
                                Text(player.nomeCompleto).tag(player.firestoreIdentifier ?? "")
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }

                    if let explicitId = currentExplicitGoalkeeperId,
                       let explicitName = goalkeeperName(for: explicitId) {
                        TournamentInfoRow(icon: "person.fill.checkmark", label: "Salvato ora", value: explicitName)
                    } else if let suggestedId = suggestedGoalkeeperId,
                              let suggestedName = goalkeeperName(for: suggestedId) {
                        TournamentInfoRow(icon: "arrowshape.turn.up.right.fill", label: "Suggerito", value: suggestedName)
                    }
                }

                Section {
                    Button {
                        Task { await saveSelection() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text(isSaving ? "Salvataggio..." : "Salva portiere")
                        }
                    }
                    .disabled(isSaving || teamSlot == nil)
                }
            }
        }
        .navigationTitle("Portiere partita")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPlayers()
        }
        .alert("Errore", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Portiere aggiornato", isPresented: Binding(
            get: { successMessage != nil },
            set: {
                if !$0 {
                    successMessage = nil
                    dismiss()
                }
            }
        )) {
            Button("OK") {
                successMessage = nil
                dismiss()
            }
        } message: {
            Text(successMessage ?? selectedGoalkeeperName)
        }
    }

    private var faseLabel: String {
        if TournamentPhaseKey.isGroupStage(currentMatch.fase) {
            return "Giornata \(currentMatch.giornata)"
        }
        return TournamentPhaseKey.displayName(currentMatch.fase)
    }

    private func loadPlayers() async {
        guard teamSlot != nil else {
            isLoading = false
            return
        }

        do {
            let players = try await appState.firestoreService.fetchPlayers(teamId: teamId)
            teamPlayers = players.sorted {
                let lhsNumber = $0.numeroMaglia ?? 99
                let rhsNumber = $1.numeroMaglia ?? 99
                if lhsNumber == rhsNumber {
                    return $0.nomeCompleto.localizedCaseInsensitiveCompare($1.nomeCompleto) == .orderedAscending
                }
                return lhsNumber < rhsNumber
            }

            if let explicitId = currentExplicitGoalkeeperId,
               selectablePlayers.contains(where: { $0.firestoreIdentifier == explicitId }) {
                selectedGoalkeeperId = explicitId
            } else if let suggestedId = suggestedGoalkeeperId,
                      selectablePlayers.contains(where: { $0.firestoreIdentifier == suggestedId }) {
                selectedGoalkeeperId = suggestedId
            } else {
                selectedGoalkeeperId = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func saveSelection() async {
        guard let teamSlot, let matchId = currentMatch.id else { return }
        if let player = teamPlayers.first(where: { $0.firestoreIdentifier == selectedGoalkeeperId }),
           isPlayerSuspended(player) {
            errorMessage = "Giocatore squalificato per questa partita."
            return
        }
        isSaving = true
        defer { isSaving = false }

        do {
            try await appState.cloudFunctionsService.setMatchGoalkeeperSelection(
                matchId: matchId,
                teamSlot: teamSlot,
                playerId: selectedGoalkeeperId.isEmpty ? nil : selectedGoalkeeperId
            )

            switch teamSlot {
            case .team1:
                currentMatch.team1GoalkeeperPlayerId = selectedGoalkeeperId.isEmpty ? nil : selectedGoalkeeperId
                currentMatch.team1GoalkeeperPlayerName = selectedGoalkeeperId.isEmpty ? nil : goalkeeperName(for: selectedGoalkeeperId)
            case .team2:
                currentMatch.team2GoalkeeperPlayerId = selectedGoalkeeperId.isEmpty ? nil : selectedGoalkeeperId
                currentMatch.team2GoalkeeperPlayerName = selectedGoalkeeperId.isEmpty ? nil : goalkeeperName(for: selectedGoalkeeperId)
            }

            successMessage = selectedGoalkeeperId.isEmpty
                ? "Portiere rimosso dalla partita."
                : "Portiere salvato per questa partita."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goalkeeperName(for playerId: String?) -> String? {
        guard let playerId, !playerId.isEmpty else { return nil }
        return teamPlayers.first {
            ($0.firestoreIdentifier == playerId) || ($0.playerAuthUid == playerId)
        }?.nomeCompleto
    }

    private func isPlayerSuspended(_ player: Player) -> Bool {
        MatchSuspensionSupport.isPlayerSuspended(
            playerId: player.firestoreIdentifier ?? player.playerAuthUid,
            playerName: player.nomeCompleto,
            teamId: teamId,
            in: currentMatch,
            within: appState.allMatches
        )
    }
}

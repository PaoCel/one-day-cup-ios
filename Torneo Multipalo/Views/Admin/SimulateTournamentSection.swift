import SwiftUI

struct SimulateTournamentSection: View {
    @Environment(AppState.self) private var appState
    @State private var isSimulating = false
    @State private var progressMessage: String?
    @State private var showConfirm = false

    var body: some View {
        TournamentFormSection(
            title: "Simulazione torneo",
            subtitle: "Simula tutte le partite del girone con eventi realistici (~40s ciascuna)",
            icon: "play.rectangle"
        ) {
            if isSimulating {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(TournamentPalette.accent)
                    if let progressMessage {
                        Text(progressMessage)
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else {
                Button {
                    showConfirm = true
                } label: {
                    Label("Simula fase a gironi", systemImage: "sportscourt")
                        .tournamentButtonChrome(.primary)
                }
                .buttonStyle(.tournamentPress)
            }

            if !isSimulating, let progressMessage, progressMessage.contains("completata") {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TournamentPalette.success)
                    Text(progressMessage)
                        .font(.caption)
                        .foregroundStyle(TournamentPalette.success)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .alert("Simulazione torneo", isPresented: $showConfirm) {
            Button("Annulla", role: .cancel) {}
            Button("Simula") { startSimulation() }
        } message: {
            Text("Verranno simulate tutte le partite non giocate della fase a gironi con gol, cartellini e assist casuali. Ogni partita dura circa 40 secondi.")
        }
    }

    private func startSimulation() {
        isSimulating = true
        progressMessage = "Preparazione..."
        Task {
            let simulator = TournamentSimulator()
            simulator.onProgress = { message in
                Task { @MainActor in
                    progressMessage = message
                }
            }
            do {
                let rounds = try await simulator.simulate(
                    config: .init(edition: appState.activeEdition)
                )
                progressMessage = "Simulazione completata: \(rounds) giornate giocate"
            } catch {
                progressMessage = "Errore: \(error.localizedDescription)"
            }
            isSimulating = false
        }
    }
}

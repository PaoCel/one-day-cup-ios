import SwiftUI

// MARK: - ViewModel

@Observable
@MainActor
final class QuickRosterViewModel {
    struct PlayerRow: Identifiable {
        let id = UUID()
        var name: String = ""
        var number: String = ""
        var isSaving = false
        var isSaved = false
        var errorMessage: String?
    }

    var rows: [PlayerRow] = []
    var isBatchSaving = false
    var savedCount = 0
    var errorMessage: String?
    var existingPlayers: [Player] = []

    func initialize(initialCount: Int = 5) {
        rows = (0..<initialCount).map { _ in PlayerRow() }
    }

    func addRow() {
        rows.append(PlayerRow())
    }

    func removeRow(at index: Int) {
        guard index < rows.count, rows.count > 1 else { return }
        rows.remove(at: index)
    }

    var filledRows: [PlayerRow] {
        rows.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func loadExistingPlayers(appState: AppState) async {
        do {
            existingPlayers = try await appState.firestoreService.fetchAllPlayers()
        } catch {
            // Non-blocking
        }
    }

    func findExistingPlayer(name: String) -> Player? {
        let normalized = normalizedName(name)
        guard normalized.count >= 3 else { return nil }
        return existingPlayers.first { normalizedName($0.nomeCompleto) == normalized }
    }

    func saveAll(teamId: String, appState: AppState) async {
        isBatchSaving = true
        savedCount = 0

        for i in rows.indices {
            let trimmedName = rows[i].name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, !rows[i].isSaved else { continue }

            rows[i].isSaving = true

            do {
                // Check for existing player
                if let existing = findExistingPlayer(name: trimmedName),
                   let existingId = existing.id {
                    if existing.isFreeAgent {
                        // Reuse free agent
                        if appState.authService.userRole == .admin {
                            try await appState.cloudFunctionsService.adminAssignPlayerToTeam(
                                playerId: existingId, teamId: teamId
                            )
                        }
                    }
                    // If already in another team, skip (would need transfer request)
                } else {
                    let numero = Int(rows[i].number.trimmingCharacters(in: .whitespacesAndNewlines))
                    _ = try await appState.firestoreService.addManagedPlayer(
                        nomeCompleto: trimmedName,
                        teamId: teamId,
                        numeroMaglia: numero,
                        positionPrimary: nil,
                        piedeDominante: nil,
                        pictureURL: nil
                    )
                }

                rows[i].isSaved = true
                rows[i].isSaving = false
                savedCount += 1
            } catch {
                rows[i].isSaving = false
                rows[i].errorMessage = error.localizedDescription
            }
        }

        isBatchSaving = false
        TournamentHaptics.success()
    }

    private func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

// MARK: - View

struct QuickRosterView: View {
    let teamId: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = QuickRosterViewModel()

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: 16) {
                        TournamentFormSection(
                            title: "Inserimento rapido rosa",
                            subtitle: "Inserisci nome e numero maglia per ogni giocatore. I giocatori gia esistenti verranno riutilizzati.",
                            icon: "list.bullet.clipboard.fill"
                        ) {
                            VStack(spacing: 0) {
                                ForEach(viewModel.rows) { row in
                                    if let index = viewModel.rows.firstIndex(where: { $0.id == row.id }) {
                                        playerInputRow(index: index, row: row)

                                        if index < viewModel.rows.count - 1 {
                                            Divider().padding(.leading, 44)
                                        }
                                    }
                                }
                            }
                            .tournamentCard(padding: 0)
                        }
                        .padding(.horizontal, 16)

                        HStack(spacing: 12) {
                            Button {
                                viewModel.addRow()
                            } label: {
                                Label("Aggiungi riga", systemImage: "plus.circle.fill")
                                    .tournamentButtonChrome(.secondary, fullWidth: true)
                            }
                            .buttonStyle(.tournamentPress)
                        }
                        .padding(.horizontal, 16)

                        if viewModel.savedCount > 0 {
                            Text("\(viewModel.savedCount) giocatori salvati")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TournamentPalette.success)
                        }

                        Button {
                            Task {
                                await viewModel.saveAll(teamId: teamId, appState: appState)
                                if viewModel.filledRows.allSatisfy(\.isSaved) {
                                    await appState.loadTeams()
                                    dismiss()
                                }
                            }
                        } label: {
                            HStack {
                                if viewModel.isBatchSaving {
                                    ProgressView().tint(.white).padding(.trailing, 4)
                                }
                                Text("Salva tutti (\(viewModel.filledRows.count))")
                            }
                            .tournamentButtonChrome(.primary)
                        }
                        .buttonStyle(.tournamentPress)
                        .disabled(viewModel.filledRows.isEmpty || viewModel.isBatchSaving)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Rosa rapida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
            .onAppear {
                viewModel.initialize()
                Task { await viewModel.loadExistingPlayers(appState: appState) }
            }
        }
    }

    @ViewBuilder
    private func playerInputRow(index: Int, row: QuickRosterViewModel.PlayerRow) -> some View {
        let rowId = row.id

        HStack(spacing: 8) {
            // Status indicator
            ZStack {
                if row.isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if row.isSaved {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TournamentPalette.success)
                } else {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }
            .frame(width: 28, height: 28)

            // Name input
            TextField("Nome e cognome", text: Binding(
                get: {
                    guard let i = viewModel.rows.firstIndex(where: { $0.id == rowId }),
                          i < viewModel.rows.count else { return "" }
                    return viewModel.rows[i].name
                },
                set: {
                    guard let i = viewModel.rows.firstIndex(where: { $0.id == rowId }),
                          i < viewModel.rows.count else { return }
                    viewModel.rows[i].name = $0
                }
            ))
            .textContentType(.name)
            .font(.subheadline)
            .disabled(row.isSaved)
            .foregroundStyle(row.isSaved ? TournamentPalette.inkMuted : TournamentPalette.ink)

            // Number input
            TextField("#", text: Binding(
                get: {
                    guard let i = viewModel.rows.firstIndex(where: { $0.id == rowId }),
                          i < viewModel.rows.count else { return "" }
                    return viewModel.rows[i].number
                },
                set: {
                    guard let i = viewModel.rows.firstIndex(where: { $0.id == rowId }),
                          i < viewModel.rows.count else { return }
                    viewModel.rows[i].number = $0
                }
            ))
            .keyboardType(.numberPad)
            .font(.subheadline.weight(.bold))
            .frame(width: 40)
            .multilineTextAlignment(.center)
            .disabled(row.isSaved)

            // Duplicate indicator
            if !row.name.isEmpty, let existing = viewModel.findExistingPlayer(name: row.name) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.warm)
                    .help("Giocatore esistente: \(existing.nomeCompleto)")
            }

            // Remove button
            if !row.isSaved && viewModel.rows.count > 1 {
                Button {
                    withAnimation { viewModel.removeRow(at: index) }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(TournamentPalette.danger.opacity(0.7))
                        .font(.caption)
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(row.isSaved ? TournamentPalette.success.opacity(0.05) : .clear)

        if let error = row.errorMessage {
            Text(error)
                .font(.caption2)
                .foregroundStyle(TournamentPalette.danger)
                .padding(.horizontal, 44)
        }
    }
}

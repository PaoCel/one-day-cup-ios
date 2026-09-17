import SwiftUI

struct RosterView: View {
    let teamId: String
    let team: Team
    let players: [Player]

    @Environment(AppState.self) private var appState

    @State private var showAddPlayer = false
    @State private var showQuickRoster = false
    @State private var playerToEdit: Player?
    @State private var playerToDelete: Player?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                if players.isEmpty {
                    EmptyStateView(
                        icon: "person.2.slash",
                        title: "Nessun giocatore",
                        message: "Aggiungi i giocatori della tua rosa e costruisci il profilo squadra in modo completo."
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(players.enumerated()), id: \.offset) { index, player in
                            PlayerRow(player: player) {
                                playerToEdit = player
                            } onDelete: {
                                playerToDelete = player
                                showDeleteConfirm = true
                            }

                            if index < players.count - 1 {
                                Divider().padding(.leading, 72)
                            }
                        }
                    }
                    .tournamentCard(padding: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $showAddPlayer) {
            AddPlayerView(teamId: teamId)
        }
        .sheet(isPresented: $showQuickRoster) {
            QuickRosterView(teamId: teamId)
        }
        .sheet(item: $playerToEdit) { player in
            EditPlayerPhotoView(player: player)
        }
        .confirmationDialog(
            "Rimuovere \(playerToDelete?.nomeCompleto ?? "il giocatore") dalla rosa?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Rimuovi dalla rosa", role: .destructive) {
                if let p = playerToDelete { Task { await removePlayer(p) } }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Il giocatore diventerà un free agent.")
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                TournamentSectionHeader(
                    title: "Rosa squadra",
                    subtitle: "\(players.count) giocatori registrati. Tocca un giocatore per modificare numero, ruolo, piede e foto."
                )
                Spacer()
                TournamentPill(label: "\(players.count) nomi", tone: .accent)
            }

            Button {
                showAddPlayer = true
            } label: {
                Label("Aggiungi giocatore", systemImage: "plus")
                    .tournamentButtonChrome(.primary)
            }
            .buttonStyle(.tournamentPress)

            Button {
                showQuickRoster = true
            } label: {
                Label("Inserimento rapido", systemImage: "list.bullet.clipboard")
                    .tournamentButtonChrome(.secondary)
            }
            .buttonStyle(.tournamentPress)
        }
        .tournamentCard()
    }

    private func removePlayer(_ player: Player) async {
        guard let id = player.id else { return }
        isDeleting = true
        do {
            if appState.authService.userRole == .admin {
                try await appState.cloudFunctionsService.adminRemovePlayerFromTeam(playerId: id)
            } else {
                try await appState.firestoreService.removePlayerFromTeam(playerId: id)
            }
            await appState.loadTeams()
        } catch {
            alertTitle = "Errore"
            alertMessage = "Impossibile rimuovere il giocatore: \(error.localizedDescription)"
            showAlert = true
        }
        isDeleting = false
    }
}

private struct PlayerRow: View {
    let player: Player
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    CachedAsyncImage(
                        urlString: player.displayPhotoURL,
                        placeholderIcon: "person.fill",
                        placeholderColor: TournamentPalette.accentSoft,
                        contentAlignment: .top
                    )
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(TournamentPalette.border, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(player.nomeCompleto)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TournamentPalette.ink)
                                .lineLimit(1)
                            if let carica = player.carica {
                                Text(carica.sigla)
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(TournamentPalette.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(TournamentPalette.accentSoft)
                                    .clipShape(Capsule())
                            }
                        }

                        HStack(spacing: 6) {
                            if let pos = player.positionPrimary, !pos.isEmpty {
                                Text(pos)
                                    .font(.caption)
                                    .foregroundStyle(TournamentPalette.inkMuted)
                            }
                            if let piede = player.piedeDominante, !piede.isEmpty {
                                if let pos = player.positionPrimary, !pos.isEmpty {
                                    Text("·")
                                        .foregroundStyle(TournamentPalette.inkMuted)
                                }
                                Text(piede)
                                    .font(.caption)
                                    .foregroundStyle(TournamentPalette.inkMuted)
                            }
                            if (player.positionPrimary ?? "").isEmpty && (player.piedeDominante ?? "").isEmpty {
                                Text("Tocca per modificare")
                                    .font(.caption)
                                    .foregroundStyle(TournamentPalette.inkMuted)
                            }
                        }
                    }

                    Spacer()

                    if let numero = player.numeroMaglia {
                        Text("#\(numero)")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(TournamentPalette.accent)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }
            .buttonStyle(.tournamentPress)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.danger)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TournamentPalette.danger.opacity(0.12))
                    )
            }
            .buttonStyle(.tournamentPress)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

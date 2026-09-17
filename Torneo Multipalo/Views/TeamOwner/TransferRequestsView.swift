import SwiftUI
import FirebaseCore

struct TransferRequestsView: View {
    let teamId: String
    let teamName: String

    @Environment(AppState.self) private var appState

    @State private var requests: [TransferRequest] = []
    @State private var allPlayers: [Player] = []
    @State private var isLoading = true
    @State private var showFreeAgents = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        TournamentScreen {
            ScrollView {
                VStack(spacing: 16) {
                    TournamentHeroCard(
                        eyebrow: "Mercato squadra",
                        title: "Richieste trasferimento",
                        subtitle: "Inviti inviati e ricerca mercato, tra svincolati e giocatori gia tesserati, organizzati in un flusso più chiaro.",
                        accent: TournamentPalette.accent,
                        systemImage: "arrow.left.arrow.right"
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    actionCard
                    requestsCard
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Richieste trasferimento")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await caricaRichieste() }
        .task { await caricaRichieste() }
        .sheet(isPresented: $showFreeAgents) {
            FreeAgentsSheet(teamId: teamId, teamName: teamName, onSent: {
                Task { await caricaRichieste() }
            })
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var actionCard: some View {
        TournamentFormSection(
            title: "Nuova richiesta",
            subtitle: "Cerca nel mercato e invia un invito alla tua squadra.",
            icon: "magnifyingglass"
        ) {
            Button {
                showFreeAgents = true
            } label: {
                Label("Apri mercato giocatori", systemImage: "person.crop.circle.badge.plus")
                    .tournamentButtonChrome(.primary)
            }
            .buttonStyle(.tournamentPress)
        }
        .padding(.horizontal, 16)
    }

    private var requestsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Richieste inviate (\(requests.count))",
                subtitle: "Stato aggiornato delle richieste già partite dalla tua squadra."
            )

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, 12)
            } else if requests.isEmpty {
                Text("Nessuna richiesta inviata. Parti dal mercato per rinforzare la rosa.")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(requests) { request in
                    RequestRow(request: request, playerName: playerName(for: request))

                    if request.id != requests.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
        }
        .tournamentCard()
        .padding(.horizontal, 16)
    }

    private func caricaRichieste() async {
        isLoading = true
        do {
            requests = try await appState.firestoreService.fetchRequests(forTeam: teamId)
                .sorted {
                    ($0.createdAt?.dateValue() ?? .distantPast) >
                    ($1.createdAt?.dateValue() ?? .distantPast)
                }
            allPlayers = try await appState.firestoreService.fetchAllPlayers()
        } catch {
            alertTitle = "Errore"
            alertMessage = error.localizedDescription
            showAlert = true
        }
        isLoading = false
    }

    private func playerName(for request: TransferRequest) -> String {
        if let explicitName = request.toPlayerName,
           !explicitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitName
        }
        return allPlayers.first { $0.id == request.playerId }?.nomeCompleto ?? "Giocatore"
    }
}

private struct RequestRow: View {
    let request: TransferRequest
    let playerName: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: statusIcon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(statusColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(playerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)

                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }

            Spacer()

            if let date = request.createdAt?.dateValue() {
                Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch request.status {
        case "accepted": return TournamentPalette.success
        case "rejected": return TournamentPalette.danger
        case "cancelled": return TournamentPalette.inkMuted
        case "pending": return TournamentPalette.warm
        default: return TournamentPalette.inkMuted
        }
    }

    private var statusIcon: String {
        switch request.status {
        case "accepted": return "checkmark"
        case "rejected": return "xmark"
        case "cancelled": return "minus"
        case "pending": return "clock"
        default: return "questionmark"
        }
    }

    private var statusLabel: String {
        switch request.status {
        case "accepted": return "Accettata"
        case "rejected": return "Rifiutata"
        case "cancelled": return "Annullata"
        case "pending":  return "In attesa"
        default:         return request.status.capitalized
        }
    }
}

private struct FreeAgentsSheet: View {
    let teamId: String
    let teamName: String
    let onSent: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Player] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sendingId: String?
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var filtered: [Player] {
        let sorted = candidates.sorted { lhs, rhs in
            switch (lhs.isFreeAgent, rhs.isFreeAgent) {
            case (true, false):
                return true
            case (false, true):
                return false
            default:
                return lhs.nomeCompleto.localizedCaseInsensitiveCompare(rhs.nomeCompleto) == .orderedAscending
            }
        }
        if searchText.isEmpty { return sorted }
        return sorted.filter {
            $0.nomeCompleto.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                Group {
                    if isLoading {
                        LoadingView(message: "Caricamento giocatori...")
                    } else if candidates.isEmpty {
                        EmptyStateView(
                            icon: "person.2",
                            title: "Nessun candidato",
                            message: "Non risultano giocatori disponibili fuori dalla tua rosa."
                        )
                    } else {
                        List(filtered) { player in
                            HStack(spacing: 12) {
                                CachedAsyncImage(
                                    urlString: player.displayPhotoURL,
                                    placeholderIcon: "person.fill",
                                    placeholderColor: Color(.systemGray5),
                                    contentAlignment: .top
                                )
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.nomeCompleto)
                                        .font(.subheadline.weight(.semibold))
                                    Text(playerSubtitle(for: player))
                                        .font(.caption)
                                        .foregroundStyle(TournamentPalette.inkMuted)
                                }

                                Spacer()

                                if sendingId == player.id {
                                    ProgressView().frame(width: 32)
                                } else {
                                    Button {
                                        if let id = player.id {
                                            Task { await inviaRichiesta(playerId: id) }
                                        }
                                    } label: {
                                        Text(player.isClaimed ? "Invita" : "Non attivo")
                                            .tournamentButtonChrome(player.isClaimed ? .secondary : .neutral, fullWidth: false)
                                    }
                                    .buttonStyle(.tournamentPress)
                                    .disabled(!player.isClaimed)
                                    .opacity(player.isClaimed ? 1 : 0.6)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .searchable(text: $searchText, prompt: "Cerca giocatore")
                    }
                }
            }
            .navigationTitle("Mercato giocatori")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
            .task { await carica() }
        }
    }

    private func carica() async {
        isLoading = true
        do {
            let all = try await appState.firestoreService.fetchAllPlayers()
            candidates = all.filter { player in
                guard let id = player.id, !id.isEmpty else { return false }
                return player.teamId != teamId
            }
        } catch {
            alertTitle = "Errore"
            alertMessage = error.localizedDescription
            showAlert = true
        }
        isLoading = false
    }

    private func playerSubtitle(for player: Player) -> String {
        if player.isFreeAgent {
            return player.isClaimed ? "Svincolato" : "Svincolato · profilo non collegato"
        }
        if let currentTeamId = player.teamId,
           let currentTeamName = appState.teams.first(where: { $0.id == currentTeamId })?.nomeSquadra,
           !currentTeamName.isEmpty {
            return player.isClaimed ? currentTeamName : "\(currentTeamName) · profilo non collegato"
        }
        return player.isClaimed ? "Altra squadra" : "Profilo non collegato"
    }

    private func inviaRichiesta(playerId: String) async {
        sendingId = playerId
        do {
            try await appState.cloudFunctionsService.sendPlayerRequest(playerId: playerId)
            onSent()
            try? await Task.sleep(for: .milliseconds(300))
            dismiss()
        } catch {
            alertTitle = "Errore"
            alertMessage = "Impossibile inviare la richiesta: \(error.localizedDescription)"
            showAlert = true
        }
        sendingId = nil
    }
}

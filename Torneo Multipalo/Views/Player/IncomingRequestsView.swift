import SwiftUI
import FirebaseFirestore

struct IncomingRequestsView: View {
    let playerId: String
    let playerAuthUid: String?

    @Environment(AppState.self) private var appState

    @State private var requests: [TransferRequest] = []
    @State private var isLoading = true
    @State private var processingId: String?
    @State private var listener = FirestoreListenerToken()
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var pending: [TransferRequest] {
        requests.filter(\.isPendingLike)
            .sorted { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }
    }

    private var gestite: [TransferRequest] {
        requests.filter(\.isHandled)
            .sorted { ($0.createdAt?.dateValue() ?? .distantPast) > ($1.createdAt?.dateValue() ?? .distantPast) }
    }

    var body: some View {
        TournamentScreen {
            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        LoadingView(message: "Caricamento richieste...")
                    } else if requests.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "Nessuna richiesta",
                            message: "Non hai ancora ricevuto richieste da squadre."
                        )
                    } else {
                        if !pending.isEmpty {
                            requestsSection(
                                title: "In attesa (\(pending.count))",
                                subtitle: "Richieste che richiedono una tua decisione."
                            ) {
                                ForEach(pending) { req in
                                    PendingRequestRow(
                                        request: req,
                                        teamName: teamName(for: req.fromTeamId),
                                        isProcessing: processingId == req.id
                                    ) { accept in
                                        if let id = req.id { Task { await rispondi(requestId: id, accept: accept) } }
                                    }

                                    if req.id != pending.last?.id {
                                        Divider().padding(.leading, 54)
                                    }
                                }
                            }
                        }

                        if !gestite.isEmpty {
                            requestsSection(
                                title: "Archivio",
                                subtitle: "Richieste già gestite e chiuse."
                            ) {
                                ForEach(gestite) { req in
                                    ArchivedRequestRow(request: req, teamName: teamName(for: req.fromTeamId))

                                    if req.id != gestite.last?.id {
                                        Divider().padding(.leading, 54)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Richieste ricevute")
        .navigationBarTitleDisplayMode(.inline)
        .alert(alertTitle, isPresented: $showAlert) { Button("OK") {} } message: { Text(alertMessage) }
        .onAppear { avviaListener() }
        .onDisappear { listener.cancel() }
    }

    private func requestsSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(title: title, subtitle: subtitle)
            content()
        }
        .tournamentCard()
    }

    private func avviaListener() {
        isLoading = true
        listener.replace(with: appState.firestoreService.listenToRequests(
            forPlayerId: playerId,
            playerAuthUid: playerAuthUid
        ) { reqs in
            Task { @MainActor in
                self.requests = reqs
                self.isLoading = false
            }
        })
    }

    private func teamName(for teamId: String) -> String {
        appState.teams.first { $0.id == teamId }?.nomeSquadra
            ?? requests.first { $0.fromTeamId == teamId }?.fromTeamName
            ?? teamId
    }

    private func rispondi(requestId: String, accept: Bool) async {
        processingId = requestId
        do {
            try await appState.cloudFunctionsService.respondPlayerRequest(requestId: requestId, accept: accept)
        } catch {
            alertTitle = accept ? "Errore accettazione" : "Errore rifiuto"
            alertMessage = error.localizedDescription
            showAlert = true
        }
        processingId = nil
    }
}

private struct PendingRequestRow: View {
    let request: TransferRequest
    let teamName: String
    let isProcessing: Bool
    let onAction: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(TournamentPalette.warm.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "clock.fill")
                            .foregroundStyle(TournamentPalette.warm)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(teamName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                    Text("Vuole aggiungerti alla loro rosa")
                        .font(.caption)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
                Spacer()
                if let date = request.createdAt?.dateValue() {
                    Text(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }

            if isProcessing {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else {
                HStack(spacing: 10) {
                    Button {
                        onAction(false)
                    } label: {
                        Text("Rifiuta")
                            .tournamentButtonChrome(.neutral)
                    }
                    .buttonStyle(.tournamentPress)

                    Button {
                        onAction(true)
                    } label: {
                        Text("Accetta")
                            .tournamentButtonChrome(.primary)
                    }
                    .buttonStyle(.tournamentPress)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ArchivedRequestRow: View {
    let request: TransferRequest
    let teamName: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: statusIcon)
                        .font(.caption.bold())
                        .foregroundStyle(statusColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(teamName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
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
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch request.status {
        case "accepted":
            return TournamentPalette.success
        case "cancelled":
            return TournamentPalette.inkMuted
        default:
            return TournamentPalette.danger
        }
    }

    private var statusIcon: String {
        switch request.status {
        case "accepted":
            return "checkmark"
        case "cancelled":
            return "minus"
        default:
            return "xmark"
        }
    }

    private var statusLabel: String {
        switch request.status {
        case "accepted":
            return "Accettata"
        case "cancelled":
            return "Annullata"
        default:
            return "Rifiutata"
        }
    }
}

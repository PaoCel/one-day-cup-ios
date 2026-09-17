import SwiftUI
import FirebaseAuth

/// Phase 4 — Picker di selezione torneo presentato come modal sheet card-based.
///
/// Layout:
///  - NavigationStack interno con toolbar X di chiusura (per presentazione `.sheet`)
///  - lista di card per ciascun torneo: logo + nome + status pill, bordo accent
///    + checkmark sul torneo corrente.
///
/// Caricamento:
///  - mostra la lista `availableTournaments` dello store (status == "active")
///  - se l'utente loggato è super-admin, passa `includeAll: true` allo store
///    per mostrare anche tornei `draft` / `archived` (utile per testing).
///
/// Cambio torneo:
///  - applica la selezione tramite `TournamentSelectionStore.setCurrentTournament(_:)`
///  - l'AppState osserva la notification `.tournamentChanged` e ricarica i feed
///    (matches, teams, participations).
struct TournamentPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var tournaments: [Tournament] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var store: TournamentSelectionStore { appState.tournamentSelectionStore }

    var body: some View {
        NavigationStack {
            OneDayEntranceScreen {
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            OneDayEntryLogo()
                                .frame(width: 92, height: 80)
                            VStack(spacing: 4) {
                                Text("SCEGLI IL TORNEO")
                                    .font(.caption.weight(.bold))
                                    .tracking(1.4)
                                    .foregroundStyle(OneDayEntrancePalette.gold)
                                Text("Un ingresso, tutti i tuoi tornei")
                                    .font(.subheadline)
                                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            }
                        }
                        .padding(.top, 8)

                        if isLoading && tournaments.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(OneDayEntrancePalette.gold)
                                Text("Carico tornei…")
                                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else if let errorMessage {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(OneDayEntrancePalette.gold)
                                    .font(.title2)
                                Text(errorMessage)
                                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                                    .multilineTextAlignment(.center)
                                Button("Riprova") {
                                    Task { await load(force: true) }
                                }
                                .tint(OneDayEntrancePalette.gold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        } else if tournaments.isEmpty {
                            Text("Nessun torneo disponibile.")
                                .foregroundStyle(OneDayEntrancePalette.inkMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(tournaments) { tournament in
                                    TournamentCardView(
                                        tournament: tournament,
                                        isCurrent: tournament.id == store.currentTournamentId
                                    ) {
                                        apply(tournamentId: tournament.id)
                                    }
                                }
                            }

                            Text("Cambiando torneo l'app ricarica le partite e le classifiche.")
                                .font(.caption)
                                .foregroundStyle(OneDayEntrancePalette.inkDim)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    }
                    .accessibilityLabel("Chiudi")
                }
            }
            .task { await load() }
            .refreshable { await load(force: true) }
        }
    }

    private func load(force: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        let isSuper = await isSuperAdmin()
        let list = await store.loadAvailableTournaments(force: force, includeAll: isSuper)
        tournaments = list
        if list.isEmpty {
            errorMessage = "Impossibile caricare la lista tornei. Riprova."
        } else {
            errorMessage = nil
        }
    }

    private func isSuperAdmin() async -> Bool {
        guard Auth.auth().currentUser?.uid != nil else { return false }
        if case .admin = appState.authService.userRole { return true }
        return false
    }

    private func apply(tournamentId: String) {
        guard tournamentId != store.currentTournamentId else {
            dismiss()
            return
        }
        store.setCurrentTournament(tournamentId)
        // L'AppState gestisce il reload via notification observer.
        dismiss()
    }
}

// MARK: - Card

private struct TournamentCardView: View {
    let tournament: Tournament
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 14) {
                ZStack {
                    // Alone nel colore del torneo — logo "nudo", niente card.
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    accentColor.opacity(0.38),
                                    accentColor.opacity(0.10),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 4,
                                endRadius: 120
                            )
                        )
                        .frame(width: 214, height: 172)
                        .blur(radius: 4)

                    logo
                        .frame(width: 112, height: 112)
                        .shadow(color: .black.opacity(0.45), radius: 14, y: 8)
                }
                .frame(height: 170)

                VStack(spacing: 8) {
                    Text(tournament.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(OneDayEntrancePalette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    // Un torneo di prova deve dirlo: i dati sono finti e le
                    // notifiche che manda non sono quelle vere.
                    if tournament.sandbox {
                        Text("SANDBOX · SOLO TEST")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.yellow))
                    }

                    if isCurrent {
                        Label("In uso", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(hex: "#221302") ?? .black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(OneDayEntrancePalette.gold))
                    } else {
                        statusBadge
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.tournamentPress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private var accentColor: Color {
        tournament.branding.primaryColor ?? OneDayEntrancePalette.gold
    }

    @ViewBuilder
    private var logo: some View {
        if let url = tournament.branding.logoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    fallbackLogo
                }
            }
        } else {
            fallbackLogo
        }
    }

    private var fallbackLogo: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.16))
            Image(systemName: "trophy.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(accentColor)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let label: String = {
            switch tournament.status {
            case "active":   return "Attivo"
            case "draft":    return "Bozza"
            case "archived": return "Archiviato"
            default:         return tournament.status.capitalized
            }
        }()
        let color: Color = {
            switch tournament.status {
            case "active":   return Color(hex: "#34D399") ?? .green
            case "draft":    return Color(hex: "#FBBF24") ?? .orange
            case "archived": return OneDayEntrancePalette.inkDim
            default:         return OneDayEntrancePalette.inkDim
            }
        }()

        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(OneDayEntrancePalette.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(OneDayEntrancePalette.surface))
        .overlay(Capsule().stroke(OneDayEntrancePalette.stroke, lineWidth: 1))
    }
}

#Preview {
    TournamentPickerView()
        .environment(AppState())
}

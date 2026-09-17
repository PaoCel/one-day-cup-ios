import SwiftUI

/// Phase 4 — riga riusabile per aprire il `TournamentPickerView` come modal sheet.
/// Da inserire nelle schermate Profilo (TeamDashboard, PlayerDashboard,
/// RuoloPlaceholder, AdminRouter). La sezione si nasconde automaticamente se
/// è disponibile un solo torneo (backward compat: app multi-torneo a fase 4
/// installata su DB single-torneo).
struct TournamentPickerLinkSection: View {
    @Environment(AppState.self) private var appState
    @State private var availableCount: Int = 0
    @State private var didLoad = false
    @State private var showPicker = false

    var body: some View {
        Group {
            // Bastava un torneo solo "disponibile" e la riga spariva del
            // tutto: dal Profilo non si tornava più all'altro torneo, nemmeno
            // per guardarlo. Si nasconde solo se la lista è vuota davvero.
            if availableCount >= 1 {
                Button {
                    showPicker = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(appState.currentBranding.primaryColor ?? Color.accentColor)
                                .frame(width: 32, height: 32)
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.white)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Cambia torneo")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(currentTournamentLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tournamentPress)
            } else {
                EmptyView()
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            let list = await appState.tournamentSelectionStore.loadAvailableTournaments()
            availableCount = list.count
            // Se la lettura non ha restituito niente (rete, permessi, guest)
            // la riga resta comunque: il picker ricarica da sé, e sparire è
            // peggio che mostrare una lista che si popola.
            if list.isEmpty { availableCount = 1 }
        }
        .sheet(isPresented: $showPicker) {
            TournamentPickerView()
                .environment(appState)
        }
    }

    private var currentTournamentLabel: String {
        let store = appState.tournamentSelectionStore
        if let current = store.availableTournaments.first(where: { $0.id == store.currentTournamentId }) {
            return current.displayName
        }
        return store.currentTournamentId
    }
}

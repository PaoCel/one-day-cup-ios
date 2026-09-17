import SwiftUI

struct PlayerDetailLazyView: View {
    let playerId: String
    /// Dalla push "figurina pronta": la lente si apre appena la scheda c'e'.
    var apreLente = false
    @Environment(AppState.self) private var appState
    @State private var player: Player?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let player {
                PlayerDetailView(player: player, apreLente: apreLente)
            } else if isLoading {
                LoadingView(message: "Caricamento giocatore...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(
                    icon: "person.fill.questionmark",
                    title: "Giocatore non trovato",
                    message: ""
                )
            }
        }
        .task {
            do {
                player = try await appState.firestoreService.fetchPlayer(id: playerId)
            } catch {
                print("Failed to load player \(playerId): \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}

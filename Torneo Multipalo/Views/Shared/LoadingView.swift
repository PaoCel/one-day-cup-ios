import SwiftUI

struct LoadingView: View {
    var message: String = "Caricamento..."

    var body: some View {
        TournamentLoadingCard(message: message)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }
}

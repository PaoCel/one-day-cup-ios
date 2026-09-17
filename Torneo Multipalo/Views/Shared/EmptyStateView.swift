import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(TournamentPalette.warm.opacity(0.16))
                    .frame(width: 84, height: 84)

                Image(systemName: icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(TournamentPalette.ink)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TournamentPalette.ink)

                if !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
        .tournamentCard()
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
}

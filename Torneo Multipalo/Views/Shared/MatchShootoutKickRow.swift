import SwiftUI

struct MatchShootoutKickRow: View {
    let kick: Match.PenaltyKick
    let isTeam1: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isTeam1 {
                orderLabel
                MatchEventIcon(.shootout(scored: kick.scored))
                playerLabel
            } else {
                playerLabel
                MatchEventIcon(.shootout(scored: kick.scored))
                orderLabel
            }
        }
    }

    private var orderLabel: some View {
        Text("\(kick.order)°")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(TournamentPalette.inkMuted)
            .frame(width: 24, alignment: isTeam1 ? .leading : .trailing)
    }

    private var playerLabel: some View {
        Text(kick.playerName ?? "—")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(TournamentPalette.ink)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: isTeam1 ? .leading : .trailing)
    }
}

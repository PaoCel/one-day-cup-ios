import SwiftUI

/// Il momento in cui il giocatore scopre che carta gli è uscita.
/// Le statistiche non si possono più cambiare: da qui si va solo avanti.
struct PlayerCardResultStepView: View {
    let viewModel: PlayerCardFlowViewModel
    // Lo stato dell'animazione resta nella view: se stesse nel ViewModel,
    // un aggiornamento asincrono potrebbe farla ripartire a metà.
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
            PlayerCardStepHeader(
                title: "Ecco la tua carta",
                subtitle: "Statistiche calcolate su ruolo e risposte."
            )

            if let result = viewModel.result {
                PlayerCardTierBadge(tier: result.tier, overall: revealed ? result.overall : 0)
                    .scaleEffect(revealed ? 1 : 0.94)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: revealed)

                VStack(alignment: .leading, spacing: TournamentSpacing.md) {
                    identityRow
                    Divider().background(TournamentPalette.divider)
                    PlayerCardStatsGrid(stats: result.stats, animated: revealed)
                }
                .tournamentCard()

                Button { withAnimation { viewModel.goToConfirm() } } label: {
                    Text("Continua")
                        .tournamentButtonChrome(.primary)
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .onAppear {
            guard !revealed else { return }
            withAnimation { revealed = true }
        }
    }

    private var identityRow: some View {
        HStack(spacing: TournamentSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.player.nomeCompleto)
                    .font(.headline)
                    .foregroundStyle(TournamentPalette.ink)
                HStack(spacing: TournamentSpacing.xs) {
                    if let position = viewModel.position {
                        Text(position.shortLabel)
                    }
                    if let teamName = viewModel.teamName {
                        Text("·")
                        Text(teamName)
                    }
                    if let number = viewModel.player.numeroMaglia {
                        Text("·")
                        Text("#\(number)")
                    }
                }
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
            }
            Spacer(minLength: 0)
            if let logo = viewModel.teamLogoURL, !logo.isEmpty {
                CachedAsyncImage(urlString: logo, placeholderIcon: "shield.fill", contentMode: .fit)
                    .frame(width: 40, height: 40)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

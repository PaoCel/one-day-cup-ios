import SwiftUI

/// Stato della generazione. Il client non aspetta nessuna richiesta lunga:
/// il job è già stato accettato, qui si osserva soltanto come procede.
/// Il giocatore può uscire e tornare quando vuole.
struct PlayerCardStatusView: View {
    let viewModel: PlayerCardFlowViewModel
    /// Quale delle due figurine sta nel riquadro grande. Sta nella view e non
    /// nel ViewModel: e' una preferenza di sguardo, non un dato del sorteggio.
    @State private var mostraPrecedente = false

    var body: some View {
        VStack(spacing: TournamentSpacing.lg) {
            switch viewModel.job?.status ?? .none {
            case .ready:
                readyState
            default:
                // `failed` compreso: vedi `PlayerCardStatus.pareInLavorazione`.
                workingState
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Anche da `failed`: quando la rimettiamo in coda l'aggiornamento
            // deve arrivare a chi ha la schermata aperta, senza riaprirla.
            if viewModel.job?.status.pareInLavorazione == true { viewModel.startObserving() }
        }
    }

    // MARK: - In lavorazione

    private var workingState: some View {
        VStack(spacing: TournamentSpacing.md) {
            ZStack {
                Circle()
                    .fill(TournamentPalette.accentSoft)
                    .frame(width: 108, height: 108)
                Text("⚽️").font(.system(size: 46))
            }
            .padding(.top, TournamentSpacing.xl)

            Text("Stiamo creando la tua figurina ⚽️")
                .font(.title3.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
                .multilineTextAlignment(.center)

            Text("Puoi continuare a usare One Day Cup. La troverai qui appena sarà pronta.")
                .font(.subheadline)
                .foregroundStyle(TournamentPalette.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView()
                .tint(TournamentPalette.accent)
                .padding(.top, TournamentSpacing.xs)

            if let job = viewModel.job {
                summaryCard(job)
            }
        }
        .padding(.horizontal, TournamentSpacing.sm)
    }

    // MARK: - Pronta

    private var readyState: some View {
        VStack(spacing: TournamentSpacing.md) {
            if let job = viewModel.job, let url = job.outputImageURL {
                let mostrata = (mostraPrecedente ? job.previousImageURL : url) ?? url
                Text(mostraPrecedente ? "Il tuo primo tentativo" : "La tua figurina è pronta!")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .animation(.default, value: mostraPrecedente)

                CachedAsyncImage(urlString: mostrata, placeholderIcon: "rectangle.portrait", contentMode: .fit)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 18, y: 10)
                    .accessibilityLabel("Figurina di \(job.playerName)")
                    .id(mostrata)

                if let shareURL = URL(string: mostrata) {
                    ShareLink(item: shareURL) {
                        Label("Condividi", systemImage: "square.and.arrow.up")
                            .tournamentButtonChrome(.secondary)
                    }
                    .buttonStyle(.tournamentPress)
                }

                PlayerCardTierBadge(tier: job.cardTier, overall: job.overall)
                PlayerCardStatsGrid(stats: job.stats, animated: true)
                    .tournamentCard()

                if job.canRetry {
                    VStack(spacing: TournamentSpacing.xs) {
                        Button { withAnimation { viewModel.beginRetry() } } label: {
                            Text("Rifai la figurina")
                                .tournamentButtonChrome(.secondary)
                        }
                        .buttonStyle(.tournamentPress)
                        Text("Ti resta \(viewModel.retriesLeft) tentativo su \(PlayerCardJob.maxGenerations). La nuova prende il posto di questa, che resta comunque visibile qui sotto.")
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                }

                if job.previousImageURL != nil {
                    // Si tocca l'altra per portarla nel riquadro grande.
                    // L'anteprima usa la miniatura: la card intera pesa qualche
                    // MB e per un riquadro da 110 punti non finiva di caricare.
                    let altra = mostraPrecedente ? job.outputThumbURL ?? url : job.previousThumbURL ?? job.previousImageURL
                    VStack(alignment: .leading, spacing: TournamentSpacing.xs) {
                        Text(mostraPrecedente ? "L'ultima figurina" : "Il tuo primo tentativo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { mostraPrecedente.toggle() }
                        } label: {
                            CachedAsyncImage(urlString: altra, placeholderIcon: "rectangle.portrait", contentMode: .fit)
                                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                .frame(maxWidth: 110)
                                .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                                        .stroke(TournamentPalette.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.tournamentPress)
                        .accessibilityLabel(mostraPrecedente ? "Mostra l'ultima figurina" : "Mostra il primo tentativo")
                        .accessibilityHint("La porta nel riquadro grande")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: -

    private func summaryCard(_ job: PlayerCardJob) -> some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.sm) {
            HStack {
                Text(job.playerName)
                    .font(.headline)
                    .foregroundStyle(TournamentPalette.ink)
                Spacer()
                Text(job.cardTier.label.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            PlayerCardStatsGrid(stats: job.stats, animated: true)
        }
        .tournamentCard()
    }
}

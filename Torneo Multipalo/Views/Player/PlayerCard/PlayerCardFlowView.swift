import SwiftUI

/// Contenitore del flow "crea la tua figurina".
///
/// Tiene il ViewModel e decide quale passo mostrare. I singoli passi non
/// sanno nulla della navigazione: chiamano il ViewModel e basta.
struct PlayerCardFlowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PlayerCardFlowViewModel

    init(
        player: Player,
        tournamentId: String,
        teamName: String?,
        teamLogoURL: String?,
        tournamentLogoURL: String? = nil
    ) {
        _viewModel = State(initialValue: PlayerCardFlowViewModel(
            player: player,
            tournamentId: tournamentId,
            teamName: teamName,
            teamLogoURL: teamLogoURL,
            tournamentLogoURL: tournamentLogoURL
        ))
    }

    var body: some View {
        TournamentScreen {
            Group {
                if viewModel.isLoadingJob {
                    LoadingView(message: "Controllo la tua figurina…")
                } else {
                    content
                }
            }
        }
        .navigationTitle("La tua figurina")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsBackControl {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Indietro") { withAnimation { viewModel.back() } }
                }
            }
        }
        .task { await viewModel.start() }
        .onDisappear { viewModel.stopObserving() }
    }

    /// Il passo di stato non ha "indietro": una volta avviata la generazione
    /// non si torna al quiz, e il giocatore non deve pensare di poterlo fare.
    private var showsBackControl: Bool {
        switch viewModel.step {
        case .intro, .tracking: false
        default: true
        }
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: TournamentSpacing.lg) {
                if viewModel.progress > 0 && viewModel.step != .tracking {
                    ProgressView(value: viewModel.progress)
                        .tint(TournamentPalette.accent)
                        .animation(.easeInOut(duration: 0.3), value: viewModel.progress)
                }

                switch viewModel.step {
                case .intro:
                    PlayerCardIntroStepView(viewModel: viewModel)
                case .photo:
                    PlayerCardPhotoStepView(viewModel: viewModel)
                case .role:
                    PlayerCardRoleStepView(viewModel: viewModel)
                case let .quiz(index):
                    PlayerCardQuizStepView(viewModel: viewModel, index: index)
                case .result:
                    PlayerCardResultStepView(viewModel: viewModel)
                case .confirm:
                    PlayerCardConfirmStepView(viewModel: viewModel)
                case .tracking:
                    PlayerCardStatusView(viewModel: viewModel)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(TournamentPalette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(TournamentSpacing.lg)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Intro

struct PlayerCardIntroStepView: View {
    let viewModel: PlayerCardFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
            VStack(alignment: .leading, spacing: TournamentSpacing.sm) {
                Text("⚽️")
                    .font(.system(size: 44))
                PlayerCardStepHeader(
                    title: "Facciamo la tua figurina",
                    subtitle: "Cinque domande veloci, niente voti da darsi da soli. Le statistiche escono da come giochi."
                )
            }

            VStack(alignment: .leading, spacing: TournamentSpacing.sm) {
                introRow(icon: "camera.fill", text: "Scegli la foto")
                introRow(icon: "questionmark.bubble.fill", text: "Rispondi a sei domande")
                introRow(icon: "sparkles", text: "Scopri stats, overall e rarità")
            }
            .tournamentCard()

            Label {
                Text("Hai a disposizione **\(PlayerCardJob.maxGenerations) tentativi** in tutto. Prenditela con calma sulla foto.")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.ink)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(TournamentPalette.warm)
            }
            .padding(TournamentSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                    .fill(TournamentPalette.warm.opacity(0.12))
            )

            Button { withAnimation { viewModel.beginFlow() } } label: {
                Text("Iniziamo")
                    .tournamentButtonChrome(.primary)
            }
            .buttonStyle(.tournamentPress)
        }
    }

    private func introRow(icon: String, text: String) -> some View {
        HStack(spacing: TournamentSpacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(TournamentPalette.accent)
                .frame(width: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(TournamentPalette.ink)
            Spacer(minLength: 0)
        }
    }
}

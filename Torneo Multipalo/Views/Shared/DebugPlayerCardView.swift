import SwiftUI

#if DEBUG
/// Anteprima headless dei passi della figurina.
///
/// Serve a fotografare le schermate col simulatore senza dover fare login e
/// senza toccare dati veri: si lancia l'app con `--odc-playercard-preview` e
/// `--odc-playercard-step <nome>`. Come le altre Debug*View del progetto, sta
/// dentro `#if DEBUG` e non finisce nella build spedita.
struct DebugPlayerCardView: View {
    private static let samplePlayer = Player(
        nomeCompleto: "Marco Rossi",
        numeroMaglia: 9,
        teamId: "debug-team"
    )

    @State private var viewModel = PlayerCardFlowViewModel(
        player: samplePlayer,
        tournamentId: "mormon",
        teamName: "Real Capital",
        teamLogoURL: nil
    )

    private var step: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--odc-playercard-step"), index + 1 < args.count else {
            return "intro"
        }
        return args[index + 1]
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: TournamentSpacing.lg) {
                        content
                    }
                    .padding(TournamentSpacing.lg)
                }
            }
            .navigationTitle("La tua figurina")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: prepare)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case "photo": PlayerCardPhotoStepView(viewModel: viewModel)
        case "role": PlayerCardRoleStepView(viewModel: viewModel)
        case "quiz": PlayerCardQuizStepView(viewModel: viewModel, index: 0)
        case "quiz2": PlayerCardQuizStepView(viewModel: viewModel, index: 4)
        case "result": PlayerCardResultStepView(viewModel: viewModel)
        case "confirm": PlayerCardConfirmStepView(viewModel: viewModel)
        case "working", "ready", "failed": PlayerCardStatusView(viewModel: viewModel)
        default: PlayerCardIntroStepView(viewModel: viewModel)
        }
    }

    private func prepare() {
        viewModel.isLoadingJob = false
        viewModel.position = CardPosition.attacker
        for question in PlayerCardQuiz.questions {
            viewModel.answers[question.id] = question.allowsMultiple
                ? [question.options[0].id, question.options[1].id]
                : [question.options[0].id]
        }
        viewModel.computeResult()

        switch step {
        case "confirm":
            viewModel.consentAI = true
            viewModel.consentIdentity = true
        case "working", "ready", "failed":
            viewModel.job = sampleJob(status: step == "working" ? .processing : (step == "ready" ? .ready : .failed))
        default:
            break
        }
    }

    private func sampleJob(status: CardGenerationStatus) -> PlayerCardJob {
        let result = viewModel.result ?? PlayerCardScoring.compute(
            position: .attacker, answers: viewModel.answers, seedKey: "debug"
        )
        return PlayerCardJob(
            jobId: "debug",
            playerId: "debug-player",
            tournamentId: "mormon",
            teamId: "debug-team",
            status: status,
            playerName: "Marco Rossi",
            teamName: "Real Capital",
            position: .attacker,
            jerseyNumber: 9,
            overall: result.overall,
            stats: result.stats,
            cardTier: result.tier,
            answers: viewModel.answers,
            playerPhotoURL: "",
            teamLogoURL: nil,
            tournamentLogoURL: nil,
            outputImageURL: status == .ready
                ? "https://firebasestorage.googleapis.com/v0/b/torneo-multipalo25.firebasestorage.app/o/player-cards%2Fmormon%2Ftest-player-001%2Fcard_mormon_test-player-001.png?alt=media&token=9725a9f5-1d9d-423d-9753-2d0101d2d0b2"
                : nil,
            outputStoragePath: nil,
            aiCardConsent: .accepted(),
            attempt: 1
        )
    }
}
#endif

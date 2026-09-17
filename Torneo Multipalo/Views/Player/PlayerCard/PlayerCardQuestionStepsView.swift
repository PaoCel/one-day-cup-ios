import SwiftUI

/// "In che ruolo ti identifichi?" — il ruolo decide le statistiche di partenza.
struct PlayerCardRoleStepView: View {
    let viewModel: PlayerCardFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
            PlayerCardStepHeader(
                title: "In che ruolo ti identifichi?",
                subtitle: "Quello in cui ti senti davvero, non quello che ti tocca la domenica."
            )

            VStack(spacing: TournamentSpacing.sm) {
                ForEach(CardPosition.allCases) { position in
                    PlayerCardOptionButton(
                        text: position.label,
                        icon: position.symbol,
                        isSelected: viewModel.position == position
                    ) {
                        withAnimation { viewModel.choose(position: position) }
                    }
                }
            }
        }
    }
}

/// Una domanda del quiz per schermata: si risponde e si va avanti da soli.
struct PlayerCardQuizStepView: View {
    let viewModel: PlayerCardFlowViewModel
    let index: Int

    private var question: CardQuizQuestion { PlayerCardQuiz.questions[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
            HStack(spacing: TournamentSpacing.xs) {
                Text("Domanda \(index + 1) di \(PlayerCardQuiz.questions.count)")
                if question.allowsMultiple {
                    Text("· fino a \(question.maxSelections)")
                        .foregroundStyle(TournamentPalette.accent)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(TournamentPalette.inkMuted)

            PlayerCardStepHeader(title: question.title, subtitle: question.subtitle)

            VStack(spacing: TournamentSpacing.sm) {
                ForEach(question.options) { option in
                    PlayerCardOptionButton(
                        text: option.text,
                        isSelected: viewModel.isSelected(option, in: question)
                    ) {
                        withAnimation { viewModel.toggle(option, in: question) }
                    }
                }
            }

            // Le domande a scelta singola avanzano da sole: un pulsante in piu'
            // sarebbe un tap in piu' per niente.
            if question.allowsMultiple {
                Button { withAnimation { viewModel.advance() } } label: {
                    Text(index == PlayerCardQuiz.questions.count - 1 ? "Vedi la mia carta" : "Avanti")
                        .tournamentButtonChrome(.primary)
                }
                .buttonStyle(.tournamentPress)
                .disabled(!viewModel.canAdvance(from: question))
                .opacity(viewModel.canAdvance(from: question) ? 1 : 0.5)
            }
        }
        .id(question.id)
        .transition(.opacity)
    }
}

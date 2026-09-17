import SwiftUI
import FirebaseAuth

@Observable
@MainActor
final class PredictionsViewModel {
    var questions: [PredictionQuestion] = []
    var selectionsByQuestionId: [String: String] = [:]
    var isLoading = false
    var isSyncingQuestions = false
    var submittingQuestionId: String?
    var errorMessage: String?
    var feedbackMessage: String?

    func load(appState: AppState, edition: Int? = nil, allowAdminBackfill: Bool = true) async {
        isLoading = true
        errorMessage = nil
        let targetEdition = edition ?? appState.selectedEdition

        do {
            var loadedQuestions = try await appState.firestoreService.fetchPredictionQuestions(
                edition: targetEdition
            )

            let canAdminBackfill =
                allowAdminBackfill &&
                !appState.runtimeSafety.protectsRealData &&
                appState.authService.userRole == .admin &&
                appState.allMatches.contains(where: { $0.edizione == targetEdition })

            if loadedQuestions.isEmpty, canAdminBackfill {
                isSyncingQuestions = true
                try await appState.cloudFunctionsService.adminSyncPredictionQuestions(
                    edition: targetEdition
                )
                loadedQuestions = try await appState.firestoreService.fetchPredictionQuestions(
                    edition: targetEdition
                )
                isSyncingQuestions = false
            } else if loadedQuestions.isEmpty,
                      allowAdminBackfill,
                      appState.runtimeSafety.protectsRealData,
                      appState.allMatches.contains(where: { $0.edizione == targetEdition }) {
                errorMessage = appState.runtimeSafety.protectionSummary
            }

            questions = sortQuestions(loadedQuestions)

            if let uid = appState.authService.currentUser?.uid {
                let entries = try await appState.firestoreService.fetchPredictionEntries(
                    uid: uid,
                    edition: targetEdition
                )
                selectionsByQuestionId = Dictionary(
                    uniqueKeysWithValues: entries.map { ($0.questionId, $0.selectionId) }
                )
            } else {
                selectionsByQuestionId = [:]
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isSyncingQuestions = false
    }

    func selectedOptionId(for questionId: String?) -> String? {
        guard let questionId else { return nil }
        return selectionsByQuestionId[questionId]
    }

    func isSubmitting(questionId: String?) -> Bool {
        submittingQuestionId == questionId
    }

    func submit(
        question: PredictionQuestion,
        option: PredictionQuestion.Option,
        appState: AppState
    ) async {
        guard let questionId = question.id else { return }

        let wasSelected = selectedOptionId(for: questionId) == option.id

        submittingQuestionId = questionId
        errorMessage = nil
        feedbackMessage = nil

        do {
            try await appState.cloudFunctionsService.submitPrediction(
                questionId: questionId,
                selectionId: option.id
            )
            feedbackMessage = wasSelected
                ? "Pronostico annullato"
                : "Pronostico salvato: \(option.title)"
            await load(appState: appState, edition: question.edition, allowAdminBackfill: false)
        } catch {
            errorMessage = error.localizedDescription
        }

        submittingQuestionId = nil
    }

    private func sortQuestions(_ questions: [PredictionQuestion]) -> [PredictionQuestion] {
        questions.sorted { lhs, rhs in
            let lhsScopeRank = lhs.isEditionQuestion ? 0 : 1
            let rhsScopeRank = rhs.isEditionQuestion ? 0 : 1
            if lhsScopeRank != rhsScopeRank {
                return lhsScopeRank < rhsScopeRank
            }

            let lhsStatusRank = statusRank(for: lhs)
            let rhsStatusRank = statusRank(for: rhs)
            if lhsStatusRank != rhsStatusRank {
                return lhsStatusRank < rhsStatusRank
            }

            let lhsSort = lhs.sortIndex ?? Int.max
            let rhsSort = rhs.sortIndex ?? Int.max
            if lhsSort != rhsSort {
                return lhsSort < rhsSort
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func statusRank(for question: PredictionQuestion) -> Int {
        switch question.normalizedStatus {
        case "open":
            return 0
        case "closed":
            return 1
        default:
            return 2
        }
    }
}

private struct MatchPredictionGroup: Identifiable {
    let id: String
    let title: String
    let questions: [PredictionQuestion]
    let sortIndex: Int
}

private struct PredictionOptionDisplay {
    let optionLabel: String
    let teamName: String?
    let logoURL: String?
    let accentHex: String?
}

private extension AppState {
    func predictionOptionDisplay(for option: PredictionQuestion.Option, edition: Int? = nil) -> PredictionOptionDisplay {
        let targetEdition = edition ?? selectedEdition
        let optionLabel = PredictionsView.normalizedText(option.title) ?? ""
        let fallbackTeamName = PredictionsView.normalizedText(option.subtitle)
        let fallbackLogo = PredictionsView.normalizedText(option.teamLogo)
        let fallbackAccent = PredictionsView.normalizedText(option.accentHex)
        let normalizedTeamId = PredictionsView.normalizedText(option.teamId)

        guard let normalizedTeamId, !normalizedTeamId.isEmpty else {
            return PredictionOptionDisplay(
                optionLabel: optionLabel,
                teamName: fallbackTeamName,
                logoURL: fallbackLogo,
                accentHex: fallbackAccent
            )
        }

        if let editionTeam = editionTeam(for: normalizedTeamId, edition: targetEdition) {
            return PredictionOptionDisplay(
                optionLabel: optionLabel,
                teamName: editionTeam.displayName,
                logoURL: PredictionsView.normalizedText(editionTeam.logoURL) ?? fallbackLogo,
                accentHex: PredictionsView.normalizedText(editionTeam.colors.principale) ?? fallbackAccent
            )
        }

        let resolved = resolvedTeamInfo(teamId: normalizedTeamId, edition: targetEdition)
        return PredictionOptionDisplay(
            optionLabel: optionLabel,
            teamName: PredictionsView.normalizedText(resolved.name) ?? fallbackTeamName,
            logoURL: PredictionsView.normalizedText(resolved.logo) ?? fallbackLogo,
            accentHex: fallbackAccent
        )
    }
}

struct PredictionsView: View {
    var showsNavigation = true
    var showsEditionStrip = false
    var showsScreenBackground = true

    @Environment(AppState.self) private var appState
    @State private var viewModel = PredictionsViewModel()
    @State private var showAuthSheet = false

    private var loadToken: String {
        let uid = appState.authService.currentUser?.uid ?? "guest"
        let role = appState.authService.userRole == .admin ? "admin" : "user"
        return "\(appState.selectedEdition)-\(uid)-\(role)"
    }

    private var editionQuestions: [PredictionQuestion] {
        viewModel.questions.filter(\.isEditionQuestion)
    }

    private var matchQuestions: [PredictionQuestion] {
        viewModel.questions.filter(\.isMatchOutcome)
    }

    private var matchGroups: [MatchPredictionGroup] {
        let grouped = Dictionary(grouping: matchQuestions) { question in
            groupTitle(for: question)
        }

        return grouped.map { title, questions in
            MatchPredictionGroup(
                id: title,
                title: title,
                questions: questions.sorted {
                    ($0.sortIndex ?? Int.max) < ($1.sortIndex ?? Int.max)
                },
                sortIndex: questions.compactMap(\.sortIndex).min() ?? Int.max
            )
        }
        .sorted {
            if $0.sortIndex != $1.sortIndex {
                return $0.sortIndex < $1.sortIndex
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var isLoggedIn: Bool {
        appState.authService.currentUser != nil
    }

    static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        Group {
            if showsNavigation {
                NavigationStack {
                    decoratedContent
                        .navigationTitle("Pronostici")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                TournamentEditionMenu()
                            }
                        }
                }
            } else {
                decoratedContent
            }
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthRouter()
        }
    }

    @ViewBuilder
    private var decoratedContent: some View {
        if showsScreenBackground {
            TournamentScreen { predictionsContent }
        } else {
            predictionsContent
        }
    }

    private var predictionsContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let feedbackMessage = viewModel.feedbackMessage {
                    statusCard(
                        icon: "checkmark.circle.fill",
                        message: feedbackMessage,
                        tint: TournamentPalette.success
                    )
                }

                if let errorMessage = viewModel.errorMessage {
                    statusCard(
                        icon: "exclamationmark.triangle.fill",
                        message: errorMessage,
                        tint: TournamentPalette.danger
                    )
                }

                if !isLoggedIn {
                    authPromptCard
                }

                if viewModel.isSyncingQuestions {
                    statusCard(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        message: "Aggiorno i pronostici",
                        tint: TournamentPalette.accent
                    )
                }

                if viewModel.isLoading && viewModel.questions.isEmpty {
                    LoadingView(message: "Carico i pronostici...")
                } else if viewModel.questions.isEmpty {
                    EmptyStateView(
                        icon: "checklist.checked",
                        title: "Pronostici non disponibili",
                        message: ""
                    )
                    .padding(.top, 28)
                } else {
                    if !editionQuestions.isEmpty {
                        editionPredictionsSection
                    }

                    if !matchGroups.isEmpty {
                        matchPredictionsSection
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .refreshable {
            await viewModel.load(appState: appState)
        }
        .task(id: loadToken) {
            await viewModel.load(appState: appState)
        }
    }

    private var authPromptCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Accedi per votare")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                Text("Da ospite vedi solo le percentuali.")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            Spacer(minLength: 0)

            Button("Accedi") {
                showAuthSheet = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule(style: .continuous)
                    .fill(TournamentPalette.accent)
            )
        }
        .tournamentCard()
    }

    private func statusCard(icon: String, message: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(TournamentPalette.ink)
            Spacer()
        }
        .tournamentCard()
    }

    /// Id dei blocchi che l'utente ha chiuso. Aperti di default: si arriva qui
    /// per votare, non per aprire cose.
    @State private var chiusi: Set<String> = []

    private func apriChiudi(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if chiusi.contains(id) { chiusi.remove(id) } else { chiusi.insert(id) }
        }
    }

    private var editionPredictionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TournamentSectionHeader(title: "Generali")

            ForEach(editionQuestions) { question in
                editionPredictionSection(question: question)
            }
        }
    }

    private func editionPredictionSection(question: PredictionQuestion) -> some View {
        // Richiudibile: "Vincitore del torneo" sono nove squadre in fila, e per
        // arrivare al blocco dopo tocca scorrerle tutte anche quando si e' gia'
        // votato.
        let id = question.id ?? question.title
        let aperto = !chiusi.contains(id)

        return VStack(alignment: .leading, spacing: 12) {
            Button { apriChiudi(id) } label: {
                HStack(alignment: .top) {
                    TournamentSectionHeader(
                        title: question.title,
                        eyebrow: Self.normalizedText(question.subtitle)
                    )

                    Spacer(minLength: 0)

                    if question.normalizedStatus != "open" {
                        TournamentPill(label: statusLabel(for: question), tone: statusTone(for: question))
                    }

                    Image(systemName: aperto ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.tournamentPress)

            if aperto {
            VStack(spacing: 6) {
                ForEach(question.safeOptions) { option in
                    EditionPredictionCard(
                        option: option,
                        question: question,
                        isSelected: viewModel.selectedOptionId(for: question.id) == option.id,
                        isSubmitting: viewModel.isSubmitting(questionId: question.id),
                        isLoggedIn: isLoggedIn,
                        onAuthenticate: { showAuthSheet = true },
                        onSubmit: {
                            Task {
                                await viewModel.submit(question: question, option: option, appState: appState)
                            }
                        }
                    )
                }
            }
            }
        }
    }

    private var matchPredictionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            TournamentSectionHeader(title: "Partite")

            ForEach(matchGroups) { group in
                VStack(alignment: .leading, spacing: 12) {
                    Text(group.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)
                        .padding(.horizontal, 2)

                    ForEach(group.questions) { question in
                        MatchPredictionCard(
                            question: question,
                            match: match(for: question),
                            edition: question.edition,
                            selectedOptionId: viewModel.selectedOptionId(for: question.id),
                            isSubmitting: viewModel.isSubmitting(questionId: question.id),
                            isLoggedIn: isLoggedIn,
                            onAuthenticate: { showAuthSheet = true },
                            onSubmit: { option in
                                Task {
                                    await viewModel.submit(question: question, option: option, appState: appState)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func match(for question: PredictionQuestion) -> Match? {
        guard let matchId = question.matchId else { return nil }
        return appState.allMatches.first { $0.id == matchId }
    }

    private func groupTitle(for question: PredictionQuestion) -> String {
        let normalizedPhase = TournamentPhaseKey.normalize(question.phase)

        switch normalizedPhase {
        case "girone":
            let giornata = question.giornata ?? 0
            return giornata > 0 ? "Giornata \(giornata)" : "Girone"
        case "spareggio", "ottavi", "quarti", "semifinali", "finale":
            return TournamentPhaseKey.displayName(normalizedPhase)
        default:
            if let firstPart = question.subtitle?
                .components(separatedBy: "·")
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !firstPart.isEmpty {
                return firstPart
            }
            return "Partite"
        }
    }

    private func statusLabel(for question: PredictionQuestion) -> String {
        switch question.normalizedStatus {
        case "closed":
            return "Chiuso"
        case "resolved":
            return "Risolto"
        default:
            return "Aperto"
        }
    }

    private func statusTone(for question: PredictionQuestion) -> TournamentTone {
        switch question.normalizedStatus {
        case "closed":
            return .warning
        case "resolved":
            return .success
        default:
            return .accent
        }
    }
}

private struct EditionPredictionCard: View {
    @Environment(AppState.self) private var appState

    let option: PredictionQuestion.Option
    let question: PredictionQuestion
    let isSelected: Bool
    let isSubmitting: Bool
    let isLoggedIn: Bool
    let onAuthenticate: () -> Void
    let onSubmit: () -> Void

    private var isWinner: Bool {
        question.resolvedSelectionId == option.id
    }

    private var display: PredictionOptionDisplay {
        appState.predictionOptionDisplay(for: option)
    }

    private var title: String {
        if question.usesTeamOptions {
            return display.teamName ?? display.optionLabel
        }
        return display.optionLabel
    }

    private var subtitle: String? {
        guard !question.usesTeamOptions else { return nil }
        return display.teamName
    }

    private var tint: Color {
        display.accentHex.flatMap { Color(hex: $0) } ?? TournamentPalette.accent
    }

    private var percentageLabel: String {
        "\(Int((question.optionPercentage(for: option.id) * 100).rounded()))%"
    }

    private var backgroundStyle: AnyShapeStyle {
        if isWinner {
            return AnyShapeStyle(TournamentPalette.success.opacity(0.12))
        }
        if isSelected {
            return AnyShapeStyle(tint.opacity(0.14))
        }
        return AnyShapeStyle(TournamentPalette.surfaceStrong.opacity(0.94))
    }

    private var strokeColor: Color {
        if isWinner {
            return TournamentPalette.success
        }
        if isSelected {
            return tint
        }
        return TournamentPalette.border
    }

    private var percentageValue: Double {
        question.optionPercentage(for: option.id)
    }

    /// Vero solo sull'opzione che **questo** dito ha toccato.
    ///
    /// `isSubmitting` e' della domanda, non dell'opzione: senza questo, la
    /// rotellina comparirebbe su tutte e tre le risposte insieme e non si
    /// capirebbe quale si sta salvando.
    @State private var inAttesa = false

    var body: some View {
        Button {
            guard question.isOpen, !isSubmitting else { return }
            if isLoggedIn {
                inAttesa = true
                onSubmit()
            } else {
                onAuthenticate()
            }
        } label: {
            HStack(spacing: 10) {
                TournamentTeamLogo(
                    urlString: display.logoURL,
                    size: 28,
                    placeholderTint: tint
                )

                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 110, alignment: .leading)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(TournamentPalette.surfaceStrong)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isWinner ? TournamentPalette.success : Color.black)
                            .frame(width: max(4, geo.size.width * CGFloat(percentageValue)))
                    }
                }
                .frame(height: 8)

                Text(percentageLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundStyle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(strokeColor, lineWidth: isSelected || isWinner ? 2 : 1)
            )
        }
        .buttonStyle(.tournamentPress)
        .disabled(!question.isOpen || isSubmitting)
        .opacity((!question.isOpen || isSubmitting) ? 0.94 : 1)
        // Il voto passa dal server e ci mette un attimo: senza un segno, il
        // bottone che si spegne e non fa niente sembra rotto.
        .overlay(alignment: .trailing) {
            if isSubmitting && inAttesa {
                ProgressView()
                    .controlSize(.small)
                    .tint(TournamentPalette.accent)
                    .padding(.trailing, 10)
            }
        }
        .onChange(of: isSubmitting) { _, ora in if !ora { inAttesa = false } }
    }
}

struct MatchPredictionCard: View {
    @Environment(AppState.self) private var appState

    let question: PredictionQuestion
    let match: Match?
    let edition: Int
    let selectedOptionId: String?
    let isSubmitting: Bool
    let isLoggedIn: Bool
    var showsDetailLink = true
    let onAuthenticate: () -> Void
    let onSubmit: (PredictionQuestion.Option) -> Void

    /// L'id dell'opzione toccata: la rotellina va su quella, non su tutte e tre.
    @State private var inAttesa: String?
    /// La scheda parte chiusa: con dodici partite in elenco, dodici griglie
    /// aperte sono uno scorrimento infinito per arrivare a quella che interessa.
    /// Si apre toccando la partita.
    @State private var aperta = false

    private var homeOption: PredictionQuestion.Option? {
        question.safeOptions.first { $0.id == "home" }
    }

    private var drawOption: PredictionQuestion.Option? {
        question.safeOptions.first { $0.id == "draw" }
    }

    private var awayOption: PredictionQuestion.Option? {
        question.safeOptions.first { $0.id == "away" }
    }

    private var statusPill: some View {
        Group {
            if question.normalizedStatus == "closed" {
                TournamentPill(label: "Chiuso", tone: .warning)
            } else if question.normalizedStatus == "resolved" {
                TournamentPill(label: "Risolto", tone: .success)
            }
        }
    }

    private func display(for option: PredictionQuestion.Option?) -> PredictionOptionDisplay? {
        guard let option else { return nil }
        return appState.predictionOptionDisplay(for: option, edition: edition)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { aperta.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        compactTeamSide(
                            logo: display(for: homeOption)?.logoURL,
                            name: display(for: homeOption)?.teamName ?? homeOption?.subtitle ?? "Casa",
                            alignment: .leading
                        )

                        Text("vs")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .padding(.horizontal, 4)

                        compactTeamSide(
                            logo: display(for: awayOption)?.logoURL,
                            name: display(for: awayOption)?.teamName ?? awayOption?.subtitle ?? "Trasferta",
                            alignment: .trailing
                        )
                    }

                    HStack(alignment: .center, spacing: 8) {
                        if let subtitle = question.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }

                        // Il voto gia' dato si vede a scheda chiusa: altrimenti
                        // per sapere se hai gia' pronosticato devi aprirle tutte.
                        if !aperta, let scelta = etichettaScelta {
                            TournamentPill(label: scelta, tone: .accent)
                        }

                        Spacer(minLength: 0)

                        statusPill

                        Image(systemName: aperta ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.tournamentPress)

            if aperta {
                HStack(spacing: 10) {
                    outcomeLabel("1")
                    outcomeLabel("X")
                    outcomeLabel("2")
                }

                HStack(spacing: 10) {
                    if let homeOption {
                        matchOutcomeButton(for: homeOption)
                    }
                    if let drawOption {
                        matchOutcomeButton(for: drawOption)
                    }
                    if let awayOption {
                        matchOutcomeButton(for: awayOption)
                    }
                }

                if showsDetailLink, let match {
                    NavigationLink(destination: MatchDetailView(match: match)) {
                        Text("Apri dettaglio partita")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TournamentPalette.accent)
                    }
                    .buttonStyle(.tournamentPress)
                }
            }
        }
        .tournamentCard()
    }

    /// "1", "X" o "2" se si e' gia' votato, altrimenti `nil`.
    private var etichettaScelta: String? {
        switch selectedOptionId {
        case "home": return "1"
        case "draw": return "X"
        case "away": return "2"
        default: return nil
        }
    }

    private func compactTeamSide(logo: String?, name: String, alignment: Alignment) -> some View {
        HStack(spacing: 10) {
            if alignment == .leading {
                TournamentTeamLogo(
                    urlString: logo,
                    size: 32,
                    placeholderTint: TournamentPalette.accent
                )
            }

            Text(name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
                .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: alignment)

            if alignment == .trailing {
                TournamentTeamLogo(
                    urlString: logo,
                    size: 32,
                    placeholderTint: TournamentPalette.accent
                )
                }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }

    private func outcomeLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.bold))
            .foregroundStyle(TournamentPalette.inkMuted)
            .frame(maxWidth: .infinity)
    }

    private func matchOutcomeButton(for option: PredictionQuestion.Option) -> some View {
        let isSelected = selectedOptionId == option.id
        let isWinner = question.resolvedSelectionId == option.id
        let tint = display(for: option)?.accentHex.flatMap { Color(hex: $0) } ?? TournamentPalette.accent
        let percentage = Int((question.optionPercentage(for: option.id) * 100).rounded())

        let backgroundColor: Color = {
            if isWinner { return TournamentPalette.success.opacity(0.14) }
            if isSelected { return tint.opacity(0.14) }
            return TournamentPalette.surfaceStrong
        }()

        let strokeColor: Color = {
            if isWinner { return TournamentPalette.success }
            if isSelected { return tint }
            return TournamentPalette.border
        }()

        return Button {
            guard question.isOpen, !isSubmitting else { return }
            if isLoggedIn {
                inAttesa = option.id
                onSubmit(option)
            } else {
                onAuthenticate()
            }
        } label: {
            Text("\(percentage)%")
                .font(.headline.weight(.bold))
                .foregroundStyle(
                    isWinner ? TournamentPalette.success : (isSelected ? tint : TournamentPalette.ink)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(strokeColor, lineWidth: isSelected || isWinner ? 2 : 1)
                )
        }
        .buttonStyle(.tournamentPress)
        .disabled(!question.isOpen || isSubmitting)
        .overlay {
            if isSubmitting && inAttesa == option.id {
                ProgressView()
                    .controlSize(.small)
                    .tint(TournamentPalette.accent)
            }
        }
        .onChange(of: isSubmitting) { _, ora in if !ora { inAttesa = nil } }
    }
}

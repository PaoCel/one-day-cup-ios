import SwiftUI
import FirebaseFirestore

// MARK: - ViewModel

@Observable
@MainActor
final class PenaltyShootoutViewModel {
    var match: Match?
    var team1Players: [Player] = []
    var team2Players: [Player] = []
    var penalties: [Match.PenaltyKick] = []
    var isLoading = false
    var errorMessage: String?
    var isSaved = false

    // Current turn
    var currentTeamIndex = 0 // 0 = team1, 1 = team2
    var currentRound = 1
    var isFinished = false
    /// Chi sta per calciare. Si azzera a ogni tiro registrato, perché il turno
    /// passa all'altra squadra e la sua rosa è un'altra.
    var selectedShooter: Player?

    private let listener = FirestoreListenerToken()

    var team1Penalties: [Match.PenaltyKick] {
        guard let match else { return [] }
        return penalties.filter { $0.teamId == match.team1 }.sorted { $0.order < $1.order }
    }

    var team2Penalties: [Match.PenaltyKick] {
        guard let match else { return [] }
        return penalties.filter { $0.teamId == match.team2 }.sorted { $0.order < $1.order }
    }

    var team1Score: Int { team1Penalties.filter(\.scored).count }
    var team2Score: Int { team2Penalties.filter(\.scored).count }

    var currentTeamId: String? {
        guard let match else { return nil }
        return currentTeamIndex == 0 ? match.team1 : match.team2
    }

    var currentTeamPlayers: [Player] {
        currentTeamIndex == 0 ? team1Players : team2Players
    }

    /// Chi non ha ancora tirato, per la squadra di turno.
    ///
    /// Al campo l'errore facile e' far ricalciare due volte lo stesso: i nomi
    /// scorrono, l'admin li cerca a occhio e ne tocca uno gia' usato. Qui
    /// spariscono da soli.
    ///
    /// **Quando hanno tirato tutti il giro riparte** e tornano disponibili: e'
    /// il regolamento — a oltranza si ricomincia dal primo. Il conto e' sui
    /// tiratori distinti, non sul numero di tiri, perche' un tiro anonimo
    /// (senza nome) non consuma nessuno.
    var tiratoriDisponibili: [Player] {
        let rosa = currentTeamPlayers
        guard let tid = currentTeamId else { return rosa }
        let giaTirato = Set(
            penalties.filter { $0.teamId == tid }.compactMap { $0.playerId }.filter { !$0.isEmpty }
        )
        guard !giaTirato.isEmpty else { return rosa }
        let liberi = rosa.filter { p in
            guard let id = p.firestoreIdentifier, !id.isEmpty else { return true }
            return !giaTirato.contains(id)
        }
        return liberi.isEmpty ? rosa : liberi
    }

    var winnerId: String? {
        guard let match else { return nil }
        guard isFinished else { return nil }
        if team1Score > team2Score { return match.team1 }
        if team2Score > team1Score { return match.team2 }
        return nil
    }

    func start(match initialMatch: Match, appState: AppState) {
        self.match = initialMatch
        if let existing = initialMatch.penaltyDetails, !existing.isEmpty {
            penalties = existing
            recalculateState()
        }

        guard let matchId = initialMatch.id else { return }

        listener.replace(with: appState.firestoreService.listenToMatch(matchId: matchId) { [weak self] updated in
            Task { @MainActor [weak self, updated] in
                guard let self, let updated else { return }
                self.match = updated
            }
        })

        Task {
            async let p1 = appState.firestoreService.fetchPlayers(teamId: initialMatch.team1)
            async let p2 = appState.firestoreService.fetchPlayers(teamId: initialMatch.team2)
            team1Players = Self.sortedPlayers((try? await p1) ?? [])
            team2Players = Self.sortedPlayers((try? await p2) ?? [])
        }
    }

    func stop() {
        listener.cancel()
    }

    /// Registra il tiro col nome di chi ha calciato, se è stato selezionato.
    ///
    /// Scrive **solo** in `penaltyDetails` (via `savePenaltyDetails`): i tiri
    /// dello shootout non passano mai da `eventi`, altrimenti un
    /// `rigore_segnato` finirebbe dritto nella classifica marcatori — quel tipo
    /// è nella lista di quelli contati e indica il rigore **in partita**, non
    /// il tiro della sequenza finale.
    func recordPenalty(scored: Bool, appState: AppState, missOutcome: PenaltyMiss.Outcome? = nil) async {
        guard !isLoading, let match, let teamId = currentTeamId else { return }
        guard scored || missOutcome != nil else { return }
        isLoading = true
        isSaved = false
        defer { isLoading = false }
        let previousPenalties = penalties

        let shooter = selectedShooter
        let nextOrder = penalties.count + 1
        let kick = Match.PenaltyKick(
            playerId: shooter?.firestoreIdentifier,
            playerName: shooter?.nomeCompleto,
            teamId: teamId,
            scored: scored,
            order: nextOrder,
            penaltyMiss: scored ? nil : missOutcome.map {
                match.penaltyMiss(outcome: $0, kickingTeamId: teamId, players: team1Players + team2Players)
            }
        )
        penalties.append(kick)
        TournamentHaptics.medium()

        advanceTurn()
        checkForWinner()
        if !(await savePenalties(appState: appState)) {
            penalties = previousPenalties
            recalculateState()
            selectedShooter = shooter
        }
    }

    private func advanceTurn() {
        selectedShooter = nil
        if currentTeamIndex == 0 {
            currentTeamIndex = 1
        } else {
            currentTeamIndex = 0
            currentRound += 1
        }
    }

    private func checkForWinner() {
        guard let match else { return }
        let t1Count = team1Penalties.count
        let t2Count = team2Penalties.count

        // Standard 5 rounds
        if currentRound <= 5 {
            let t1Remaining = 5 - t1Count
            let t2Remaining = 5 - t2Count

            // Team1 cannot be caught
            if team1Score > team2Score + t2Remaining {
                isFinished = true
                return
            }
            // Team2 cannot be caught
            if team2Score > team1Score + t1Remaining {
                isFinished = true
                return
            }
            // All 5 taken by both
            if t1Count >= 5 && t2Count >= 5 && team1Score != team2Score {
                isFinished = true
                return
            }
        }

        // Sudden death (after 5 rounds each)
        if t1Count >= 5 && t2Count >= 5 && t1Count == t2Count {
            if team1Score != team2Score {
                isFinished = true
                return
            }
        }

        isFinished = false
    }

    private func recalculateState() {
        guard let match else { return }
        let t1 = penalties.filter { $0.teamId == match.team1 }.count
        let t2 = penalties.filter { $0.teamId == match.team2 }.count

        if t1 > t2 {
            currentTeamIndex = 1
        } else {
            currentTeamIndex = 0
        }
        currentRound = min(t1, t2) + 1
        checkForWinner()
    }

    private func savePenalties(appState: AppState) async -> Bool {
        guard let match, let matchId = match.id else { return false }
        do {
            try await appState.firestoreService.savePenaltyDetails(
                matchId: matchId,
                penalties: penalties,
                team1Score: team1Score,
                team2Score: team2Score,
                winnerId: winnerId
            )
            isSaved = true

            // Trigger knockout advancement when penalty winner determined
            if winnerId != nil, isFinished {
                await triggerKnockoutAdvancement(match: match, appState: appState)
            }
            return true
        } catch {
            isSaved = false
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func triggerKnockoutAdvancement(match: Match, appState: AppState) async {
        // In v2 avanza il trigger server sulla partita; il percorso storico
        // scriverebbe invece accoppiamenti nella raccolta v1.
        guard appState.firestoreService.dataSource != .v2 else { return }
        let edition = match.edizione
        let format = TournamentEditionFormat.format(
            for: edition,
            tournamentId: appState.currentTournamentId,
            teamCount: appState.editionTeams.count
        )
        guard format.hasKnockout, TournamentPhaseKey.isKnockout(match.fase) else { return }

        do {
            let updatedMatches = try await appState.firestoreService.fetchAllMatches()
            let standings = appState.standings(for: edition)
            try await appState.firestoreService.updateKnockoutAdvancement(
                edition: edition,
                standings: standings,
                format: format,
                allMatches: updatedMatches
            )
        } catch {
            // Non-blocking
        }
    }

    private static func sortedPlayers(_ players: [Player]) -> [Player] {
        players.sorted { lhs, rhs in
            let lhsNumber = lhs.numeroMaglia ?? 99
            let rhsNumber = rhs.numeroMaglia ?? 99
            if lhsNumber == rhsNumber {
                return lhs.nomeCompleto.localizedCaseInsensitiveCompare(rhs.nomeCompleto) == .orderedAscending
            }
            return lhsNumber < rhsNumber
        }
    }
}

// MARK: - View

struct PenaltyShootoutView: View {
    let match: Match

    @Environment(AppState.self) private var appState
    @State private var viewModel = PenaltyShootoutViewModel()
    @State private var showPenaltyMissChoice = false

    private var currentMatch: Match { viewModel.match ?? match }

    private var resolvedTeams: (team1: AppState.ResolvedTeamInfo, team2: AppState.ResolvedTeamInfo) {
        appState.resolvedTeams(for: currentMatch)
    }

    private var terms: ShootoutTerminology {
        appState.shootoutTerminology(for: currentMatch)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Score header
            penaltyScoreHeader

            Divider()

            // La sequenza scrolla per conto suo: con la rosa in pagina, a
            // oltranza i tiri crescono e spingerebbero i comandi fuori schermo.
            ScrollView {
                VStack(spacing: 12) {
                    penaltyProgress
                    ForEach(viewModel.penalties) { kick in
                        if let save = kick.penaltySaveEvent {
                            MatchEventRow(event: save, isTeam1: save.squadraId == currentMatch.team1, timeLabel: "\(kick.order)°")
                        }
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: 180)

            Divider()

            if viewModel.isFinished {
                winnerBanner
            } else {
                // Current turn controls
                currentTurnSection
            }

            Spacer()
        }
        .background(TournamentPalette.backgroundTop)
        .navigationTitle(terms.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Errore", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .penaltyMissConfirmation(isPresented: $showPenaltyMissChoice) { outcome in
            Task { await viewModel.recordPenalty(scored: false, appState: appState, missOutcome: outcome) }
        }
        .onAppear { viewModel.start(match: match, appState: appState) }
        .onDisappear { viewModel.stop() }
    }

    // MARK: - Score Header

    private var penaltyScoreHeader: some View {
        HStack {
            VStack(spacing: 4) {
                TournamentTeamLogo(urlString: resolvedTeams.team1.logo, size: 32)
                Text(resolvedTeams.team1.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 16) {
                Text("\(viewModel.team1Score)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(TournamentPalette.accent)

                Text("-")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)

                Text("\(viewModel.team2Score)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(TournamentPalette.accent)
            }

            VStack(spacing: 4) {
                TournamentTeamLogo(urlString: resolvedTeams.team2.logo, size: 32)
                Text(resolvedTeams.team2.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(TournamentPalette.surfaceStrong)
    }

    // MARK: - Progress

    private var penaltyProgress: some View {
        HStack(alignment: .top, spacing: 24) {
            // Team 1 results
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(viewModel.team1Penalties) { kick in
                    HStack(spacing: 6) {
                        if let name = kick.playerName {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(TournamentPalette.inkMuted)
                                .lineLimit(1)
                        }
                        MatchEventIcon(.shootout(scored: kick.scored), size: 24)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

            // Round numbers
            VStack(spacing: 6) {
                let maxKicks = max(viewModel.team1Penalties.count, viewModel.team2Penalties.count)
                let rounds = max(maxKicks, 1)
                ForEach(1...rounds, id: \.self) { round in
                    Text("\(round)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .frame(height: 24)
                }
            }

            // Team 2 results
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.team2Penalties) { kick in
                    HStack(spacing: 6) {
                        MatchEventIcon(.shootout(scored: kick.scored), size: 24)
                        if let name = kick.playerName {
                            Text(name)
                                .font(.caption2)
                                .foregroundStyle(TournamentPalette.inkMuted)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Current Turn

    /// Il nome del tiratore stava dietro un foglio modale opzionale e nei fatti
    /// non lo compilava nessuno: `playerName` arrivava quasi sempre vuoto e la
    /// cronaca ripiegava su "—". Ora la rosa è qui, si tocca il giocatore e poi
    /// l'esito. I due bottoni restano usabili anche senza selezione, perché in
    /// campo capita di non vedere chi ha calciato e la sequenza non può fermarsi.
    private var currentTurnSection: some View {
        let teamName = viewModel.currentTeamIndex == 0
            ? resolvedTeams.team1.name
            : resolvedTeams.team2.name

        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("\(terms.attemptNoun) #\(viewModel.penalties.count + 1)".uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(TournamentPalette.inkMuted)
                Text(teamName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)
            }

            shooterPicker

            outcomeButtons.disabled(viewModel.isLoading)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Rosa del turno

    private var shooterPicker: some View {
        let players = viewModel.tiratoriDisponibili

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(terms.shooterPickerTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TournamentPalette.inkMuted)

                Spacer(minLength: 0)

                if viewModel.selectedShooter != nil {
                    Button("Togli nome") {
                        TournamentHaptics.selection()
                        viewModel.selectedShooter = nil
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TournamentPalette.accent)
                    .buttonStyle(.tournamentPress)
                }
            }
            .padding(.horizontal, 16)

            if players.isEmpty {
                Text("Rosa non disponibile")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(players, id: \.stableRosterKey) { player in
                            shooterChip(player)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 210)
            }
        }
    }

    private func shooterChip(_ player: Player) -> some View {
        let isSelected = viewModel.selectedShooter?.stableRosterKey == player.stableRosterKey

        return Button {
            TournamentHaptics.selection()
            viewModel.selectedShooter = isSelected ? nil : player
        } label: {
            HStack(spacing: 8) {
                // Faccia **e** numero. Al campo il gol te lo urlano col numero
                // ("ha segnato il 7"), il nome molto piu' di rado: cercarlo in
                // un elenco di soli nomi e' la parte lenta. La foto serve
                // quando il numero non c'e' o la maglia e' quella sbagliata.
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(
                        urlString: player.displayPhotoURL,
                        placeholderIcon: "person.fill",
                        placeholderColor: isSelected
                            ? TournamentPalette.surfaceStrong.opacity(0.28)
                            : TournamentPalette.accentSoft
                    )
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())

                    Text(player.numeroMaglia.map(String.init) ?? "-")
                        .font(.system(size: 9, weight: .black).monospacedDigit())
                        .foregroundStyle(isSelected ? TournamentPalette.accent : TournamentPalette.surfaceStrong)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle().fill(isSelected ? TournamentPalette.surfaceStrong : TournamentPalette.accent)
                        )
                        .offset(x: 3, y: 3)
                }

                Text(player.nomeCompleto.inizialeECognome)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? TournamentPalette.surfaceStrong : TournamentPalette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.pill, style: .continuous)
                    .fill(isSelected ? TournamentPalette.accent : TournamentPalette.surfaceStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TournamentRadius.pill, style: .continuous)
                    .stroke(isSelected ? Color.clear : TournamentPalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.tournamentPress)
    }

    // MARK: - Esito del tiro

    private var outcomeButtons: some View {
        VStack(spacing: 8) {
            Text(viewModel.selectedShooter.map { "Calcia \($0.nomeCompleto)" } ?? "Nessun nome: il tiro resta anonimo")
                .font(.caption)
                .foregroundStyle(
                    viewModel.selectedShooter == nil
                        ? TournamentPalette.inkMuted
                        : TournamentPalette.ink
                )
                .lineLimit(1)

            HStack(spacing: 16) {
                Button {
                    Task { await viewModel.recordPenalty(scored: true, appState: appState) }
                } label: {
                    HStack(spacing: 8) {
                        MatchEventIcon(.shootoutScored, size: 30)
                            .accessibilityHidden(true)
                        Text("Segnato")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                            .fill(TournamentPalette.success.opacity(0.15))
                    )
                    .foregroundStyle(TournamentPalette.success)
                }
                .buttonStyle(.tournamentPress)

                Button {
                    showPenaltyMissChoice = true
                } label: {
                    HStack(spacing: 8) {
                        MatchEventIcon(.shootoutMissed, size: 30)
                            .accessibilityHidden(true)
                        Text("Sbagliato")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                            .fill(TournamentPalette.danger.opacity(0.15))
                    )
                    .foregroundStyle(TournamentPalette.danger)
                }
                .buttonStyle(.tournamentPress)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Winner Banner

    private var winnerBanner: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundStyle(TournamentPalette.warm)

            if let winnerId = viewModel.winnerId {
                let name = winnerId == currentMatch.team1
                    ? resolvedTeams.team1.name
                    : resolvedTeams.team2.name
                Text(terms.winnerSentence(team: name))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
            }

            Text("\(viewModel.team1Score) - \(viewModel.team2Score)")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(TournamentPalette.accent)
        }
        .padding(.vertical, 24)
    }
}

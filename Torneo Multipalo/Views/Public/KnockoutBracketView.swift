import SwiftUI

private struct BracketParticipantDisplay {
    let teamId: String?
    let name: String
    let logo: String?
    let seed: Int?
    let isPlaceholder: Bool
}

private struct BracketSlotState: Identifiable {
    let definition: TournamentEditionFormat.KnockoutSlotDefinition
    let persistedMatch: Match?
    let detailMatch: Match
    let home: BracketParticipantDisplay
    let away: BracketParticipantDisplay

    var id: String { definition.id }

    var matchStatus: BracketMatchStatus {
        guard let match = persistedMatch else { return .upcoming }
        if match.isLive { return .live }
        if match.isPlayed { return .finished }
        if match.isStarted { return .live }
        return .upcoming
    }

    var homeGoals: Int { persistedMatch?.team1Goals ?? 0 }
    var awayGoals: Int { persistedMatch?.team2Goals ?? 0 }
    var hasKnownScore: Bool { persistedMatch?.hasKnownScore ?? false }
    var winnerTeamId: String? { persistedMatch?.resolvedWinnerTeamId }
    var penaltySuffix: String? {
        guard let penaltyScore = persistedMatch?.penaltyScore else { return nil }
        return "(\(penaltyScore.team1)-\(penaltyScore.team2) dcr)"
    }
}

private enum BracketSide {
    case left, right, none

    static func fromSlotId(_ id: String) -> BracketSide {
        if id.hasSuffix("_left") { return .left }
        if id.hasSuffix("_right") { return .right }
        return .none
    }

    var label: String {
        switch self {
        case .left: return "LATO SINISTRO"
        case .right: return "LATO DESTRO"
        case .none: return ""
        }
    }

    var shortLabel: String {
        switch self {
        case .left: return "SX"
        case .right: return "DX"
        case .none: return ""
        }
    }

    var color: Color {
        switch self {
        case .left: return TournamentPalette.accent
        case .right: return TournamentPalette.warm
        case .none: return TournamentPalette.inkMuted
        }
    }

    var icon: String {
        switch self {
        case .left: return "arrow.left"
        case .right: return "arrow.right"
        case .none: return "circle"
        }
    }
}

private enum BracketMatchStatus {
    case upcoming, live, finished

    var label: String {
        switch self {
        case .upcoming: return "Da giocare"
        case .live: return "In corso"
        case .finished: return "Terminata"
        }
    }

    var icon: String {
        switch self {
        case .upcoming: return "clock"
        case .live: return "circle.fill"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .upcoming: return TournamentPalette.inkMuted
        case .live: return TournamentPalette.success
        case .finished: return TournamentPalette.accent
        }
    }
}

private struct BracketPhase: Identifiable {
    let id: String
    let title: String
    let icon: String
    let subtitle: String
    let slots: [BracketSlotState]
}

struct KnockoutBracketView: View {
    var showsNavigation = true
    var showsScreenBackground = true
    var exportPreview = false

    @Environment(AppState.self) private var appState
    @State private var showBracketShareSheet = false

    private var editionFormat: TournamentEditionFormat {
        TournamentEditionFormat.resolve(
            for: appState.selectedEdition,
            tournamentId: appState.currentTournamentId,
            teamCount: appState.editionTeams.count,
            matches: appState.matches
        )
    }

    private var standingsByRank: [Int: StandingsEntry] {
        Dictionary(uniqueKeysWithValues: appState.standings.enumerated().map { ($0.offset + 1, $0.element) })
    }

    private var standingsRankByTeamId: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: appState.standings.enumerated().map { ($0.element.teamId, $0.offset + 1) }
        )
    }

    private var knockoutMatchesByPhase: [String: [Match]] {
        Dictionary(
            grouping: appState.matches.filter { TournamentPhaseKey.isKnockout($0.fase) }
        ) { TournamentPhaseKey.scopedKey(fase: $0.fase, tabellone: $0.tabellone) }
        .mapValues { matches in
            matches.sorted { lhs, rhs in
                if lhs.giornata != rhs.giornata {
                    return lhs.giornata < rhs.giornata
                }

                let lhsTime = lhs.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rhsTime = rhs.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if lhsTime != rhsTime {
                    return lhsTime < rhsTime
                }

                return (lhs.id ?? "") < (rhs.id ?? "")
            }
        }
    }

    private var slotDefinitionsById: [String: TournamentEditionFormat.KnockoutSlotDefinition] {
        Dictionary(uniqueKeysWithValues: editionFormat.knockoutSlots.map { ($0.id, $0) })
    }

    private var slotStatesById: [String: BracketSlotState] {
        Dictionary(uniqueKeysWithValues: editionFormat.knockoutSlots.map { definition in
            (definition.id, slotState(for: definition))
        })
    }

    private var bracketPhases: [BracketPhase] {
        let metadata: [String: (title: String, icon: String, subtitle: String)] = [
            "spareggio": ("Spareggio", "arrow.triangle.swap", "Accesso ai quarti"),
            "quarti": ("Quarti di finale", "arrow.triangle.branch", "Accesso alle semifinali"),
            "semifinali": ("Semifinali", "flame", "Accesso alla finale"),
            "finale_78": ("7°/8° posto", "list.number", "Piazzamento"),
            "finale_56": ("5°/6° posto", "list.number", "Piazzamento"),
            "finale_34": ("3°/4° posto", "medal", "Podio"),
            "finale": ("Finale", "trophy", "Titolo"),
            "ottavi": ("Ottavi di finale", "arrow.triangle.branch", "Accesso ai quarti"),
            // tabellone di consolazione: chi esce dalla prima fase continua qui
            "el_ottavi": ("Ottavi — consolazione", "arrow.triangle.branch", "Secondo tabellone"),
            "el_quarti": ("Quarti — consolazione", "arrow.triangle.branch", "Secondo tabellone"),
            "el_semifinali": ("Semifinali — consolazione", "flame", "Verso il secondo trofeo"),
            "el_finale_34": ("3°/4° posto — consolazione", "medal", "Podio"),
            "el_finale": ("Finale — consolazione", "trophy", "Secondo trofeo")
        ]
        let grouped = Dictionary(grouping: editionFormat.knockoutSlots) { $0.phaseKey }
        return grouped.keys.sorted {
            TournamentPhaseKey.sortRank($0) < TournamentPhaseKey.sortRank($1)
        }.compactMap { phaseKey in
            let definitions = (grouped[phaseKey] ?? []).sorted { $0.matchOrder < $1.matchOrder }
            let slots = definitions.compactMap { slotStatesById[$0.id] }
            guard !slots.isEmpty else { return nil }
            let meta = metadata[phaseKey] ?? (TournamentPhaseKey.displayName(phaseKey), "sportscourt", "")
            return BracketPhase(
                id: phaseKey,
                title: meta.title,
                icon: meta.icon,
                subtitle: meta.subtitle,
                slots: slots
            )
        }
    }

    /// Le colonne del tabellone, costruite dalle **partite** e non dagli slot
    /// del formato: gli slot ne conoscono uno per lato, e con quattro quarti
    /// significa mostrarne due.
    private var colonneTabellone: [BracketTreeView.Colonna] {
        let ordine: [(chiave: String, titolo: String, innesto: Bool)] = [
            ("spareggio", "Spareggio", true),
            ("ottavi", "Ottavi", false),
            ("quarti", "Quarti", false),
            ("semifinali", "Semifinali", false),
            ("finale", "Finale", false)
        ]
        return ordine.compactMap { voce in
            let partite = knockoutMatchesByPhase[voce.chiave] ?? []
            guard !partite.isEmpty else { return nil }
            return BracketTreeView.Colonna(
                id: voce.chiave,
                titolo: voce.titolo,
                partite: partite,
                innesto: voce.innesto
            )
        }
    }

    /// Finali di piazzamento: si giocano a lato dell'albero, non dentro.
    private var partitePiazzamento: [Match] {
        ["finale_34", "finale_56", "finale_78"].flatMap { knockoutMatchesByPhase[$0] ?? [] }
    }

    private var champion: BracketParticipantDisplay? {
        winner(ofPhase: "finale")
    }

    /// Vincitore del tabellone di consolazione: ha il suo trofeo, separato.
    private var secondaryChampion: BracketParticipantDisplay? {
        winner(ofPhase: TournamentPhaseKey.secondaryPrefix + "finale")
    }

    /// Nei formati scritti a mano lo slot della finale si chiama "final"; in
    /// quelli ricavati dalle partite l'id è generato, quindi si cerca per fase.
    private func winner(ofPhase phaseKey: String) -> BracketParticipantDisplay? {
        let slot = phaseKey == "finale"
            ? (slotStatesById["final"] ?? slotStatesById.values.first { $0.definition.phaseKey == phaseKey })
            : slotStatesById.values.first { $0.definition.phaseKey == phaseKey }
        guard let winnerId = slot?.winnerTeamId else { return nil }
        let resolved = appState.resolvedTeamInfo(teamId: winnerId, edition: appState.selectedEdition)
        return BracketParticipantDisplay(
            teamId: winnerId,
            name: resolved.name,
            logo: resolved.logo,
            seed: standingsRankByTeamId[winnerId],
            isPlaceholder: false
        )
    }

    var body: some View {
        Group {
            if showsNavigation {
                NavigationStack {
                    configuredBracket
                }
            } else {
                configuredBracket
            }
        }
    }

    private var configuredBracket: some View {
        decoratedContent
            .navigationTitle("Fase finale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsNavigation {
                    ToolbarItem(placement: .topBarTrailing) {
                        TournamentEditionMenu()
                    }
                }
            }
            .sheet(isPresented: $showBracketShareSheet) {
                BracketStoryShareView(
                    phases: bracketPhases.map { phase in
                        (name: phase.title, matches: phase.slots.map { slot in
                            (team1: slot.home.name,
                             team2: slot.away.name,
                             score1: slot.matchStatus == .finished && slot.hasKnownScore ? slot.homeGoals : nil,
                             score2: slot.matchStatus == .finished && slot.hasKnownScore ? slot.awayGoals : nil)
                        })
                    },
                    edition: appState.selectedEdition
                )
            }
    }

    @ViewBuilder
    private var decoratedContent: some View {
        if showsScreenBackground {
            TournamentScreen { bracketContent }
        } else {
            bracketContent
        }
    }

    @ViewBuilder
    private var bracketContent: some View {
        if !editionFormat.hasKnockout {
            EmptyStateView(
                icon: "trophy",
                title: "Tabellone non disponibile",
                message: ""
            )
        } else {
            ScrollView {
                VStack(spacing: 14) {
                    bracketHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    // Le edizioni storiche non hanno colonne: il loro tabellone
                    // non è un albero con lati sinistro/destro ma un elenco di
                    // fasi. Prima la condizione era `[2023, 2024].contains(...)`
                    // e la Mormon storica finiva nell'albero del formato in
                    // corso, che cerca slot (quarter_left, …) che lì non esistono.
                    if colonneTabellone.count > 1 {
                        BracketTreeView(
                            colonne: colonneTabellone,
                            piazzamenti: partitePiazzamento
                        )
                    } else {
                        // Nessun albero da disegnare (edizioni storiche, o
                        // formati senza turni successivi): resta l'elenco.
                        historicalBracketList
                            .padding(.horizontal, 16)
                    }

                    if let champion {
                        BracketChampionCard(champion: champion)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }

                    if let secondaryChampion {
                        BracketChampionCard(champion: secondaryChampion, kicker: "VINCITORE CONSOLAZIONE")
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var historicalBracketList: some View {
        VStack(spacing: 16) {
            ForEach(bracketPhases) { phase in
                VStack(alignment: .leading, spacing: 8) {
                    Label(phase.title.uppercased(), systemImage: phase.icon)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                    ForEach(phase.slots) { slot in
                        BracketMatchCard(slot: slot, isFinal: phase.id == "finale")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bracketTree: some View {
        let prelim = slotStatesById["preliminary_left"]
        let ql = slotStatesById["quarter_left"]
        let sl = slotStatesById["semifinal_left"]
        let qr = slotStatesById["quarter_right"]
        let sr = slotStatesById["semifinal_right"]

        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                BracketSideBanner(side: .left)

                if let prelim {
                    BracketPhaseLabel(text: "SPAREGGIO", color: BracketSide.left.color)
                    BracketCompactCard(slot: prelim, side: .left, phaseLabel: "Spareggio")
                    BracketConnector(side: .left)
                }

                if let ql {
                    BracketPhaseLabel(text: "QUARTO", color: BracketSide.left.color)
                    BracketCompactCard(slot: ql, side: .left, phaseLabel: "Quarto")
                    BracketConnector(side: .left)
                }

                if let sl {
                    BracketPhaseLabel(text: "SEMIFINALE", color: BracketSide.left.color)
                    BracketCompactCard(slot: sl, side: .left, phaseLabel: "Semifinale")
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(TournamentPalette.border)
                .frame(width: 1)
                .padding(.vertical, 40)

            VStack(spacing: 8) {
                BracketSideBanner(side: .right)

                if let prelim {
                    // Hidden placeholder to align right column with left's spareggio row
                    Group {
                        BracketPhaseLabel(text: "SPAREGGIO", color: BracketSide.right.color)
                        BracketCompactCard(slot: prelim, side: .right, phaseLabel: "")
                        BracketConnector(side: .right)
                    }
                    .hidden()
                }

                if let qr {
                    BracketPhaseLabel(text: "QUARTO", color: BracketSide.right.color)
                    BracketCompactCard(slot: qr, side: .right, phaseLabel: "Quarto")
                    BracketConnector(side: .right)
                }

                if let sr {
                    BracketPhaseLabel(text: "SEMIFINALE", color: BracketSide.right.color)
                    BracketCompactCard(slot: sr, side: .right, phaseLabel: "Semifinale")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var bracketHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "trophy.fill")
                .font(.title.weight(.bold))
                .foregroundStyle(TournamentPalette.warm)

            Text("FASE FINALE")
                .font(.title3.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)

            Text("Tabellone a Eliminazione Diretta")
                .font(.subheadline)
                .foregroundStyle(TournamentPalette.inkMuted)

            Text("\(editionFormat.knockoutSlots.count) Partite \u{2022} \(bracketPhases.count) Turni \u{2022} 1 Vincitore")
                .font(.caption.weight(.medium))
                .foregroundStyle(TournamentPalette.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(TournamentPalette.accentSoft)
                )

        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: - Data resolution (unchanged logic)

    private func slotState(for definition: TournamentEditionFormat.KnockoutSlotDefinition) -> BracketSlotState {
        if let match = matchForSlot(definition) {
            let resolvedTeams = appState.resolvedTeams(for: match)
            return BracketSlotState(
                definition: definition,
                persistedMatch: match,
                detailMatch: match,
                home: BracketParticipantDisplay(
                    teamId: match.team1,
                    name: resolvedTeams.team1.name,
                    logo: resolvedTeams.team1.logo,
                    seed: seed(for: definition.homeSource, resolvedTeamId: match.team1),
                    isPlaceholder: resolvedTeams.team1.isTbd
                ),
                away: BracketParticipantDisplay(
                    teamId: match.team2,
                    name: resolvedTeams.team2.name,
                    logo: resolvedTeams.team2.logo,
                    seed: seed(for: definition.awaySource, resolvedTeamId: match.team2),
                    isPlaceholder: resolvedTeams.team2.isTbd
                )
            )
        }

        let home = projectedParticipant(for: definition.homeSource)
        let away = projectedParticipant(for: definition.awaySource)

        return BracketSlotState(
            definition: definition,
            persistedMatch: nil,
            detailMatch: projectedMatch(for: definition, home: home, away: away),
            home: home,
            away: away
        )
    }

    private func matchForSlot(_ definition: TournamentEditionFormat.KnockoutSlotDefinition) -> Match? {
        let phaseMatches = knockoutMatchesByPhase[definition.phaseKey] ?? []
        guard phaseMatches.indices.contains(definition.matchOrder) else { return nil }
        return phaseMatches[definition.matchOrder]
    }

    private func projectedParticipant(
        for source: TournamentEditionFormat.KnockoutParticipantSource
    ) -> BracketParticipantDisplay {
        switch source {
        case .standing(let rank):
            if let standing = standingsByRank[rank] {
                let resolved = appState.resolvedTeamInfo(teamId: standing.teamId, edition: appState.selectedEdition)
                return BracketParticipantDisplay(
                    teamId: standing.teamId, name: resolved.name, logo: resolved.logo,
                    seed: rank, isPlaceholder: false
                )
            }
            return seedPlaceholder(rank)

        case .winner(let slotId):
            if let sourceDefinition = slotDefinitionsById[slotId],
               let winnerTeamId = matchForSlot(sourceDefinition)?.resolvedWinnerTeamId {
                let resolved = appState.resolvedTeamInfo(teamId: winnerTeamId, edition: appState.selectedEdition)
                return BracketParticipantDisplay(
                    teamId: winnerTeamId, name: resolved.name, logo: resolved.logo,
                    seed: standingsRankByTeamId[winnerTeamId], isPlaceholder: false
                )
            }
            return emptyPlaceholder()

        case .loser(let slotId):
            if let sourceDefinition = slotDefinitionsById[slotId],
               let match = matchForSlot(sourceDefinition),
               let winnerId = match.resolvedWinnerTeamId {
                let loserId = winnerId == match.team1 ? match.team2 : match.team1
                let resolved = appState.resolvedTeamInfo(teamId: loserId, edition: appState.selectedEdition)
                return BracketParticipantDisplay(
                    teamId: loserId, name: resolved.name, logo: resolved.logo,
                    seed: standingsRankByTeamId[loserId], isPlaceholder: false
                )
            }
            return emptyPlaceholder()
        }
    }

    private func seed(
        for source: TournamentEditionFormat.KnockoutParticipantSource,
        resolvedTeamId: String
    ) -> Int? {
        switch source {
        case .standing(let rank): return rank
        case .winner: return standingsRankByTeamId[resolvedTeamId]
        case .loser: return standingsRankByTeamId[resolvedTeamId]
        }
    }

    private func projectedMatch(
        for definition: TournamentEditionFormat.KnockoutSlotDefinition,
        home: BracketParticipantDisplay,
        away: BracketParticipantDisplay
    ) -> Match {
        Match(
            id: nil,
            edizione: appState.selectedEdition,
            giornata: 0,
            fase: definition.phaseKey,
            idFase: definition.id,
            campo: nil,
            matchTime: nil,
            team1: home.teamId ?? "tbd",
            team2: away.teamId ?? "tbd",
            team1Meta: Match.TeamMeta(id: home.teamId, name: home.name, logo: home.logo),
            team2Meta: Match.TeamMeta(id: away.teamId, name: away.name, logo: away.logo),
            started: false,
            played: false,
            eventi: []
        )
    }

    private func seedPlaceholder(_ seed: Int) -> BracketParticipantDisplay {
        BracketParticipantDisplay(teamId: nil, name: "", logo: nil, seed: seed, isPlaceholder: true)
    }

    private func emptyPlaceholder() -> BracketParticipantDisplay {
        BracketParticipantDisplay(teamId: nil, name: "", logo: nil, seed: nil, isPlaceholder: true)
    }
}

// MARK: - Compact bracket pieces

private struct BracketSideBanner: View {
    let side: BracketSide

    var body: some View {
        HStack(spacing: 6) {
            if side == .left {
                Image(systemName: "arrow.left")
                    .font(.caption2.weight(.bold))
                Text(side.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
            } else {
                Text(side.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(side.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(side.color.opacity(0.12))
        )
    }
}

private struct BracketPhaseLabel: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct BracketConnector: View {
    let side: BracketSide

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(side.color.opacity(0.5))
                .frame(width: 2, height: 10)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(side.color.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BracketCompactCard: View {
    let slot: BracketSlotState
    var side: BracketSide = .none
    var phaseLabel: String

    private var isLive: Bool { slot.matchStatus == .live }
    private var isFinished: Bool { slot.matchStatus == .finished }

    var body: some View {
        NavigationLink(destination: MatchDetailView(match: slot.detailMatch)) {
            HStack(spacing: 0) {
                if side != .none {
                    Rectangle()
                        .fill(side.color)
                        .frame(width: 3)
                }

                VStack(spacing: 6) {
                    HStack(spacing: 4) {
                        teamCell(slot.home, isWinner: slot.winnerTeamId == slot.home.teamId)
                        teamCell(slot.away, isWinner: slot.winnerTeamId == slot.away.teamId)
                    }

                    scoreLine
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TournamentPalette.surfaceStrong)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isLive ? TournamentPalette.success : (side != .none ? side.color.opacity(0.35) : TournamentPalette.border),
                            lineWidth: isLive ? 2 : 1)
            )
        }
        .buttonStyle(.tournamentPress)
    }

    private func teamCell(_ p: BracketParticipantDisplay, isWinner: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if !p.isPlaceholder, p.teamId != nil {
                    TournamentTeamLogo(urlString: p.logo, size: 26, placeholderTint: TournamentPalette.accent)
                } else if let seed = p.seed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(TournamentPalette.surfaceMuted)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text("\(seed)°")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(TournamentPalette.surfaceMuted)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Text("?")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TournamentPalette.border)
                        )
                }
            }

            Text(shortCode(for: p))
                .font(.caption2.weight(.bold))
                .foregroundStyle(isWinner && isFinished ? TournamentPalette.ink : TournamentPalette.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .opacity(isFinished && !isWinner && slot.winnerTeamId != nil ? 0.55 : 1)
    }

    @ViewBuilder
    private var scoreLine: some View {
        switch slot.matchStatus {
        case .upcoming:
            Text("VS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        case .live, .finished:
            if slot.hasKnownScore {
                HStack(spacing: 4) {
                    Text("\(slot.homeGoals)")
                        .foregroundStyle(winnerColor(for: slot.home))
                    Text(":")
                        .foregroundStyle(TournamentPalette.inkMuted)
                    Text("\(slot.awayGoals)")
                        .foregroundStyle(winnerColor(for: slot.away))
                    if let penaltySuffix = slot.penaltySuffix {
                        Text(penaltySuffix)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TournamentPalette.warm)
                    }
                }
                .font(.subheadline.weight(.bold).monospacedDigit())
            } else {
                Text("n.d.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
    }

    private func winnerColor(for p: BracketParticipantDisplay) -> Color {
        if isFinished, slot.winnerTeamId == p.teamId {
            return TournamentPalette.success
        }
        return TournamentPalette.ink
    }

    private func shortCode(for p: BracketParticipantDisplay) -> String {
        if p.isPlaceholder, let seed = p.seed {
            return "\(seed)°"
        }
        if p.name.isEmpty { return "TBD" }
        let cleaned = p.name.uppercased().filter { $0.isLetter }
        return String(cleaned.prefix(3))
    }
}

// MARK: - Phase Section

private struct BracketPhaseSection: View {
    let phase: BracketPhase

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: phase.icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(phaseColor)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(phaseColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title.uppercased())
                        .font(.subheadline.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(TournamentPalette.ink)
                    Text(phase.subtitle)
                        .font(.caption)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 4)

            ForEach(phase.slots) { slot in
                let slotSide = BracketSide.fromSlotId(slot.definition.id)
                VStack(spacing: 6) {
                    if slotSide != .none {
                        sideBanner(side: slotSide)
                    }
                    BracketMatchCard(
                        slot: slot,
                        side: slotSide,
                        isFinal: phase.id == "finale",
                        advancementText: advancementDescription(for: slot.definition, in: phase)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func sideBanner(side: BracketSide) -> some View {
        HStack(spacing: 6) {
            if side == .left {
                Image(systemName: "arrow.left")
                    .font(.caption2.weight(.bold))
                Text(side.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(side.label)
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.bold))
            }
        }
        .foregroundStyle(side.color)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(side.color.opacity(0.1))
        )
    }

    private func advancementDescription(
        for definition: TournamentEditionFormat.KnockoutSlotDefinition,
        in phase: BracketPhase
    ) -> String? {
        switch definition.id {
        case "preliminary_left":
            return "Quarto di finale vs 4° classificato"
        case "quarter_left":
            return "Semifinale vs 1° classificato"
        case "quarter_right":
            return "Semifinale vs 2° classificato"
        case "semifinal_left", "semifinal_right":
            return "Finale"
        case "final":
            return nil // No advancement from the final
        default:
            return nil
        }
    }

    private var phaseColor: Color {
        switch phase.id {
        case "spareggio": return TournamentPalette.inkMuted
        case "quarti": return TournamentPalette.accent
        case "semifinali": return TournamentPalette.warm
        case "finale": return TournamentPalette.success
        default: return TournamentPalette.accent
        }
    }
}

// MARK: - Match Card

private struct BracketMatchCard: View {
    let slot: BracketSlotState
    var side: BracketSide = .none
    let isFinal: Bool
    var advancementText: String? = nil

    private var isLive: Bool { slot.matchStatus == .live }
    private var isFinished: Bool { slot.matchStatus == .finished }

    var body: some View {
        NavigationLink(destination: MatchDetailView(match: slot.detailMatch)) {
            HStack(spacing: 0) {
                if side != .none {
                    Rectangle()
                        .fill(side.color)
                        .frame(width: 4)
                }

                VStack(spacing: 0) {
                matchHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Divider()
                    .background(TournamentPalette.divider)

                HStack(spacing: 0) {
                    teamSide(slot.home, goals: slot.homeGoals, isWinner: slot.winnerTeamId == slot.home.teamId)
                    scoreSeparator
                    teamSide(slot.away, goals: slot.awayGoals, isWinner: slot.winnerTeamId == slot.away.teamId)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)

                // Senza questa riga la finale Mormon ed.1 mostrava 1-1 e un
                // campione, senza far capire da dove uscisse. La card compatta
                // dell'albero (BracketCompactCard) lo faceva già, questa no:
                // il tabellone storico usa solo questa.
                if let penaltySuffix = slot.penaltySuffix {
                    Text(penaltySuffix.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TournamentPalette.warm)
                        .padding(.bottom, 10)
                }

                if let matchInfo = matchInfoText {
                    Divider()
                        .background(TournamentPalette.divider)

                    Text(matchInfo)
                        .font(.caption2)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .padding(.vertical, 8)
                }

                if let advancement = advancementText {
                    Divider()
                        .background(TournamentPalette.divider)

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(TournamentPalette.accent)

                        if isFinished, let winnerName = winnerDisplayName {
                            Text("\(winnerName) avanza: \(advancement)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(TournamentPalette.accent)
                        } else {
                            Text("Il vincitore va: \(advancement)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                    .fill(TournamentPalette.surfaceStrong.opacity(isLive ? 1 : 0.92))
            )
            .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                    .stroke(isLive ? TournamentPalette.success.opacity(0.5) : (side != .none ? side.color.opacity(0.4) : TournamentPalette.border), lineWidth: isLive ? 2 : 1)
            )
            .shadow(color: isLive ? TournamentPalette.success.opacity(0.15) : .black.opacity(0.05), radius: isLive ? 12 : 8, y: 4)
        }
        .buttonStyle(.tournamentPress)
    }

    @ViewBuilder
    private var matchHeader: some View {
        HStack {
            Text(slot.definition.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TournamentPalette.inkMuted)

            Spacer()

            HStack(spacing: 4) {
                if isLive {
                    Circle()
                        .fill(TournamentPalette.success)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: slot.matchStatus.icon)
                    .font(.caption2)
                Text(slot.matchStatus.label)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(slot.matchStatus.tint)
        }
    }

    private func teamSide(_ participant: BracketParticipantDisplay, goals: Int, isWinner: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if !participant.isPlaceholder, participant.teamId != nil {
                    TournamentTeamLogo(
                        urlString: participant.logo,
                        size: 40,
                        placeholderTint: TournamentPalette.accent
                    )
                } else if let seed = participant.seed {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TournamentPalette.surfaceMuted)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text("\(seed)\u{00B0}")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(TournamentPalette.surfaceMuted)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text("?")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(TournamentPalette.border)
                        )
                }
            }

            Text(participantName(participant))
                .font(.caption.weight(isWinner && isFinished ? .bold : .medium))
                .foregroundStyle(isWinner && isFinished ? TournamentPalette.ink : TournamentPalette.inkMuted)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)

            if slot.matchStatus != .upcoming {
                Text(slot.hasKnownScore ? "\(goals)" : "–")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(isWinner && isFinished ? TournamentPalette.accent : TournamentPalette.ink)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(isFinished && !isWinner && slot.winnerTeamId != nil ? 0.5 : 1)
    }

    @ViewBuilder
    private var scoreSeparator: some View {
        VStack(spacing: 4) {
            if slot.matchStatus == .upcoming {
                Text("VS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.top, 46)
            } else {
                Text("-")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(TournamentPalette.border)
                    .padding(.top, 68)
            }
        }
        .frame(width: 30)
    }

    private func participantName(_ p: BracketParticipantDisplay) -> String {
        if !p.name.isEmpty { return p.name }
        if let seed = p.seed { return "\(seed)\u{00B0} class." }
        return "TBD"
    }

    private var winnerDisplayName: String? {
        guard let winnerId = slot.winnerTeamId else { return nil }
        if winnerId == slot.home.teamId { return slot.home.name }
        if winnerId == slot.away.teamId { return slot.away.name }
        return nil
    }

    private var matchInfoText: String? {
        guard let match = slot.persistedMatch else { return nil }
        var parts: [String] = []
        if let time = match.matchTime, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(time)
        }
        if let campo = match.campo, !campo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Campo \(campo)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " \u{2022} ")
    }
}

// MARK: - Flow Arrow

private struct BracketFlowArrow: View {
    var body: some View {
        VStack(spacing: 2) {
            Rectangle()
                .fill(TournamentPalette.border)
                .frame(width: 2, height: 16)

            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)

            Rectangle()
                .fill(TournamentPalette.border)
                .frame(width: 2, height: 16)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Champion Card

private struct BracketChampionCard: View {
    let champion: BracketParticipantDisplay
    /// Il tabellone di consolazione ha il suo vincitore: stessa card, altro
    /// titolo, altrimenti in pagina compaiono due "CAMPIONE".
    var kicker: String = "CAMPIONE"

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.largeTitle)
                .foregroundStyle(TournamentPalette.warm)
                .shadow(color: TournamentPalette.warm.opacity(0.4), radius: 8, y: 4)

            Text(kicker)
                .font(.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(TournamentPalette.warm)

            TournamentTeamLogo(
                urlString: champion.logo,
                size: 64,
                placeholderTint: TournamentPalette.warm
            )

            Text(champion.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(TournamentPalette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: TournamentRadius.hero, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            TournamentPalette.warm.opacity(0.15),
                            TournamentPalette.surfaceStrong
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: TournamentRadius.hero, style: .continuous)
                .stroke(TournamentPalette.warm.opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: TournamentPalette.warm.opacity(0.15), radius: 16, y: 8)
    }
}

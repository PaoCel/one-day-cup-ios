import SwiftUI
import UIKit

struct TeamDetailView: View {
    private struct PlayerEventStats {
        var displayName: String = "Giocatore"
        var goals: Int = 0
        var assists: Int = 0
        var yellowCards: Int = 0
        var redCards: Int = 0
        var appearances: Int = 0
    }

    private struct TeamOverview {
        var goals: Int = 0
        var assists: Int = 0
        var yellowCards: Int = 0
        var redCards: Int = 0
    }

    private struct PlayerMetadata {
        var displayName: String
        var pictureURL: String?
    }

    private struct RankedPlayer {
        var identityKey: String
        var displayName: String
        var jersey: Int?
        var position: String?
        var pictureURL: String?
        var carica: CaricaSquadra?
        var stats: PlayerEventStats
    }

    private struct TeamRosterSharePayload: Identifiable {
        let id: String
        let teamName: String
        let teamLogoURL: String?
        let players: [TeamRosterSharePlayer]
        let primaryHex: String
        let secondaryHex: String
        let tournamentLogoURL: String?
        let tournamentLogoAsset: String?
    }

    let initialTeam: EditionTeam

    @Environment(AppState.self) private var appState

    @State private var livePlayers: [Player] = []
    @State private var isLoadingPlayers = true
    @State private var selectedTeamEdition: Int
    @State private var showAdminEditor = false
    @State private var isTogglingNotifications = false
    @State private var notificationErrorMessage: String?
    @State private var rosterSharePayload: TeamRosterSharePayload?
    @State private var selectedSection = 0
    @State private var showAllPlayerStats = false
    @State private var teamRanking: RankingEntry?
    @State private var showRanking = false
    /// Apre l'album già alla pagina di questa squadra, come il link della PWA.
    @State private var showAlbum = false

    // Scope stats cross-torneo (gemello del selettore statsScope della PWA):
    // pill per ogni torneo a cui la squadra ha partecipato + "Totale".
    private struct StatsScope: Identifiable, Equatable {
        let id: String          // tournamentId oppure "__all__"
        let name: String
        let color: Color?
    }

    @State private var statsScopes: [StatsScope] = []
    @State private var scopeMatchesByTid: [String: [Match]] = [:]
    @State private var selectedStatsScopeId: String?
    // Filtro edizione dentro lo scope: sul torneo corrente "Tutte le
    // edizioni" è un flag (la singola edizione resta il selettore di pagina);
    // sugli altri tornei è un filtro sul pool già caricato.
    @State private var statsAllEditionsCurrent = false
    @State private var scopedOtherEdition: Int?
    // Rose per (torneo, edizione) dagli snapshot partecipazioni: servono per
    // presenze corrette e per i giocatori delle edizioni passate (anche
    // rose legacy di soli nomi). Chiave "tid|ed".
    @State private var scopeRostersByTidEd: [String: FirestoreService.ParticipationRoster] = [:]

    init(team: EditionTeam) {
        self.initialTeam = team
        _selectedTeamEdition = State(initialValue: team.edition)
    }

    private var teamId: String { initialTeam.teamId }

    private var displayedTeam: EditionTeam {
        if let resolved = appState.editionTeam(for: teamId, edition: selectedTeamEdition) {
            return resolved
        }
        if selectedTeamEdition == initialTeam.edition {
            return initialTeam
        }
        return EditionTeam(
            edition: selectedTeamEdition,
            team: appState.teams.first { $0.id == teamId },
            participation: nil,
            preferLiveTeamData: selectedTeamEdition == appState.activeEdition
        )
    }

    private var teamEditions: [Int] {
        // `editions(forTeamId:)` somma anche `ultimeEdizioni` del doc squadra,
        // che è GLOBALE: dentro il Multipalo compariva l'"Edizione 1" della
        // Mormon. `tournamentEditions` nasce già filtrato per torneo (stesso
        // fix fatto nell'elenco squadre).
        let scoped = initialTeam.tournamentEditions
        if !scoped.isEmpty { return scoped.sorted(by: >) }
        let editions = appState.editions(forTeamId: teamId)
        return editions.isEmpty ? [selectedTeamEdition] : editions
    }

    private var editionStandings: [StandingsEntry] {
        appState.standings(for: selectedTeamEdition)
    }

    private var standingsEntry: StandingsEntry? {
        editionStandings.first { $0.teamId == teamId }
    }

    private var position: Int? {
        guard let standingsEntry else { return nil }
        return editionStandings.firstIndex { $0.teamId == standingsEntry.teamId }.map { $0 + 1 }
    }

    private var archivedRoster: [EditionParticipation.PlayerSnapshot] {
        displayedTeam.rosterSnapshots.sorted {
            ($0.numero ?? 99, $0.nome ?? "") < ($1.numero ?? 99, $1.nome ?? "")
        }
    }

    private var usesSnapshotRoster: Bool {
        !archivedRoster.isEmpty && (
            selectedTeamEdition != appState.activeEdition ||
            (!isLoadingPlayers && livePlayers.isEmpty)
        )
    }

    private var rosterCount: Int {
        usesSnapshotRoster ? archivedRoster.count : livePlayers.count
    }

    private var editionMatches: [Match] {
        appState.allMatches.filter {
            $0.edizione == selectedTeamEdition &&
            ($0.team1 == teamId || $0.team2 == teamId)
        }
    }

    private var completedOrLiveMatches: [Match] {
        editionMatches.filter { $0.isPlayed || $0.isStarted }
    }

    private var playerMetadataByKey: [String: PlayerMetadata] {
        var metadata: [String: PlayerMetadata] = [:]

        for player in livePlayers {
            let item = PlayerMetadata(
                displayName: player.nomeCompleto,
                pictureURL: player.displayPhotoURL
            )
            for key in statsKeys(playerId: player.id, alternateId: player.playerAuthUid, name: player.nomeCompleto) {
                metadata[key] = item
            }
        }

        for snapshot in archivedRoster {
            let item = PlayerMetadata(
                displayName: snapshot.nome ?? "Giocatore",
                pictureURL: snapshot.pictureURL
            )
            for key in statsKeys(playerId: snapshot.giocatoreId, alternateId: nil, name: snapshot.nome) {
                if metadata[key] == nil {
                    metadata[key] = item
                }
            }
        }

        return metadata
    }

    private var currentTournamentId: String {
        appState.tournamentSelectionStore.currentTournamentId
    }

    /// Scope effettivo: se le pill torneo non ci sono (squadra mono-torneo)
    /// vale il torneo corrente.
    private var effectiveStatsScopeId: String {
        (statsScopes.isEmpty ? nil : selectedStatsScopeId) ?? currentTournamentId
    }

    /// Edizioni selezionabili per lo scope corrente (pill "Edizione X").
    /// NON usa teamEditions: quello unisce primaEdizione/ultimeEdizioni della
    /// squadra GLOBALE e in un torneo nuovo mostrerebbe le edizioni dell'altro
    /// torneo. Qui contano solo partite e partecipazioni del torneo scelto.
    private var statsEditionOptions: [Int] {
        let sid = effectiveStatsScopeId
        if sid == "__all__" { return [] }
        var eds = Set<Int>()
        if sid == currentTournamentId {
            for m in appState.allMatches where m.team1 == teamId || m.team2 == teamId {
                eds.insert(m.edizione)
            }
        } else {
            for m in scopeMatchesByTid[sid] ?? [] where m.team1 == teamId || m.team2 == teamId {
                eds.insert(m.edizione)
            }
        }
        for roster in scopeRostersByTidEd.values where roster.tournamentId == sid {
            eds.insert(roster.edition)
        }
        return eds.sorted(by: >)
    }

    /// Partite della squadra nello scope selezionato; nil = comportamento
    /// classico (torneo corrente, edizione selezionata dal picker).
    private var scopedTeamMatches: [Match]? {
        let sid = effectiveStatsScopeId
        if sid == currentTournamentId {
            // "Tutte le edizioni" del torneo corrente: pool già in appState.
            guard statsAllEditionsCurrent else { return nil }
            return appState.allMatches.filter {
                ($0.team1 == teamId || $0.team2 == teamId) && ($0.isPlayed || $0.isStarted)
            }
        }
        let pool: [Match]
        if sid == "__all__" {
            pool = scopeMatchesByTid.values.flatMap { $0 }
        } else {
            pool = scopeMatchesByTid[sid] ?? []
        }
        return pool.filter { m in
            guard m.team1 == teamId || m.team2 == teamId, m.isPlayed || m.isStarted else { return false }
            if sid != "__all__", let ed = scopedOtherEdition { return m.edizione == ed }
            return true
        }
    }

    /// Membri della rosa per la (torneo, edizione) di una partita: presenze
    /// accreditate solo a chi era in rosa in QUELLA edizione. Senza snapshot
    /// si credita tutta la rosa (legacy). La rosa viva copre i nuovi arrivi
    /// dell'edizione attiva.
    private func statsMemberKeys(for match: Match) -> Set<String>? {
        let rawTid = match.tournamentId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tid = rawTid.isEmpty ? "multipalo" : rawTid
        guard let roster = scopeRostersByTidEd["\(tid)|\(match.edizione)"] else { return nil }
        var keys = Set<String>()
        for pid in roster.playerIds { keys.insert("id:\(pid)") }
        for name in roster.playerNames {
            if let n = Player.normalizedLookupName(from: name) { keys.insert("name:\(n)") }
        }
        if tid == currentTournamentId && match.edizione == appState.activeEdition {
            for player in livePlayers {
                statsKeys(playerId: player.id, alternateId: player.playerAuthUid, name: player.nomeCompleto)
                    .forEach { keys.insert($0) }
                if let n = Player.normalizedLookupName(from: player.nomeCompleto) { keys.insert("name:\(n)") }
            }
        }
        return keys.isEmpty ? nil : keys
    }

    /// Rosa per le righe stats negli scope cross-edizione/torneo: snapshot
    /// delle edizioni coinvolte (anche rose legacy di soli nomi, per chi non
    /// è più in squadra) uniti alla rosa viva. nil = vista classica.
    private func scopeRosterEntriesForStats() -> [(key: String, displayName: String)]? {
        guard scopedTeamMatches != nil, !scopeRostersByTidEd.isEmpty else { return nil }
        let sid = effectiveStatsScopeId

        var entries: [(key: String, displayName: String)] = []
        var seenKeys = Set<String>()
        var seenNames = Set<String>()
        func add(key: String?, name: String) {
            guard let key else { return }
            let norm = Player.normalizedLookupName(from: name) ?? name.lowercased()
            if seenKeys.contains(key) || seenNames.contains(norm) { return }
            seenKeys.insert(key)
            seenNames.insert(norm)
            entries.append((key, name))
        }

        // La rosa viva entra per prima: vince la riga con nome/foto attuali.
        let coversCurrent = sid == "__all__" || sid == currentTournamentId
        if coversCurrent {
            for player in livePlayers {
                add(
                    key: statsKeys(playerId: player.id, alternateId: player.playerAuthUid, name: player.nomeCompleto).first,
                    name: player.nomeCompleto
                )
            }
        }

        for roster in scopeRostersByTidEd.values {
            if sid != "__all__" && roster.tournamentId != sid { continue }
            if sid != "__all__" && sid != currentTournamentId,
               let ed = scopedOtherEdition, roster.edition != ed { continue }
            for name in roster.displayNames {
                add(key: statKey(playerId: nil, name: name), name: name)
            }
        }

        return entries.isEmpty ? nil : entries
    }

    private var teamStatsByPlayer: [String: PlayerEventStats] {
        var stats: [String: PlayerEventStats] = [:]

        let rosterEntries: [(key: String, displayName: String)] = scopeRosterEntriesForStats() ?? {
            if usesSnapshotRoster {
                return archivedRoster.compactMap { snapshot in
                    guard let key = statKey(playerId: snapshot.giocatoreId, name: snapshot.nome) else { return nil }
                    return (key, snapshot.nome ?? "Giocatore")
                }
            }
            return livePlayers.compactMap { player in
                statsKeys(playerId: player.id, alternateId: player.playerAuthUid, name: player.nomeCompleto)
                    .first
                    .map { ($0, player.nomeCompleto) }
            }
        }()

        for rosterEntry in rosterEntries {
            stats[rosterEntry.key] = PlayerEventStats(displayName: rosterEntry.displayName)
        }

        // Alias nome→chiave: rose vecchie per nome, eventi nuovi per id (e
        // viceversa). Senza il ponte, gol 2025 e presenze 2026 dello stesso
        // giocatore finirebbero su due righe diverse.
        var aliasByName: [String: String] = [:]
        for entry in rosterEntries {
            if let norm = Player.normalizedLookupName(from: entry.displayName), aliasByName[norm] == nil {
                aliasByName[norm] = entry.key
            }
        }
        func resolveKey(_ raw: String?, name: String?) -> String? {
            guard let raw else { return nil }
            if stats[raw] != nil { return raw }
            if let norm = Player.normalizedLookupName(from: name), let alias = aliasByName[norm] {
                return alias
            }
            return raw
        }
        let isScoped = scopedTeamMatches != nil

        let orderedMatches = (scopedTeamMatches ?? completedOrLiveMatches).sorted {
            if $0.giornata != $1.giornata {
                return $0.giornata < $1.giornata
            }
            return ($0.matchTime ?? "") < ($1.matchTime ?? "")
        }

        var pendingSuspensions = Set<String>()

        for match in orderedMatches {
            let activeSuspensions = pendingSuspensions
            pendingSuspensions.removeAll()

            let members = isScoped ? statsMemberKeys(for: match) : nil
            for rosterEntry in rosterEntries where !activeSuspensions.contains(rosterEntry.key) {
                if let members {
                    let nameKey = Player.normalizedLookupName(from: rosterEntry.displayName).map { "name:\($0)" }
                    let isMember = members.contains(rosterEntry.key) || (nameKey.map { members.contains($0) } ?? false)
                    if !isMember { continue }
                }
                stats[rosterEntry.key, default: PlayerEventStats(displayName: rosterEntry.displayName)].appearances += 1
            }

            for event in match.safeEventi where event.squadraId == teamId {
                if let playerKey = resolveKey(statKey(playerId: event.giocatoreId, name: event.giocatoreNome), name: event.giocatoreNome) {
                    var entry = stats[playerKey] ?? PlayerEventStats(displayName: event.giocatoreNome ?? "Giocatore")

                    if entry.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       let playerName = event.giocatoreNome {
                        entry.displayName = playerName
                    }

                    switch event.tipo {
                    case "gol", "rigore_segnato", "punizione_segnata":
                        entry.goals += 1
                    case "assist":
                        entry.assists += 1
                    case "ammonizione":
                        entry.yellowCards += 1
                    case "espulsione":
                        entry.redCards += 1
                        pendingSuspensions.insert(playerKey)
                    default:
                        break
                    }

                    stats[playerKey] = entry
                }

                if ["gol", "rigore_segnato", "punizione_segnata"].contains(event.tipo),
                   let assistName = event.assistName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !assistName.isEmpty,
                   let assistKey = resolveKey(statKey(playerId: event.assistPlayerId, name: assistName), name: assistName) {
                    var assistEntry = stats[assistKey] ?? PlayerEventStats(displayName: assistName)
                    assistEntry.assists += 1
                    stats[assistKey] = assistEntry
                }
            }
        }

        return stats
    }

    private var teamOverview: TeamOverview {
        var overview = TeamOverview()

        for match in (scopedTeamMatches ?? completedOrLiveMatches) {
            overview.goals += match.team1 == teamId ? match.team1Goals : match.team2Goals
        }

        for playerStats in teamStatsByPlayer.values {
            overview.assists += playerStats.assists
            overview.yellowCards += playerStats.yellowCards
            overview.redCards += playerStats.redCards
        }

        return overview
    }

    // Rosa normalizzata: snapshot d'edizione o rosa viva, con le statistiche
    // già agganciate. La usano sia il tab Rosa sia quello Statistiche.
    // Negli scope cross-edizione le righe vengono dall'unione delle rose
    // coinvolte (chi ha lasciato la squadra compare senza foto/numero).
    private var rosterPlayers: [RankedPlayer] {
        if selectedSection == 1, let scopedEntries = scopeRosterEntriesForStats() {
            let statsMap = teamStatsByPlayer
            return scopedEntries.map { entry in
                let live = livePlayers.first {
                    Player.normalizedLookupName(from: $0.nomeCompleto) == Player.normalizedLookupName(from: entry.displayName)
                }
                return RankedPlayer(
                    identityKey: entry.key,
                    displayName: live?.nomeCompleto ?? entry.displayName,
                    jersey: live?.numeroMaglia,
                    position: live?.positionPrimary,
                    pictureURL: live?.displayPhotoURL,
                    carica: live?.carica,
                    stats: statsMap[entry.key] ?? PlayerEventStats(displayName: entry.displayName)
                )
            }
        }

        if usesSnapshotRoster {
            return archivedRoster.map { snapshot in
                RankedPlayer(
                    identityKey: statKey(
                        playerId: snapshot.giocatoreId,
                        name: snapshot.nome
                    ) ?? "name:\(snapshot.nome ?? "giocatore")",
                    displayName: snapshot.nome ?? "Giocatore",
                    jersey: snapshot.numero,
                    position: snapshot.ruolo,
                    pictureURL: snapshot.pictureURL,
                    carica: snapshot.carica,
                    stats: statsForSnapshot(snapshot)
                )
            }
        }

        return livePlayers.map { player in
            RankedPlayer(
                identityKey: statsKeys(
                    playerId: player.id,
                    alternateId: player.playerAuthUid,
                    name: player.nomeCompleto
                ).first ?? "name:\(player.nomeCompleto)",
                displayName: player.nomeCompleto,
                jersey: player.numeroMaglia,
                position: player.positionPrimary,
                pictureURL: player.displayPhotoURL,
                carica: player.carica,
                stats: statsForPlayer(player)
            )
        }
    }

    // Ordine del mockup: chi incide di più in cima (gol + assist).
    private var rankedPlayerStats: [RankedPlayer] {
        rosterPlayers.sorted { lhs, rhs in
            let lhsScore = lhs.stats.goals + lhs.stats.assists
            let rhsScore = rhs.stats.goals + rhs.stats.assists
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.stats.goals != rhs.stats.goals { return lhs.stats.goals > rhs.stats.goals }
            if lhs.stats.appearances != rhs.stats.appearances { return lhs.stats.appearances > rhs.stats.appearances }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private var rosterSubtitle: String {
        if rosterCount == 0 {
            return "Nessun giocatore registrato"
        }

        return "\(rosterCount) giocatori registrati"
    }

    private var rosterFallbackNote: String? {
        guard selectedTeamEdition != appState.activeEdition,
              archivedRoster.isEmpty,
              !livePlayers.isEmpty else {
            return nil
        }

        return "Per questa edizione non esiste uno snapshot dedicato: viene mostrata la rosa corrente."
    }

    private var isAdmin: Bool {
        appState.authService.userRole == .admin
    }

    private var canOpenAdminEditor: Bool {
        isAdmin && !teamId.isEmpty
    }

    private var isFollowingTeamNotifications: Bool {
        appState.notificationService.isSubscribedToTeam(
            teamId: displayedTeam.teamId,
            edition: selectedTeamEdition
        )
    }

    /// Posizione e punteggio nel ranking generale. Compare solo se la squadra
    /// c'è: finché la function non ha calcolato non si mostra un buco.
    @ViewBuilder
    private var rankingBadge: some View {
        if let ranking = teamRanking {
            Button {
                showRanking = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TournamentPalette.accent)
                        .frame(width: 38, height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(TournamentPalette.accent.opacity(0.14))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("RANKING")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(TournamentPalette.inkMuted)
                        Text("\(ranking.position)° posto")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TournamentPalette.ink)
                    }

                    Spacer(minLength: 8)

                    Text(ranking.scoreLabel)
                        .font(.title3.weight(.black))
                        .foregroundStyle(TournamentPalette.accent)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
                .tournamentCard()
            }
            .buttonStyle(.tournamentPress)
        }
    }

    private func loadTeamRanking() async {
        let all = (try? await appState.firestoreService.fetchRanking(
            tournamentId: appState.currentTournamentId
        )) ?? []
        teamRanking = all.first { $0.teamId == teamId }
    }

    var body: some View {
        TournamentScreen {
            ScrollView {
                VStack(spacing: 14) {
                    teamHeader
                    rankingBadge
                    SchedaTabs(
                        tabs: [
                            SchedaTab(title: "Rosa", icon: "person.2.fill"),
                            SchedaTab(title: "Statistiche", icon: "chart.bar.fill")
                        ],
                        selection: $selectedSection
                    )

                    if selectedSection == 0 {
                        rosterCard
                    } else {
                        if statsScopes.count > 1 || statsEditionOptions.count > 1 {
                            statsScopeStrip
                        }
                        teamOverviewCard
                        playerStatsCard
                        ArchiveIncompleteNote()
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle(displayedTeam.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if teamEditions.count > 1 {
                    teamEditionMenu
                }

                // Il tasto Condividi sta nella barra azioni sotto il nome
                // (etichettato): qui c'era un secondo bottone identico.

                if !displayedTeam.teamId.isEmpty {
                    TournamentNotificationBellButton(
                        isActive: isFollowingTeamNotifications,
                        isBusy: isTogglingNotifications,
                        accessibilityLabel: isFollowingTeamNotifications
                            ? "Disattiva notifiche squadra"
                            : "Attiva notifiche squadra"
                    ) {
                        Task { await toggleTeamNotifications() }
                    }
                }

                if canOpenAdminEditor {
                    Button {
                        showAdminEditor = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .task(id: selectedTeamEdition) {
            await loadLivePlayers()
        }
        .task(id: currentTournamentId) {
            resetStatsScopeState()
            await loadStatsScopes()
            await loadTeamRanking()
        }
        .navigationDestination(isPresented: $showAlbum) {
            AlbumPagesView(startTeamId: teamId)
        }
        .sheet(isPresented: $showRanking) {
            NavigationStack {
                RankingView()
                    .navigationTitle("Ranking")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDragIndicator(.visible)
        }
        .refreshable {
            await loadLivePlayers()
        }
        .sheet(isPresented: $showAdminEditor, onDismiss: {
            Task {
                await appState.loadTeams()
                await loadLivePlayers()
            }
        }) {
            AdminTeamEditorView(teamId: displayedTeam.teamId)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $rosterSharePayload) { payload in
            TeamRosterShareView(
                teamName: payload.teamName,
                teamLogoURL: payload.teamLogoURL,
                players: payload.players,
                primaryHex: payload.primaryHex,
                secondaryHex: payload.secondaryHex,
                tournamentLogoURL: payload.tournamentLogoURL,
                tournamentLogoAsset: payload.tournamentLogoAsset
            )
        }
        .alert("Notifiche squadra", isPresented: Binding(
            get: { notificationErrorMessage != nil },
            set: { if !$0 { notificationErrorMessage = nil } }
        )) {
            if appState.notificationService.authorizationState == .denied {
                Button("Impostazioni") { openSettings() }
            }
            Button("OK", role: .cancel) {
                notificationErrorMessage = nil
            }
        } message: {
            Text(notificationErrorMessage ?? "")
        }
    }

    // Identità squadra come nel mockup: logo nudo a sinistra, dati a destra su
    // righe. Prima era una fascia coi due colori squadra e il logo a cavallo,
    // che rubava mezza schermata e non diceva nulla in più.
    private var teamHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                TournamentTeamLogo(
                    urlString: displayedTeam.logoURL,
                    size: 76,
                    placeholderTint: Color(hex: displayedTeam.colors.principale) ?? TournamentPalette.accent
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text(displayedTeam.displayName.uppercased())
                        .font(.system(size: 24, weight: .black))
                        .italic()
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    VStack(alignment: .leading, spacing: 7) {
                        if !displayedTeam.representative.nome.isEmpty {
                            headerRow(icon: "person.fill", text: displayedTeam.representative.nome, badge: "CAP")
                        }
                        headerRow(icon: "person.2.fill", text: "\(rosterCount) giocatori")
                        headerRow(icon: "calendar", text: "Edizione \(String(selectedTeamEdition))")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SchedaActionBar(actions: headerActions)
        }
        .tournamentCard()
    }

    private var headerActions: [SchedaAction] {
        var actions: [SchedaAction] = []

        if canOpenAdminEditor {
            actions.append(SchedaAction(title: "Modifica", icon: "pencil") {
                showAdminEditor = true
            })
        }

        // L'album di questa edizione, aperto già alla pagina della squadra.
        // Solo per l'edizione che l'album racconta: le rose passate hanno la
        // storia, non le figurine.
        if selectedTeamEdition == appState.selectedEdition,
           appState.editionParticipations.contains(where: { $0.squadraId == teamId }) {
            actions.append(SchedaAction(title: "Album", icon: "rectangle.portrait.on.rectangle.portrait.angled") {
                showAlbum = true
            })
        }

        actions.append(SchedaAction(title: "Aggiorna", icon: "arrow.clockwise") {
            Task { await loadLivePlayers() }
        })

        return actions
    }

    private func headerRow(icon: String, text: String, badge: String? = nil) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TournamentPalette.accent)
                .frame(width: 16)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
                .lineLimit(1)

            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .heavy))
                    .kerning(0.6)
                    .foregroundStyle(TournamentPalette.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(TournamentPalette.accentSoft)
                    .clipShape(Capsule())
            }
        }
    }

    // Panoramica: gare/vittorie/gol fatti/gol subiti arrivano dalla classifica
    // dell'edizione, che le calcola già; qui non si ricalcola niente.
    // Pill per torneo + Totale (colorate, solo con ≥2 tornei) e pill
    // edizione (neutre): stessa gerarchia della PWA.
    /// Torneo ed edizione in due menu etichettati. Erano due file di pill che
    /// scorrevano fuori schermo e non dicevano cosa fossero: la riga dei tornei
    /// si leggeva come un cambio edizione con dentro "l'altro torneo".
    private var statsScopeStrip: some View {
        HStack(spacing: 10) {
            if statsScopes.count > 1 {
                statsScopeMenu(
                    label: "Torneo",
                    value: effectiveStatsScopeId == "__all__"
                        ? "Totale OneDay Cup"
                        : (statsScopes.first { $0.id == effectiveStatsScopeId }?.name ?? "Torneo").scopeMenuName
                ) {
                    ForEach(statsScopes) { scope in
                        Button(scope.name) {
                            selectedStatsScopeId = scope.id
                            statsAllEditionsCurrent = false
                            scopedOtherEdition = nil
                        }
                    }
                }
            }

            if statsEditionOptions.count > 1 {
                let sid = effectiveStatsScopeId
                let isCurrent = sid == currentTournamentId
                let currentValue: String = {
                    if isCurrent {
                        return statsAllEditionsCurrent ? "Tutte" : String(selectedTeamEdition)
                    }
                    return scopedOtherEdition.map(String.init) ?? "Tutte"
                }()

                statsScopeMenu(label: "Edizione", value: currentValue) {
                    Button("Tutte le edizioni") {
                        if isCurrent { statsAllEditionsCurrent = true } else { scopedOtherEdition = nil }
                    }
                    // Le edizioni offerte sono sempre quelle del torneo
                    // selezionato, mai la lista globale.
                    ForEach(statsEditionOptions, id: \.self) { ed in
                        Button("Edizione \(ed)") {
                            if isCurrent {
                                statsAllEditionsCurrent = false
                                selectedTeamEdition = ed
                            } else {
                                scopedOtherEdition = ed
                            }
                        }
                    }
                }
            }
        }
    }

    private func statsScopeMenu<Content: View>(
        label: String,
        value: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .black))
                        .tracking(0.8)
                        .foregroundStyle(TournamentPalette.inkMuted)
                    Text(value)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TournamentPalette.accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(TournamentPalette.inkMuted.opacity(0.18), lineWidth: 1)
            )
        }
    }

    private func loadStatsScopes() async {
        guard scopeRostersByTidEd.isEmpty, !teamId.isEmpty else { return }
        guard let all = try? await appState.firestoreService.fetchParticipationRosters() else { return }
        let mine = all.filter { $0.teamId == teamId }
        guard !mine.isEmpty else { return }

        var rostersByKey: [String: FirestoreService.ParticipationRoster] = [:]
        var tids: [String] = []
        for roster in mine {
            rostersByKey["\(roster.tournamentId)|\(roster.edition)"] = roster
            if !tids.contains(roster.tournamentId) { tids.append(roster.tournamentId) }
        }

        let currentTid = currentTournamentId
        tids.sort { a, b in
            if a == currentTid { return true }
            if b == currentTid { return false }
            return a < b
        }

        var byTid: [String: [Match]] = [:]
        for tid in tids where tid != currentTid {
            byTid[tid] = (try? await appState.firestoreService.fetchMatches(tournamentId: tid)) ?? []
        }

        scopeRostersByTidEd = rostersByKey
        scopeMatchesByTid = byTid

        if tids.count >= 2 {
            let known = appState.tournamentSelectionStore.availableTournaments
            var scopes: [StatsScope] = tids.map { tid in
                let meta = known.first { $0.id == tid }
                return StatsScope(id: tid, name: meta?.displayName ?? tid, color: meta?.branding.primaryColor)
            }
            scopes.append(StatsScope(id: "__all__", name: "Totale", color: nil))
            statsScopes = scopes
            selectedStatsScopeId = currentTid
        }
    }

    // Aggregato calcolato dalle partite dello scope cross-torneo: la
    // classifica (standingsEntry) esiste solo per il torneo corrente, quindi
    // con uno scope diverso gare/vittorie/gol si contano dalle partite.
    private struct ScopedAggregate {
        var played = 0
        var won = 0
        var goalsFor = 0
        var goalsAgainst = 0
    }

    private var scopedAggregate: ScopedAggregate? {
        guard let matches = scopedTeamMatches else { return nil }
        var agg = ScopedAggregate()
        for match in matches {
            let goalsFor = match.team1 == teamId ? match.team1Goals : match.team2Goals
            let goalsAgainst = match.team1 == teamId ? match.team2Goals : match.team1Goals
            agg.played += 1
            agg.goalsFor += goalsFor
            agg.goalsAgainst += goalsAgainst
            if goalsFor > goalsAgainst { agg.won += 1 }
        }
        return agg
    }

    private var overviewSubtitle: String {
        guard scopedTeamMatches != nil else {
            return "Edizione \(String(selectedTeamEdition))"
        }
        let sid = effectiveStatsScopeId
        if sid == "__all__" { return "Totale OneDay Cup" }
        let name = statsScopes.first { $0.id == sid }?.name
            ?? appState.tournamentSelectionStore.availableTournaments.first { $0.id == sid }?.displayName
            ?? "Questo torneo"
        if sid != currentTournamentId, let ed = scopedOtherEdition {
            return "\(name) · Edizione \(ed)"
        }
        return "\(name) · tutte le edizioni"
    }

    private var teamOverviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            TournamentSectionHeader(
                title: "Panoramica squadra",
                subtitle: overviewSubtitle
            )

            SchedaStatStrip(items: [
                SchedaStatItem(value: "\(scopedAggregate?.played ?? standingsEntry?.played ?? 0)", label: "Gare", icon: "soccerball"),
                SchedaStatItem(value: "\(scopedAggregate?.won ?? standingsEntry?.won ?? 0)", label: "Vittorie", icon: "trophy.fill", tint: TournamentPalette.warm),
                SchedaStatItem(value: "\(scopedAggregate?.goalsFor ?? standingsEntry?.goalsFor ?? teamOverview.goals)", label: "Gol fatti", icon: "target", tint: TournamentPalette.accent),
                SchedaStatItem(value: "\(scopedAggregate?.goalsAgainst ?? standingsEntry?.goalsAgainst ?? 0)", label: "Gol subiti", icon: "shield.fill", tint: TournamentPalette.inkMuted),
                SchedaStatItem(value: "\(winPercent)%", label: "% vittorie", percent: winRatio)
            ])

            Divider()

            SchedaStatStrip(items: [
                // Posizione e punti hanno senso solo nella classifica del
                // torneo corrente: con scope cross-torneo restano fuori.
                SchedaStatItem(value: scopedAggregate == nil ? (position.map { "#\($0)" } ?? "—") : "—", label: "Posizione", icon: "list.number", tint: TournamentPalette.inkMuted),
                SchedaStatItem(value: scopedAggregate == nil ? "\(standingsEntry?.points ?? 0)" : "—", label: "Punti", icon: "star.fill", tint: TournamentPalette.warm),
                SchedaStatItem(value: "\(teamOverview.assists)", label: "Assist", icon: "figure.soccer", tint: TournamentPalette.success),
                SchedaStatItem(value: "\(teamOverview.yellowCards)", label: "Gialli", icon: "rectangle.fill", tint: TournamentPalette.warm),
                SchedaStatItem(value: "\(teamOverview.redCards)", label: "Rossi", icon: "rectangle.fill", tint: TournamentPalette.danger)
            ])
        }
        .tournamentCard()
    }

    private var winPercent: Int {
        if let agg = scopedAggregate {
            guard agg.played > 0 else { return 0 }
            return Int((Double(agg.won) / Double(agg.played) * 100).rounded())
        }
        guard let entry = standingsEntry, entry.played > 0 else { return 0 }
        return Int((Double(entry.won) / Double(entry.played) * 100).rounded())
    }

    private var winRatio: Double {
        if let agg = scopedAggregate {
            guard agg.played > 0 else { return 0 }
            return Double(agg.won) / Double(agg.played)
        }
        guard let entry = standingsEntry, entry.played > 0 else { return 0 }
        return Double(entry.won) / Double(entry.played)
    }

    // Una riga per giocatore con gol, assist e cartellini insieme: sostituisce
    // "Top marcatori" e "Top assist", che ripetevano gli stessi nomi in due
    // liste separate.
    private var playerStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                TournamentSectionHeader(title: "Statistiche individuali", subtitle: nil)

                Spacer(minLength: 12)

                if rankedPlayerStats.count > 5 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAllPlayerStats.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Text(showAllPlayerStats ? "Mostra meno" : "Vedi tutti")
                                .font(.system(size: 11, weight: .heavy))
                                .kerning(0.4)
                            Image(systemName: showAllPlayerStats ? "arrow.up" : "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(TournamentPalette.accent)
                    }
                    .buttonStyle(.tournamentPress)
                }
            }

            if rankedPlayerStats.isEmpty {
                Text("Nessun giocatore in rosa.")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(visiblePlayerStats.enumerated()), id: \.offset) { index, entry in
                    NavigationLink(destination: statsPlayerDestination(for: entry)) {
                        SchedaPlayerRow(
                            rank: index + 1,
                            name: entry.displayName,
                            jersey: entry.jersey,
                            position: entry.position,
                            pictureURL: entry.pictureURL,
                            goals: entry.stats.goals,
                            assists: entry.stats.assists,
                            yellows: entry.stats.yellowCards,
                            reds: entry.stats.redCards,
                            appearances: entry.stats.appearances
                        )
                    }
                    .buttonStyle(.tournamentPress)
                }
            }
        }
        .tournamentCard()
    }

    private var visiblePlayerStats: [RankedPlayer] {
        showAllPlayerStats ? rankedPlayerStats : Array(rankedPlayerStats.prefix(5))
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Rosa",
                subtitle: rosterSubtitle
            )

            if let rosterFallbackNote {
                Text(rosterFallbackNote)
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            if isLoadingPlayers && !usesSnapshotRoster {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(TournamentPalette.accent)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if usesSnapshotRoster {
                if archivedRoster.isEmpty {
                    Text("Per questa edizione non ci sono giocatori registrati.")
                        .font(.subheadline)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(archivedRoster.enumerated()), id: \.offset) { index, snapshot in
                        NavigationLink(destination: HistoricPlayerDetailView(profile: historicProfile(for: snapshot))) {
                            archivedPlayerRow(snapshot)
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
            } else if livePlayers.isEmpty {
                Text("Per questa squadra non risultano giocatori registrati.")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(livePlayers.enumerated()), id: \.offset) { index, player in
                    NavigationLink(destination: playerDestination(for: player)) {
                        livePlayerRow(player)
                    }
                    .buttonStyle(.tournamentPress)
                }
            }
        }
        .tournamentCard()
    }

    private func archivedPlayerRow(_ player: EditionParticipation.PlayerSnapshot) -> some View {
        SchedaPlayerRow(
            rank: nil,
            name: player.nome ?? "Giocatore",
            jersey: player.numero,
            position: player.ruolo,
            pictureURL: player.pictureURL,
            goals: statsForSnapshot(player).goals,
            assists: statsForSnapshot(player).assists,
            yellows: statsForSnapshot(player).yellowCards,
            reds: statsForSnapshot(player).redCards,
            appearances: statsForSnapshot(player).appearances,
            carica: player.carica
        )
    }

    private func livePlayerRow(_ player: Player) -> some View {
        let stats = statsForPlayer(player)
        return SchedaPlayerRow(
            rank: nil,
            name: player.nomeCompleto,
            jersey: player.numeroMaglia,
            position: player.positionPrimary,
            pictureURL: player.displayPhotoURL,
            goals: stats.goals,
            assists: stats.assists,
            yellows: stats.yellowCards,
            reds: stats.redCards,
            appearances: stats.appearances,
            carica: player.carica
        )
    }

    private var teamEditionMenu: some View {
        Menu {
            ForEach(teamEditions.sorted(by: >), id: \.self) { edition in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTeamEdition = edition
                    }
                } label: {
                    if edition == selectedTeamEdition {
                        Label("Edizione \(String(edition))", systemImage: "checkmark")
                    } else {
                        Text("Edizione \(String(edition))")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                // Il solo numero non diceva a cosa servisse il bottone.
                Image(systemName: "calendar")
                    .font(.caption.weight(.bold))
                Text("Ed. \(String(selectedTeamEdition))")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(TournamentPalette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(TournamentPalette.surfaceStrong.opacity(0.94))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(TournamentPalette.border, lineWidth: 1)
            )
        }
    }

    private func statKey(playerId: String?, name: String?) -> String? {
        if let normalizedId = normalizedId(playerId) {
            return "id:\(normalizedId)"
        }
        if let normalizedName = Player.normalizedLookupName(from: name) {
            return "name:\(normalizedName)"
        }
        return nil
    }

    private func statsKeys(playerId: String?, alternateId: String?, name: String?) -> [String] {
        var keys: [String] = []

        if let normalizedId = normalizedId(playerId) {
            keys.append("id:\(normalizedId)")
        }

        if let normalizedAlternateId = normalizedId(alternateId),
           !keys.contains("id:\(normalizedAlternateId)") {
            keys.append("id:\(normalizedAlternateId)")
        }

        if let normalizedName = Player.normalizedLookupName(from: name),
           !keys.contains("name:\(normalizedName)") {
            keys.append("name:\(normalizedName)")
        }

        return keys
    }

    private func normalizedId(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resetStatsScopeState() {
        statsScopes = []
        scopeMatchesByTid = [:]
        selectedStatsScopeId = nil
        statsAllEditionsCurrent = false
        scopedOtherEdition = nil
        scopeRostersByTidEd = [:]
        showAllPlayerStats = false
    }

    private func statsForPlayer(_ player: Player) -> PlayerEventStats {
        for key in statsKeys(playerId: player.id, alternateId: player.playerAuthUid, name: player.nomeCompleto) {
            if let stats = teamStatsByPlayer[key] {
                return stats
            }
        }

        return PlayerEventStats(displayName: player.nomeCompleto)
    }

    private func statsForSnapshot(_ snapshot: EditionParticipation.PlayerSnapshot) -> PlayerEventStats {
        for key in statsKeys(playerId: snapshot.giocatoreId, alternateId: nil, name: snapshot.nome) {
            if let stats = teamStatsByPlayer[key] {
                return stats
            }
        }

        return PlayerEventStats(displayName: snapshot.nome ?? "Giocatore")
    }

    private func historicProfile(for snapshot: EditionParticipation.PlayerSnapshot) -> HistoricPlayerProfile {
        HistoricPlayerProfile(
            id: snapshot.giocatoreId ?? "\(displayedTeam.teamId)|\(snapshot.nome ?? UUID().uuidString)",
            playerId: snapshot.giocatoreId,
            displayName: snapshot.nome ?? "Giocatore",
            pictureURL: snapshot.pictureURL,
            teamId: displayedTeam.teamId,
            teamName: displayedTeam.displayName,
            edition: displayedTeam.edition,
            jerseyNumber: snapshot.numero,
            position: snapshot.ruolo,
            carica: snapshot.carica
        )
    }

    private func historicProfile(for player: Player) -> HistoricPlayerProfile {
        HistoricPlayerProfile(
            id: player.id ?? "\(displayedTeam.teamId)|\(player.nomeCompleto)",
            playerId: player.id ?? player.playerAuthUid,
            displayName: player.nomeCompleto,
            pictureURL: player.displayPhotoURL,
            teamId: displayedTeam.teamId,
            teamName: displayedTeam.displayName,
            edition: displayedTeam.edition,
            jerseyNumber: player.numeroMaglia,
            position: player.positionPrimary
        )
    }

    @ViewBuilder
    private func statsPlayerDestination(for entry: RankedPlayer) -> some View {
        let normalizedName = Player.normalizedLookupName(from: entry.displayName)

        if let player = livePlayers.first(where: {
            Player.normalizedLookupName(from: $0.nomeCompleto) == normalizedName
        }) {
            PlayerDetailView(player: player)
        } else if let snapshot = archivedRoster.first(where: {
            Player.normalizedLookupName(from: $0.nome) == normalizedName
        }) {
            HistoricPlayerDetailView(profile: historicProfile(for: snapshot))
        } else {
            let playerId = entry.identityKey.hasPrefix("id:")
                ? String(entry.identityKey.dropFirst(3))
                : nil
            let contextEdition = scopedOtherEdition ?? selectedTeamEdition
            HistoricPlayerDetailView(
                profile: HistoricPlayerProfile(
                    id: playerId ?? "\(teamId)|\(entry.identityKey)",
                    playerId: playerId,
                    displayName: entry.displayName,
                    pictureURL: entry.pictureURL,
                    teamId: teamId,
                    teamName: displayedTeam.displayName,
                    edition: contextEdition,
                    jerseyNumber: entry.jersey,
                    position: entry.position
                )
            )
        }
    }

    @ViewBuilder
    private func playerDestination(for player: Player) -> some View {
        if displayedTeam.edition == appState.selectedEdition {
            PlayerDetailView(player: player)
        } else {
            HistoricPlayerDetailView(profile: historicProfile(for: player))
        }
    }

    private func toggleTeamNotifications() async {
        guard !isTogglingNotifications else { return }
        isTogglingNotifications = true
        defer { isTogglingNotifications = false }

        do {
            let shouldEnable = !isFollowingTeamNotifications
            _ = try await appState.notificationService.setTeamSubscription(
                enabled: shouldEnable,
                teamId: displayedTeam.teamId,
                edition: selectedTeamEdition,
                cloudFunctionsService: appState.cloudFunctionsService
            )
        } catch {
            notificationErrorMessage = error.localizedDescription
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func loadLivePlayers() async {
        guard displayedTeam.hasCurrentTeamDocument, !teamId.isEmpty else {
            isLoadingPlayers = false
            livePlayers = []
            return
        }

        if !archivedRoster.isEmpty && displayedTeam.edition != appState.activeEdition {
            isLoadingPlayers = false
            return
        }

        isLoadingPlayers = true

        do {
            livePlayers = normalizedRoster(
                try await appState.firestoreService.fetchPlayers(teamId: teamId)
            )
        } catch {
            print("Errore caricamento rosa: \(error.localizedDescription)")
            livePlayers = []
        }

        isLoadingPlayers = false
    }

    private func normalizedRoster(_ players: [Player]) -> [Player] {
        var uniquePlayers: [String: Player] = [:]

        for player in players {
            uniquePlayers[player.stableRosterKey] = player
        }

        return uniquePlayers.values.sorted {
            let lhsNumber = $0.numeroMaglia ?? 99
            let rhsNumber = $1.numeroMaglia ?? 99
            if lhsNumber == rhsNumber {
                return $0.nomeCompleto.localizedCaseInsensitiveCompare($1.nomeCompleto) == .orderedAscending
            }
            return lhsNumber < rhsNumber
        }
    }

    private func makeRosterSharePayload() -> TeamRosterSharePayload {
        let sharePlayers: [TeamRosterSharePlayer]

        if usesSnapshotRoster {
            sharePlayers = archivedRoster.enumerated().map { index, snapshot in
                TeamRosterSharePlayer(
                    id: snapshot.giocatoreId ?? "\(displayedTeam.teamId)-snapshot-\(index)",
                    name: snapshot.nome ?? "Giocatore",
                    jerseyNumber: snapshot.numero,
                    photoURL: snapshot.pictureURL,
                    role: snapshot.ruolo,
                    carica: snapshot.carica
                )
            }
        } else {
            sharePlayers = livePlayers.enumerated().map { index, player in
                TeamRosterSharePlayer(
                    id: player.firestoreIdentifier ?? player.playerAuthUid ?? "\(displayedTeam.teamId)-live-\(index)",
                    name: player.nomeCompleto,
                    jerseyNumber: player.numeroMaglia,
                    photoURL: player.displayPhotoURL,
                    role: player.positionPrimary,
                    carica: player.carica
                )
            }
        }

        return TeamRosterSharePayload(
            id: "\(displayedTeam.teamId)-\(selectedTeamEdition)-roster",
            teamName: displayedTeam.displayName,
            teamLogoURL: displayedTeam.logoURL,
            players: sharePlayers,
            primaryHex: displayedTeam.colors.principale,
            secondaryHex: displayedTeam.colors.secondario,
            tournamentLogoURL: appState.currentBranding.logoURL?.absoluteString,
            tournamentLogoAsset: LocalTournamentLogos.assetName(for: currentTournamentId)
        )
    }
}

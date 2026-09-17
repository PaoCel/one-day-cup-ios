import SwiftUI
import FirebaseAuth
import UIKit

struct PlayerDetailView: View {
    let player: Player
    /// Aperta dal tap sulla push "figurina pronta": la lente parte gia' su.
    var apreLente = false

    @Environment(AppState.self) private var appState
    @State private var isTogglingNotifications = false
    @State private var notificationErrorMessage: String?
    @State private var selectedSection = 0
    /// La figurina a schermo pieno (lente). Stato della sola presentazione:
    /// resta nella View.
    @State private var mostraLente = false

    // Scope stats cross-torneo/edizione (gemello dei filtri della PWA):
    // una riga di storia per ogni (torneo, edizione, squadra) del giocatore.
    private struct ScopeHistoryRow: Equatable {
        let tid: String
        let ed: Int
        let teamId: String
        let teamName: String
    }
    private struct ScopeTournament: Identifiable, Equatable {
        let id: String
        let name: String
        let color: Color?
    }
    private struct ScopeBucket: Identifiable {
        let id: String
        let tid: String
        let edition: Int
        let teamName: String
        let stats: ComputedPlayerStats
    }

    @State private var scopeHistory: [ScopeHistoryRow] = []
    @State private var scopeMatchesByTid: [String: [Match]] = [:]
    @State private var awards: [PlayerAward] = []
    @State private var participationsByKey: [String: EditionParticipation] = [:]
    // Premi scritti sul doc edizione: i suoi, più quelli delle edizioni che ha
    // giocato (servono a non contraddire il capocannoniere calcolato).
    @State private var editionAwards: [FirestoreService.EditionAward] = []
    @State private var scopeTournaments: [ScopeTournament] = []
    @State private var selectedScopeTid: String?    // tid oppure "__all__"
    @State private var selectedScopeEdition: Int?   // nil = tutte le edizioni
    @State private var scopesReady = false

    private var team: EditionTeam? {
        let playerId = player.firestoreIdentifier
        let normalizedName = Player.normalizedLookupName(from: player.nomeCompleto)
        let participation = appState.editionParticipations.first { participation in
            participation.playerSnapshots.contains { snapshot in
                if let playerId, snapshot.giocatoreId == playerId {
                    return true
                }
                return Player.normalizedLookupName(from: snapshot.nome) == normalizedName
            }
        }
        guard let participation else { return nil }
        return appState.editionTeam(for: participation.squadraId)
    }

    private var computed: ComputedPlayerStats {
        Self.computeStats(
            playerId: player.firestoreIdentifier,
            playerName: player.nomeCompleto,
            teamId: team?.teamId,
            from: appState.matches
        )
    }

    private var playerMatches: [Match] {
        Self.matches(
            playerId: player.firestoreIdentifier,
            playerName: player.nomeCompleto,
            teamId: team?.teamId,
            from: appState.matches
        )
    }

    /// Partite del giocatore nello scope scelto (torneo + edizione). Senza
    /// scope caricato resta il comportamento storico: l'edizione corrente.
    private var scopedPlayerMatches: [Match] {
        guard scopesReady, let sid = selectedScopeTid else { return playerMatches }
        let rows = scopeHistory.filter { row in
            if sid != "__all__" && row.tid != sid { return false }
            if sid != "__all__", let ed = selectedScopeEdition, row.ed != ed { return false }
            return true
        }
        var seen = Set<String>()
        var out: [Match] = []
        for row in rows {
            let pool = (scopeMatchesByTid[row.tid] ?? []).filter {
                $0.edizione == row.ed && ($0.team1 == row.teamId || $0.team2 == row.teamId)
            }
            for match in pool {
                let key = match.id ?? UUID().uuidString
                if seen.insert(key).inserted { out.append(match) }
            }
        }
        return out
    }

    private var isCurrentUser: Bool {
        guard let uid = appState.authService.currentUser?.uid else { return false }
        return player.playerAuthUid == uid
    }

    private var notificationPlayerId: String? {
        player.firestoreIdentifier
    }

    private var notificationTeamId: String? {
        team?.teamId
    }

    private var isFollowingPlayerNotifications: Bool {
        appState.notificationService.isSubscribedToPlayer(
            playerId: notificationPlayerId,
            teamId: notificationTeamId,
            edition: appState.selectedEdition
        )
    }

    var body: some View {
        ZStack {
            (Color(hex: "#f8fafc") ?? TournamentPalette.backgroundTop)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if isCurrentUser {
                        HStack {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundStyle(TournamentPalette.accent)
                            Text("Questo sei tu")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(TournamentPalette.ink)
                            Spacer()
                        }
                        .tournamentCard()
                    }

                    headerCard

                    // La figurina **dopo** l'intestazione, non prima: sopra
                    // c'e' gia' il ritratto grande del giocatore, e la carta
                    // stampata a tutta larghezza sembrava la stessa foto due
                    // volte invece di un oggetto in piu'. Le statistiche della
                    // carta (PAC/SHO/DRI, da quiz autocompilato) restano
                    // chiuse dentro la carta: non si mescolano con quelle vere
                    // qui sotto, che sono partite e gol davvero giocati.
                    if let figurina = figurinaGiocatore {
                        figurinaScheda(figurina)
                    }

                    SchedaTabs(
                        tabs: [
                            SchedaTab(title: "Profilo", icon: "person.fill"),
                            SchedaTab(title: "Stats", icon: "chart.bar.fill"),
                            SchedaTab(title: "Partite", icon: "soccerball")
                        ],
                        selection: $selectedSection
                    )

                    switch selectedSection {
                    case 0:
                        computedStatsCard
                        detailsCard
                    case 1:
                        scopeFilterCard
                        performanceCard
                        awardsCard
                        if scopeBuckets.count >= 2 {
                            perTeamBreakdownCard
                        }
                        // Niente più link a "Carriera": diceva le stesse cose
                        // del filtro su "Totale OneDay Cup", con numeri diversi
                        // perché li prendeva da un altro aggregato.
                        ArchiveIncompleteNote()
                    default:
                        // Il filtro vale anche qui: prima le partite delle altre
                        // edizioni non erano raggiungibili da questa tab.
                        scopeFilterCard
                        if scopedPlayerMatches.isEmpty {
                            Text("Nessuna partita in questa selezione.")
                                .font(.subheadline)
                                .foregroundStyle(TournamentPalette.inkMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .tournamentCard()
                        } else {
                            recentMatchesCard
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle(player.nomeCompleto)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if notificationPlayerId != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    TournamentNotificationBellButton(
                        isActive: isFollowingPlayerNotifications,
                        isBusy: isTogglingNotifications,
                        accessibilityLabel: isFollowingPlayerNotifications
                            ? "Disattiva notifiche giocatore"
                            : "Attiva notifiche giocatore"
                    ) {
                        Task { await togglePlayerNotifications() }
                    }
                }
            }
        }
        .alert("Notifiche giocatore", isPresented: Binding(
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
        .task(id: appState.currentTournamentId) {
            resetStatsScopes()
            await loadStatsScopes()
        }
        // La lente copre tutto, barre comprese: è un oggetto in mano, non una
        // schermata dell'app. Niente "Apri la scheda" qui: la scheda è questa.
        .toolbar(mostraLente ? .hidden : .automatic, for: .navigationBar)
        .toolbar(mostraLente ? .hidden : .automatic, for: .tabBar)
        // La figurina puo' arrivare dopo la scheda (cache dell'album ancora
        // vuota): si apre al primo momento in cui c'e', una volta sola.
        .task(id: figurinaGiocatore?.image) {
            if apreLente, !mostraLente, figurinaGiocatore != nil {
                withAnimation(.easeOut(duration: 0.15)) { mostraLente = true }
            }
        }
        .overlay {
            if mostraLente, let figurina = figurinaGiocatore {
                FigurinaLenteView(
                    figurina: figurina,
                    nome: player.nomeCompleto,
                    retroURL: appState.currentBranding.cardBackURL?.absoluteString,
                    chiudi: { withAnimation(.easeOut(duration: 0.15)) { mostraLente = false } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: mostraLente)
    }

    // MARK: - Figurina

    /// La figurina di **questo torneo**: dal documento del giocatore se il
    /// chiamante l'ha caricato fresco, altrimenti dalla cache dell'album (le
    /// schede aperte da liste costruite sugli snapshot non portano la mappa).
    private var figurinaGiocatore: Figurina? {
        let tid = appState.currentTournamentId
        return player.figurine?[tid]
            ?? appState.figurineStore.figurina(player.firestoreIdentifier, tournamentId: tid)
    }

    /// La riga che porta alla figurina.
    ///
    /// Era la carta stampata grande in cima, com'e' sul web. Su iOS pero'
    /// l'intestazione del profilo ha gia' il ritratto grande, e due volte la
    /// stessa faccia di fila sembra un errore di caricamento piu' che una
    /// vetrina. Qui la carta si annuncia e si apre: il colpo d'occhio resta
    /// quello della lente, dove la figurina e' grande davvero e si muove.
    private func figurinaScheda(_ figurina: Figurina) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { mostraLente = true }
        } label: {
            HStack(spacing: 12) {
                // Il nero della carta fa da cartoncino: niente scontorno.
                CachedAsyncImage(
                    urlString: figurina.thumbURL,
                    placeholderIcon: "rectangle.portrait.on.rectangle.portrait.angled",
                    placeholderColor: .black,
                    contentMode: .fill
                )
                .frame(width: 44, height: 66)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mostra la figurina")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TournamentPalette.ink)
                    if let etichetta = figurina.etichetta {
                        Text(etichetta)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                    .fill(TournamentPalette.surface)
            )
        }
        .buttonStyle(.tournamentPress)
        .accessibilityLabel("Mostra la figurina")
        .accessibilityHint("A schermo pieno, si inclina col dito")
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SchedaPlayerHero(
                firstName: nameParts.first,
                lastName: nameParts.last,
                jersey: player.numeroMaglia,
                // "capitano" in ruoloSquadra è una carica, non un ruolo in campo.
                roleLabel: player.positionPrimary ?? (player.carica == nil ? player.ruoloSquadra : nil) ?? "Ruolo n.d.",
                editionLabel: "Edizione \(String(appState.selectedEdition))",
                pictureURL: player.displayPhotoURL,
                onPhotoTap: nil
            )

            if let t = team {
                NavigationLink(destination: TeamDetailView(team: t)) {
                    HStack(spacing: 12) {
                        TournamentTeamLogo(
                            urlString: t.logoURL,
                            size: 40,
                            placeholderTint: Color(hex: t.colors.principale) ?? TournamentPalette.accent
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TournamentPalette.ink)
                                .lineLimit(1)
                            Text("Squadra attuale")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(TournamentPalette.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous))
                }
                .buttonStyle(.tournamentPress)
            } else if player.isFreeAgent {
                Text("Free agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TournamentPalette.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    // Nome proprio sopra, cognome nel colore del torneo sotto, come il mockup.
    private var nameParts: (first: String, last: String) {
        let parts = player.nomeCompleto
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count > 1 else {
            return ("", parts.first ?? "Giocatore")
        }
        return (parts[0], parts.dropFirst().joined(separator: " "))
    }

    // MARK: - Computed Stats

    private var computedStatsCard: some View {
        SchedaStatStrip(items: [
            SchedaStatItem(value: "\(computed.appearances)", label: "Presenze", icon: "tshirt.fill", tint: TournamentPalette.inkMuted),
            SchedaStatItem(value: "\(computed.goals)", label: "Gol", icon: "soccerball", tint: TournamentPalette.accent),
            SchedaStatItem(value: "\(computed.yellow)", label: "Gialli", icon: "rectangle.fill", tint: TournamentPalette.warm),
            SchedaStatItem(value: "\(computed.red)", label: "Rossi", icon: "rectangle.fill", tint: TournamentPalette.danger)
        ])
        .tournamentCard()
    }

    // Tab Statistiche. Erano sei righe etichetta→valore tutte uguali: gol,
    // presenze e media (quello che si cerca davvero) pesavano come
    // "espulsioni: 0". Ora tre numeri grandi e i cartellini come contorno.
    private var performanceCard: some View {
        let shown = scopedTotals ?? computed
        return VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Rendimento",
                subtitle: performanceSubtitle
            )

            HStack(spacing: 8) {
                bigStat(value: "\(shown.goals)", label: "Gol", highlighted: true)
                bigStat(value: "\(shown.appearances)", label: "Presenze", highlighted: false)
                bigStat(value: goalsPerMatch, label: "Gol/partita", highlighted: false)
            }

            HStack(spacing: 8) {
                miniStat(value: "\(shown.yellow)", label: "ammonizioni", tint: TournamentPalette.warm)
                miniStat(value: "\(shown.red)", label: "espulsioni", tint: TournamentPalette.danger)
                if mvpCount > 0 {
                    miniStat(value: "\(mvpCount)", label: "MVP", tint: TournamentPalette.accent)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private func bigStat(value: String, label: String, highlighted: Bool) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(highlighted ? TournamentPalette.accent : TournamentPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(0.6)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(highlighted
                      ? TournamentPalette.accent.opacity(0.12)
                      : TournamentPalette.surfaceMuted)
        )
    }

    private func miniStat(value: String, label: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 8, height: 8)
            Text(value)
                .font(.caption.weight(.black))
                .foregroundStyle(TournamentPalette.ink)
            Text(label)
                .font(.caption2)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Capsule().fill(TournamentPalette.surfaceMuted))
    }

    private var performanceSubtitle: String {
        guard scopesReady, let sid = selectedScopeTid else {
            return "Edizione \(String(appState.selectedEdition))"
        }
        if sid == "__all__" { return "Totale OneDay Cup" }
        let name = scopeTournaments.first { $0.id == sid }?.name ?? "Questo torneo"
        if let ed = selectedScopeEdition { return "\(name) · Edizione \(ed)" }
        return "\(name) · tutte le edizioni"
    }

    private var goalsPerMatch: String {
        let shown = scopedTotals ?? computed
        guard shown.appearances > 0 else { return "0.00" }
        return String(format: "%.2f", Double(shown.goals) / Double(shown.appearances))
    }

    // MARK: - Scope stats (torneo / edizione / per squadra)

    private var scopeEditionsForSelectedTid: [Int] {
        guard let sid = selectedScopeTid, sid != "__all__" else { return [] }
        return Array(Set(scopeHistory.filter { $0.tid == sid }.map(\.ed))).sorted(by: >)
    }

    private var scopeBuckets: [ScopeBucket] {
        guard scopesReady, let sid = selectedScopeTid else { return [] }
        let rows = scopeHistory.filter { row in
            if sid != "__all__" && row.tid != sid { return false }
            if sid != "__all__", let ed = selectedScopeEdition, row.ed != ed { return false }
            return true
        }
        let pid = player.firestoreIdentifier ?? player.id
        return rows.map { row in
            let pool = (scopeMatchesByTid[row.tid] ?? []).filter {
                $0.edizione == row.ed && ($0.team1 == row.teamId || $0.team2 == row.teamId)
            }
            let stats = Self.computeStats(
                playerId: pid,
                playerName: player.nomeCompleto,
                teamId: row.teamId,
                from: pool
            )
            return ScopeBucket(
                id: "\(row.tid)|\(row.ed)|\(row.teamId)",
                tid: row.tid,
                edition: row.ed,
                teamName: row.teamName,
                stats: stats
            )
        }
    }

    private var scopedTotals: ComputedPlayerStats? {
        guard scopesReady else { return nil }
        let buckets = scopeBuckets
        guard !buckets.isEmpty else { return nil }
        var total = ComputedPlayerStats(goals: 0, appearances: 0, yellow: 0, red: 0)
        for b in buckets {
            total.goals += b.stats.goals
            total.appearances += b.stats.appearances
            total.yellow += b.stats.yellow
            total.red += b.stats.red
        }
        return total
    }

    private func loadStatsScopes() async {
        guard !scopesReady else { return }
        let pid = player.firestoreIdentifier ?? player.id ?? ""
        let myName = player.nomeCompleto.lowercased().trimmingCharacters(in: .whitespaces)
        guard !pid.isEmpty || !myName.isEmpty else { return }
        guard let rosters = try? await appState.firestoreService.fetchParticipationRosters() else { return }

        var rows: [ScopeHistoryRow] = []
        for r in rosters {
            let mine = (!pid.isEmpty && r.playerIds.contains(pid))
                || (!myName.isEmpty && r.playerNames.contains(myName))
            if mine {
                rows.append(ScopeHistoryRow(tid: r.tournamentId, ed: r.edition, teamId: r.teamId, teamName: r.teamName))
            }
        }

        let currentTid = appState.tournamentSelectionStore.currentTournamentId
        // L'affiliazione globale corrente non equivale alla partecipazione a
        // ogni torneo della squadra: servono le rose per torneo/edizione.
        guard !rows.isEmpty else { return }

        var tids = Array(Set(rows.map(\.tid)))
        tids.sort { a, b in a == currentTid ? true : (b == currentTid ? false : a < b) }

        var byTid: [String: [Match]] = [currentTid: appState.allMatches]
        for tid in tids where tid != currentTid {
            byTid[tid] = (try? await appState.firestoreService.fetchMatches(tournamentId: tid)) ?? []
        }

        let known = appState.tournamentSelectionStore.availableTournaments
        // Solo i tornei che questo utente può vedere: `availableTournaments`
        // include i sandbox solo per i tester, quindi una simulazione non
        // compare nella carriera di un giocatore vero.
        let visible = Set(known.map(\.id))
        tids = tids.filter { visible.contains($0) || $0 == currentTid }
        rows = rows.filter { tids.contains($0.tid) }
        guard !rows.isEmpty else { return }

        scopeHistory = rows
        scopeMatchesByTid = byTid
        scopeTournaments = tids.map { tid in
            let meta = known.first { $0.id == tid }
            return ScopeTournament(id: tid, name: meta?.displayName ?? tid, color: meta?.branding.primaryColor)
        }
        selectedScopeTid = tids.contains(currentTid) ? currentTid : tids.first
        selectedScopeEdition = rows.contains { $0.tid == selectedScopeTid && $0.ed == appState.activeEdition }
            ? appState.activeEdition : nil
        scopesReady = true

        // Le partecipazioni servono ai "Premi" (piazzamento finale): una
        // lettura per squadra, e solo quelle in cui il giocatore è stato.
        var participations: [String: EditionParticipation] = [:]
        for teamId in Set(rows.map(\.teamId)) where !teamId.isEmpty {
            let docs = (try? await appState.firestoreService.fetchParticipations(forTeam: teamId)) ?? []
            for doc in docs {
                let tid = doc.tournamentId ?? currentTid
                participations["\(tid)|\(doc.edizione)|\(doc.squadraId)"] = doc
            }
        }
        participationsByKey = participations

        // Premi ufficiali: `premiPlayerIds` trova i suoi ovunque (un premiato
        // può non essere in nessuna rosa: delle rose Mormon 1 e 2 non è
        // rimasto niente), i doc delle edizioni giocate dicono se quelle
        // edizioni hanno un capocannoniere scritto.
        var awardsById: [String: FirestoreService.EditionAward] = [:]
        let ownAwards = (try? await appState.firestoreService.fetchEditionAwards(playerId: pid)) ?? []
        let playedAwards = (try? await appState.firestoreService.fetchEditionAwards(
            editionKeys: rows.map { "\($0.tid)_\($0.ed)" }
        )) ?? []
        for award in ownAwards + playedAwards {
            awardsById["\(award.tournamentId)_\(award.edition)_\(award.tipo)"] = award
        }
        editionAwards = Array(awardsById.values)

        loadAwards()
    }

    private func resetStatsScopes() {
        scopeHistory = []
        scopeMatchesByTid = [:]
        awards = []
        participationsByKey = [:]
        editionAwards = []
        scopeTournaments = []
        selectedScopeTid = nil
        selectedScopeEdition = nil
        scopesReady = false
    }

    // Pill torneo (colorate) + pill edizione (neutre), come la PWA.
    /// Torneo ed edizione in due menu etichettati. Le due file di pill che
    /// c'erano prima scorrevano in orizzontale e non dicevano cosa fossero:
    /// l'owner leggeva la riga dei tornei come un cambio edizione.
    @ViewBuilder
    private var scopeFilterCard: some View {
        if scopesReady && (scopeTournaments.count >= 2 || scopeEditionsForSelectedTid.count >= 2) {
            HStack(spacing: 10) {
                if scopeTournaments.count >= 2 {
                    scopeMenu(
                        label: "Torneo",
                        value: selectedScopeTid == "__all__"
                            ? "Totale OneDay Cup"
                            : (scopeTournaments.first { $0.id == selectedScopeTid }?.name ?? "Torneo").scopeMenuName
                    ) {
                        ForEach(scopeTournaments) { t in
                            Button(t.name) {
                                selectedScopeTid = t.id
                                selectedScopeEdition = nil
                            }
                        }
                        Button("Totale OneDay Cup") {
                            selectedScopeTid = "__all__"
                            selectedScopeEdition = nil
                        }
                    }
                }

                if selectedScopeTid != "__all__" && scopeEditionsForSelectedTid.count >= 2 {
                    scopeMenu(
                        label: "Edizione",
                        value: selectedScopeEdition.map(String.init) ?? "Tutte"
                    ) {
                        Button("Tutte le edizioni") { selectedScopeEdition = nil }
                        // Le edizioni sono SEMPRE quelle del torneo scelto:
                        // mescolarle fra tornei era il bug segnalato.
                        ForEach(scopeEditionsForSelectedTid, id: \.self) { ed in
                            Button("Edizione \(ed)") { selectedScopeEdition = ed }
                        }
                    }
                }
            }
        }
    }

    private func scopeMenu<Content: View>(
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

    private func scopePill(label: String, dotColor: Color?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        let tint = dotColor ?? TournamentPalette.accent
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { action() }
        } label: {
            HStack(spacing: 7) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(.caption.weight(.heavy))
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? tint.opacity(0.18) : TournamentPalette.surfaceMuted)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isSelected ? tint : TournamentPalette.border, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? TournamentPalette.ink : TournamentPalette.inkMuted)
        }
        .buttonStyle(.tournamentPress)
    }

    // MARK: - Premi
    //
    // Quasi tutto si deduce dai dati che già ci sono:
    //  · titoli di squadra  → finalPosition della partecipazione d'edizione
    //  · capocannoniere     → conteggio gol dell'edizione, calcolato in locale
    //  · MVP partita        → match.mvp
    // L'eccezione sono i premi individuali delle edizioni storiche
    // (`edizioni/{tid}_{ed}.premi`): le partite importate non hanno eventi mvp
    // e un vincitore può non avere nemmeno una scheda giocatore.
    @ViewBuilder
    private var awardsCard: some View {
        if !awards.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                TournamentSectionHeader(title: "Premi e titoli", subtitle: "Tutta la carriera")
                    .padding(.bottom, 6)

                ForEach(Array(awards.enumerated()), id: \.element.id) { index, award in
                    if index > 0 { Divider() }
                    HStack(spacing: 12) {
                        Image(systemName: award.icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(award.tint)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(award.tint.opacity(0.16)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(award.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TournamentPalette.ink)
                            Text(award.subtitle)
                                .font(.caption)
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tournamentCard()
        }
    }

    /// MVP nello scope selezionato (per la riga di contorno del rendimento).
    private var mvpCount: Int {
        let pid = player.firestoreIdentifier ?? player.id
        let name = player.nomeCompleto.lowercased()
        let pool: [Match] = scopesReady ? scopedPlayerMatches : appState.matches
        return pool.filter { match in
            guard let mvp = match.mvp else { return false }
            if let pid, let mvpId = mvp.playerId, !mvpId.isEmpty { return mvpId == pid }
            return (mvp.playerName ?? "").lowercased() == name
        }.count
    }

    private func loadAwards() {
        let pid = player.firestoreIdentifier ?? player.id
        let name = player.nomeCompleto
        var result: [PlayerAward] = []

        // Titoli: la partecipazione di quell'edizione porta il piazzamento.
        for row in scopeHistory {
            guard let position = participationsByKey["\(row.tid)|\(row.ed)|\(row.teamId)"]?.finalPosition,
                  let podium = PlayerAward.podium(position) else { continue }
            result.append(PlayerAward(
                id: "title-\(row.tid)-\(row.ed)",
                sort: (0, position, -row.ed),
                icon: podium.icon,
                tint: podium.tint,
                title: "\(podium.label) · \(tournamentName(row.tid))",
                subtitle: "Edizione \(row.ed) · \(row.teamName)"
            ))
        }

        // Premi scritti sul doc edizione: non si deducono da niente, quindi
        // vengono letti così come sono.
        for award in editionAwards {
            guard let meta = PlayerAward.official(award.tipo) else { continue }
            guard let awardPlayerId = award.playerId, let pid, awardPlayerId == pid else { continue }
            result.append(PlayerAward(
                id: "award-\(award.tournamentId)-\(award.edition)-\(award.tipo)",
                sort: (1, meta.order, -award.edition),
                icon: meta.icon,
                tint: TournamentPalette.accent,
                title: "\(meta.label) · \(tournamentName(award.tournamentId))",
                subtitle: award.teamName.isEmpty
                    ? "Edizione \(award.edition)"
                    : "Edizione \(award.edition) · \(award.teamName)"
            ))
        }

        // Un capocannoniere scritto batte quello contato dai gol: nella Mormon
        // ed.2 l'archivio dà un pari merito a 8 gol, il premio no.
        let officialTopScorerEditions = Set(
            editionAwards
                .filter { $0.tipo == "capocannoniere" }
                .map { "\($0.tournamentId)_\($0.edition)" }
        )

        // Capocannoniere: si conta l'edizione intera dalle partite che
        // abbiamo già in memoria, senza leggere altri aggregati.
        for (tid, ed) in Set(scopeHistory.map { ScopeKey(tid: $0.tid, ed: $0.ed) }).map({ ($0.tid, $0.ed) }) {
            if officialTopScorerEditions.contains("\(tid)_\(ed)") { continue }
            let editionMatches = (scopeMatchesByTid[tid] ?? []).filter { $0.edizione == ed }
            let ranking = Self.goalsByPlayer(in: editionMatches)
            guard let best = ranking.values.max(), best > 0 else { continue }
            let mine = ranking[Self.scorerKey(playerId: pid, playerName: name)] ?? 0
            guard mine == best else { continue }
            let shared = ranking.values.filter { $0 == best }.count > 1
            result.append(PlayerAward(
                id: "topscorer-\(tid)-\(ed)",
                sort: (2, 0, -ed),
                icon: "soccerball",
                tint: TournamentPalette.accent,
                title: "Capocannoniere · \(tournamentName(tid))",
                subtitle: "Edizione \(ed) · \(best) gol" + (shared ? " (a pari merito)" : "")
            ))
        }

        // MVP partita: uno solo se è uno, altrimenti il totale.
        let mvpTotal = scopeMatchesByTid.values.flatMap { $0 }.filter { match in
            guard let mvp = match.mvp else { return false }
            if let pid, let mvpId = mvp.playerId, !mvpId.isEmpty { return mvpId == pid }
            return (mvp.playerName ?? "").lowercased() == name.lowercased()
        }.count
        if mvpTotal > 0 {
            result.append(PlayerAward(
                id: "mvp",
                sort: (3, 0, 0),
                icon: "star.fill",
                tint: TournamentPalette.warm,
                title: mvpTotal == 1 ? "MVP di una partita" : "MVP di \(mvpTotal) partite",
                subtitle: "Migliore in campo"
            ))
        }

        awards = result.sorted {
            ($0.sort.0, $0.sort.1, $0.sort.2) < ($1.sort.0, $1.sort.1, $1.sort.2)
        }
    }

    private func tournamentName(_ tid: String) -> String {
        if let name = scopeTournaments.first(where: { $0.id == tid })?.name { return name }
        // Un premio può arrivare da un torneo che non è nello storico del
        // giocatore: il portiere premiato nella Mormon 1 e 2 non risulta in
        // nessuna rosa di quel torneo, le rose sono andate perse.
        return appState.tournamentSelectionStore.availableTournaments
            .first { $0.id == tid }?.displayName ?? tid
    }

    private struct ScopeKey: Hashable {
        let tid: String
        let ed: Int
    }

    /// Gol per giocatore in un gruppo di partite. La chiave è l'id quando c'è,
    /// altrimenti il nome normalizzato: le edizioni storiche hanno marcatori
    /// per solo nome.
    static func goalsByPlayer(in matches: [Match]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for match in matches {
            for event in match.safeEventi where ["gol", "rigore_segnato", "punizione_segnata"].contains(event.tipo) {
                let key = scorerKey(playerId: event.giocatoreId, playerName: event.giocatoreNome ?? "")
                guard !key.isEmpty else { continue }
                counts[key, default: 0] += 1
            }
        }
        return counts
    }

    static func scorerKey(playerId: String?, playerName: String) -> String {
        if let playerId, !playerId.isEmpty { return "id:\(playerId)" }
        let normalized = playerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? "" : "name:\(normalized)"
    }

    // Spacchettamento per squadra: gol/presenze con ogni maglia, per
    // edizione/torneo. Compare solo quando lo scope copre più bucket.
    private var perTeamBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TournamentSectionHeader(
                title: "Per squadra",
                subtitle: "Nello scope selezionato"
            )
            .padding(.bottom, 6)

            let ordered = scopeBuckets.sorted {
                if $0.edition != $1.edition { return $0.edition > $1.edition }
                return $0.tid < $1.tid
            }
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, b in
                if index > 0 { Divider() }
                HStack(spacing: 10) {
                    Circle()
                        .fill(scopeTournaments.first { $0.id == b.tid }?.color ?? TournamentPalette.inkMuted)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.teamName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                        // String(edition): l'interpolazione di Text formatta
                        // gli Int col separatore di migliaia ("Ed. 2.026").
                        Text("\(scopeTournaments.first { $0.id == b.tid }?.name ?? b.tid) · Ed. \(String(b.edition)) · \(b.stats.appearances) pres.")
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.inkMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(b.stats.goals) gol")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(TournamentPalette.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(TournamentPalette.surfaceMuted))
                }
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    // MARK: - Career link

    // MARK: - Partite giocate

    private var recentMatchesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Partite giocate (\(scopedPlayerMatches.count))",
                subtitle: "Gare della selezione qui sopra."
            )

            ForEach(scopedPlayerMatches.prefix(12)) { m in
                NavigationLink(destination: MatchDetailView(match: m)) {
                    let resolved = appState.resolvedTeams(for: m)
                    HStack(spacing: 8) {
                        Text(resolved.team1.name)
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(m.team1Goals) - \(m.team2Goals)")
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(TournamentPalette.ink)
                        Spacer()
                        Text(resolved.team2.name)
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 8)
                }
                .foregroundStyle(TournamentPalette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    // MARK: - Dettagli

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TournamentSectionHeader(
                title: "Dettagli profilo",
                subtitle: nil
            )
            .padding(.bottom, 6)

            if let numero = player.numeroMaglia {
                SchedaInfoRow(icon: "tshirt.fill", label: "Numero di maglia", value: "\(numero)")
                Divider()
            }
            if let pos = player.positionPrimary, !pos.isEmpty {
                SchedaInfoRow(icon: "shield.fill", label: "Ruolo principale", value: pos)
                Divider()
            }
            if let pos2 = player.positionSecondary, !pos2.isEmpty {
                SchedaInfoRow(icon: "arrow.triangle.swap", label: "Ruolo alternativo", value: pos2)
                Divider()
            }
            if let piede = player.piedeDominante, !piede.isEmpty {
                SchedaInfoRow(icon: "figure.run", label: "Piede preferito", value: piede)
                Divider()
            }
            if let status = player.tesseramentoStatus {
                SchedaInfoRow(
                    icon: "checkmark.seal.fill",
                    label: "Stato tesseramento",
                    value: status == "tesserato" ? "Tesserato" : "Free agent",
                    iconTint: status == "tesserato" ? TournamentPalette.success : TournamentPalette.inkMuted
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    // MARK: - Helpers

    private func badgeView(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func infoRow(icon: String, label: String, valore: String,
                          valueColor: Color = TournamentPalette.ink) -> some View {
        TournamentInfoRow(icon: icon, label: label, value: valore, valueColor: valueColor)
    }

    private func togglePlayerNotifications() async {
        guard !isTogglingNotifications else { return }
        isTogglingNotifications = true
        defer { isTogglingNotifications = false }

        do {
            let shouldEnable = !isFollowingPlayerNotifications
            _ = try await appState.notificationService.setPlayerSubscription(
                enabled: shouldEnable,
                playerId: notificationPlayerId,
                teamId: notificationTeamId,
                edition: appState.selectedEdition,
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

    // MARK: - Computed Stats Helper

    static func computeStats(for player: Player, from matches: [Match]) -> ComputedPlayerStats {
        var goals = 0, appearances = 0, yellow = 0, red = 0
        var suspendedNextTeamMatch = false
        let teamId = player.teamId

        for match in MatchGoalkeeperResolver.sortedMatches(matches).filter({ $0.isPlayed || $0.isStarted }) {
            let teamMatch = teamId != nil && (match.team1 == teamId || match.team2 == teamId)
            if teamMatch {
                if suspendedNextTeamMatch {
                    suspendedNextTeamMatch = false
                    continue
                }
                appearances += 1
            }

            let playerEvents = match.safeEventi.filter { player.matches(event: $0) }
            if !playerEvents.isEmpty && !teamMatch {
                appearances += 1
            }
            goals += playerEvents.filter { ["gol", "rigore_segnato", "punizione_segnata"].contains($0.tipo) }.count
            yellow += playerEvents.filter { $0.tipo == "ammonizione" }.count
            let redEvents = playerEvents.filter { $0.tipo == "espulsione" }.count
            red += redEvents
            if redEvents > 0, let teamId {
                suspendedNextTeamMatch = true
            }
        }
        return ComputedPlayerStats(
            goals: max(goals, player.stats?.gol ?? 0),
            appearances: max(appearances, player.stats?.presenze ?? 0),
            yellow: max(yellow, player.stats?.ammonizioni ?? 0),
            red: max(red, player.stats?.espulsioni ?? 0)
        )
    }

    static func computeStats(playerId: String?, playerName: String, teamId: String?, from matches: [Match]) -> ComputedPlayerStats {
        var goals = 0, appearances = 0, yellow = 0, red = 0
        var suspendedNextTeamMatch = false

        for match in MatchGoalkeeperResolver.sortedMatches(matches).filter({ $0.isPlayed || $0.isStarted }) {
            let teamMatch = teamId != nil && (match.team1 == teamId || match.team2 == teamId)
            if teamMatch {
                if suspendedNextTeamMatch {
                    suspendedNextTeamMatch = false
                    continue
                }
                appearances += 1
            }

            let playerEvents = match.safeEventi.filter {
                matchesProfile(event: $0, playerId: playerId, playerName: playerName, teamId: teamId)
            }
            if !playerEvents.isEmpty && !teamMatch {
                appearances += 1
            }
            goals += playerEvents.filter { ["gol", "rigore_segnato", "punizione_segnata"].contains($0.tipo) }.count
            yellow += playerEvents.filter { $0.tipo == "ammonizione" }.count
            let redEvents = playerEvents.filter { $0.tipo == "espulsione" }.count
            red += redEvents
            if redEvents > 0, teamId != nil {
                suspendedNextTeamMatch = true
            }
        }

        return ComputedPlayerStats(
            goals: goals,
            appearances: appearances,
            yellow: yellow,
            red: red
        )
    }

    static func matches(playerId: String?, playerName: String, teamId: String?, from matches: [Match]) -> [Match] {
        var suspendedNextTeamMatch = false
        var result: [Match] = []

        for match in MatchGoalkeeperResolver.sortedMatches(matches).filter({ $0.isPlayed || $0.isStarted }) {
            let teamMatch = teamId != nil && (match.team1 == teamId || match.team2 == teamId)
            let playerEvents = match.safeEventi.filter {
                matchesProfile(event: $0, playerId: playerId, playerName: playerName, teamId: teamId)
            }

            if teamMatch {
                if suspendedNextTeamMatch {
                    suspendedNextTeamMatch = false
                } else {
                    result.append(match)
                }
            } else if !playerEvents.isEmpty {
                result.append(match)
            }

            if playerEvents.contains(where: { $0.tipo == "espulsione" }), teamId != nil {
                suspendedNextTeamMatch = true
            }
        }

        return result.sorted { $0.giornata > $1.giornata }
    }

    private static func matchesProfile(event: MatchEvent, playerId: String?, playerName: String, teamId: String?) -> Bool {
        if let teamId, let eventTeamId = event.squadraId, eventTeamId != teamId {
            return false
        }

        if let playerId, !playerId.isEmpty, event.giocatoreId == playerId {
            return true
        }

        guard let normalizedTarget = Player.normalizedLookupName(from: playerName),
              let normalizedEvent = Player.normalizedLookupName(from: event.giocatoreNome) else {
            return false
        }

        return normalizedTarget == normalizedEvent && (teamId == nil || event.squadraId == teamId)
    }
}

struct ComputedPlayerStats {
    var goals: Int
    var appearances: Int
    var yellow: Int
    var red: Int
}

struct HistoricPlayerProfile: Identifiable {
    var id: String
    var playerId: String?
    var displayName: String
    var pictureURL: String?
    var teamId: String?
    var teamName: String
    var edition: Int
    var jerseyNumber: Int?
    var position: String?
    var carica: CaricaSquadra? = nil

    init(
        id: String,
        playerId: String? = nil,
        displayName: String,
        pictureURL: String? = nil,
        teamId: String? = nil,
        teamName: String,
        edition: Int,
        jerseyNumber: Int? = nil,
        position: String? = nil,
        carica: CaricaSquadra? = nil
    ) {
        self.id = id
        self.playerId = playerId
        self.displayName = displayName
        self.pictureURL = pictureURL
        self.teamId = teamId
        self.teamName = teamName
        self.edition = edition
        self.jerseyNumber = jerseyNumber
        self.position = position
        self.carica = carica
    }

    init(entry: StatsViewModel.PlayerStatEntry, edition: Int) {
        self.init(
            id: entry.playerDocumentId ?? entry.id,
            playerId: entry.playerDocumentId ?? entry.id,
            displayName: entry.nome,
            pictureURL: entry.pictureURL,
            teamId: entry.teamId,
            teamName: entry.teamName,
            edition: edition,
            jerseyNumber: entry.jerseyNumber,
            position: entry.position
        )
    }

    init(entry: AwardStandingsBuilder.Entry, edition: Int) {
        self.init(
            id: entry.playerDocumentId ?? entry.id,
            playerId: entry.playerDocumentId ?? entry.id,
            displayName: entry.nome,
            pictureURL: entry.pictureURL,
            teamId: entry.teamId,
            teamName: entry.teamName,
            edition: edition,
            jerseyNumber: entry.jerseyNumber,
            position: entry.position
        )
    }
}

struct HistoricPlayerDetailView: View {
    let profile: HistoricPlayerProfile

    @Environment(AppState.self) private var appState
    @State private var selectedSection = 0

    private var editionMatches: [Match] {
        appState.allMatches.filter { $0.edizione == profile.edition }
    }

    private var computed: ComputedPlayerStats {
        PlayerDetailView.computeStats(
            playerId: profile.playerId,
            playerName: profile.displayName,
            teamId: profile.teamId,
            from: editionMatches
        )
    }

    private var recentMatches: [Match] {
        PlayerDetailView.matches(
            playerId: profile.playerId,
            playerName: profile.displayName,
            teamId: profile.teamId,
            from: editionMatches
        )
    }

    private var editionTeam: EditionTeam? {
        guard let teamId = profile.teamId else { return nil }
        return appState.editionTeam(for: teamId, edition: profile.edition)
    }

    var body: some View {
        ZStack {
            (Color(hex: "#f8fafc") ?? TournamentPalette.backgroundTop)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard

                    SchedaTabs(
                        tabs: [
                            SchedaTab(title: "Profilo", icon: "person.fill"),
                            SchedaTab(title: "Stats", icon: "chart.bar.fill"),
                            SchedaTab(title: "Partite", icon: "soccerball")
                        ],
                        selection: $selectedSection
                    )

                    switch selectedSection {
                    case 0:
                        computedStatsCard
                        detailsCard
                    case 1:
                        performanceCard
                    default:
                        if recentMatches.isEmpty {
                            Text("Nessuna partita per questa edizione.")
                                .font(.subheadline)
                                .foregroundStyle(TournamentPalette.inkMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .tournamentCard()
                        } else {
                            recentMatchesCard
                        }
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SchedaPlayerHero(
                firstName: nameParts.first,
                lastName: nameParts.last,
                jersey: profile.jerseyNumber,
                roleLabel: profile.position ?? "Ruolo n.d.",
                editionLabel: "Edizione \(profile.edition)",
                pictureURL: profile.pictureURL,
                onPhotoTap: nil
            )

            if let team = editionTeam {
                NavigationLink(destination: TeamDetailView(team: team)) {
                    HStack(spacing: 12) {
                        TournamentTeamLogo(
                            urlString: team.logoURL,
                            size: 40,
                            placeholderTint: Color(hex: team.colors.principale) ?? TournamentPalette.accent
                        )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.displayName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(TournamentPalette.ink)
                                .lineLimit(1)
                            Text("Squadra · Edizione \(profile.edition)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(TournamentPalette.inkMuted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(TournamentPalette.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous))
                }
                .buttonStyle(.tournamentPress)
            } else {
                Label(profile.teamName, systemImage: "shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private var nameParts: (first: String, last: String) {
        let parts = profile.displayName
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        guard parts.count > 1 else {
            return ("", parts.first ?? "Giocatore")
        }
        return (parts[0], parts.dropFirst().joined(separator: " "))
    }

    private var computedStatsCard: some View {
        SchedaStatStrip(items: [
            SchedaStatItem(value: "\(computed.appearances)", label: "Presenze", icon: "tshirt.fill", tint: TournamentPalette.inkMuted),
            SchedaStatItem(value: "\(computed.goals)", label: "Gol", icon: "soccerball", tint: TournamentPalette.accent),
            SchedaStatItem(value: "\(computed.yellow)", label: "Gialli", icon: "rectangle.fill", tint: TournamentPalette.warm),
            SchedaStatItem(value: "\(computed.red)", label: "Rossi", icon: "rectangle.fill", tint: TournamentPalette.danger)
        ])
        .tournamentCard()
    }

    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TournamentSectionHeader(
                title: "Rendimento",
                subtitle: "\(profile.teamName) · Edizione \(profile.edition)"
            )
            .padding(.bottom, 6)

            SchedaInfoRow(icon: "tshirt.fill", label: "Presenze", value: "\(computed.appearances)")
            Divider()
            SchedaInfoRow(icon: "soccerball", label: "Gol", value: "\(computed.goals)")
            Divider()
            SchedaInfoRow(icon: "chart.line.uptrend.xyaxis", label: "Gol a partita", value: goalsPerMatch)
            Divider()
            SchedaInfoRow(icon: "rectangle.fill", label: "Ammonizioni", value: "\(computed.yellow)", iconTint: TournamentPalette.warm)
            Divider()
            SchedaInfoRow(icon: "rectangle.fill", label: "Espulsioni", value: "\(computed.red)", iconTint: TournamentPalette.danger)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private var goalsPerMatch: String {
        guard computed.appearances > 0 else { return "0.00" }
        return String(format: "%.2f", Double(computed.goals) / Double(computed.appearances))
    }

    private var recentMatchesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Partite giocate",
                subtitle: "\(recentMatches.count) · Edizione \(profile.edition)"
            )

            ForEach(recentMatches.prefix(5)) { match in
                NavigationLink(destination: MatchDetailView(match: match)) {
                    let resolved = appState.resolvedTeams(for: match)
                    HStack(spacing: 8) {
                        Text(resolved.team1.name)
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(
                            match.scoreKnown == false
                                ? "Risultato n.d."
                                : "\(match.team1Goals) - \(match.team2Goals)"
                        )
                            .font(.caption.bold().monospacedDigit())
                            .foregroundStyle(TournamentPalette.ink)
                        Spacer()
                        Text(resolved.team2.name)
                            .font(.caption)
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(TournamentPalette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TournamentSectionHeader(title: "Informazioni", subtitle: nil)
                .padding(.bottom, 6)

            SchedaInfoRow(icon: "calendar", label: "Edizione", value: "\(profile.edition)")
            Divider()
            SchedaInfoRow(icon: "shield.fill", label: "Squadra", value: profile.teamName)
            if let position = profile.position, !position.isEmpty {
                Divider()
                SchedaInfoRow(icon: "figure.run", label: "Ruolo", value: position)
            }
            if let jerseyNumber = profile.jerseyNumber {
                Divider()
                SchedaInfoRow(icon: "number.square.fill", label: "Numero", value: "#\(jerseyNumber)")
            }
            if let carica = profile.carica {
                Divider()
                SchedaInfoRow(icon: carica.symbol, label: "Incarico", value: carica.label, iconTint: TournamentPalette.warm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }
}

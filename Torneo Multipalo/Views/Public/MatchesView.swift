import SwiftUI
import UIKit

private enum MatchesPhaseFilter: String, CaseIterable, Identifiable {
    case all = "Tutte"
    case groupStage = "Girone"
    case knockout = "Finali"

    var id: String { rawValue }
}

private struct MatchListSection: Identifiable {
    let id: String
    let title: String
    let matches: [Match]
}

struct MatchesView: View {
    @Environment(AppState.self) private var appState
    @State private var isTogglingTournamentNotifications = false
    @State private var notificationErrorMessage: String?
    @State private var selectedFilter: MatchesPhaseFilter = .all
    // Ricerca su tutto l'archivio (squadre e giocatori di ogni torneo ed
    // edizione), non solo sulle partite in pagina: vedi GlobalSearchView.
    @State private var searchText = ""
    @State private var searchStore = GlobalSearchStore()
    /// La ricerca sta dietro un bottone: il campo sempre aperto rubava la riga
    /// piu' alta a chi apre l'app solo per vedere il risultato.
    @State private var mostraRicerca = false
    @FocusState private var ricercaAttiva: Bool
    /// Quanto si e' scorso: serve a rimpicciolire il logo in testa.
    @State private var scorrimento: CGFloat = 0

    /// Da 0 (in cima) a 1 (logo ritirato del tutto). I 96 punti sono la corsa
    /// in cui il logo passa da grande a sparito: piu' corta e sembra uno
    /// scatto, piu' lunga e il logo resta in mezzo ai piedi.
    private var ritiro: CGFloat {
        min(max(scorrimento / 96, 0), 1)
    }

    @ViewBuilder
    private var logoInTesta: some View {
        if let t = currentTournament {
            // Una misura sola, grande, ridotta con `scaleEffect`: cambiare il
            // `size` a ogni frame rifa' il layout dell'immagine e lo
            // scorrimento diventa a scatti. Lo spazio che occupa lo governa
            // l'altezza del contenitore, che si chiude fino a zero — cosi' la
            // lista sale mentre il logo rimpicciolisce, e a fine corsa il logo
            // e' esattamente quello della barra.
            TournamentBrandLogoMark(
                logoURL: t.branding.logoURL,
                localAsset: LocalTournamentLogos.assetName(for: t.id),
                size: 104
            )
            .scaleEffect(1 - 0.72 * ritiro, anchor: .top)
            .opacity(Double(1 - ritiro))
            .frame(height: max(0, 104 * (1 - ritiro)), alignment: .top)
            .frame(maxWidth: .infinity)
            .padding(.top, ritiro < 1 ? 6 : 0)
            .clipped()
            .accessibilityLabel(t.displayName)
            .allowsHitTesting(false)
        }
    }

    /// Torneo corrente per il brand header (§4.3).
    private var currentTournament: Tournament? {
        let s = appState.tournamentSelectionStore
        return s.availableTournaments.first { $0.id == s.currentTournamentId }
    }

    private var isTournamentSubscribed: Bool {
        appState.notificationService.isSubscribedToTournament(
            edition: appState.selectedEdition
        )
    }

    private var editionFormat: TournamentEditionFormat {
        TournamentEditionFormat.resolve(
            for: appState.selectedEdition,
            tournamentId: appState.currentTournamentId,
            teamCount: appState.editionTeams.count,
            matches: appState.matches
        )
    }

    private var groupStageSections: [MatchListSection] {
        let grouped = Dictionary(grouping: appState.matches.filter { TournamentPhaseKey.isGroupStage($0.fase) }) { $0.giornata }

        return grouped
            .sorted { $0.key < $1.key }
            .map { giornata, matches in
                MatchListSection(
                    id: "giornata_\(giornata)",
                    title: giornata > 0 ? "Giornata \(giornata)" : "Girone",
                    matches: matches.sorted(by: sortMatches(lhs:rhs:))
                )
            }
    }

    private var knockoutSections: [MatchListSection] {
        let grouped = Dictionary(
            grouping: appState.matches.filter { TournamentPhaseKey.isKnockout($0.fase) }
        ) { TournamentPhaseKey.normalize($0.fase) }

        return grouped
            .sorted { TournamentPhaseKey.sortRank($0.key) < TournamentPhaseKey.sortRank($1.key) }
            .map { phaseKey, matches in
                MatchListSection(
                    id: "phase_\(phaseKey)",
                    title: TournamentPhaseKey.displayName(phaseKey),
                    matches: matches.sorted(by: sortMatches(lhs:rhs:))
                )
            }
    }

    /// Chi sta giocando **adesso**, tolto dalla sua giornata e messo in cima.
    ///
    /// Colorare la riga dove si trova non bastava: la giornata in corso puo'
    /// stare a meta' elenco e per vederla bisogna cercarla. Finita la partita
    /// la riga torna al suo posto da sola.
    private var sezioneLive: MatchListSection? {
        let live = appState.matches.filter { $0.isLive }.sorted(by: sortMatches(lhs:rhs:))
        guard !live.isEmpty else { return nil }
        return MatchListSection(
            id: "in_campo",
            title: live.count == 1 ? "In campo" : "In campo adesso",
            matches: live
        )
    }

    private var visibleSections: [MatchListSection] {
        let base: [MatchListSection]
        switch selectedFilter {
        case .all:
            base = groupStageSections + knockoutSections
        case .groupStage:
            base = groupStageSections
        case .knockout:
            base = knockoutSections
        }

        guard let sezioneLive else { return base }
        // Le partite in campo non si ripetono piu' giu' nella loro giornata:
        // vederle due volte fa dubitare che siano due partite diverse.
        let idLive = Set(sezioneLive.matches.compactMap(\.id))
        let resto = base.compactMap { sezione -> MatchListSection? in
            let rimaste = sezione.matches.filter { !idLive.contains($0.id ?? "") }
            guard !rimaste.isEmpty else { return nil }
            return MatchListSection(id: sezione.id, title: sezione.title, matches: rimaste)
        }
        return [sezioneLive] + resto
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: 16) {
                        // Il logo del torneo grande in testa, che si ritira
                        // scorrendo. Sta **dentro** la lista, non in una
                        // testata fissa: una fascia separata con uno stacco
                        // netto mangia mezzo schermo e sembra un'altra
                        // schermata appiccicata sopra le partite.
                        logoInTesta

                        if mostraRicerca {
                            barraRicerca
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }

                        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                            GlobalSearchResultsView(query: searchText, store: searchStore)
                        }

                        if appState.matches.isEmpty && appState.isLoadingMatches {
                            LoadingView()
                                .padding(.top, 8)
                        } else if appState.matches.isEmpty {
                            // Stato "in attesa del calendario" (porting PWA index-tabs):
                            // il calendario esce alla chiusura iscrizioni → intanto
                            // mostra le squadre già iscritte.
                            waitingStatePanel
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        } else {
                            filterBar
                                .padding(.horizontal, 16)

                            if visibleSections.isEmpty {
                                EmptyStateView(
                                    icon: selectedFilter == .knockout ? "trophy" : "sportscourt",
                                    title: emptyStateTitle,
                                    message: ""
                                )
                            } else {
                                // La striscia dell'album sta **sopra** le
                                // giornate, al contrario del tabellone che sta
                                // sotto. Il tabellone e' un riquadro alto e
                                // spingerebbe giu' chi gioca adesso; questa e'
                                // una riga sola, e in fondo — dopo ventisette
                                // partite — non la vedeva nessuno.
                                // Da sola decide se comparire: zero figurine,
                                // niente riga.
                                AlbumStripView()
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)

                                LazyVStack(spacing: 14) {
                                    ForEach(visibleSections) { section in
                                        MatchGroupSection(
                                            title: section.title,
                                            matches: section.matches
                                        )
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }

                        // Il tabellone sta **sotto** le partite: prima era la
                        // prima cosa dopo la testata e spingeva giu' proprio
                        // quello per cui si apre questa scheda, cioe' chi gioca
                        // adesso.
                        if editionFormat.hasKnockout && !appState.matches.isEmpty {
                            NavigationLink(destination: KnockoutBracketView(showsNavigation: false)) {
                                knockoutEntryCard
                            }
                            .buttonStyle(.tournamentPress)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                    }
                    .padding(.bottom, 24)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: ScorrimentoKey.self,
                                value: -g.frame(in: .named("partite")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "partite")
                .onPreferenceChange(ScorrimentoKey.self) { scorrimento = $0 }
            }
            .navigationBarTitleDisplayMode(.inline)
            .task(id: searchText.count >= 2) {
                guard searchText.count >= 2 else { return }
                await searchStore.loadIfNeeded(using: appState.firestoreService)
            }
            // La cache delle figurine si scalda qui: la striscia decide se
            // esistere in base a quello che trova.
            .task {
                await appState.figurineStore.loadIfNeeded(using: appState.firestoreService)
            }
            // Edizione a sinistra, logo del torneo al centro, cerca a destra:
            // come la scheda "Ora" della PWA. Il nome del torneo scritto e' via
            // — il logo lo dice meglio e in meno spazio — e la campanella e'
            // passata al Profilo, dove stanno le altre preferenze.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    TournamentEditionMenu()
                }
                ToolbarItem(placement: .principal) {
                    // Sempre presente, si scopre man mano che quello grande si
                    // ritira: cosi' il logo sembra **salire** nella barra
                    // invece di sparire di colpo. Con un `if` la barra non
                    // ricalcolava il suo contenuto e il logo non ricompariva
                    // mai — era il motivo per cui l'animazione "non c'era".
                    if let t = currentTournament {
                        TournamentBrandLogoMark(
                            logoURL: t.branding.logoURL,
                            localAsset: LocalTournamentLogos.assetName(for: t.id),
                            size: 30
                        )
                        .opacity(Double(ritiro))
                        .scaleEffect(0.85 + 0.15 * ritiro)
                        .accessibilityLabel(t.displayName)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            mostraRicerca.toggle()
                            if !mostraRicerca { searchText = "" }
                        }
                    } label: {
                        Image(systemName: mostraRicerca ? "xmark" : "magnifyingglass")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(TournamentPalette.accent)
                    }
                    .accessibilityLabel(mostraRicerca ? "Chiudi ricerca" : "Cerca")
                }
            }
            .refreshable {
                await appState.loadMatches()
            }
            .alert("Notifiche torneo", isPresented: Binding(
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
    }

    private var barraRicerca: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TournamentPalette.inkMuted)
            TextField("Cerca squadra o giocatore", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($ricercaAttiva)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TournamentPalette.surfaceStrong.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
        .onAppear { ricercaAttiva = true }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(MatchesPhaseFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            selectedFilter == filter ? .white : TournamentPalette.ink
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    selectedFilter == filter
                                        ? AnyShapeStyle(
                                            LinearGradient(
                                                colors: [TournamentPalette.accent, TournamentPalette.accentDeep],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        : AnyShapeStyle(TournamentPalette.surfaceStrong.opacity(0.92))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    selectedFilter == filter
                                        ? TournamentPalette.accent.opacity(0.08)
                                        : TournamentPalette.border,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TournamentPalette.surface.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(TournamentPalette.border, lineWidth: 1)
        )
    }

    private var knockoutEntryCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.headline.weight(.semibold))
                .foregroundStyle(TournamentPalette.warm)
                .frame(width: 42, height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(TournamentPalette.warm.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Tabellone finale")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                Text("Percorso verso la finale")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .tournamentCard()
    }

    // MARK: - Stato "in attesa del calendario" (porting PWA index-tabs waiting state)

    private var waitingStatePanel: some View {
        VStack(spacing: 22) {
            // Banner semplice "iscrizioni ancora in corso".
            VStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(TournamentPalette.accent)
                    .padding(14)
                    .background(Circle().fill(TournamentPalette.accent.opacity(0.12)))
                Text("Iscrizioni ancora in corso")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)
                    .multilineTextAlignment(.center)
                Text("Il calendario esce alla chiusura delle iscrizioni. Intanto ecco le squadre già iscritte.")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            let teams = appState.editionTeams
            if teams.isEmpty {
                Text("Nessuna squadra ancora iscritta.")
                    .font(.subheadline)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                // Loghi squadre "nudi", fluttuanti (niente riquadri).
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 96, maximum: 140), spacing: 16)],
                    spacing: 24
                ) {
                    ForEach(Array(teams.enumerated()), id: \.element.id) { index, team in
                        NavigationLink(destination: TeamDetailView(team: team)) {
                            WaitingTeamCard(team: team, index: index)
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyStateTitle: String {
        switch selectedFilter {
        case .all:
            return "Nessuna partita"
        case .groupStage:
            return "Girone non disponibile"
        case .knockout:
            return "Fase finale non disponibile"
        }
    }

    private func sortMatches(lhs: Match, rhs: Match) -> Bool {
        let lhsPhaseRank = TournamentPhaseKey.sortRank(lhs.fase)
        let rhsPhaseRank = TournamentPhaseKey.sortRank(rhs.fase)
        if lhsPhaseRank != rhsPhaseRank {
            return lhsPhaseRank < rhsPhaseRank
        }

        if lhs.giornata != rhs.giornata {
            return lhs.giornata < rhs.giornata
        }

        let lhsField = fieldPriority(lhs.campo)
        let rhsField = fieldPriority(rhs.campo)

        if lhsField != rhsField {
            return lhsField < rhsField
        }

        let lhsTime = lhs.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rhsTime = rhs.matchTime?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if lhsTime != rhsTime {
            return lhsTime < rhsTime
        }

        return (lhs.id ?? "") < (rhs.id ?? "")
    }

    private func fieldPriority(_ field: String?) -> Int {
        let normalized = field?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""

        switch normalized {
        case "A", "1", "CAMPO 1":
            return 0
        case "B", "2", "CAMPO 2":
            return 1
        case "":
            return 2
        default:
            return 3
        }
    }

    private func toggleTournamentNotifications() async {
        guard !isTogglingTournamentNotifications else { return }
        isTogglingTournamentNotifications = true
        defer { isTogglingTournamentNotifications = false }

        do {
            let shouldEnable = !appState.notificationService.isSubscribedToTournament(
                edition: appState.selectedEdition
            )
            _ = try await appState.notificationService.setTournamentSubscription(
                enabled: shouldEnable,
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
}

private struct WaitingTeamCard: View {
    let team: EditionTeam
    var index: Int = 0

    var body: some View {
        // Logo nudo che fluttua dolcemente, sfasato per indice.
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let offsetY = sin(time * 1.1 + Double(index) * 0.9) * 4

            VStack(spacing: 10) {
                logo
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.18), radius: 9, y: 6)
                    .offset(y: offsetY)
                Text(team.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let s = team.logoURL, !s.isEmpty, let url = URL(string: s) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFit().clipShape(Circle())
                } else {
                    monogram
                }
            }
        } else {
            monogram
        }
    }

    private var monogram: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [TournamentPalette.accent, TournamentPalette.accent.opacity(0.6)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            )
    }

    private var initials: String {
        let parts = team.displayName.split(separator: " ")
        guard let f = parts.first else { return "?" }
        if parts.count == 1 { return String(f.prefix(2)).uppercased() }
        return (String(f.prefix(1)) + String(parts[1].prefix(1))).uppercased()
    }
}

private struct MatchGroupSection: View {
    let title: String
    let matches: [Match]

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TournamentPalette.ink)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(TournamentPalette.surfaceMuted)

            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.offset) { index, match in
                    NavigationLink(destination: MatchDetailView(match: match)) {
                        MatchRowView(match: match)
                    }
                    .buttonStyle(.tournamentPress)

                    if index < matches.count - 1 {
                        Divider()
                            .background(TournamentPalette.divider)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .tournamentCard(padding: 0)
    }
}


/// Quanto e' scorsa la lista delle partite, per il logo che si ritira.
private struct ScorrimentoKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

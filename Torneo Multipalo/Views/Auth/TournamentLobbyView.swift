import SwiftUI

/// Lobby "Scegli il torneo" — gate forzato post-ingresso quando ci sono ≥2
/// tornei attivi. Porting della PWA `scegli-torneo.html` (approvata dall'owner):
/// design SOLO-LOGO (niente card né bordi), alone del colore del torneo dietro
/// al logo, badge stato iscrizioni sotto. Ordine: aperte → in arrivo →
/// prossimamente → chiuse → concluse, poi alfabetico.
///
/// Su tap: imposta il torneo corrente e chiama `onChosen` (l'AppRootView
/// prosegue verso l'app / il benvenuto-torneo).
struct TournamentLobbyView: View {
    @Environment(AppState.self) private var appState
    let onChosen: () -> Void

    @State private var entries: [LobbyEntry] = []
    @State private var isLoading = true
    /// L'elenco degli altri tornei sta chiuso finche' non lo si chiede.
    @State private var mostraTutti = false

    private var store: TournamentSelectionStore { appState.tournamentSelectionStore }

    var body: some View {
        OneDayEntranceScreen {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    if isLoading {
                        ProgressView()
                            .tint(OneDayEntrancePalette.gold)
                            .padding(.top, 48)
                    } else {
                        stage
                    }
                    Text("Potrai cambiare torneo in qualsiasi momento dal menu.")
                        .font(.caption)
                        .foregroundStyle(OneDayEntrancePalette.inkDim)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 44)
            }
        }
        .environment(\.colorScheme, .dark)
        .task { await load() }
    }

    // MARK: - Header (brand OneDay Cup)

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 8) {
            Text("OneDay Cup")
                .font(.footnote.weight(.bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(OneDayEntrancePalette.gold)
        }
    }

    // MARK: - Stage

    /// Un torneo solo, grande, al centro. Gli altri dietro a "Altri tornei".
    ///
    /// La griglia con tutti allo stesso peso aveva senso quando i tornei attivi
    /// erano due che contavano uguale. Oggi se ne gioca uno, e chiedere di
    /// scegliere fra un torneo vivo e uno concluso e' una domanda finta: chi
    /// apre l'app vuole entrare li' dentro, non decidere.
    ///
    /// Il primo della lista non e' "il primo che capita": l'ordinamento in
    /// `load()` mette davanti quello con le iscrizioni piu' vive.
    @ViewBuilder
    private var stage: some View {
        if let principale = entries.first {
            VStack(spacing: 22) {
                Button {
                    choose(principale)
                } label: {
                    TournamentLogoTile(entry: principale, grande: true)
                }
                .buttonStyle(LobbyTileButtonStyle())

                if entries.count > 1 {
                    VStack(spacing: 10) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { mostraTutti.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Text("Altri tornei")
                                    .font(.footnote.weight(.bold))
                                Image(systemName: mostraTutti ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tournamentPress)

                        // Una **lista** piccola, non di nuovo la griglia dei
                        // loghi grandi: quella era la schermata da cui si
                        // veniva, e riproporla identica sembrava un passo
                        // indietro invece che un dettaglio in più.
                        if mostraTutti {
                            VStack(spacing: 2) {
                                ForEach(entries.dropFirst()) { entry in
                                    Button { choose(entry) } label: { rigaTorneo(entry) }
                                        .buttonStyle(.tournamentPress)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Riga compatta: logo piccolo e nome. Niente stato, niente alone — quelli
    /// stanno sul torneo in evidenza, qui servirebbero solo a fare rumore.
    private func rigaTorneo(_ entry: LobbyEntry) -> some View {
        HStack(spacing: 12) {
            TournamentLogoTile(entry: entry, riga: true)
            Text(entry.tournament.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneDayEntrancePalette.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OneDayEntrancePalette.inkDim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }


    // MARK: - Actions

    private func choose(_ entry: LobbyEntry) {
        TournamentHaptics.selection()
        store.setCurrentTournament(entry.tournament.id)
        onChosen()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        // `isActive` include i sandbox del tester: il filtro su status secco
        // li avrebbe scartati proprio a chi deve provarli.
        let tournaments = (await store.loadAvailableTournaments())
            .filter { $0.isActive }

        // Se non c'è nulla da scegliere, prosegui trasparente.
        guard !tournaments.isEmpty else { onChosen(); return }

        let fs = appState.firestoreService
        var built: [LobbyEntry] = []
        for t in tournaments {
            let window = (try? await fs.fetchRegistrationWindow(for: t.id))
                ?? FirestoreService.RegistrationWindow(editionNum: nil, status: .notConfigured, openFrom: nil, openTo: nil)
            var kind = LobbyKind(from: window.status)
            if kind == .closed, let ed = window.editionNum,
               await fs.editionHasMatches(tournamentId: t.id, edition: ed) {
                kind = .done
            }
            built.append(LobbyEntry(tournament: t, kind: kind, window: window))
        }

        built.sort {
            if $0.kind.rank != $1.kind.rank { return $0.kind.rank < $1.kind.rank }
            return $0.tournament.displayName
                .localizedCaseInsensitiveCompare($1.tournament.displayName) == .orderedAscending
        }
        entries = built
    }
}

// MARK: - Model

struct LobbyEntry: Identifiable {
    let tournament: Tournament
    let kind: LobbyKind
    let window: FirestoreService.RegistrationWindow
    var id: String { tournament.id }
}

/// Loghi torneo bundlati come fallback quando `tournaments/{id}.logoUrl` non è
/// impostato su Firestore (che, se presente, vince). Parità con la PWA
/// (`scegli-torneo.html` LOCAL_LOGOS). `logoUrl` su Firestore ha comunque la precedenza.
enum LocalTournamentLogos {
    static let byId: [String: String] = [
        "mormon": "MormonLogo",
        "multipalo": "TournamentBrandLogo"
    ]
    static func assetName(for tid: String) -> String? { byId[tid] }
}

enum LobbyKind {
    case open, notYet, notConfigured, closed, done

    init(from status: FirestoreService.RegistrationWindow.Status) {
        switch status {
        case .open:          self = .open
        case .notYet:        self = .notYet
        case .closed:        self = .closed
        case .notConfigured: self = .notConfigured
        }
    }

    var rank: Int {
        switch self {
        case .open: return 0
        case .notYet: return 1
        case .notConfigured: return 2
        case .closed: return 3
        case .done: return 4
        }
    }
}

// MARK: - Logo tile

private struct TournamentLogoTile: View {
    let entry: LobbyEntry
    /// Il torneo in evidenza: stesso disegno, misure piu' generose.
    var grande = false
    /// Riga della lista "Altri tornei": solo il logo, piccolo, senza alone.
    var riga = false

    private var accent: Color { entry.tournament.branding.primaryColor ?? OneDayEntrancePalette.gold }
    private var isDone: Bool { entry.kind == .done }

    private var lato: CGFloat { grande ? 210 : 132 }

    var body: some View {
        if riga {
            logo
                .frame(width: 34, height: 34)
                .saturation(isDone ? 0.35 : 1)
                .opacity(isDone ? 0.7 : 1)
        } else {
            completo
        }
    }

    private var completo: some View {
        VStack(spacing: grande ? 20 : 16) {
            ZStack {
                // Glow discreto del colore torneo dietro il logo nudo.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(isDone ? 0.10 : 0.26), accent.opacity(0)],
                            center: .center, startRadius: 4, endRadius: lato * 0.65
                        )
                    )
                    .frame(width: lato * 1.14, height: lato * 1.14)
                    .blur(radius: grande ? 12 : 8)
                logo
                    .frame(width: lato, height: lato)
                    .saturation(isDone ? 0.35 : 1)
                    .opacity(isDone ? 0.7 : 1)
                    .shadow(color: .black.opacity(0.5), radius: grande ? 20 : 14, x: 0, y: 10)
            }
            .frame(height: lato * 1.18)

            if grande {
                Text(entry.tournament.displayName)
                    .font(.system(size: 30, weight: .heavy)).italic()
                    .textCase(.uppercase)
                    .foregroundStyle(OneDayEntrancePalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }

            badge
        }
    }

    @ViewBuilder
    private var logo: some View {
        if let url = entry.tournament.branding.logoURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: localOrMonogram
                }
            }
        } else {
            localOrMonogram
        }
    }

    /// Logo bundlato (parità PWA LOCAL_LOGOS) o, in assenza, monogramma.
    @ViewBuilder
    private var localOrMonogram: some View {
        if let asset = LocalTournamentLogos.assetName(for: entry.tournament.id) {
            Image(asset).resizable().scaledToFit()
        } else {
            monogram
        }
    }

    private var monogram: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [accent, accent.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                Text(initials(entry.tournament.displayName))
                    .font(.system(size: 52, weight: .black)).italic()
                    .foregroundStyle(.white)
            )
    }

    private var badge: some View {
        let b = badgeContent
        return HStack(spacing: 6) {
            if b.dot {
                Circle().fill(b.color).frame(width: 6, height: 6)
            }
            Text(b.label)
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .textCase(.uppercase)
        }
        .foregroundStyle(b.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(b.color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(b.color.opacity(0.28), lineWidth: 1))
    }

    private struct BadgeContent { var label: String; var color: Color; var dot: Bool }

    private var badgeContent: BadgeContent {
        let dim = OneDayEntrancePalette.inkDim
        switch entry.kind {
        case .open:
            return BadgeContent(label: "Iscrizioni aperte", color: Color(hex: "#34D399") ?? .green, dot: true)
        case .notYet:
            let from = Self.formatDay(entry.window.openFrom)
            return BadgeContent(label: from != nil ? "Iscrizioni dal \(from!)" : "Iscrizioni a breve",
                                color: OneDayEntrancePalette.goldBright, dot: false)
        case .notConfigured:
            return BadgeContent(label: "Prossimamente", color: OneDayEntrancePalette.goldBright, dot: false)
        case .closed:
            return BadgeContent(label: "Iscrizioni chiuse", color: dim, dot: false)
        case .done:
            return BadgeContent(label: "Concluso", color: dim, dot: false)
        }
    }

    private func initials(_ name: String) -> String {
        let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard let first = parts.first else { return "?" }
        if parts.count == 1 { return String(first.prefix(2)).uppercased() }
        return (String(first.prefix(1)) + String(parts[1].prefix(1))).uppercased()
    }

    private static func formatDay(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = DateFormatter()
        parser.dateFormat = "yyyy-MM-dd"
        parser.locale = Locale(identifier: "it_IT")
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "it_IT")
        out.dateFormat = "d MMMM"
        return out.string(from: date)
    }
}

// MARK: - Button style (float + press)

private struct LobbyTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

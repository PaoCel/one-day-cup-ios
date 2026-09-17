import SwiftUI

/// L'album delle figurine dell'edizione. Porting fedele di `vAlbum` della PWA.
///
/// Due schermate sole: l'**indice** (le squadre, ognuna col suo contatore) e
/// la **pagina di una squadra**. Non una lista unica di novanta caselle: con
/// dodici giocatori a squadra sarebbe uno scorrimento infinito, e nessuno
/// arriverebbe in fondo. Dentro una pagina si passa alle altre di lato, come
/// si sfoglia.
///
/// ⚠️ **Le caselle vuote portano un nome.** È il motivo per cui l'album
/// esiste: con quattro figurine su novantuno, quello che conta non è
/// valorizzare le quattro fatte, è che chi non ce l'ha veda il proprio buco
/// accanto a quello del compagno. Uno slot anonimo non lo farebbe.
///
/// Le carte NON si scontornano: il generatore mette attorno alla figurina un
/// bagliore che sfuma nel nero e non esiste un bordo netto da tagliare
/// (provato il 2026-09-02, anche con rembg: ritaglia il giocatore e butta via
/// la cornice). Il fondo nero della carta diventa quindi il cartoncino dentro
/// la casella, e le due sagome — piena e vuota — coincidono.

// MARK: - Modello

/// Una casella dell'album: un posto in rosa, con o senza adesivo attaccato.
struct AlbumCasella: Identifiable {
    let id: String
    let playerId: String?
    let nome: String
    let numero: Int?
    let figurina: Figurina?
    /// Vero solo per la casella di chi sta guardando: è l'unica che parla.
    let isMia: Bool

    /// "Gabriele Celestini" → "Celestini": nella casella vuota c'è spazio per
    /// una parola sola.
    var cognome: String {
        let parti = nome.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ").map(String.init)
        if parti.count > 1 { return parti.dropFirst().joined(separator: " ") }
        return parti.first ?? "—"
    }
}

struct AlbumSquadra: Identifiable {
    let id: String
    let nome: String
    let logo: String?
    let caselle: [AlbumCasella]

    var fatte: Int { caselle.filter { $0.figurina != nil }.count }
}

/// Costruisce le pagine dell'album da quello che l'app ha **già in memoria**:
/// squadre e rose dagli snapshot di partecipazione in `AppState`, figurine
/// dalla cache del `FigurineStore`. Nessuna lettura nuova, come nella PWA.
enum AlbumModello {

    @MainActor
    static func squadre(appState: AppState) -> [AlbumSquadra] {
        let tid = appState.currentTournamentId
        let store = appState.figurineStore
        let mio = mioPlayerId(appState)

        return appState.editionParticipations
            .filter { !$0.squadraId.isEmpty }
            .sorted { a, b in
                // Come la PWA: prima per girone (chi non ne ha finisce in
                // fondo), poi per nome.
                let ga = a.group ?? "Z", gb = b.group ?? "Z"
                if ga != gb { return ga < gb }
                return a.nomeSquadra.localizedCaseInsensitiveCompare(b.nomeSquadra) == .orderedAscending
            }
            .map { partecipazione in
                let rosa = partecipazione.playerSnapshots
                    .sorted { a, b in
                        // In ordine di numero di maglia, come si leggono le
                        // formazioni; i senza-numero in coda.
                        let na = a.numero ?? 999, nb = b.numero ?? 999
                        if na != nb { return na < nb }
                        return (a.nome ?? "").localizedCaseInsensitiveCompare(b.nome ?? "") == .orderedAscending
                    }
                let caselle = rosa.enumerated().map { indice, giocatore -> AlbumCasella in
                    let pid = giocatore.giocatoreId
                    return AlbumCasella(
                        id: pid ?? "\(partecipazione.squadraId)#\(indice)",
                        playerId: pid,
                        nome: giocatore.nome ?? "—",
                        numero: giocatore.numero,
                        figurina: store.figurina(pid, tournamentId: tid),
                        isMia: pid != nil && pid == mio
                    )
                }
                // Logo dello snapshot prima di quello vivo: l'album è
                // dell'edizione, e lo stemma è quello con cui la si gioca.
                let logoVivo = appState.teams.first { $0.id == partecipazione.squadraId }?.logoSquadra
                return AlbumSquadra(
                    id: partecipazione.squadraId,
                    nome: partecipazione.nomeSquadra,
                    logo: partecipazione.logoSquadra?.nonEmpty ?? logoVivo,
                    caselle: caselle
                )
            }
    }

    /// Il giocatore collegato all'account che sta guardando, se c'è: la sua
    /// casella vuota diventa l'invito "Fai la tua".
    @MainActor
    static func mioPlayerId(_ appState: AppState) -> String? {
        for ruolo in appState.authService.availableRoles {
            if case .player(let pid) = ruolo { return pid }
        }
        return appState.authService.playerIdIfAdmin
    }
}

// MARK: - Indice

struct AlbumView: View {
    @Environment(AppState.self) private var appState

    private var squadre: [AlbumSquadra] { AlbumModello.squadre(appState: appState) }

    var body: some View {
        let squadre = self.squadre
        let fatte = squadre.reduce(0) { $0 + $1.fatte }
        let totali = squadre.reduce(0) { $0 + $1.caselle.count }

        TournamentScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
                    testa(fatte: fatte, totali: totali)

                    if squadre.isEmpty {
                        if appState.figurineStore.isLoading || appState.isLoadingTeams {
                            LoadingView(message: "Apriamo l'album...")
                                .frame(maxWidth: .infinity)
                        } else {
                            EmptyStateView(
                                icon: "rectangle.portrait.on.rectangle.portrait.angled",
                                title: "Nessuna squadra iscritta",
                                message: "L'album si riempie con le iscrizioni."
                            )
                        }
                    } else {
                        indice(squadre: squadre)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appState.figurineStore.loadIfNeeded(using: appState.firestoreService)
        }
        .refreshable {
            await appState.figurineStore.refresh(using: appState.firestoreService)
        }
    }

    /// Il contatore grande con la barra: quanto album è già attaccato.
    private func testa(fatte: Int, totali: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(appState.currentTournamentName) · Edizione \(String(appState.selectedEdition))")
                .font(.caption.weight(.bold))
                .kerning(0.8)
                .textCase(.uppercase)
                .foregroundStyle(TournamentPalette.inkMuted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(fatte)")
                    .font(.system(size: 44, weight: .black))
                    .italic()
                    .foregroundStyle(TournamentPalette.accent)
                    .contentTransition(.numericText())
                Text("/ \(totali)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TournamentPalette.border)
                    Capsule()
                        .fill(TournamentPalette.accent)
                        .frame(width: totali > 0 ? geo.size.width * CGFloat(fatte) / CGFloat(totali) : 0)
                }
            }
            .frame(height: 4)
        }
    }

    private func indice(squadre: [AlbumSquadra]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 96), spacing: 10)],
            spacing: 14
        ) {
            ForEach(squadre) { squadra in
                NavigationLink(destination: AlbumPagesView(startTeamId: squadra.id)) {
                    VStack(spacing: 6) {
                        // Stemma nudo, mai chiuso in cerchi o card.
                        TournamentTeamLogo(urlString: squadra.logo, size: 56)
                        Text(squadra.nome)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(TournamentPalette.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text("\(squadra.fatte) / \(squadra.caselle.count)")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(squadra.fatte > 0 ? TournamentPalette.accent : TournamentPalette.inkMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tournamentPress)
            }
        }
    }
}

// MARK: - Pagina squadra

/// Le pagine dell'album, una per squadra, da sfogliare di lato. Il `TabView`
/// a pagine dà lo swipe orizzontale gratis e con la fisica giusta; le frecce
/// restano per chi non lo scopre, e in più sanno fare il giro.
struct AlbumPagesView: View {
    let startTeamId: String

    @Environment(AppState.self) private var appState
    @State private var indice = 0
    @State private var posizionato = false
    /// La casella aperta a schermo pieno; `nil` = lente chiusa.
    @State private var lente: AlbumCasella?
    /// Scheda da aprire dal collegamento sotto la carta.
    @State private var schedaDaAprire: SchedaDestinazione?

    private struct SchedaDestinazione: Identifiable, Hashable {
        let id: String
    }

    private var squadre: [AlbumSquadra] { AlbumModello.squadre(appState: appState) }

    var body: some View {
        let squadre = self.squadre

        TournamentScreen {
            if squadre.isEmpty {
                LoadingView(message: "Apriamo l'album...")
            } else {
                VStack(spacing: 0) {
                    TabView(selection: $indice) {
                        ForEach(Array(squadre.enumerated()), id: \.element.id) { i, squadra in
                            paginaSquadra(squadra, totale: squadre.count)
                                .tag(i)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    punti(totale: squadre.count)
                }
            }
        }
        .navigationTitle("Album")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await appState.figurineStore.loadIfNeeded(using: appState.firestoreService)
            // La pagina di partenza si può fissare solo quando le squadre ci
            // sono: arrivando dalla scheda squadra lo store può essere vergine.
            if !posizionato, let i = self.squadre.firstIndex(where: { $0.id == startTeamId }) {
                indice = i
                posizionato = true
            }
        }
        // La lente copre tutto, barre comprese: è un oggetto in mano, non una
        // schermata dell'app.
        .toolbar(lente == nil ? .automatic : .hidden, for: .navigationBar)
        .toolbar(lente == nil ? .automatic : .hidden, for: .tabBar)
        .overlay {
            if let casella = lente, let figurina = casella.figurina {
                FigurinaLenteView(
                    figurina: figurina,
                    nome: casella.nome,
                    apriScheda: casella.playerId.map { pid in
                        {
                            lente = nil
                            schedaDaAprire = SchedaDestinazione(id: pid)
                        }
                    },
                    retroURL: appState.currentBranding.cardBackURL?.absoluteString,
                    chiudi: { withAnimation(.easeOut(duration: 0.15)) { lente = nil } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: lente?.id)
        .navigationDestination(item: $schedaDaAprire) { destinazione in
            PlayerDetailLazyView(playerId: destinazione.id)
        }
    }

    private func paginaSquadra(_ squadra: AlbumSquadra, totale: Int) -> some View {
        ScrollView {
            VStack(spacing: TournamentSpacing.sm) {
                intestazione(squadra, totale: totale)

                if squadra.caselle.isEmpty {
                    Text("Rosa non ancora in archivio.")
                        .font(.subheadline)
                        .foregroundStyle(TournamentPalette.inkMuted)
                        .padding(.top, 32)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3),
                        spacing: 9
                    ) {
                        ForEach(squadra.caselle) { casella in
                            AlbumCasellaView(casella: casella) {
                                withAnimation(.easeOut(duration: 0.15)) { lente = casella }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }

                Spacer(minLength: 16)
            }
            .padding(.top, 8)
        }
    }

    private func intestazione(_ squadra: AlbumSquadra, totale: Int) -> some View {
        HStack(spacing: 10) {
            freccia(sistema: "chevron.left", etichetta: "Squadra precedente") {
                withAnimation { indice = (indice - 1 + totale) % totale }
            }

            HStack(spacing: 10) {
                TournamentTeamLogo(urlString: squadra.logo, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(squadra.nome)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TournamentPalette.ink)
                        .lineLimit(1)
                    Text("\(squadra.fatte) / \(squadra.caselle.count) figurine")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
                Spacer(minLength: 0)
            }

            freccia(sistema: "chevron.right", etichetta: "Squadra successiva") {
                withAnimation { indice = (indice + 1) % totale }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func freccia(sistema: String, etichetta: String, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            Image(systemName: sistema)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(TournamentPalette.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(TournamentPalette.surfaceMuted))
        }
        .buttonStyle(.tournamentPress)
        .accessibilityLabel(etichetta)
    }

    /// I puntini in fondo: dicono a che pagina sei, come sfogliando un album
    /// vero si sente quante pagine mancano.
    private func punti(totale: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<totale, id: \.self) { i in
                Circle()
                    .fill(i == indice ? TournamentPalette.accent : TournamentPalette.border)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }
}

// MARK: - Casella

/// Una casella della griglia, rapporto 2:3 come la carta.
///
/// Piena: la miniatura riempie tutto, col suo nero da cartoncino. Vuota:
/// numero grande sbiadito e cognome, perché il buco deve avere un nome.
/// Mia: bordo col colore del torneo e "Fai la tua" — l'unica casella che
/// parla, le altre restano zitte.
private struct AlbumCasellaView: View {
    let casella: AlbumCasella
    let apri: () -> Void

    private let raggio: CGFloat = 12

    var body: some View {
        Group {
            if casella.figurina != nil {
                Button(action: apri) {
                    piena.contentShape(RoundedRectangle(cornerRadius: raggio, style: .continuous))
                }
                .buttonStyle(.tournamentPress)
                .accessibilityLabel("Figurina di \(casella.nome)")
            } else if casella.isMia, let pid = casella.playerId {
                NavigationLink(destination: FigurinaFlowLazyView(playerId: pid)) {
                    vuota.contentShape(RoundedRectangle(cornerRadius: raggio, style: .continuous))
                }
                .buttonStyle(.tournamentPress)
                .accessibilityLabel("Fai la tua figurina")
            } else {
                vuota
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(casella.nome), figurina mancante")
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
    }

    private var piena: some View {
        CachedAsyncImage(
            urlString: casella.figurina?.thumbURL,
            placeholderIcon: "rectangle.portrait.on.rectangle.portrait.angled",
            placeholderColor: .black,
            contentMode: .fill
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: raggio, style: .continuous))
    }

    private var vuota: some View {
        VStack(spacing: 6) {
            Text(casella.numero.map(String.init) ?? "–")
                .font(.system(size: 26, weight: .semibold, design: .monospaced))
                .foregroundStyle(colore.opacity(0.5))
            Text(casella.isMia ? "Fai la tua" : casella.cognome)
                .font(.system(size: 11, weight: casella.isMia ? .bold : .regular))
                .foregroundStyle(colore)
                .lineLimit(1)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Nella PWA la casella vuota è più chiara del fondo scuro; qui, su
        // tema chiaro, l'equivalente è il bianco delle card col solito bordo
        // sottile — senza, la sagoma annegava nel fondale.
        .background(
            RoundedRectangle(cornerRadius: raggio, style: .continuous)
                .fill(TournamentPalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: raggio, style: .continuous)
                .stroke(casella.isMia ? TournamentPalette.accent : TournamentPalette.border,
                        lineWidth: 1)
        )
    }

    private var colore: Color {
        casella.isMia ? TournamentPalette.accent : TournamentPalette.inkMuted
    }
}

// MARK: - Ingresso al flusso figurina

/// Carica il documento del giocatore e apre il flow di creazione già
/// esistente: la casella "Fai la tua" non ha in mano il `Player` completo.
private struct FigurinaFlowLazyView: View {
    let playerId: String
    @Environment(AppState.self) private var appState
    @State private var player: Player?
    @State private var caricamentoFallito = false

    var body: some View {
        Group {
            if let player {
                let team = appState.teams.first { $0.id == player.teamId }
                PlayerCardFlowView(
                    player: player,
                    tournamentId: appState.currentTournamentId,
                    teamName: team?.nomeSquadra,
                    teamLogoURL: team?.logoSquadra,
                    tournamentLogoURL: appState.currentBranding.logoURL?.absoluteString
                )
            } else if caricamentoFallito {
                EmptyStateView(
                    icon: "person.fill.questionmark",
                    title: "Giocatore non trovato",
                    message: "Riprova tra un momento."
                )
            } else {
                LoadingView(message: "Prepariamo la tua figurina...")
            }
        }
        .task {
            guard player == nil else { return }
            player = try? await appState.firestoreService.fetchPlayer(id: playerId)
            caricamentoFallito = (player == nil)
        }
    }
}

// MARK: - Striscia in home

/// La striscia dell'album in home: esiste perché ogni figurina nuova è una
/// notizia finché sono poche. Non compare se il torneo non ne ha nessuna —
/// una riga a zero non invita, avvisa che non funziona.
struct AlbumStripView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let squadre = AlbumModello.squadre(appState: appState)
        let totale = squadre.reduce(0) { $0 + $1.caselle.count }
        let fatte = squadre.flatMap(\.caselle).filter { $0.figurina != nil }

        if !fatte.isEmpty {
            NavigationLink(destination: AlbumView()) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Album")
                            .font(.caption.weight(.bold))
                            .kerning(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(TournamentPalette.inkMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(fatte.count)")
                                .font(.system(size: 26, weight: .black))
                                .italic()
                                .foregroundStyle(TournamentPalette.accent)
                            Text("/ \(totale)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(TournamentPalette.inkMuted)
                        }
                    }

                    Spacer(minLength: 8)

                    // Le ultime figurine attaccate, come mazzetto sventagliato:
                    // ultime in ordine d'album, la più recente davanti.
                    HStack(spacing: -8) {
                        ForEach(fatte.suffix(5).reversed()) { casella in
                            CachedAsyncImage(
                                urlString: casella.figurina?.thumbURL,
                                placeholderIcon: "rectangle.portrait.fill",
                                placeholderColor: .black,
                                contentMode: .fill
                            )
                            .frame(width: 34, height: 51)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                        .fill(TournamentPalette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous)
                        .stroke(TournamentPalette.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: TournamentRadius.control, style: .continuous))
            }
            .buttonStyle(.tournamentPress)
            .accessibilityLabel("Album figurine: \(fatte.count) su \(totale). Sfoglia")
        }
    }
}

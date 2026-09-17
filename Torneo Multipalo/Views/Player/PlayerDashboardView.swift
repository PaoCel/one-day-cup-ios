import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

// MARK: - ViewModel

@Observable
@MainActor
final class PlayerDashboardViewModel {
    var player: Player?
    var team: Team?
    var pendingCount = 0
    var isLoading = true
    var isUploadingPhoto = false

    private let requestsListener = FirestoreListenerToken()

    func start(playerId: String, firestoreService: FirestoreService, playerAuthUid: String?) {
        isLoading = true
        Task {
            do {
                player = try await firestoreService.fetchPlayer(id: playerId)
                if let teamId = player?.teamId {
                    team = try await firestoreService.fetchTeam(id: teamId)
                }
                requestsListener.replace(with: firestoreService.listenToRequests(
                    forPlayerId: playerId,
                    playerAuthUid: playerAuthUid ?? player?.playerAuthUid
                ) { [weak self] reqs in
                    Task { @MainActor [weak self, reqs] in
                        self?.pendingCount = reqs.filter(\.isPendingLike).count
                    }
                })
            } catch {
                print("Errore caricamento giocatore: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    func uploadPhoto(image: UIImage, playerId: String,
                     storageService: StorageService,
                     firestoreService: FirestoreService) async {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return }
        isUploadingPhoto = true
        do {
            let path = "giocatori/profili/\(playerId).jpg"
            let url = try await storageService.uploadImage(data, path: path)
            let urlString = url.absoluteString
            try await firestoreService.updatePlayerPicture(playerId: playerId, pictureURL: urlString)
            player?.pictureURL = urlString
        } catch {
            print("Errore upload foto: \(error.localizedDescription)")
        }
        isUploadingPhoto = false
    }

    func stop() { requestsListener.cancel() }
}

// MARK: - View

struct PlayerDashboardView: View {
    let playerId: String
    /// Se true, non avvolge il contenuto in un NavigationStack (usato quando pushato da AdminRouter).
    var isNested: Bool = false

    @Environment(AppState.self) private var appState
    @State private var vm = PlayerDashboardViewModel()
    @State private var showImagePicker = false
    @State private var showSourceChoice = false
    @State private var selectedImage: UIImage?
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    private var computed: ComputedPlayerStats {
        guard let player = vm.player else {
            return ComputedPlayerStats(goals: 0, appearances: 0, yellow: 0, red: 0)
        }
        return PlayerDetailView.computeStats(for: player, from: appState.matches)
    }

    private var recentMatches: [Match] {
        guard let player = vm.player else { return [] }
        return appState.matches
            .filter { m in
                (m.isPlayed || m.isStarted) &&
                m.safeEventi.contains { player.matches(event: $0) }
            }
            .sorted { ($0.giornata) > ($1.giornata) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        if isNested {
            mainContent
        } else {
            NavigationStack {
                mainContent
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        TournamentScreen {
            Group {
                if vm.isLoading {
                    LoadingView(message: "Caricamento profilo...")
                } else if let player = vm.player {
                    ScrollView {
                        VStack(spacing: 20) {
                            ProfileRoleSwitcher()
                            tournamentStrip
                            playerHeader(player)
                            computedStatsGrid
                            if !recentMatches.isEmpty { recentMatchesCard }
                            infoCard(player)
                            playerCardButton(player: player)
                            careerButton(player: player)
                            notificationPreferencesButton
                            requestsButton
                            // Phase 3c — link picker torneo (auto-hide se < 2 tornei).
                            TournamentPickerLinkSection()
                            if !isNested {
                                logoutButton
                                accountDeletionSection
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                } else {
                    EmptyStateView(
                        icon: "person.fill.xmark",
                        title: "Profilo non trovato",
                        message: "Impossibile caricare i tuoi dati."
                    )
                }
            }
        }
        .navigationTitle("Il mio profilo")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSourceChoice = true
                } label: {
                    Image(systemName: "camera")
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage, sourceType: imageSourceType)
        }
        .confirmationDialog("Scegli foto", isPresented: $showSourceChoice) {
            Button("Fotocamera") {
                presentImagePicker(.camera)
            }
            Button("Libreria foto") {
                presentImagePicker(.photoLibrary)
            }
            Button("Annulla", role: .cancel) {}
        }
        .onChange(of: selectedImage) { _, newImage in
            if let newImage {
                Task {
                    await vm.uploadPhoto(
                        image: newImage,
                        playerId: playerId,
                        storageService: appState.storageService,
                        firestoreService: appState.firestoreService
                    )
                }
            }
        }
        .onAppear {
            vm.start(playerId: playerId,
                     firestoreService: appState.firestoreService,
                     playerAuthUid: appState.authService.currentUser?.uid)
            Task {
                guard !appState.runtimeSafety.protectsRealData else { return }
                guard appState.authService.currentUser != nil else { return }
                _ = await appState.notificationService.requestPermissionIfNeeded()
                if let token = appState.notificationService.fcmToken {
                    try? await appState.cloudFunctionsService.registerFcmToken(
                        token: token,
                        installationId: appState.notificationService.installationId
                    )
                }
            }
        }
        .onDisappear { vm.stop() }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Header

    /// Riga del torneo in cima al profilo.
    ///
    /// Senza, la pagina non diceva in quale torneo fossero i numeri che mostra:
    /// con piu' tornei nello stesso account e' un'informazione, non un ornamento.
    private var tournamentStrip: some View {
        HStack(spacing: 10) {
            if let logo = appState.currentBranding.logoURL {
                CachedAsyncImage(urlString: logo.absoluteString, placeholderIcon: "trophy.fill", contentMode: .fit)
                    .frame(width: 30, height: 30)
            }
            Text(appState.currentTournamentName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
            Spacer(minLength: 0)
            TournamentEditionMenu()
        }
        .accessibilityElement(children: .combine)
    }

    private func playerHeader(_ player: Player) -> some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(
                    urlString: player.displayPhotoURL,
                    placeholderIcon: "person.fill",
                    placeholderColor: TournamentPalette.accentSoft
                )
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)

                if vm.isUploadingPhoto {
                    ProgressView()
                        .frame(width: 28, height: 28)
                        .background(Color(.systemBackground))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 8)

            VStack(spacing: 4) {
                Text(player.nomeCompleto)
                    .font(.title2.bold())
                    .foregroundStyle(TournamentPalette.ink)

                HStack(spacing: 8) {
                    if let pos = player.positionPrimary, !pos.isEmpty {
                        TournamentPill(label: pos, tone: .accent)
                    }
                    if let numero = player.numeroMaglia {
                        TournamentPill(label: "#\(numero)", tone: .neutral)
                    }
                }

                if let squadra = vm.team {
                    HStack(spacing: 7) {
                        // Lo stemma vero, non un simbolo generico: la squadra ha
                        // un logo e questa e' la pagina dove ci si riconosce.
                        if let logo = squadra.logoSquadra, !logo.isEmpty {
                            CachedAsyncImage(urlString: logo, placeholderIcon: "shield.fill", contentMode: .fit)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "shield.fill")
                                .font(.caption)
                                .foregroundStyle(Color(hex: squadra.colori.principale) ?? .blue)
                        }
                        Text(squadra.nomeSquadra)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TournamentPalette.ink)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .tournamentCard()
    }

    // MARK: - Computed Stats

    private var computedStatsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            TournamentSectionHeader(
                title: "Statistiche",
                subtitle: "Edizione \(appState.selectedEdition) · \(appState.currentTournamentName)"
            )

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()),
                                GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 10) {
                statCell(valore: "\(computed.goals)", label: "Gol", icon: "soccerball", colore: TournamentPalette.accent)
                statCell(valore: "\(computed.appearances)", label: "Presenze", icon: "sportscourt.fill", colore: TournamentPalette.warm)
                statCell(valore: "\(computed.yellow)", label: "Amm.", icon: "rectangle.fill", colore: TournamentPalette.warm)
                statCell(valore: "\(computed.red)", label: "Esp.", icon: "rectangle.fill", colore: TournamentPalette.danger)
            }

            // Tutti zero non vuol dire "profilo vuoto": quasi sempre vuol dire
            // che quell'edizione non e' ancora stata giocata. Senza dirlo,
            // sembra che manchino i dati.
            if computed.goals == 0 && computed.appearances == 0 && computed.yellow == 0 && computed.red == 0 {
                Text(appState.availableEditions.count > 1
                     ? "Questa edizione non è ancora stata giocata. Cambia edizione qui sopra per vedere le altre."
                     : "Questa edizione non è ancora stata giocata.")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tournamentCard()
    }

    // MARK: - Ultime partite

    private var recentMatchesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Ultime partite",
                subtitle: "Le gare più recenti in cui compaiono eventi del profilo."
            )

            ForEach(recentMatches) { m in
                NavigationLink(destination: MatchDetailView(match: m)) {
                    let resolved = appState.resolvedTeams(for: m)
                    HStack(spacing: 8) {
                        Text(resolved.team1.name)
                            .font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(m.team1Goals) - \(m.team2Goals)")
                            .font(.caption.bold().monospacedDigit())
                        Spacer()
                        Text(resolved.team2.name)
                            .font(.caption).lineLimit(1)
                    }
                    .padding(.vertical, 8)
                }
                .foregroundStyle(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private func statCell(valore: String, label: String, icon: String, colore: Color) -> some View {
        TournamentMetricTile(value: valore, label: label, icon: icon, tint: colore)
    }

    // MARK: - Info card

    private func infoCard(_ player: Player) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TournamentSectionHeader(
                title: "Dettagli",
                subtitle: "Informazioni personali e stato di tesseramento."
            )

            if let piede = player.piedeDominante, !piede.isEmpty {
                infoRow(icon: "figure.run", label: "Piede dominante", valore: piede)
            }
            if let pos2 = player.positionSecondary, !pos2.isEmpty {
                infoRow(icon: "arrow.triangle.swap", label: "Posizione alt.", valore: pos2)
            }
            if let status = player.tesseramentoStatus {
                let label = status == "tesserato" ? "Tesserato" : "Free agent"
                let color = status == "tesserato" ? (Color(hex: "#10b981") ?? .green) : .secondary
                infoRow(icon: "checkmark.seal.fill", label: "Stato", valore: label, valueColor: color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tournamentCard()
    }

    private func infoRow(icon: String, label: String, valore: String,
                          valueColor: Color = .primary) -> some View {
        TournamentInfoRow(icon: icon, label: label, value: valore, valueColor: valueColor)
    }

    // MARK: - Pulsante richieste

    private var requestsButton: some View {
        NavigationLink(destination: IncomingRequestsView(
            playerId: playerId,
            playerAuthUid: appState.authService.currentUser?.uid
        )) {
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                Text("Richieste ricevute")
                Spacer()
                if vm.pendingCount > 0 {
                    Text("\(vm.pendingCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(TournamentPalette.danger)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .tournamentButtonChrome(.neutral)
        }
        .buttonStyle(.tournamentPress)
        .foregroundStyle(.primary)
    }

    // MARK: - Figurina

    /// Ingresso al flow della figurina. La squadra serve solo per stampare nome
    /// e logo sulla card: se il giocatore e' svincolato la card si fa lo stesso.
    private func playerCardButton(player: Player) -> some View {
        let team = appState.teams.first { $0.id == player.teamId }
        return NavigationLink(destination: PlayerCardFlowView(
            player: player,
            tournamentId: appState.currentTournamentId,
            teamName: team?.nomeSquadra,
            teamLogoURL: team?.logoSquadra,
            tournamentLogoURL: appState.currentBranding.logoURL?.absoluteString
        )) {
            HStack {
                Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill")
                Text("La mia figurina")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .tournamentButtonChrome(.neutral)
        }
        .buttonStyle(.tournamentPress)
        .foregroundStyle(.primary)
    }

    // MARK: - Career

    private func careerButton(player: Player) -> some View {
        let careerPlayerId = player.firestoreIdentifier ?? playerId
        return NavigationLink(destination: PlayerCareerView(
            playerId: careerPlayerId,
            fallbackName: player.nomeCompleto
        )) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("La mia carriera")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .tournamentButtonChrome(.neutral)
        }
        .buttonStyle(.tournamentPress)
        .foregroundStyle(.primary)
    }

    private var notificationPreferencesButton: some View {
        NavigationLink(destination: NotificationPreferencesView()) {
            HStack {
                Image(systemName: "bell.badge")
                Text("Notifiche")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
            .tournamentButtonChrome(.neutral)
        }
        .buttonStyle(.tournamentPress)
        .foregroundStyle(.primary)
    }

    // MARK: - Logout

    private var logoutButton: some View {
        Button(role: .destructive) {
            appState.authService.logout()
        } label: {
            Label("Esci dall'account", systemImage: "rectangle.portrait.and.arrow.right")
                .tournamentButtonChrome(.destructive)
        }
        .buttonStyle(.tournamentPress)
    }

    private var accountDeletionSection: some View {
        VStack(spacing: 16) {
            AccountDeletionSection()
            LegalLinksSection()
        }
    }

    private func presentImagePicker(_ sourceType: UIImagePickerController.SourceType) {
        guard UIImagePickerController.isSourceTypeAvailable(sourceType) else {
            alertTitle = "Sorgente non disponibile"
            alertMessage = sourceType == .camera
                ? "La fotocamera non e disponibile su questo dispositivo."
                : "La libreria foto non e disponibile in questo momento."
            showAlert = true
            return
        }

        imageSourceType = sourceType
        showImagePicker = true
    }
}

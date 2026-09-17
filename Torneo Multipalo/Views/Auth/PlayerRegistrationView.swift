import SwiftUI
import FirebaseAuth

struct PlayerRegistrationView: View {
    private enum RegistrationMode: String, CaseIterable, Identifiable {
        case claimExisting
        case createFreeAgent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .claimExisting:
                return "Collega profilo"
            case .createFreeAgent:
                return "Nuovo svincolato"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var registrationMode: RegistrationMode = .claimExisting

    // Dati giocatore nuovo
    @State private var nomeCompleto = ""
    @State private var numeroMagliaText = ""
    @State private var posizione = ""
    @State private var piedeDominante = ""

    // Claim profilo esistente
    @State private var teams: [Team] = []
    @State private var players: [Player] = []
    @State private var selectedTeamId = ""
    @State private var selectedExistingPlayerId: String?
    @State private var isLoadingExistingProfiles = false

    // Account
    @State private var emailInput = ""
    @State private var usaEmailGenerata = false
    @State private var password = ""
    @State private var confermaPassword = ""
    @State private var generatedEmailSuffix = String(Int.random(in: 1000...9999))

    // Stato
    @State private var isLoading = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    // Header informativo iscrizioni (stato/date/evento). No gating: i giocatori
    // possono collegare/creare il profilo a prescindere dalla finestra squadre.
    @State private var registrationWindow: FirestoreService.RegistrationWindow?
    @State private var tournamentDoc: Tournament?

    private let posizioniDisponibili = [
        "Portiere", "Difensore", "Centrocampista", "Attaccante", "Ala"
    ]
    private let piediDisponibili = ["Destro", "Sinistro", "Ambidestro"]

    private var authenticatedUser: FirebaseAuth.User? { appState.authService.currentUser }
    private var hasAuthenticatedSession: Bool { authenticatedUser != nil }

    private var emailSeedName: String {
        switch registrationMode {
        case .claimExisting:
            return selectedExistingPlayer?.nomeCompleto ?? ""
        case .createFreeAgent:
            return nomeCompleto
        }
    }

    private var emailEffettiva: String {
        if usaEmailGenerata || emailInput.trimmingCharacters(in: .whitespaces).isEmpty {
            let base = normalizedGeneratedEmailBase(from: emailSeedName)
            return "\(base).\(generatedEmailSuffix)@players.torneomultipalo.app"
        }
        return emailInput.trimmingCharacters(in: .whitespaces)
    }

    private var claimableTeams: [Team] {
        let teamIdsWithUnclaimedPlayers = Set(
            players.compactMap { player -> String? in
                guard let teamId = player.teamId,
                      !teamId.isEmpty,
                      !player.isClaimed else {
                    return nil
                }
                return teamId
            }
        )

        return teams
            .filter { team in
                guard let teamId = team.id else { return false }
                return teamIdsWithUnclaimedPlayers.contains(teamId)
            }
            .sorted {
                $0.nomeSquadra.localizedCaseInsensitiveCompare($1.nomeSquadra) == .orderedAscending
            }
    }

    private var claimablePlayersForSelectedTeam: [Player] {
        players
            .filter { player in
                player.teamId == selectedTeamId && !player.isClaimed
            }
            .sorted {
                if ($0.numeroMaglia ?? Int.max) != ($1.numeroMaglia ?? Int.max) {
                    return ($0.numeroMaglia ?? Int.max) < ($1.numeroMaglia ?? Int.max)
                }
                return $0.nomeCompleto.localizedCaseInsensitiveCompare($1.nomeCompleto) == .orderedAscending
            }
    }

    private var selectedExistingPlayer: Player? {
        guard let selectedExistingPlayerId else { return nil }
        return players.first { $0.id == selectedExistingPlayerId }
    }

    private var submitButtonTitle: String {
        switch registrationMode {
        case .claimExisting:
            return "Collega profilo"
        case .createFreeAgent:
            return "Crea profilo"
        }
    }

    var body: some View {
        OneDayEntranceScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OneDayEntranceHero(
                        eyebrow: "Registrazione giocatore",
                        title: registrationMode == .claimExisting
                            ? "Collega il tuo profilo esistente al torneo"
                            : "Crea un nuovo profilo giocatore pronto per il torneo",
                        subtitle: registrationMode == .claimExisting
                            ? "Se sei gia in una rosa, seleziona squadra e profilo non ancora reclamato: evitiamo duplicati e allineiamo i dati reali."
                            : "Ruolo, numero e credenziali vengono raccolti in un flusso iOS coerente con il backend reale.",
                        systemImage: registrationMode == .claimExisting ? "link.circle.fill" : "person.fill"
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    if let w = registrationWindow {
                        RegistrationStatusHeader(window: w, tournament: tournamentDoc)
                            .padding(.horizontal, 16)
                    }

                    OneDayEntranceSection(
                        title: "Modalita",
                        subtitle: "Scegli se collegare una scheda gia esistente o creare un nuovo profilo svincolato.",
                        icon: "arrow.triangle.branch"
                    ) {
                        Picker("Modalita", selection: $registrationMode) {
                            ForEach(RegistrationMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal, 16)

                    Group {
                        switch registrationMode {
                        case .claimExisting:
                            existingProfileSection
                        case .createFreeAgent:
                            newProfileSection
                        }
                    }
                    .padding(.horizontal, 16)

                    accessSection
                        .padding(.horizontal, 16)

                    Button {
                        Task { await registraGiocatore() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white).padding(.trailing, 4)
                            }
                            Text(submitButtonTitle)
                        }
                        .oneDayEntranceButton(.primaryGold)
                    }
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.7 : 1)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Registra Giocatore")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.colorScheme, .dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            registrationWindow = try? await appState.firestoreService.fetchRegistrationWindow()
            tournamentDoc = await appState.tournamentSelectionStore.currentTournamentDoc()
            await loadExistingProfilesIfNeeded()
        }
        .onChange(of: registrationMode) { _, newValue in
            if newValue == .claimExisting {
                Task { await loadExistingProfilesIfNeeded() }
            }
        }
        .onChange(of: selectedTeamId) { _, _ in
            selectedExistingPlayerId = nil
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Sections

    private var existingProfileSection: some View {
        OneDayEntranceSection(
            title: "Profilo esistente",
            subtitle: "Seleziona una squadra e collega uno dei profili non ancora reclamati.",
            icon: "person.text.rectangle.fill"
        ) {
            if isLoadingExistingProfiles {
                LoadingView(message: "Caricamento profili disponibili...")
            } else if claimableTeams.isEmpty {
                EmptyStateView(
                    icon: "person.crop.circle.badge.exclamationmark",
                    title: "Nessun profilo da collegare",
                    message: "Al momento non risultano giocatori di squadra ancora non reclamati."
                )
            } else {
                formField(label: "Squadra") {
                    Picker("Squadra", selection: $selectedTeamId) {
                        Text("Seleziona...").tag("")
                        ForEach(claimableTeams) { team in
                            Text(team.nomeSquadra).tag(team.id ?? "")
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if selectedTeamId.isEmpty {
                    Text("Scegli una squadra per vedere i profili ancora disponibili.")
                        .font(.caption)
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                        .padding(.horizontal, 4)
                } else if claimablePlayersForSelectedTeam.isEmpty {
                    Text("Questa squadra non ha profili disponibili da collegare.")
                        .font(.caption)
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                        .padding(.horizontal, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Profili disponibili")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)

                        ForEach(claimablePlayersForSelectedTeam) { player in
                            Button {
                                selectedExistingPlayerId = player.id
                            } label: {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(
                                        urlString: player.displayPhotoURL,
                                        placeholderIcon: "person.fill",
                                        placeholderColor: OneDayEntrancePalette.surface,
                                        contentAlignment: .top
                                    )
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(player.nomeCompleto)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(OneDayEntrancePalette.ink)

                                        HStack(spacing: 8) {
                                            if let numero = player.numeroMaglia {
                                                Text("#\(numero)")
                                                    .font(.caption)
                                                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                                            }
                                            if let position = player.positionPrimary, !position.isEmpty {
                                                Text(position)
                                                    .font(.caption)
                                                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: selectedExistingPlayerId == player.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selectedExistingPlayerId == player.id ? OneDayEntrancePalette.gold : OneDayEntrancePalette.inkMuted)
                                }
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                                        .fill(OneDayEntrancePalette.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                                        .stroke(
                                            selectedExistingPlayerId == player.id ? OneDayEntrancePalette.gold : OneDayEntrancePalette.stroke,
                                            lineWidth: selectedExistingPlayerId == player.id ? 2 : 1
                                        )
                                )
                            }
                            .buttonStyle(.tournamentPress)
                        }
                    }
                }
            }
        }
    }

    private var newProfileSection: some View {
        OneDayEntranceSection(
            title: "Nuovo profilo",
            subtitle: "Informazioni sportive principali del profilo giocatore.",
            icon: "person.fill"
        ) {
            formField(label: "Nome completo") {
                TextField("Mario Rossi", text: $nomeCompleto)
                    .textContentType(.name)
            }

            formField(label: "Numero maglia") {
                TextField("Es. 10", text: $numeroMagliaText)
                    .keyboardType(.numberPad)
            }

            formField(label: "Posizione in campo") {
                Picker("Posizione", selection: $posizione) {
                    Text("Seleziona...").tag("")
                    ForEach(posizioniDisponibili, id: \.self) { pos in
                        Text(pos).tag(pos)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            formField(label: "Piede dominante") {
                Picker("Piede", selection: $piedeDominante) {
                    Text("Seleziona...").tag("")
                    ForEach(piediDisponibili, id: \.self) { piede in
                        Text(piede).tag(piede)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var accessSection: some View {
        OneDayEntranceSection(
            title: hasAuthenticatedSession ? "Accesso attivo" : "Credenziali accesso",
            subtitle: accessSectionSubtitle,
            icon: hasAuthenticatedSession ? "checkmark.shield.fill" : "lock.fill"
        ) {
            if hasAuthenticatedSession {
                authenticatedAccountCard
            } else {
                Toggle(isOn: $usaEmailGenerata) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usa email automatica")
                            .font(.subheadline)
                        Text("Verrà generata un'email fittizia per il login")
                            .font(.caption)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    }
                }
                .tint(OneDayEntrancePalette.gold)
                .oneDayEntranceCard()

                if !usaEmailGenerata {
                    formField(label: "Email (opzionale)") {
                        TextField("mario@esempio.it", text: $emailInput)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } else if !emailSeedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(OneDayEntrancePalette.gold)
                        Text("Email: \(emailEffettiva)")
                            .font(.caption)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 4)
                }

                formField(label: "Password") {
                    SecureField("Minimo 8 caratteri", text: $password)
                        .textContentType(.newPassword)
                }

                formField(label: "Conferma password") {
                    SecureField("Ripeti la password", text: $confermaPassword)
                        .textContentType(.newPassword)
                }

                if !password.isEmpty && !confermaPassword.isEmpty && password != confermaPassword {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(OneDayEntrancePalette.danger)
                        Text("Le password non coincidono.")
                            .font(.caption)
                            .foregroundStyle(OneDayEntrancePalette.danger)
                    }
                }
            }
        }
    }

    // MARK: - Helpers UI

    private func formField<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(OneDayEntrancePalette.inkMuted)
            content()
                .oneDayEntranceInput()
        }
    }

    private var authenticatedAccountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Hai già effettuato l'accesso.", systemImage: "person.crop.circle.badge.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneDayEntrancePalette.gold)

            Text(registrationMode == .claimExisting
                 ? "Completeremo solo il collegamento tra questo account e il profilo giocatore selezionato."
                 : "Completeremo il profilo sportivo e collegheremo questo account al torneo.")
                .font(.caption)
                .foregroundStyle(OneDayEntrancePalette.inkMuted)

            Divider()

            infoLine("Email", authenticatedUser?.email ?? "Privata o non disponibile")
            infoLine("Provider", providerLabel)
        }
        .oneDayEntranceCard()
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(OneDayEntrancePalette.inkMuted)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(OneDayEntrancePalette.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private func normalizedGeneratedEmailBase(from value: String) -> String {
        let base = value
            .lowercased()
            .replacingOccurrences(of: " ", with: ".")
            .filter { $0.isLetter || $0.isNumber || $0 == "." }
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        return base.isEmpty ? "giocatore" : base
    }

    private var accessSectionSubtitle: String {
        if hasAuthenticatedSession {
            return registrationMode == .claimExisting
                ? "Usiamo l'account corrente per reclamare il profilo esistente."
                : "Completiamo solo il profilo sportivo."
        }
        return registrationMode == .claimExisting
            ? "Configura l'account che userai per reclamare il profilo gia esistente."
            : "Configura l'account con cui il giocatore accederà all'app."
    }

    private var providerLabel: String {
        let providerIDs = (authenticatedUser?.providerData ?? [])
            .map(\.providerID)
            .filter { $0 != "firebase" }

        if providerIDs.contains("apple.com") {
            return "Apple"
        }
        if providerIDs.contains("google.com") {
            return "Google"
        }
        if providerIDs.contains("password") {
            return "Email e password"
        }
        return "Account autenticato"
    }

    // MARK: - Data loading

    private func loadExistingProfilesIfNeeded() async {
        guard teams.isEmpty || players.isEmpty else { return }

        isLoadingExistingProfiles = true
        defer { isLoadingExistingProfiles = false }

        do {
            async let teamsTask = appState.firestoreService.fetchTeams()
            async let playersTask = appState.firestoreService.fetchAllPlayers()
            teams = try await teamsTask
            players = try await playersTask

            if selectedTeamId.isEmpty {
                selectedTeamId = claimableTeams.first?.id ?? ""
            }
        } catch {
            showError("Errore caricamento", "Impossibile caricare i profili esistenti: \(error.localizedDescription)")
        }
    }

    // MARK: - Submit

    private func registraGiocatore() async {
        if !hasAuthenticatedSession {
            guard password.count >= 8 else {
                showError("Password troppo corta", "La password deve avere almeno 8 caratteri.")
                return
            }
            guard password == confermaPassword else {
                showError("Password non corrispondenti", "Le due password inserite non coincidono.")
                return
            }
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let user: FirebaseAuth.User
            if let existingUser = authenticatedUser {
                user = existingUser
            } else {
                user = try await appState.authService.register(
                    email: emailEffettiva,
                    password: password
                )
            }

            switch registrationMode {
            case .claimExisting:
                guard let playerId = selectedExistingPlayerId, !playerId.isEmpty else {
                    showError("Profilo mancante", "Seleziona prima un profilo giocatore da collegare.")
                    return
                }
                try await appState.firestoreService.claimExistingPlayer(uid: user.uid, playerId: playerId)

            case .createFreeAgent:
                guard !nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showError("Campo mancante", "Inserisci il tuo nome completo.")
                    return
                }

                let playerId = try await appState.firestoreService.createPlayer(
                    nomeCompleto: nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines),
                    playerAuthUid: user.uid,
                    email: user.email,
                    numeroMaglia: Int(numeroMagliaText),
                    positionPrimary: posizione.isEmpty ? nil : posizione,
                    piedeDominante: piedeDominante.isEmpty ? nil : piedeDominante
                )
                try await appState.firestoreService.createPlayerClaim(uid: user.uid, playerId: playerId)
            }

            await appState.authService.resolveRole(uid: user.uid)
            dismiss()
        } catch {
            showError("Errore registrazione", localizedFirebaseError(error))
        }
    }

    private func showError(_ title: String, _ message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func localizedFirebaseError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case 17007:
            return "Esiste già un account con questa email. Effettua il login e riprendi il collegamento del profilo."
        case 17008:
            return "L'indirizzo email non è valido."
        case 17026:
            return "La password deve avere almeno 8 caratteri."
        case 17020:
            return "Nessuna connessione internet."
        default:
            return error.localizedDescription
        }
    }
}

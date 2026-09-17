import SwiftUI
import FirebaseAuth

struct TeamRegistrationView: View {
    private enum RegistrationMode: String, CaseIterable, Identifiable {
        case newTeam
        case existingTeam

        var id: String { rawValue }

        var title: String {
            switch self {
            case .newTeam:
                return "Nuova squadra"
            case .existingTeam:
                return "Squadra esistente"
            }
        }
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var registrationMode: RegistrationMode = .newTeam

    @State private var nomeSquadra = ""
    @State private var emailSquadra = ""
    @State private var nomeRappresentante = ""
    @State private var telefonoRappresentante = ""
    @State private var colorePrincipale = "1a73e8"
    @State private var coloreSecondario = "ffffff"

    @State private var existingTeams: [Team] = []
    @State private var selectedExistingTeamId = ""
    @State private var isLoadingExistingTeams = false

    @State private var password = ""
    @State private var confermaPassword = ""

    @State private var isLoading = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    // Stato iscrizioni (finestra date) + doc torneo per header e gating.
    @State private var registrationWindow: FirestoreService.RegistrationWindow?
    @State private var tournamentDoc: Tournament?

    /// Preselezione modalità (deep-link dal benvenuto-torneo, parità PWA
    /// team-registration `?scelta=esistente|nuova`). nil = default (nuova).
    init(preselectExistingTeam: Bool? = nil) {
        if let preselectExistingTeam {
            _registrationMode = State(initialValue: preselectExistingTeam ? .existingTeam : .newTeam)
        }
    }

    private var registrationBlocked: Bool {
        // Blocca il submit solo se la finestra è caricata e NON aperta.
        if let w = registrationWindow { return !w.isOpen }
        return false
    }

    private var authenticatedUser: FirebaseAuth.User? { appState.authService.currentUser }
    private var hasAuthenticatedSession: Bool { authenticatedUser != nil }

    private var availableExistingTeams: [Team] {
        existingTeams
            .filter { !$0.hasEdition(appState.activeEdition) }
            .sorted {
                $0.nomeSquadra.localizedCaseInsensitiveCompare($1.nomeSquadra) == .orderedAscending
            }
    }

    private var selectedExistingTeam: Team? {
        availableExistingTeams.first { $0.id == selectedExistingTeamId }
    }

    private var stepTitles: [String] {
        switch registrationMode {
        case .newTeam:
            return ["Informazioni", "Colori", hasAuthenticatedSession ? "Accesso" : "Account"]
        case .existingTeam:
            return ["Squadra", "Conferma", hasAuthenticatedSession ? "Accesso" : "Account"]
        }
    }

    private var heroTitle: String {
        switch registrationMode {
        case .newTeam:
            return "Crea una nuova squadra pronta per il torneo"
        case .existingTeam:
            return "Collega una squadra gia esistente e iscrivila all'edizione attiva"
        }
    }

    private var heroSubtitle: String {
        switch registrationMode {
        case .newTeam:
            return "Dati contatto, identita colori e account vengono raccolti in un flusso iOS piu chiaro e coerente con il backend reale."
        case .existingTeam:
            return "Riutilizziamo la scheda squadra esistente, aggiorniamo ownerUid e registriamo la partecipazione corrente senza duplicare i dati."
        }
    }

    private var submitButtonTitle: String {
        switch registrationMode {
        case .newTeam:
            return "Registra squadra"
        case .existingTeam:
            return "Collega e iscrivi"
        }
    }

    var body: some View {
        OneDayEntranceScreen {
            ScrollView {
                VStack(spacing: 20) {
                    OneDayEntranceHero(
                        eyebrow: "Registrazione squadra",
                        title: heroTitle,
                        subtitle: heroSubtitle,
                        systemImage: registrationMode == .newTeam ? "shield.fill" : "link.badge.plus"
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    if let w = registrationWindow {
                        RegistrationStatusHeader(window: w, tournament: tournamentDoc)
                            .padding(.horizontal, 16)
                    }

                    modeSection
                        .padding(.horizontal, 16)

                    stepIndicator
                        .padding(.horizontal, 16)

                    Group {
                        switch step {
                        case 0:
                            firstStepView
                        case 1:
                            secondStepView
                        default:
                            accessStepView
                        }
                    }
                    .padding(.horizontal, 16)

                    navigationButtons
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Registra Squadra")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.colorScheme, .dark)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadRegistrationInfo()
            if registrationMode == .existingTeam {
                await loadExistingTeamsIfNeeded()
            }
        }
        .onChange(of: registrationMode) { _, newValue in
            withAnimation {
                step = 0
            }

            if newValue == .existingTeam {
                Task { await loadExistingTeamsIfNeeded() }
            }
        }
        .onChange(of: selectedExistingTeamId) { _, _ in
            applySelectedExistingTeamPreset()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var modeSection: some View {
        OneDayEntranceSection(
            title: "Modalita",
            subtitle: "Scegli se creare una nuova squadra o recuperare una squadra storica gia presente nel database.",
            icon: "arrow.triangle.branch"
        ) {
            Picker("Modalita", selection: $registrationMode) {
                ForEach(RegistrationMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var stepIndicator: some View {
        TournamentStepIndicator(titles: stepTitles, currentStep: step, accent: OneDayEntrancePalette.gold)
            .oneDayEntranceCard()
    }

    private var firstStepView: some View {
        Group {
            switch registrationMode {
            case .newTeam:
                newTeamInfoStep
            case .existingTeam:
                existingTeamSelectionStep
            }
        }
    }

    private var secondStepView: some View {
        Group {
            switch registrationMode {
            case .newTeam:
                teamColorsStep
            case .existingTeam:
                existingTeamConfirmationStep
            }
        }
    }

    private var accessStepView: some View {
        OneDayEntranceSection(
            title: hasAuthenticatedSession ? "Accesso gia attivo" : "Credenziali account",
            subtitle: accessSectionSubtitle,
            icon: hasAuthenticatedSession ? "checkmark.shield.fill" : "lock.fill"
        ) {
            if hasAuthenticatedSession {
                authenticatedAccountCard
            } else {
                Text("L'email usata per accedere sara: **\(emailSquadra)**")
                    .font(.subheadline)
                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    .padding(.vertical, 4)

                formField(label: "Password") {
                    SecureField("Minimo 8 caratteri", text: $password)
                        .textContentType(.newPassword)
                }

                formField(label: "Conferma password") {
                    SecureField("Ripeti la password", text: $confermaPassword)
                        .textContentType(.newPassword)
                }

                if !password.isEmpty && !confermaPassword.isEmpty && password != confermaPassword {
                    inlineError("Le password non coincidono.")
                }

                if registrationMode == .existingTeam {
                    Text("Se questa email e gia registrata, effettua prima il login dalla schermata di accesso e poi riprendi il collegamento della squadra.")
                        .font(.caption)
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                }
            }
        }
    }

    private var newTeamInfoStep: some View {
        OneDayEntranceSection(
            title: "Informazioni squadra",
            subtitle: "Nome, contatti e referente della squadra.",
            icon: "shield.fill"
        ) {
            formField(label: "Nome squadra") {
                TextField("Es. FC Campioni", text: $nomeSquadra)
            }

            formField(label: "Email") {
                TextField("email@squadra.it", text: $emailSquadra)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            formField(label: "Nome rappresentante") {
                TextField("Mario Rossi", text: $nomeRappresentante)
                    .textContentType(.name)
            }

            formField(label: "Telefono") {
                TextField("+39 333 1234567", text: $telefonoRappresentante)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
            }
        }
    }

    private var teamColorsStep: some View {
        OneDayEntranceSection(
            title: "Colori della squadra",
            subtitle: "Imposta l'identita visiva base che useremo su card e dettagli squadra.",
            icon: "paintpalette.fill"
        ) {
            HStack(spacing: 16) {
                colorPreviewCard(title: "Principale", hex: colorePrincipale)
                colorPreviewCard(title: "Secondario", hex: coloreSecondario)
            }

            formField(label: "Colore principale (HEX)") {
                HStack {
                    Text("#")
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                        .padding(.leading, 4)
                    TextField("1a73e8", text: $colorePrincipale)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: colorePrincipale) { _, newValue in
                            colorePrincipale = normalizedHexInput(newValue)
                        }
                }
            }

            formField(label: "Colore secondario (HEX)") {
                HStack {
                    Text("#")
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                        .padding(.leading, 4)
                    TextField("ffffff", text: $coloreSecondario)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: coloreSecondario) { _, newValue in
                            coloreSecondario = normalizedHexInput(newValue)
                        }
                }
            }

            Text("Inserisci il codice esadecimale del colore (6 caratteri, senza #).")
                .font(.caption)
                .foregroundStyle(OneDayEntrancePalette.inkMuted)
        }
    }

    private var existingTeamSelectionStep: some View {
        OneDayEntranceSection(
            title: "Squadra esistente",
            subtitle: "Mostriamo solo le squadre che non risultano ancora registrate all'edizione \(appState.activeEdition).",
            icon: "shield.lefthalf.filled"
        ) {
            if isLoadingExistingTeams {
                LoadingView(message: "Caricamento squadre esistenti...")
            } else if availableExistingTeams.isEmpty {
                EmptyStateView(
                    icon: "checkmark.shield",
                    title: "Nessuna squadra disponibile",
                    message: "Tutte le squadre conosciute risultano gia iscritte all'edizione \(appState.activeEdition). Usa la modalita nuova squadra solo se devi crearne una da zero."
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Seleziona la squadra da collegare")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)

                    ForEach(availableExistingTeams) { team in
                        Button {
                            selectedExistingTeamId = team.id ?? ""
                        } label: {
                            existingTeamRow(team)
                        }
                        .buttonStyle(.tournamentPress)
                    }
                }
            }
        }
    }

    private var existingTeamConfirmationStep: some View {
        OneDayEntranceSection(
            title: "Conferma dati squadra",
            subtitle: "Aggiorniamo owner e contatti della scheda esistente senza creare duplicati.",
            icon: "checkmark.shield.fill"
        ) {
            if let team = selectedExistingTeam {
                selectedTeamSummaryCard(team)

                formField(label: "Email squadra") {
                    TextField("email@squadra.it", text: $emailSquadra)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                formField(label: "Nome rappresentante") {
                    TextField("Mario Rossi", text: $nomeRappresentante)
                        .textContentType(.name)
                }

                formField(label: "Telefono rappresentante") {
                    TextField("+39 333 1234567", text: $telefonoRappresentante)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(OneDayEntrancePalette.gold)
                    Text("Logo e colori restano quelli della scheda esistente. In questo passaggio aggiorniamo ownerUid e registriamo la squadra all'edizione \(appState.activeEdition).")
                        .font(.caption)
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                }
            } else {
                inlineError("Seleziona prima una squadra esistente.")
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Indietro") {
                    withAnimation {
                        step -= 1
                    }
                }
                .oneDayEntranceButton(.ghost)
            }

            Button {
                if step < 2 {
                    if validateCurrentStep() {
                        withAnimation {
                            step += 1
                        }
                    }
                } else {
                    Task { await registraSquadra() }
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 4)
                    }
                    Text(step < 2 ? "Avanti" : submitButtonTitle)
                }
                .oneDayEntranceButton(.primaryGold)
            }
            .disabled(isLoading || (step >= 2 && registrationBlocked))
            .opacity(isLoading || (step >= 2 && registrationBlocked) ? 0.7 : 1)
        }
    }

    private func loadRegistrationInfo() async {
        registrationWindow = try? await appState.firestoreService.fetchRegistrationWindow()
        tournamentDoc = await appState.tournamentSelectionStore.currentTournamentDoc()
    }

    private func loadExistingTeamsIfNeeded() async {
        guard existingTeams.isEmpty else {
            if selectedExistingTeamId.isEmpty {
                selectedExistingTeamId = availableExistingTeams.first?.id ?? ""
            }
            applySelectedExistingTeamPreset()
            return
        }

        isLoadingExistingTeams = true
        defer { isLoadingExistingTeams = false }

        do {
            existingTeams = try await appState.firestoreService.fetchTeams()
            if selectedExistingTeamId.isEmpty {
                selectedExistingTeamId = availableExistingTeams.first?.id ?? ""
            }
            applySelectedExistingTeamPreset()
        } catch {
            showError("Errore caricamento", "Impossibile caricare le squadre esistenti: \(error.localizedDescription)")
        }
    }

    private func applySelectedExistingTeamPreset() {
        guard registrationMode == .existingTeam,
              let team = selectedExistingTeam else { return }

        nomeSquadra = team.nomeSquadra

        if !team.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emailSquadra = team.email
        }

        if !team.rappresentante.nome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nomeRappresentante = team.rappresentante.nome
        }

        if !team.rappresentante.telefono.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            telefonoRappresentante = team.rappresentante.telefono
        }

        let normalizedPrimary = team.colori.principale.replacingOccurrences(of: "#", with: "")
        if normalizedPrimary.count == 6 {
            colorePrincipale = normalizedPrimary
        }

        let normalizedSecondary = team.colori.secondario.replacingOccurrences(of: "#", with: "")
        if normalizedSecondary.count == 6 {
            coloreSecondario = normalizedSecondary
        }
    }

    private func validateCurrentStep() -> Bool {
        switch step {
        case 0:
            switch registrationMode {
            case .newTeam:
                guard !nomeSquadra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showError("Campo mancante", "Inserisci il nome della squadra.")
                    return false
                }
                guard emailSquadra.contains("@") else {
                    showError("Email non valida", "Inserisci un indirizzo email valido.")
                    return false
                }
                guard !nomeRappresentante.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showError("Campo mancante", "Inserisci il nome del rappresentante.")
                    return false
                }
                guard !telefonoRappresentante.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showError("Campo mancante", "Inserisci il numero di telefono.")
                    return false
                }
            case .existingTeam:
                guard selectedExistingTeam != nil else {
                    showError("Squadra mancante", "Seleziona la squadra esistente che vuoi collegare.")
                    return false
                }
            }
        case 1:
            switch registrationMode {
            case .newTeam:
                guard colorePrincipale.count == 6 else {
                    showError("Colore non valido", "Il colore principale deve essere un HEX a 6 caratteri.")
                    return false
                }
                guard coloreSecondario.count == 6 else {
                    showError("Colore non valido", "Il colore secondario deve essere un HEX a 6 caratteri.")
                    return false
                }
            case .existingTeam:
                guard emailSquadra.contains("@") else {
                    showError("Email non valida", "Inserisci un indirizzo email valido per la squadra.")
                    return false
                }
                guard !nomeRappresentante.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showError("Campo mancante", "Inserisci il nome del rappresentante.")
                    return false
                }
                guard !telefonoRappresentante.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    showError("Campo mancante", "Inserisci il numero di telefono del rappresentante.")
                    return false
                }
            }
        default:
            break
        }

        return true
    }

    private func registraSquadra() async {
        guard validateCurrentStep() else { return }

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
            let normalizedPrimary = normalizedHexInput(colorePrincipale)
            let normalizedSecondary = normalizedHexInput(coloreSecondario)
            let user: FirebaseAuth.User
            if let authenticatedUser {
                user = authenticatedUser
            } else {
                user = try await appState.authService.register(
                    email: emailSquadra.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
            }

            switch registrationMode {
            case .newTeam:
                let teamId = try await appState.firestoreService.createTeam(
                    nomeSquadra: nomeSquadra.trimmingCharacters(in: .whitespacesAndNewlines),
                    email: emailSquadra.trimmingCharacters(in: .whitespacesAndNewlines),
                    ownerUid: user.uid,
                    rappresentanteNome: nomeRappresentante.trimmingCharacters(in: .whitespacesAndNewlines),
                    rappresentanteTelefono: telefonoRappresentante.trimmingCharacters(in: .whitespacesAndNewlines),
                    colorePrincipale: normalizedPrimary,
                    coloreSecondario: normalizedSecondary,
                    edizione: appState.activeEdition
                )

                try await appState.firestoreService.registerTeamToEdition(
                    squadraId: teamId,
                    nomeSquadra: nomeSquadra.trimmingCharacters(in: .whitespacesAndNewlines),
                    edizione: appState.activeEdition
                )

            case .existingTeam:
                guard let existingTeam = selectedExistingTeam,
                      let teamId = existingTeam.id,
                      !teamId.isEmpty else {
                    showError("Squadra mancante", "Seleziona prima una squadra valida.")
                    return
                }

                try await appState.firestoreService.claimExistingTeam(
                    uid: user.uid,
                    teamId: teamId,
                    email: emailSquadra,
                    rappresentanteNome: nomeRappresentante,
                    rappresentanteTelefono: telefonoRappresentante
                )

                try await appState.firestoreService.registerTeamToEdition(
                    squadraId: teamId,
                    nomeSquadra: existingTeam.nomeSquadra,
                    edizione: appState.activeEdition
                )
            }

            await appState.authService.resolveRole(uid: user.uid)
            dismiss()
        } catch {
            showError("Errore registrazione", localizedFirebaseError(error))
        }
    }

    private func existingTeamRow(_ team: Team) -> some View {
        HStack(spacing: 12) {
            TournamentTeamLogo(
                urlString: team.logoSquadra,
                size: 52,
                placeholderTint: OneDayEntrancePalette.gold
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(team.nomeSquadra)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OneDayEntrancePalette.ink)

                HStack(spacing: 8) {
                    if let firstEdition = team.primaEdizione {
                        Text("Dal \(firstEdition)")
                            .font(.caption)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    }
                    if let editions = team.ultimeEdizioni, !editions.isEmpty {
                        Text("\(editions.count) edizioni")
                            .font(.caption)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    }
                }

                Text(ownerBadgeText(for: team))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ownerBadgeTone(for: team))
            }

            Spacer()

            Image(systemName: selectedExistingTeamId == team.id ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selectedExistingTeamId == team.id ? OneDayEntrancePalette.gold : OneDayEntrancePalette.inkMuted)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                .fill(OneDayEntrancePalette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                .stroke(
                    selectedExistingTeamId == team.id ? OneDayEntrancePalette.gold : OneDayEntrancePalette.stroke,
                    lineWidth: selectedExistingTeamId == team.id ? 2 : 1
                )
        )
    }

    private func selectedTeamSummaryCard(_ team: Team) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TournamentTeamLogo(
                    urlString: team.logoSquadra,
                    size: 58,
                    placeholderTint: OneDayEntrancePalette.gold
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(team.nomeSquadra)
                        .font(.headline)
                        .foregroundStyle(OneDayEntrancePalette.ink)

                    if let firstEdition = team.primaEdizione {
                        Text("Presente dal \(firstEdition)")
                            .font(.caption)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                    }

                    Text(ownerBadgeText(for: team))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ownerBadgeTone(for: team))
                }

                Spacer()
            }

            HStack(spacing: 12) {
                colorPreviewCard(title: "Primario", hex: team.colori.principale.replacingOccurrences(of: "#", with: ""))
                colorPreviewCard(title: "Secondario", hex: team.colori.secondario.replacingOccurrences(of: "#", with: ""))
            }
        }
        .oneDayEntranceCard()
    }

    private func ownerBadgeText(for team: Team) -> String {
        let ownerUid = team.ownerUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUid = authenticatedUser?.uid ?? ""

        if ownerUid.isEmpty {
            return "Owner non assegnato"
        }
        if ownerUid == currentUid {
            return "Gia collegata al tuo account"
        }
        return "Richiede l'account gia associato"
    }

    private func ownerBadgeTone(for team: Team) -> Color {
        let ownerUid = team.ownerUid.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentUid = authenticatedUser?.uid ?? ""

        if ownerUid.isEmpty {
            return OneDayEntrancePalette.gold
        }
        if ownerUid == currentUid {
            return TournamentPalette.success
        }
        return OneDayEntrancePalette.danger
    }

    private var accessSectionSubtitle: String {
        if hasAuthenticatedSession {
            switch registrationMode {
            case .newTeam:
                return "Useremo l'account corrente per gestire la nuova squadra."
            case .existingTeam:
                return "Useremo l'account corrente per collegare la squadra esistente e iscriverla all'edizione attiva."
            }
        }

        switch registrationMode {
        case .newTeam:
            return "Configura l'account che controllera questa nuova squadra."
        case .existingTeam:
            return "Configura l'account che userai per collegare e gestire la squadra esistente."
        }
    }

    private var authenticatedAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Userai l'account gia autenticato per gestire la squadra.", systemImage: "person.crop.circle.badge.checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OneDayEntrancePalette.gold)

            Text(registrationMode == .newTeam
                 ? "L'email squadra resta un contatto pubblico del torneo. L'accesso all'app usera invece il tuo account attuale."
                 : "Aggiorneremo ownerUid sulla squadra selezionata e completeremo l'iscrizione dell'edizione corrente senza creare una nuova scheda.")
                .font(.caption)
                .foregroundStyle(OneDayEntrancePalette.inkMuted)

            Divider()

            infoLine("Account", authenticatedUser?.email ?? "Privato o non disponibile")
            infoLine("Provider", providerLabel)
            if !emailSquadra.isEmpty {
                infoLine("Email squadra", emailSquadra)
            }
        }
        .oneDayEntranceCard()
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

    private func colorPreviewCard(title: String, hex: String) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: hex) ?? Color(.systemGray5))
                .frame(height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(OneDayEntrancePalette.inkMuted)
            Spacer()
            Text(value)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }

    private func inlineError(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(OneDayEntrancePalette.danger)
            Text(message)
                .font(.caption)
                .foregroundStyle(OneDayEntrancePalette.danger)
            Spacer()
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
            return "Esiste gia un account con questa email. Effettua il login e riprendi il collegamento della squadra."
        case 17008:
            return "L'indirizzo email non e valido."
        case 17026:
            return "La password deve avere almeno 8 caratteri."
        case 17020:
            return "Nessuna connessione internet."
        default:
            return error.localizedDescription
        }
    }

    private func normalizedHexInput(_ value: String) -> String {
        String(
            value
                .replacingOccurrences(of: "#", with: "")
                .filter(\.isHexDigit)
                .prefix(6)
        ).lowercased()
    }
}

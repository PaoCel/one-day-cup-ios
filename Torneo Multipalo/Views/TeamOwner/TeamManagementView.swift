import SwiftUI
import UIKit

struct TeamManagementView: View {
    let teamId: String
    let initialTeam: Team?

    @Environment(AppState.self) private var appState

    // Form — inizializzato con i valori correnti della squadra
    @State private var nomeSquadra = ""
    @State private var nomeRappresentante = ""
    @State private var telefonoRappresentante = ""
    @State private var colorePrincipale = ""
    @State private var coloreSecondario = ""

    // Logo
    @State private var logoImage: UIImage?
    @State private var showImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showSourceChoice = false
    @State private var isUploadingLogo = false

    // Stato
    @State private var liveTeam: Team?
    @State private var teamListener = FirestoreListenerToken()
    @State private var hasLoadedInitialValues = false
    @State private var isSaving = false
    @State private var showSuccessBanner = false
    @State private var successBannerText = "Modifiche salvate"
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    init(teamId: String, team: Team? = nil) {
        self.teamId = teamId
        self.initialTeam = team
    }

    init(team: Team) {
        self.init(teamId: team.id ?? "", team: team)
    }

    private var currentTeam: Team? {
        liveTeam ?? initialTeam
    }

    private var displayedLogoURL: String? {
        currentTeam?.logoSquadra
    }

    private var displayedPrimaryColor: Color {
        if let primaryHex = currentTeam?.colori.principale,
           let color = Color(hex: primaryHex) {
            return color.opacity(0.15)
        }
        return .blue.opacity(0.15)
    }

    private static let primaryPalette: [TeamColorOption] = [
        .init(name: "Blu", hex: "1a73e8"),
        .init(name: "Navy", hex: "1d4ed8"),
        .init(name: "Rosso", hex: "dc2626"),
        .init(name: "Bordeaux", hex: "9f1239"),
        .init(name: "Arancio", hex: "ea580c"),
        .init(name: "Oro", hex: "ca8a04"),
        .init(name: "Verde", hex: "16a34a"),
        .init(name: "Smeraldo", hex: "059669"),
        .init(name: "Turchese", hex: "0891b2"),
        .init(name: "Viola", hex: "7c3aed"),
        .init(name: "Fucsia", hex: "db2777"),
        .init(name: "Nero", hex: "111827")
    ]

    private static let secondaryPalette: [TeamColorOption] = [
        .init(name: "Bianco", hex: "ffffff"),
        .init(name: "Panna", hex: "f8fafc"),
        .init(name: "Ghiaccio", hex: "e2e8f0"),
        .init(name: "Argento", hex: "cbd5e1"),
        .init(name: "Antracite", hex: "334155"),
        .init(name: "Blu notte", hex: "0f172a"),
        .init(name: "Oro chiaro", hex: "fde68a"),
        .init(name: "Crema", hex: "fef3c7")
    ]

    private var primaryColorOptions: [TeamColorOption] {
        paletteOptions(from: Self.primaryPalette, selectedHex: colorePrincipale)
    }

    private var secondaryColorOptions: [TeamColorOption] {
        paletteOptions(from: Self.secondaryPalette, selectedHex: coloreSecondario)
    }

    var body: some View {
        TournamentScreen {
            ScrollView {
                VStack(spacing: 20) {
                logoSection

                TournamentFormSection(
                    title: "Informazioni squadra",
                    subtitle: "Aggiorna il nome con cui la squadra appare nell'app.",
                    icon: "shield.fill"
                ) {

                    formField(label: "Nome squadra") {
                        TextField("Nome squadra", text: $nomeSquadra)
                    }
                }
                .padding(.horizontal, 16)

                TournamentFormSection(
                    title: "Rappresentante",
                    subtitle: "Contatti usati per l'organizzazione del torneo.",
                    icon: "person.fill"
                ) {

                    formField(label: "Nome completo") {
                        TextField("Mario Rossi", text: $nomeRappresentante)
                            .textContentType(.name)
                    }

                    formField(label: "Telefono") {
                        TextField("+39 333 1234567", text: $telefonoRappresentante)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                    }
                }
                .padding(.horizontal, 16)

                TournamentFormSection(
                    title: "Colori squadra",
                    subtitle: "Scegli i colori da una palette pronta: verranno riusati nelle card e nei dettagli della squadra.",
                    icon: "paintpalette.fill"
                ) {

                    HStack(spacing: 12) {
                        colorPreview(hex: colorePrincipale, label: "Principale")
                        colorPreview(hex: coloreSecondario, label: "Secondario")
                    }

                    paletteField(
                        label: "Colore principale",
                        helperText: "Tocca un colore per impostare il tono principale della squadra.",
                        selection: $colorePrincipale,
                        options: primaryColorOptions
                    )

                    paletteField(
                        label: "Colore secondario",
                        helperText: "Usato per contrasti, sfondi e dettagli secondari.",
                        selection: $coloreSecondario,
                        options: secondaryColorOptions
                    )
                }
                .padding(.horizontal, 16)

                Button {
                    Task { await salva() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white).padding(.trailing, 4)
                        }
                        Text("Salva modifiche")
                    }
                    .tournamentButtonChrome(.primary)
                }
                .buttonStyle(.tournamentPress)
                .disabled(isSaving)
                .opacity(isSaving ? 0.7 : 1)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        }
        .navigationTitle("Modifica squadra")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            caricaValoriInizialiSeDisponibili()
            startListeningToTeam()
        }
        .onDisappear {
            teamListener.cancel()
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $logoImage, sourceType: imageSourceType)
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
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
        .overlay(alignment: .top) {
            if showSuccessBanner {
                successBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4), value: showSuccessBanner)
    }

    // MARK: - Logo section

    private var logoSection: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                TournamentTeamLogo(
                    urlString: logoImage == nil ? displayedLogoURL : nil,
                    localImage: logoImage,
                    size: 96,
                    placeholderTint: displayedPrimaryColor
                )

                if isUploadingLogo {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.black.opacity(0.4))
                        .frame(width: 96, height: 96)
                        .overlay(ProgressView().tint(.white))
                } else {
                    Circle()
                        .fill(TournamentPalette.accent)
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.caption2)
                                .foregroundStyle(.white)
                        )
                        .offset(x: 4, y: 4)
                }
            }
            .onTapGesture { showSourceChoice = true }

            Text("Tocca per scegliere il logo, poi salva le modifiche")
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .padding(.top, 8)
        .padding(.horizontal, 16)
    }

    // MARK: - Banner successo

    private var successBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(hex: "#10b981") ?? .green)
            Text(successBannerText)
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Helpers UI

    private func sectionHeader(_ titolo: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(TournamentPalette.accent)
            Text(titolo).font(.headline)
        }
    }

    private func formField<Content: View>(label: String,
                                          @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(TournamentPalette.inkMuted)
            content()
                .tournamentInputChrome()
        }
    }

    private func colorPreview(hex: String, label: String) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: hex) ?? Color(.systemGray5))
                .frame(height: 48)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(TournamentPalette.border, lineWidth: 1))
            Text(label).font(.caption).foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private func paletteField(label: String,
                              helperText: String,
                              selection: Binding<String>,
                              options: [TeamColorOption]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(TournamentPalette.inkMuted)

            Text(helperText)
                .font(.caption2)
                .foregroundStyle(TournamentPalette.inkMuted)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(options) { option in
                    paletteSwatch(
                        option: option,
                        isSelected: normalizedHexInput(selection.wrappedValue) == option.normalizedHex
                    ) {
                        selection.wrappedValue = option.normalizedHex
                    }
                }
            }

            Text("Selezionato: \(displayHex(selection.wrappedValue))")
                .font(.caption2.monospaced())
                .foregroundStyle(TournamentPalette.inkMuted)
        }
    }

    private func paletteSwatch(option: TeamColorOption,
                               isSelected: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Circle()
                    .fill(option.color)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(option.isLight ? 0.55 : 0.25), lineWidth: 1)
                    )
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(option.isLight ? TournamentPalette.ink : .white)
                        }
                    }

                Text(option.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? TournamentPalette.accentSoft : TournamentPalette.surfaceStrong)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? TournamentPalette.accent : TournamentPalette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.tournamentPress)
    }

    // MARK: - Logica

    private func caricaValoriInizialiSeDisponibili() {
        guard !hasLoadedInitialValues, let team = currentTeam else { return }
        caricaValoriIniziali(from: team)
    }

    private func caricaValoriIniziali(from team: Team) {
        nomeSquadra = team.nomeSquadra
        nomeRappresentante = team.rappresentante.nome
        telefonoRappresentante = team.rappresentante.telefono
        colorePrincipale = normalizedHexInput(team.colori.principale)
        coloreSecondario = normalizedHexInput(team.colori.secondario)
        hasLoadedInitialValues = true
    }

    private func startListeningToTeam() {
        guard !teamId.isEmpty else { return }
        teamListener.replace(with: appState.firestoreService.listenToTeam(teamId: teamId) { team in
            Task { @MainActor in
                liveTeam = team
                if let team, !hasLoadedInitialValues {
                    caricaValoriIniziali(from: team)
                }
            }
        })
    }

    @MainActor
    private func salva() async {
        guard !teamId.isEmpty else {
            alertTitle = "Squadra non valida"
            alertMessage = "Impossibile salvare questa squadra perche manca l'identificativo."
            showAlert = true
            return
        }
        guard !nomeSquadra.trimmingCharacters(in: .whitespaces).isEmpty else {
            alertTitle = "Campo mancante"
            alertMessage = "Il nome squadra non può essere vuoto."
            showAlert = true
            return
        }
        let normalizedPrimary = normalizedHexInput(colorePrincipale)
        let normalizedSecondary = normalizedHexInput(coloreSecondario)
        guard normalizedPrimary.count == 6, normalizedSecondary.count == 6 else {
            alertTitle = "Colore non valido"
            alertMessage = "I colori devono essere codici HEX di 6 caratteri."
            showAlert = true
            return
        }

        isSaving = true
        let hadPendingLogo = logoImage != nil
        let trimmedNomeSquadra = nomeSquadra.trimmingCharacters(in: .whitespaces)
        let trimmedRappresentante = nomeRappresentante.trimmingCharacters(in: .whitespaces)
        let trimmedTelefono = telefonoRappresentante.trimmingCharacters(in: .whitespaces)

        defer { isSaving = false }

        do {
            try await appState.firestoreService.updateTeamDetails(
                teamId: teamId,
                nomeSquadra: trimmedNomeSquadra,
                rappresentanteNome: trimmedRappresentante,
                rappresentanteTelefono: trimmedTelefono,
                colorePrincipale: normalizedPrimary,
                coloreSecondario: normalizedSecondary
            )

            if let pendingLogo = logoImage {
                do {
                    isUploadingLogo = true
                    try await uploadLogo(pendingLogo)
                    logoImage = nil
                } catch {
                    isUploadingLogo = false
                    await appState.loadTeams()
                    showSuccess(message: "Dati squadra salvati")
                    alertTitle = "Logo non aggiornato"
                    alertMessage = "I dati squadra sono stati salvati, ma il logo non è stato caricato: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                isUploadingLogo = false
            }

            await appState.loadTeams()
            showSuccess(message: hadPendingLogo ? "Logo e dati salvati" : "Modifiche salvate")
        } catch {
            alertTitle = "Errore"
            alertMessage = "Impossibile salvare: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func showSuccess(message: String) {
        successBannerText = message
        showSuccessBanner = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            showSuccessBanner = false
        }
    }

    private func uploadLogo(_ img: UIImage) async throws {
        guard !teamId.isEmpty else {
            throw NSError(
                domain: "TeamManagementView",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Manca l'identificativo della squadra."]
            )
        }

        let payload = try logoUploadPayload(from: img)
        let path = "squadre/\(teamId)/logo_\(Int(Date().timeIntervalSince1970 * 1000)).\(payload.fileExtension)"
        let url = try await appState.storageService.uploadImage(payload.data, path: path)
        try await appState.firestoreService.updateTeamLogo(teamId: teamId, logoURL: url.absoluteString)
    }

    private func logoUploadPayload(from image: UIImage) throws -> (data: Data, fileExtension: String) {
        let hasAlpha: Bool
        if let alphaInfo = image.cgImage?.alphaInfo {
            switch alphaInfo {
            case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
                hasAlpha = true
            default:
                hasAlpha = false
            }
        } else {
            hasAlpha = false
        }

        if hasAlpha, let pngData = image.pngData() {
            return (pngData, "png")
        }

        if let jpegData = image.jpegData(compressionQuality: 0.86) {
            return (jpegData, "jpg")
        }

        if let pngData = image.pngData() {
            return (pngData, "png")
        }

        throw NSError(
            domain: "TeamManagementView",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Immagine logo non valida."]
        )
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

    private func paletteOptions(from baseOptions: [TeamColorOption], selectedHex: String) -> [TeamColorOption] {
        let normalized = normalizedHexInput(selectedHex)
        guard normalized.count == 6 else { return baseOptions }
        guard !baseOptions.contains(where: { $0.normalizedHex == normalized }) else { return baseOptions }
        return [.init(name: "Attuale", hex: normalized)] + baseOptions
    }

    private func displayHex(_ value: String) -> String {
        let normalized = normalizedHexInput(value)
        guard normalized.count == 6 else { return "Non impostato" }
        return "#\(normalized.uppercased())"
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

private struct TeamColorOption: Identifiable, Hashable {
    let name: String
    let hex: String

    var normalizedHex: String {
        hex
            .replacingOccurrences(of: "#", with: "")
            .lowercased()
    }

    var id: String { normalizedHex }

    var color: Color {
        Color(hex: normalizedHex) ?? TournamentPalette.surfaceMuted
    }

    var isLight: Bool {
        guard let rgbValue = UInt64(normalizedHex, radix: 16) else { return false }
        let red = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000FF) / 255.0
        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.72
    }
}

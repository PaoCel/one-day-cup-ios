import SwiftUI
import UIKit

struct AddPlayerView: View {
    let teamId: String

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Form
    @State private var nomeCompleto = ""
    @State private var numeroMagliaText = ""
    @State private var carica: CaricaSquadra?
    @State private var existingPlayers: [Player] = []
    @State private var selectedExistingPlayerId: String?

    // Foto
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showSourceChoice = false

    // Stato
    @State private var isLoading = false
    @State private var isLoadingExistingPlayers = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showDuplicateConfirm = false
    @State private var dismissAfterAlert = false
    @State private var skippedPhotoForNow = false

    private var trimmedName: String {
        nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAdmin: Bool {
        appState.authService.userRole == .admin
    }

    private var normalizedQuery: String {
        normalizedName(trimmedName)
    }

    private var existingMatches: [Player] {
        guard normalizedQuery.count >= 2 else { return [] }

        return existingPlayers
            .filter { player in
                player.teamId != teamId &&
                normalizedName(player.nomeCompleto).contains(normalizedQuery)
            }
            .sorted { lhs, rhs in
                let lhsRank = searchRank(for: lhs)
                let rhsRank = searchRank(for: rhs)
                if lhsRank != rhsRank {
                    return lhsRank < rhsRank
                }
                switch (lhs.isFreeAgent, rhs.isFreeAgent) {
                case (true, false):
                    return true
                case (false, true):
                    return false
                default:
                    return lhs.nomeCompleto.localizedCaseInsensitiveCompare(rhs.nomeCompleto) == .orderedAscending
                }
            }
            .prefix(8)
            .map(\.self)
    }

    private var exactExistingMatches: [Player] {
        guard !normalizedQuery.isEmpty else { return [] }
        return existingPlayers.filter { normalizedName($0.nomeCompleto) == normalizedQuery }
    }

    private var sameTeamExactMatch: Player? {
        exactExistingMatches.first { $0.teamId == teamId }
    }

    private var selectedExistingPlayer: Player? {
        guard let selectedExistingPlayerId else { return nil }
        return existingPlayers.first { candidateId(for: $0) == selectedExistingPlayerId }
    }

    private var actionButtonTitle: String {
        if let selectedExistingPlayer {
            if isAdmin {
                return selectedExistingPlayer.isFreeAgent
                    ? "Inserisci in rosa"
                    : "Sposta in rosa"
            }
            return "Invia richiesta al giocatore"
        }
        return "Crea nuovo giocatore"
    }

    private var actionButtonDisabled: Bool {
        if isLoading { return true }
        if let selectedExistingPlayer {
            return !isAdmin && !selectedExistingPlayer.isClaimed
        }
        return trimmedName.isEmpty
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: 20) {
                        if selectedExistingPlayer == nil {
                            photoSelector
                        }

                        TournamentFormSection(
                            title: "Giocatore",
                            subtitle: "Scrivi nome e cognome: prima controlliamo se esiste già nel database, così evitiamo doppioni.",
                            icon: "person.fill"
                        ) {
                            formField(label: "Nome e cognome *") {
                                TextField("Mario Rossi", text: $nomeCompleto)
                                    .textContentType(.name)
                            }

                            formField(label: "Numero di maglia") {
                                TextField("Es. 10", text: $numeroMagliaText)
                                    .keyboardType(.numberPad)
                            }

                            if selectedExistingPlayer == nil {
                                formField(label: "Carica") {
                                    CaricaPicker(carica: $carica)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        if isLoadingExistingPlayers {
                            LoadingView(message: "Ricerca giocatori esistenti...")
                                .padding(.horizontal, 16)
                        } else if !existingMatches.isEmpty {
                            TournamentFormSection(
                                title: "Giocatori già presenti",
                                subtitle: isAdmin
                                    ? "Selezionandone uno puoi inserirlo subito nella squadra corrente."
                                    : "Selezionandone uno invii una richiesta, che il giocatore dovrà approvare."
                                ,
                                icon: "magnifyingglass"
                            ) {
                                VStack(spacing: 0) {
                                    ForEach(Array(existingMatches.enumerated()), id: \.offset) { index, player in
                                        Button {
                                            let candidate = candidateId(for: player)
                                            selectedExistingPlayerId = (selectedExistingPlayerId == candidate) ? nil : candidate
                                        } label: {
                                            existingPlayerRow(
                                                player: player,
                                                isSelected: selectedExistingPlayerId == candidateId(for: player)
                                            )
                                        }
                                        .buttonStyle(.tournamentPress)

                                        if index < existingMatches.count - 1 {
                                            Divider().padding(.leading, 56)
                                        }
                                    }
                                }
                                .tournamentCard(padding: 0)
                            }
                            .padding(.horizontal, 16)
                        }

                        if let sameTeamExactMatch {
                            TournamentFormSection(
                                title: "Giocatore già presente",
                                subtitle: "\(sameTeamExactMatch.nomeCompleto) è già nella rosa di questa squadra.",
                                icon: "exclamationmark.circle.fill"
                            ) {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(
                                        urlString: sameTeamExactMatch.displayPhotoURL,
                                        placeholderIcon: "person.fill",
                                        placeholderColor: TournamentPalette.accentSoft,
                                        contentAlignment: .top
                                    )
                                    .frame(width: 42, height: 42)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(sameTeamExactMatch.nomeCompleto)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(TournamentPalette.ink)

                                        Text("Usa il profilo esistente invece di crearne un altro.")
                                            .font(.caption)
                                            .foregroundStyle(TournamentPalette.inkMuted)
                                    }

                                    Spacer()
                                }
                                .tournamentCard(padding: 16)
                            }
                            .padding(.horizontal, 16)
                        }

                        if let selectedExistingPlayer {
                            TournamentFormSection(
                                title: isAdmin ? "Azione admin" : "Azione richiesta",
                                subtitle: isAdmin
                                    ? "L'admin può assegnare subito il profilo alla squadra corrente, senza approvazione del giocatore."
                                    : "Le richieste verso profili già esistenti passano sempre dall'approvazione del giocatore."
                                ,
                                icon: isAdmin ? "gearshape.fill" : "paperplane.fill"
                            ) {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(
                                        urlString: selectedExistingPlayer.displayPhotoURL,
                                        placeholderIcon: "person.fill",
                                        placeholderColor: TournamentPalette.accentSoft,
                                        contentAlignment: .top
                                    )
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(selectedExistingPlayer.nomeCompleto)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(TournamentPalette.ink)

                                        Text(playerSubtitle(for: selectedExistingPlayer))
                                            .font(.caption)
                                            .foregroundStyle(TournamentPalette.inkMuted)
                                    }

                                    Spacer()

                                    TournamentPill(
                                        label: isAdmin ? "Assegnazione diretta" : "Richiesta",
                                        tone: isAdmin ? .accent : .neutral
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        Button {
                            Task { await handlePrimaryAction() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.white).padding(.trailing, 4)
                                }
                                Text(actionButtonTitle)
                            }
                            .tournamentButtonChrome(.primary)
                        }
                        .buttonStyle(.tournamentPress)
                        .disabled(actionButtonDisabled)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Aggiungi giocatore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Annulla") { dismiss() }
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
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK") {
                    if dismissAfterAlert {
                        dismiss()
                    }
                    dismissAfterAlert = false
                }
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(
                "Esistono già profili con questo nome",
                isPresented: $showDuplicateConfirm,
                titleVisibility: .visible
            ) {
                Button("Crea comunque nuovo profilo") {
                    Task { await createManagedPlayer() }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Prima di creare un duplicato puoi selezionare un giocatore già presente nella lista qui sopra.")
            }
            .task {
                await loadExistingPlayers()
            }
            .onChange(of: nomeCompleto) { _, _ in
                if let selectedExistingPlayer,
                   normalizedName(selectedExistingPlayer.nomeCompleto) != normalizedQuery,
                   !existingMatches.contains(where: { candidateId(for: $0) == selectedExistingPlayerId }) {
                    selectedExistingPlayerId = nil
                }
            }
        }
    }

    // MARK: - Foto selector

    private var photoSelector: some View {
        VStack(spacing: 12) {
            ZStack {
                if let img = selectedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 100, height: 100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(TournamentPalette.border, lineWidth: 1))
                } else {
                    Circle()
                        .fill(TournamentPalette.accentSoft)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(TournamentPalette.accent)
                        )
                }

                Circle()
                    .fill(TournamentPalette.accent)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                    )
                    .offset(x: 34, y: 34)
            }
            .onTapGesture {
                skippedPhotoForNow = false
                showSourceChoice = true
            }

            VStack(spacing: 4) {
                Text("Foto profilo opzionale")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)

                Text("Puoi caricarla adesso oppure aggiungerla piu tardi dalla rosa.")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    skippedPhotoForNow = false
                    showSourceChoice = true
                } label: {
                    Label(selectedImage == nil ? "Aggiungi foto" : "Cambia foto", systemImage: "camera.fill")
                        .tournamentButtonChrome(.secondary, fullWidth: true)
                }
                .buttonStyle(.tournamentPress)

                Button {
                    selectedImage = nil
                    skippedPhotoForNow = true
                } label: {
                    Label(selectedImage == nil ? "La aggiungo dopo" : "Rimuovi foto", systemImage: selectedImage == nil ? "arrow.right" : "trash")
                        .tournamentButtonChrome(.neutral, fullWidth: true)
                }
                .buttonStyle(.tournamentPress)
            }
            .padding(.horizontal, 16)

            if skippedPhotoForNow && selectedImage == nil {
                Text("Ok, creiamo il giocatore senza foto. Potrai aggiungerla dopo.")
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers UI

    private func sectionHeader(_ titolo: String) -> some View {
        Text(titolo)
            .font(.headline)
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

    // MARK: - Salva

    private func handlePrimaryAction() async {
        if let selectedExistingPlayer {
            await handleExistingPlayerSelection(selectedExistingPlayer)
            return
        }

        guard !trimmedName.isEmpty else { return }

        if let sameTeamExactMatch {
            alertTitle = "Giocatore già in rosa"
            alertMessage = "\(sameTeamExactMatch.nomeCompleto) è già presente nella squadra corrente."
            showAlert = true
            return
        }

        if !exactExistingMatches.isEmpty {
            showDuplicateConfirm = true
            return
        }

        await createManagedPlayer()
    }

    private func createManagedPlayer() async {
        guard !trimmedName.isEmpty else { return }
        isLoading = true

        do {
            let parsedNumero: Int? = {
                let trimmed = numeroMagliaText.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : Int(trimmed)
            }()

            let createdPlayerId = try await appState.firestoreService.addManagedPlayer(
                nomeCompleto: trimmedName,
                teamId: teamId,
                numeroMaglia: parsedNumero,
                positionPrimary: nil,
                piedeDominante: nil,
                pictureURL: nil
            )
            // La carica dopo la creazione: il service toglie la stessa carica a
            // chi la aveva e riscrive lo snapshot. Se fallisce il giocatore c'è
            // lo stesso, e la carica si rimette dalla rosa.
            if let carica {
                try? await appState.firestoreService.assegnaCarica(playerId: createdPlayerId, teamId: teamId, carica: carica)
            }

            if let img = selectedImage,
               let data = img.jpegData(compressionQuality: 0.75) {
                let path = "giocatori/profili/\(createdPlayerId).jpg"
                do {
                    let url = try await appState.storageService.uploadImage(data, path: path)
                    try await appState.firestoreService.updatePlayerPicture(
                        playerId: createdPlayerId,
                        pictureURL: url.absoluteString
                    )
                    try? await appState.firestoreService.refreshCurrentEditionParticipationSnapshot(teamId: teamId)
                } catch {
                    await appState.loadTeams()
                    dismissAfterAlert = true
                    alertTitle = "Giocatore creato"
                    alertMessage = "Il profilo e stato creato, ma il caricamento della foto non e riuscito. Puoi aggiungerla o cambiarla piu tardi dalla rosa."
                    showAlert = true
                    isLoading = false
                    return
                }
            }

            await appState.loadTeams()
            dismiss()
        } catch {
            dismissAfterAlert = false
            alertTitle = "Errore"
            alertMessage = "Impossibile aggiungere il giocatore: \(error.localizedDescription)"
            showAlert = true
        }
        isLoading = false
    }

    private func handleExistingPlayerSelection(_ player: Player) async {
        guard let playerId = player.id, !playerId.isEmpty else {
            alertTitle = "Profilo non valido"
            alertMessage = "Questo giocatore non ha un identificativo valido."
            showAlert = true
            return
        }

        if !isAdmin && !player.isClaimed {
            alertTitle = "Profilo non collegato"
            alertMessage = "Questo giocatore esiste nel database, ma non ha un account collegato per approvare il trasferimento."
            showAlert = true
            return
        }

        isLoading = true
        do {
            if isAdmin {
                try await appState.cloudFunctionsService.adminAssignPlayerToTeam(
                    playerId: playerId,
                    teamId: teamId
                )
                if let previousTeamId = player.teamId,
                   !previousTeamId.isEmpty,
                   previousTeamId != teamId {
                    try? await appState.firestoreService.refreshCurrentEditionParticipationSnapshot(teamId: previousTeamId)
                }
                try? await appState.firestoreService.refreshCurrentEditionParticipationSnapshot(teamId: teamId)
            } else {
                try await appState.cloudFunctionsService.sendPlayerRequest(playerId: playerId)
            }
            await appState.loadTeams()
            dismiss()
        } catch {
            alertTitle = "Errore"
            alertMessage = isAdmin
                ? "Impossibile inserire il giocatore in rosa: \(error.localizedDescription)"
                : "Impossibile inviare la richiesta: \(error.localizedDescription)"
            showAlert = true
        }
        isLoading = false
    }

    private func loadExistingPlayers() async {
        isLoadingExistingPlayers = true
        defer { isLoadingExistingPlayers = false }

        do {
            existingPlayers = try await appState.firestoreService.fetchAllPlayers()
        } catch {
            alertTitle = "Errore"
            alertMessage = "Impossibile caricare i giocatori esistenti: \(error.localizedDescription)"
            showAlert = true
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

    private func existingPlayerRow(player: Player, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(
                urlString: player.displayPhotoURL,
                placeholderIcon: "person.fill",
                placeholderColor: TournamentPalette.accentSoft,
                contentAlignment: .top
            )
            .frame(width: 42, height: 42)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(player.nomeCompleto)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TournamentPalette.ink)

                Text(playerSubtitle(for: player))
                    .font(.caption)
                    .foregroundStyle(TournamentPalette.inkMuted)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(TournamentPalette.accent)
            } else if !player.isClaimed && !isAdmin {
                TournamentPill(label: "Non collegato", tone: .neutral)
            } else if player.isFreeAgent {
                TournamentPill(label: "Svincolato", tone: .accent)
            } else {
                TournamentPill(label: isAdmin ? "Trasferisci" : "Richiedi", tone: .neutral)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? TournamentPalette.accentSoft.opacity(0.55) : .clear)
    }

    private func playerSubtitle(for player: Player) -> String {
        if player.isFreeAgent {
            return player.isClaimed ? "Svincolato" : "Svincolato · profilo non collegato"
        }

        if let currentTeamId = player.teamId,
           let currentTeamName = appState.teams.first(where: { $0.id == currentTeamId })?.nomeSquadra,
           !currentTeamName.isEmpty {
            return player.isClaimed ? currentTeamName : "\(currentTeamName) · profilo non collegato"
        }

        return player.isClaimed ? "Altra squadra" : "Profilo non collegato"
    }

    private func candidateId(for player: Player) -> String {
        if let id = player.id, !id.isEmpty {
            return id
        }
        if let identityUid = player.identityUid, !identityUid.isEmpty {
            return identityUid
        }
        return "\(normalizedName(player.nomeCompleto))|\(player.teamId ?? "svincolato")|\(player.numeroMaglia ?? -1)"
    }

    private func searchRank(for player: Player) -> Int {
        let normalizedPlayerName = normalizedName(player.nomeCompleto)
        if normalizedPlayerName == normalizedQuery {
            return 0
        }
        if normalizedPlayerName.hasPrefix(normalizedQuery) {
            return 1
        }
        return 2
    }

    private func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

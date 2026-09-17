import SwiftUI
import UIKit

struct EditPlayerPhotoView: View {
    let player: Player

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private let posizioniDisponibili = ["Portiere", "Difensore", "Centrocampista", "Attaccante", "Ala"]
    private let piediDisponibili = ["Destro", "Sinistro", "Ambidestro"]

    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imageSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var showSourceChoice = false
    @State private var isSaving = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var nomeCompleto = ""
    @State private var numeroMagliaText = ""
    @State private var posizione = ""
    @State private var piedeDominante = ""
    @State private var carica: CaricaSquadra?

    private var trimmedName: String {
        nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedNumeroMaglia: Int? {
        let trimmed = numeroMagliaText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private var playerDataChanged: Bool {
        trimmedName != player.nomeCompleto.trimmingCharacters(in: .whitespacesAndNewlines)
            || parsedNumeroMaglia != player.numeroMaglia
            || posizione != (player.positionPrimary ?? "")
            || piedeDominante != (player.piedeDominante ?? "")
            || carica != player.carica
    }

    private var hasChanges: Bool {
        selectedImage != nil || playerDataChanged
    }

    var body: some View {
        NavigationStack {
            TournamentScreen {
                ScrollView {
                    VStack(spacing: 20) {
                        photoPickerHeader

                        TournamentFormSection(
                            title: "Dati giocatore",
                            subtitle: "Aggiorna rapidamente i dati principali della rosa.",
                            icon: "person.text.rectangle.fill"
                        ) {
                            formField(label: "Nome e cognome") {
                                TextField("Nome giocatore", text: $nomeCompleto)
                            }

                            formField(label: "Numero di maglia") {
                                TextField("Es. 10", text: $numeroMagliaText)
                                    .keyboardType(.numberPad)
                            }

                            formField(label: "Ruolo") {
                                Picker("Ruolo", selection: $posizione) {
                                    Text("Non impostato").tag("")
                                    ForEach(posizioniDisponibili, id: \.self) { ruolo in
                                        Text(ruolo).tag(ruolo)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            formField(label: "Piede dominante") {
                                Picker("Piede", selection: $piedeDominante) {
                                    Text("Non impostato").tag("")
                                    ForEach(piediDisponibili, id: \.self) { piede in
                                        Text(piede).tag(piede)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            formField(label: "Carica") {
                                CaricaPicker(carica: $carica)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .padding(.top, 16)
                }
            }
            .navigationTitle(player.nomeCompleto)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Chiudi") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await saveChanges() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.headline.weight(.bold))
                        }
                    }
                    .disabled(!hasChanges || isSaving)
                }
            }
        }
        .onAppear {
            nomeCompleto = player.nomeCompleto
            if let n = player.numeroMaglia {
                numeroMagliaText = String(n)
            }
            posizione = player.positionPrimary ?? ""
            piedeDominante = player.piedeDominante ?? ""
            carica = player.carica
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
            Button("OK") {}
        } message: {
            Text(alertMessage)
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

    private var photoPickerHeader: some View {
        VStack(spacing: 10) {
            Button {
                showSourceChoice = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    profilePreview

                    ZStack {
                        Circle()
                            .fill(TournamentPalette.accent)
                            .frame(width: 38, height: 38)

                        Image(systemName: "camera.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle()
                            .stroke(TournamentPalette.surface, lineWidth: 3)
                    )
                }
            }
            .buttonStyle(.tournamentPress)

            Text("Tocca la foto per cambiarla")
                .font(.caption)
                .foregroundStyle(TournamentPalette.inkMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private var profilePreview: some View {
        Group {
            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                CachedAsyncImage(
                    urlString: player.pictureURL,
                    placeholderIcon: "person.fill",
                    placeholderColor: TournamentPalette.accentSoft
                )
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(Circle())
        .overlay(Circle().stroke(TournamentPalette.border, lineWidth: 1))
    }

    private func saveChanges() async {
        guard let playerId = player.id, !playerId.isEmpty else {
            alertTitle = "Profilo non valido"
            alertMessage = "Questo giocatore non ha un ID valido."
            showAlert = true
            return
        }

        guard !trimmedName.isEmpty else {
            alertTitle = "Nome richiesto"
            alertMessage = "Inserisci il nome del giocatore prima di salvare."
            showAlert = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            if playerDataChanged {
                try await appState.firestoreService.updateManagedPlayer(
                    playerId: playerId,
                    nomeCompleto: trimmedName,
                    numeroMaglia: parsedNumeroMaglia,
                    positionPrimary: posizione.isEmpty ? nil : posizione,
                    piedeDominante: piedeDominante.isEmpty ? nil : piedeDominante
                )
            }

            if carica != player.carica, let teamId = player.teamId, !teamId.isEmpty {
                try await appState.firestoreService.assegnaCarica(playerId: playerId, teamId: teamId, carica: carica)
            }

            if let selectedImage,
               let data = selectedImage.jpegData(compressionQuality: 0.75) {
                let path = "giocatori/profili/\(playerId).jpg"
                let url = try await appState.storageService.uploadImage(data, path: path)
                try await appState.firestoreService.updatePlayerPicture(
                    playerId: playerId,
                    pictureURL: url.absoluteString
                )
            }

            if let teamId = player.teamId, !teamId.isEmpty {
                try? await appState.firestoreService.refreshCurrentEditionParticipationSnapshot(teamId: teamId)
            }
            await appState.loadTeams()
            dismiss()
        } catch {
            alertTitle = "Errore"
            alertMessage = "Impossibile salvare le modifiche: \(error.localizedDescription)"
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
}

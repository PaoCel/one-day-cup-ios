import SwiftUI
import UIKit

/// Passo foto.
///
/// Se il giocatore ha già una foto su One Day Cup non gli si chiede di
/// caricarne un'altra: gliela si mostra e gli si chiede solo conferma. Il
/// picker si apre da solo soltanto quando non c'è proprio niente da riusare.
struct PlayerCardPhotoStepView: View {
    @Bindable var viewModel: PlayerCardFlowViewModel
    @State private var isShowingPicker = false
    /// Da dove arriva la foto. Chi non ne ha una in archivio e' anche chi non
    /// ne ha una buona in libreria: senza la fotocamera qui deve uscire
    /// dall'app, scattare e rientrare — e il flusso ricomincia da capo.
    @State private var sorgente: UIImagePickerController.SourceType = .photoLibrary

    private var fotocameraDisponibile: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var hasExisting: Bool { viewModel.existingPhotoURL?.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
            PlayerCardStepHeader(
                title: hasExisting && viewModel.isUsingExistingPhoto
                    ? "Usiamo questa foto per la tua figurina?"
                    : "Scegli la foto della figurina",
                subtitle: "È il volto che finirà sulla card."
            )

            photoPreview
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                        .stroke(TournamentPalette.border, lineWidth: 1)
                )

            tips

            VStack(spacing: TournamentSpacing.sm) {
                if viewModel.hasPhoto {
                    Button { withAnimation { viewModel.confirmPhoto() } } label: {
                        Text("Usa questa foto")
                            .tournamentButtonChrome(.primary)
                    }
                    .buttonStyle(.tournamentPress)
                }
                if fotocameraDisponibile {
                    Button { apri(.camera) } label: {
                        Text("Scatta una foto")
                            .tournamentButtonChrome(viewModel.hasPhoto ? .secondary : .primary)
                    }
                    .buttonStyle(.tournamentPress)
                }
                Button { apri(.photoLibrary) } label: {
                    Text(viewModel.hasPhoto ? "Scegli un'altra foto" : "Scegli dalla libreria")
                        .tournamentButtonChrome(viewModel.hasPhoto || fotocameraDisponibile ? .secondary : .primary)
                }
                .buttonStyle(.tournamentPress)
            }
        }
        .sheet(isPresented: $isShowingPicker) {
            ImagePicker(
                image: Binding(
                    get: { viewModel.pickedImage },
                    set: { newImage in
                        guard let newImage else { return }
                        viewModel.pickedImage = newImage
                        viewModel.isUsingExistingPhoto = false
                    }
                ),
                sourceType: sorgente,
                allowsEditing: false
            )
            .ignoresSafeArea()
        }
        // Nessuna foto da riusare: si apre il picker senza far toccare due volte.
        .onAppear {
            if !hasExisting && viewModel.pickedImage == nil { isShowingPicker = true }
        }
    }

    @ViewBuilder
            // La foto va mostrata INTERA. Con un ritaglio `fill` la testa
            // finiva fuori dal riquadro e sembrava che la foto fosse sbagliata:
            // l'inquadratura della card la decide il generatore, non questa
            // anteprima, e far preoccupare l'utente per un taglio che non
            // esiste e' il modo piu' rapido di fargli cambiare una foto buona.
    private var photoPreview: some View {
        if let picked = viewModel.pickedImage, !viewModel.isUsingExistingPhoto {
            ZStack {
                TournamentPalette.surfaceMuted
                Image(uiImage: picked)
                    .resizable()
                    .scaledToFit()
            }
            .accessibilityLabel("Foto scelta per la figurina")
        } else if hasExisting {
            ZStack {
                TournamentPalette.surfaceMuted
                CachedAsyncImage(
                    urlString: viewModel.existingPhotoURL,
                    placeholderIcon: "person.fill",
                    contentMode: .fit
                )
            }
            .accessibilityLabel("La tua foto profilo attuale")
        } else {
            ZStack {
                TournamentPalette.surfaceMuted
                VStack(spacing: TournamentSpacing.xs) {
                    Image(systemName: "person.crop.square.badge.camera")
                        .font(.largeTitle)
                        .foregroundStyle(TournamentPalette.inkMuted)
                    Text("Nessuna foto selezionata")
                        .font(.footnote)
                        .foregroundStyle(TournamentPalette.inkMuted)
                }
            }
        }
    }

    private func apri(_ nuova: UIImagePickerController.SourceType) {
        sorgente = nuova
        isShowingPicker = true
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.xs) {
            // Primo consiglio e non ultimo: e' l'errore che rovina davvero la
            // card. Da un campo lungo il modello non ha lineamenti da copiare
            // e finisce per inventarsi un viso somigliante ma non tuo.
            tip("Meglio un primo piano: da lontano il viso viene meno somigliante")
            tip("Volto ben visibile e a fuoco")
            tip("Luce chiara, niente controluce")
            Divider().background(TournamentPalette.divider).padding(.vertical, 2)
            HStack(alignment: .top, spacing: TournamentSpacing.xs) {
                Image(systemName: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.accent)
                Text("La figurina viene creata dalla foto intera: l'inquadratura la decide la grafica, tu non devi ritagliare niente.")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .tournamentCard(padding: TournamentSpacing.md)
    }

    private func tip(_ text: String) -> some View {
        HStack(alignment: .top, spacing: TournamentSpacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(TournamentPalette.success)
            Text(text)
                .font(.footnote)
                .foregroundStyle(TournamentPalette.inkMuted)
            Spacer(minLength: 0)
        }
    }
}

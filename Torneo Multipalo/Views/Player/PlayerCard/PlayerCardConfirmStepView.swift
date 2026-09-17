import SwiftUI

/// Consenso + conferma finale. È l'ultimo punto in cui si può tornare indietro:
/// premuto il pulsante, la generazione viene consumata.
struct PlayerCardConfirmStepView: View {
    @Environment(AppState.self) private var appState
    @Bindable var viewModel: PlayerCardFlowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.lg) {
            PlayerCardStepHeader(
                title: "Controlla bene la tua foto 👀",
                subtitle: nil
            )

            Text(viewModel.isRetry
                 ? "Questo è il tuo ultimo tentativo: la figurina che hai adesso verrà sostituita da quella nuova. Assicurati che il viso sia ben visibile e che questa sia la foto giusta."
                 : "Hai a disposizione \(PlayerCardJob.maxGenerations) tentativi in tutto. Assicurati che il viso sia ben visibile e che questa sia la foto che vuoi utilizzare.")
                .font(.subheadline)
                .foregroundStyle(TournamentPalette.ink)
                .fixedSize(horizontal: false, vertical: true)

            photoPreview
                .frame(maxWidth: .infinity)
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TournamentRadius.card, style: .continuous)
                        .stroke(TournamentPalette.border, lineWidth: 1)
                )

            HStack(alignment: .top, spacing: TournamentSpacing.xs) {
                Image(systemName: "info.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.accent)
                Text("Vedi la foto per intero: la card viene costruita su questa, senza tagli decisi da te. Se il viso è piccolo o lontano, però, verrà meno somigliante: meglio un primo piano.")
                    .font(.footnote)
                    .foregroundStyle(TournamentPalette.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            consentBlock

            VStack(spacing: TournamentSpacing.sm) {
                Button {
                    Task { await viewModel.submit(appState: appState) }
                } label: {
                    HStack(spacing: TournamentSpacing.xs) {
                        if viewModel.isSubmitting { ProgressView().tint(.white) }
                        Text(viewModel.isSubmitting
                             ? "Avvio in corso…"
                             : viewModel.isRetry ? "Rifai la mia figurina" : "Genera la mia figurina")
                    }
                    .tournamentButtonChrome(.primary)
                }
                .buttonStyle(.tournamentPress)
                .disabled(!viewModel.canSubmit)
                .opacity(viewModel.canSubmit ? 1 : 0.5)
                .accessibilityHint("Avvia la generazione definitiva della figurina")

                Button { withAnimation { viewModel.changePhotoFromConfirm() } } label: {
                    Text("Cambia foto")
                        .tournamentButtonChrome(.secondary)
                }
                .buttonStyle(.tournamentPress)
                .disabled(viewModel.isSubmitting)
            }
        }
    }

    @ViewBuilder
    private var photoPreview: some View {
        // Stessa scelta del passo foto: intera, mai ritagliata.
        ZStack {
            TournamentPalette.surfaceMuted
            if let picked = viewModel.pickedImage, !viewModel.isUsingExistingPhoto {
                Image(uiImage: picked).resizable().scaledToFit()
            } else {
                CachedAsyncImage(
                    urlString: viewModel.existingPhotoURL,
                    placeholderIcon: "person.fill",
                    contentMode: .fit
                )
            }
        }
    }

    private var consentBlock: some View {
        VStack(alignment: .leading, spacing: TournamentSpacing.sm) {
            Text("Prima di creare la tua figurina")
                .font(.headline)
                .foregroundStyle(TournamentPalette.ink)

            Text("Per generare la tua card, la foto selezionata verrà inviata a \(AICardConsent.provider), un servizio di intelligenza artificiale generativa, esclusivamente per creare la tua figurina.")
                .font(.footnote)
                .foregroundStyle(TournamentPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Text("Procedendo autorizzi One Day Cup a trasmettere questa immagine al servizio di generazione AI.")
                .font(.footnote)
                .foregroundStyle(TournamentPalette.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            Divider().background(TournamentPalette.divider)

            PlayerCardConsentToggle(
                text: "Acconsento all'invio della foto a \(AICardConsent.provider) per generare la mia figurina.",
                isOn: $viewModel.consentAI
            )
            PlayerCardConsentToggle(
                text: "Confermo di essere la persona raffigurata nella foto o di avere il permesso di utilizzarla.",
                isOn: $viewModel.consentIdentity
            )
        }
        .tournamentCard()
    }
}

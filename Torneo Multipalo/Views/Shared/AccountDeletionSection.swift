import AuthenticationServices
import FirebaseAuth
import SwiftUI

struct AccountDeletionSection: View {
    enum Style { case card, compact }

    var style: Style = .card

    @Environment(AppState.self) private var appState

    @State private var currentPassword = ""
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var showPasswordSheet = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        Button(role: .destructive) {
            if appState.authService.requiresPasswordForAccountDeletion {
                showPasswordSheet = true
            } else {
                showDeleteConfirmation = true
            }
        } label: {
            Group {
                switch style {
                case .card:
                    cardLabel
                case .compact:
                    compactLabel
                }
            }
        }
        .buttonStyle(.tournamentPress)
        .disabled(isDeleting)
        .opacity(isDeleting ? 0.7 : 1)
        .confirmationDialog(
            "Eliminare account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Elimina definitivamente", role: .destructive) {
                Task { await deleteAccount(currentPassword: nil) }
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Questa azione elimina l'accesso all'app per questo account.")
        }
        .sheet(isPresented: $showPasswordSheet, onDismiss: {
            currentPassword = ""
        }) {
            NavigationStack {
                TournamentScreen {
                    VStack(spacing: 20) {
                        TournamentFormSection(
                            title: "Conferma password",
                            subtitle: "Per sicurezza, reinserisci la password corrente prima di eliminare l'account.",
                            icon: "lock.fill"
                        ) {
                            SecureField("Password corrente", text: $currentPassword)
                                .textContentType(.password)
                                .tournamentInputChrome()

                            Button(role: .destructive) {
                                Task { await deleteAccount(currentPassword: currentPassword) }
                            } label: {
                                HStack {
                                    if isDeleting {
                                        ProgressView()
                                            .tint(.white)
                                            .padding(.trailing, 4)
                                    }
                                    Text("Elimina definitivamente")
                                }
                                .tournamentButtonChrome(.destructive)
                            }
                            .buttonStyle(.tournamentPress)
                            .disabled(isDeleting || currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity((isDeleting || currentPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.7 : 1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 24)

                        Spacer()
                    }
                }
                .navigationTitle("Elimina account")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Annulla") {
                            showPasswordSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var cardLabel: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TournamentPalette.danger.opacity(0.08))
                    .frame(width: 38, height: 38)

                if isDeleting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(TournamentPalette.danger)
                } else {
                    Image(systemName: "trash")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(TournamentPalette.danger)
                }
            }

            Text("Elimina account")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TournamentPalette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
        .tournamentCard()
    }

    private var compactLabel: some View {
        HStack(spacing: 8) {
            if isDeleting {
                ProgressView()
                    .controlSize(.small)
                    .tint(TournamentPalette.danger)
            } else {
                Image(systemName: "trash")
                    .font(.footnote.weight(.semibold))
            }
            Text("Elimina account")
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(TournamentPalette.danger)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TournamentPalette.danger.opacity(0.08))
        )
    }

    private func deleteAccount(currentPassword: String?) async {
        isDeleting = true
        defer { isDeleting = false }

        do {
            try await appState.authService.deleteCurrentAccount(
                cloudFunctionsService: appState.cloudFunctionsService,
                currentPassword: currentPassword
            )
            self.currentPassword = ""
            showPasswordSheet = false
            showDeleteConfirmation = false
        } catch {
            alertTitle = "Eliminazione non completata"
            alertMessage = localizedDeletionError(error)
            showAlert = true
        }
    }

    private func localizedDeletionError(_ error: Error) -> String {
        if let error = error as? AccountDeletionError {
            return error.localizedDescription
        }
        if let authorizationError = error as? ASAuthorizationError {
            switch authorizationError.code {
            case .canceled:
                return "Conferma Apple annullata."
            case .failed:
                return "Conferma Apple non riuscita. Riprova."
            default:
                return authorizationError.localizedDescription
            }
        }

        let nsError = error as NSError
        switch nsError.code {
        case AuthErrorCode.wrongPassword.rawValue:
            return "La password corrente non e corretta."
        case AuthErrorCode.networkError.rawValue:
            return "Connessione assente o instabile. Riprova."
        default:
            return error.localizedDescription
        }
    }
}

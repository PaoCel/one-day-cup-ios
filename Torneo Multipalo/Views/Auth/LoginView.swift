import SwiftUI
import AuthenticationServices
import FirebaseAuth
import GoogleSignInSwift

struct LoginView: View {
    @Environment(AppState.self) private var appState

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        OneDayEntranceScreen {
            ScrollView {
                VStack(spacing: 22) {
                    OneDayEntryLogo()
                        .frame(width: 140, height: 124)
                        .padding(.top, 12)

                    VStack(spacing: 6) {
                        Text("Accedi al tuo account")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(OneDayEntrancePalette.ink)
                            .multilineTextAlignment(.center)
                        Text("Email e password, oppure Google o Apple.")
                            .font(.subheadline)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            TextField("esempio@email.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .oneDayEntranceInput()
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(OneDayEntrancePalette.inkMuted)
                            SecureField("La tua password", text: $password)
                                .textContentType(.password)
                                .oneDayEntranceInput()
                        }

                        if let errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text(errorMessage)
                                    .font(.caption)
                                Spacer()
                            }
                            .foregroundStyle(OneDayEntrancePalette.danger)
                        }

                        Button {
                            Task { await login() }
                        } label: {
                            HStack {
                                if isLoading {
                                    ProgressView()
                                        .tint(Color(hex: "#221302") ?? .black)
                                        .padding(.trailing, 4)
                                }
                                Text("Accedi")
                            }
                            .oneDayEntranceButton(.primaryGold)
                        }
                        .buttonStyle(.tournamentPress)
                        .disabled(isLoading || email.isEmpty || password.isEmpty)
                        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1)

                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(OneDayEntrancePalette.stroke)
                                .frame(height: 1)
                            Text("oppure")
                                .font(.caption)
                                .foregroundStyle(OneDayEntrancePalette.inkDim)
                            Rectangle()
                                .fill(OneDayEntrancePalette.stroke)
                                .frame(height: 1)
                        }
                        .padding(.vertical, 2)

                        // I due bottoni restano quelli ufficiali di Google e
                        // Apple — sono asset che le due aziende impongono e non
                        // si ridisegnano — ma **la forma la decidiamo noi**:
                        // ciascuno arrivava col suo raggio e uscivano uno
                        // stondato e uno no, appaiati, che e' la prima cosa che
                        // si nota aprendo l'app.
                        GoogleSignInButton(
                            scheme: .dark,
                            style: .wide,
                            state: isLoading ? .disabled : .normal
                        ) {
                            Task { await loginWithGoogle() }
                        }
                        .modifier(TastoAccessoSocial())
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.6 : 1)

                        SignInWithAppleButton(.continue) { request in
                            appState.authService.prepareAppleSignInRequest(request)
                        } onCompletion: { result in
                            Task { await loginWithApple(result) }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .modifier(TastoAccessoSocial())
                        .disabled(isLoading)
                        .opacity(isLoading ? 0.6 : 1)
                    }
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 20)

                    VStack(spacing: 10) {
                        Text("Non hai ancora un profilo torneo?")
                            .font(.footnote)
                            .foregroundStyle(OneDayEntrancePalette.inkMuted)

                        NavigationLink(destination: TeamRegistrationView()) {
                            Label("Registra la tua squadra", systemImage: "shield.fill")
                                .oneDayEntranceButton(.surface)
                        }
                        .buttonStyle(.tournamentPress)

                        NavigationLink(destination: PlayerRegistrationView()) {
                            Label("Registrati come giocatore", systemImage: "person.fill")
                                .oneDayEntranceButton(.ghost)
                        }
                        .buttonStyle(.tournamentPress)
                    }
                    .frame(maxWidth: 380)
                    .padding(.horizontal, 20)

                    OneDayEntranceLegalLinks()
                        .padding(.top, 4)

                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func login() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            let user = try await appState.authService.login(email: email, password: password)
            await appState.authService.resolveRole(uid: user.uid)
        } catch {
            errorMessage = localizedFirebaseError(error)
        }
        isLoading = false
    }

    private func loginWithApple(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await appState.authService.completeAppleSignIn(with: result)
            await appState.authService.resolveRole(uid: user.uid)
        } catch {
            errorMessage = localizedAppleError(error)
        }
        isLoading = false
    }

    private func loginWithGoogle() async {
        isLoading = true
        errorMessage = nil
        do {
            let user = try await appState.authService.loginWithGoogle()
            await appState.authService.resolveRole(uid: user.uid)
        } catch {
            errorMessage = localizedGoogleError(error)
        }
        isLoading = false
    }

    private func localizedFirebaseError(_ error: Error) -> String {
        let code = (error as NSError).code
        switch code {
        case 17009: return "Password non corretta."
        case 17011: return "Nessun account trovato con questa email."
        case 17010: return "Troppi tentativi. Riprova tra qualche minuto."
        case 17020: return "Nessuna connessione internet."
        default:    return "Errore di accesso. Riprova."
        }
    }

    private func localizedAppleError(_ error: Error) -> String {
        if let error = error as? AppleSignInError {
            return error.localizedDescription
        }
        if let authError = error as? ASAuthorizationError {
            switch authError.code {
            case .canceled:
                return "Accesso con Apple annullato."
            case .failed:
                return "Accesso con Apple non riuscito."
            case .invalidResponse:
                return "Risposta Apple non valida."
            case .notHandled:
                return "Richiesta Apple non completata."
            case .unknown:
                return "Errore Apple sconosciuto."
            default:
                return authError.localizedDescription
            }
        }
        let nsError = error as NSError
        switch nsError.code {
        case 17012: return "Questo account usa un altro metodo di accesso."
        case 17020: return "Nessuna connessione internet."
        default:    return error.localizedDescription
        }
    }

    private func localizedGoogleError(_ error: Error) -> String {
        if let error = error as? GoogleSignInError {
            return error.localizedDescription
        }

        let nsError = error as NSError
        switch nsError.code {
        case -5:
            return "Accesso con Google annullato."
        case 17012:
            return "Questo account usa un altro metodo di accesso."
        case 17020:
            return "Nessuna connessione internet."
        default:
            return error.localizedDescription
        }
    }
}



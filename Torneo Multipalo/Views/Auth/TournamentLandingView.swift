import SwiftUI
import AuthenticationServices
import FirebaseAuth
import GoogleSignInSwift

struct TournamentLandingView: View {
    @Environment(AppState.self) private var appState

    var canShowActions = true
    let onEnterAsGuest: () -> Void

    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showActions = false
    @State private var splashDidFinish = false
    @State private var splashFallbackScheduled = false

    var body: some View {
        NavigationStack {
            OneDayEntranceScreen {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        Spacer(minLength: 16)

                        // Il logo resta nudo, ma non è più tutta la pagina: sotto
                        // ha un titolo, e i due insieme fanno il terzo alto.
                        Group {
                            if splashDidFinish {
                                OneDayEntryLogo()
                            } else {
                                OneDayEntryLogoIntro(revealDelay: 0.85) {
                                    completeSplashIfNeeded()
                                }
                            }
                        }
                        .frame(
                            width: min(geometry.size.width * 0.62, 250),
                            height: min(geometry.size.height * 0.27, 230)
                        )

                        OneDayEntranceTitle(
                            title: "Vivi il torneo",
                            subtitle: "Risultati in diretta, classifiche, tabellone e figurine dei tornei di un giorno."
                        )
                        .padding(.horizontal, 32)
                        .padding(.top, 6)
                        .rivelato(showActions, ordine: 0)

                        Spacer(minLength: 24)

                        VStack(spacing: 12) {
                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(OneDayEntrancePalette.danger)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 8)
                                    .transition(.opacity)
                            }

                            SignInWithAppleButton(.continue) { request in
                                appState.authService.prepareAppleSignInRequest(request)
                            } onCompletion: { result in
                                Task { await loginWithApple(result) }
                            }
                            .signInWithAppleButtonStyle(.white)
                            .modifier(TastoAccessoSocial())
                            .disabled(isLoading)
                            .opacity(isLoading ? 0.6 : 1)
                            .rivelato(showActions, ordine: 1)

                            GoogleSignInButton(
                                scheme: .light,
                                style: .wide,
                                state: isLoading ? .disabled : .normal
                            ) {
                                Task { await loginWithGoogle() }
                            }
                            .modifier(TastoAccessoSocial())
                            .disabled(isLoading)
                            .opacity(isLoading ? 0.6 : 1)
                            .rivelato(showActions, ordine: 2)

                            NavigationLink(destination: LoginView()) {
                                HStack(spacing: 10) {
                                    if isLoading {
                                        ProgressView()
                                            .tint(OneDayEntrancePalette.ink)
                                    } else {
                                        Image(systemName: "envelope.fill")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(OneDayEntrancePalette.gold)
                                    }
                                    Text("Accedi con email")
                                }
                                .oneDayEntranceButton(.surface)
                            }
                            .buttonStyle(.tournamentPress)
                            .disabled(isLoading)
                            .opacity(isLoading ? 0.6 : 1)
                            .rivelato(showActions, ordine: 3)

                            // L'ospite non è un ripiego: è la porta di chi vuole
                            // solo guardare, e su un torneo di un giorno è la
                            // maggioranza. Oro, senza cornice: si vede, non pesa.
                            Button {
                                Task { await enterAsGuest() }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Entra come ospite")
                                    Image(systemName: "arrow.right")
                                        .font(.subheadline.weight(.bold))
                                }
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(OneDayEntrancePalette.gold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.tournamentPress)
                            .disabled(isLoading)
                            .opacity(isLoading ? 0.6 : 1)
                            .rivelato(showActions, ordine: 4)

                            HStack(spacing: 4) {
                                Text("Non hai un account?")
                                    .foregroundStyle(OneDayEntrancePalette.inkMuted)
                                NavigationLink(destination: RegistrationChoiceView()) {
                                    Text("Registrati")
                                        .foregroundStyle(OneDayEntrancePalette.ink)
                                        .underline(true, color: OneDayEntrancePalette.gold)
                                }
                            }
                            .font(.footnote.weight(.medium))
                            .rivelato(showActions, ordine: 5)

                            OneDayEntranceLegalLinks()
                                .padding(.top, 6)
                                .rivelato(showActions, ordine: 6)
                        }
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .allowsHitTesting(showActions)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .task {
            guard !splashFallbackScheduled else { return }
            splashFallbackScheduled = true
            try? await Task.sleep(for: .seconds(2.2))
            completeSplashIfNeeded()
        }
    }

    private func loginWithApple(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await appState.authService.completeAppleSignIn(with: result)
            await appState.authService.resolveRole(uid: user.uid)
        } catch {
            errorMessage = localizedAppleError(error)
        }
    }

    private func loginWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let user = try await appState.authService.loginWithGoogle()
            await appState.authService.resolveRole(uid: user.uid)
        } catch {
            errorMessage = localizedGoogleError(error)
        }
    }

    private func enterAsGuest() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if let currentUser = appState.authService.currentUser,
               currentUser.isAnonymous {
                await appState.authService.resolveRole(uid: currentUser.uid)
            } else {
                let user = try await appState.authService.loginAnonymously()
                await appState.authService.resolveRole(uid: user.uid)
            }
            onEnterAsGuest()
        } catch {
            errorMessage = "Non sono riuscito ad aprire l'accesso ospite."
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
        case 17012:
            return "Questo account usa un altro metodo di accesso."
        case 17020:
            return "Nessuna connessione internet."
        default:
            return error.localizedDescription
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

    private func completeSplashIfNeeded() {
        guard !splashDidFinish else { return }
        splashDidFinish = true
        revealActionsIfReady()
    }

    private func revealActionsIfReady() {
        guard splashDidFinish, !showActions else { return }
        withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
            showActions = true
        }
    }
}

private extension View {
    /// La rivelazione a cascata dopo il logo: ogni riga arriva un soffio dopo
    /// la precedente, dal titolo in giù. Un blocco unico che appariva tutto
    /// insieme sembrava un cambio di schermata; così sembra la pagina che si
    /// compone. Lo stato dell'animazione resta nella view.
    func rivelato(_ visibile: Bool, ordine: Int) -> some View {
        self
            .opacity(visibile ? 1 : 0)
            .offset(y: visibile ? 0 : 18)
            .animation(.spring(response: 0.55, dampingFraction: 0.86).delay(Double(ordine) * 0.06), value: visibile)
    }
}

struct RegistrationChoiceView: View {
    var body: some View {
        OneDayEntranceScreen {
            VStack(spacing: 0) {
                Spacer(minLength: 28)

                OneDayEntryLogo()
                    .frame(width: 128, height: 112)

                Spacer(minLength: 20)

                VStack(spacing: 12) {
                    Text("REGISTRAZIONE")
                        .font(.caption.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(OneDayEntrancePalette.gold)

                    Text("Scegli come vuoi entrare nel torneo")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(OneDayEntrancePalette.ink)
                        .multilineTextAlignment(.center)

                    Text("Il percorso resta quello attuale, qui ripuliamo solo l’ingresso.")
                        .font(.subheadline)
                        .foregroundStyle(OneDayEntrancePalette.inkMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 28)

                VStack(spacing: 12) {
                    NavigationLink(destination: TeamRegistrationView()) {
                        Label("Registra la tua squadra", systemImage: "shield.fill")
                            .oneDayEntranceButton(.primaryGold)
                    }
                    .buttonStyle(.tournamentPress)

                    NavigationLink(destination: PlayerRegistrationView()) {
                        Label("Registrati come giocatore", systemImage: "person.fill")
                            .oneDayEntranceButton(.surface)
                    }
                    .buttonStyle(.tournamentPress)

                    NavigationLink(destination: LoginView()) {
                        Text("Hai già un account? Accedi")
                            .oneDayEntranceButton(.ghost)
                    }
                    .buttonStyle(.tournamentPress)
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
            }
        }
        .navigationTitle("Registrazione")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

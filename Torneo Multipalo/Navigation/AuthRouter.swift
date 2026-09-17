import SwiftUI

/// Gestisce la navigazione nel flusso di autenticazione:
/// LoginView → TeamRegistrationView / PlayerRegistrationView
struct AuthRouter: View {
    var body: some View {
        NavigationStack {
            LoginView()
        }
    }
}

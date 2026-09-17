import AuthenticationServices
import CryptoKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleSignIn
import UIKit

@Observable
@MainActor
class AuthService {
    var currentUser: FirebaseAuth.User?
    var userRole: UserRole = .publicUser
    var availableRoles: [UserRole] = []
    var playerIdIfAdmin: String?
    var isLoading = true

    private var authListener: NSObjectProtocol?
    private var currentNonce: String?
    private let appleDeletionCoordinator = AppleAccountDeletionCoordinator()

    var currentAuthProviderIDs: [String] {
        providerIDs(for: currentUser)
    }

    var requiresPasswordForAccountDeletion: Bool {
        currentAuthProviderIDs.contains("password")
            && !currentAuthProviderIDs.contains("apple.com")
            && !currentAuthProviderIDs.contains("google.com")
    }

    func listenToAuthState() {
        guard authListener == nil else { return }

        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.currentUser = user
                if let user {
                    await self.resolveRole(uid: user.uid)
                } else {
                    self.userRole = .publicUser
                    self.availableRoles = []
                    self.playerIdIfAdmin = nil
                }
                self.isLoading = false
            }
        }
    }

    @discardableResult
    func login(email: String, password: String) async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        currentUser = result.user
        return result.user
    }

    func register(email: String, password: String) async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        currentUser = result.user
        return result.user
    }

    @discardableResult
    func loginAnonymously() async throws -> FirebaseAuth.User {
        let result = try await Auth.auth().signInAnonymously()
        currentUser = result.user
        return result.user
    }

    func loginWithGoogle() async throws -> FirebaseAuth.User {
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw GoogleSignInError.missingClientID
        }

        let presentingViewController = try Self.resolvePresentationViewController()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let signInResult: GIDSignInResult = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: GoogleSignInError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }

        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw GoogleSignInError.missingIdentityToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: signInResult.user.accessToken.tokenString
        )
        let authResult = try await Auth.auth().signIn(with: credential)
        currentUser = authResult.user
        return authResult.user
    }

    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleSignIn(with result: Result<ASAuthorization, Error>) async throws -> FirebaseAuth.User {
        switch result {
        case .failure(let error):
            throw error

        case .success(let authorization):
            guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppleSignInError.invalidCredential
            }
            guard let nonce = currentNonce else {
                throw AppleSignInError.missingNonce
            }
            guard let tokenData = appleCredential.identityToken,
                  let idTokenString = String(data: tokenData, encoding: .utf8) else {
                throw AppleSignInError.missingIdentityToken
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleCredential.fullName
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            currentNonce = nil
            currentUser = authResult.user
            return authResult.user
        }
    }

    func deleteCurrentAccount(
        cloudFunctionsService: CloudFunctionsService,
        currentPassword: String? = nil
    ) async throws {
        guard let user = Auth.auth().currentUser else {
            throw AccountDeletionError.notAuthenticated
        }

        let providerIDs = providerIDs(for: user)

        if providerIDs.contains("apple.com") {
            try await reauthenticateAndRevokeAppleToken(for: user)
        } else if providerIDs.contains("password") {
            try await reauthenticateWithPasswordIfNeeded(for: user, currentPassword: currentPassword)
        } else if providerIDs.contains("google.com") {
            try await reauthenticateWithGoogle(for: user)
        }

        _ = try await cloudFunctionsService.deleteCurrentAccount()
        logout()
    }

    func logout() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        currentUser = nil
        userRole = .publicUser
        availableRoles = []
        playerIdIfAdmin = nil
    }

    var hasMultipleProfileRoles: Bool {
        availableRoles.count > 1
    }

    func setActiveRole(_ role: UserRole) {
        guard availableRoles.contains(role) else { return }
        userRole = role
    }

    func resolveRole(uid: String) async {
        let db = Firestore.firestore()

        playerIdIfAdmin = nil

        do {
            let adminDoc = try await db.collection("admins").document(uid).getDocument()
            if adminDoc.exists {
                userRole = .admin
                availableRoles = [.admin]
                if let playerId = await resolvePlayerId(uid: uid, db: db) {
                    playerIdIfAdmin = playerId
                }
                return
            }
        } catch {}

        var resolvedRoles: [UserRole] = []

        do {
            let teamsQuery = try await db.collection("squadre")
                .whereField("ownerUid", isEqualTo: uid)
                .getDocuments()
            if let teamDoc = teamsQuery.documents.first {
                resolvedRoles.append(.teamOwner(teamId: teamDoc.documentID))
            }
        } catch {}

        if let playerId = await resolvePlayerId(uid: uid, db: db) {
            resolvedRoles.append(.player(playerId: playerId))
        }

        if !resolvedRoles.isEmpty {
            availableRoles = resolvedRoles
            if availableRoles.contains(userRole) {
                return
            }
            if let teamOwnerRole = availableRoles.first(where: {
                if case .teamOwner = $0 { return true }
                return false
            }) {
                userRole = teamOwnerRole
            } else if let firstRole = availableRoles.first {
                userRole = firstRole
            }
            return
        }

        availableRoles = []
        userRole = .publicUser
    }

    private func resolvePlayerId(uid: String, db: Firestore) async -> String? {
        if let playerDoc = await findPlayerDocument(uid: uid, db: db) {
            return playerDoc.documentID
        }
        return nil
    }

    private func findPlayerDocument(uid: String, db: Firestore) async -> QueryDocumentSnapshot? {
        do {
            let claimDoc = try await db.collection("playerClaims").document(uid).getDocument()
            if let playerId = claimDoc.data()?["playerId"] as? String, !playerId.isEmpty {
                let playerDoc = try await db.collection("giocatori").document(playerId).getDocument()
                if playerDoc.exists,
                   let snapshot = try? await db.collection("giocatori")
                    .whereField(FieldPath.documentID(), isEqualTo: playerId)
                    .limit(to: 1)
                    .getDocuments()
                    .documents.first {
                    return snapshot
                }
            }
        } catch {}

        for field in ["playerAuthUid", "userId", "claimedBy"] {
            do {
                let query = try await db.collection("giocatori")
                    .whereField(field, isEqualTo: uid)
                    .limit(to: 1)
                    .getDocuments()
                if let document = query.documents.first {
                    return document
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func providerIDs(for user: FirebaseAuth.User?) -> [String] {
        (user?.providerData ?? [])
            .map(\.providerID)
            .filter { $0 != "firebase" }
    }

    private func reauthenticateWithPasswordIfNeeded(
        for user: FirebaseAuth.User,
        currentPassword: String?
    ) async throws {
        let trimmedPassword = currentPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedPassword.isEmpty else {
            throw AccountDeletionError.passwordRequired
        }
        guard let email = user.email, !email.isEmpty else {
            throw AccountDeletionError.emailUnavailable
        }

        let credential = EmailAuthProvider.credential(withEmail: email, password: trimmedPassword)
        _ = try await user.reauthenticate(with: credential)
    }

    private func reauthenticateAndRevokeAppleToken(for user: FirebaseAuth.User) async throws {
        let nonce = Self.randomNonceString()
        let appleCredential = try await appleDeletionCoordinator.requestCredential(rawNonce: nonce)

        guard let tokenData = appleCredential.identityToken,
              let idTokenString = String(data: tokenData, encoding: .utf8) else {
            throw AccountDeletionError.appleIdentityTokenMissing
        }

        let credential = OAuthProvider.credential(
            providerID: .apple,
            idToken: idTokenString,
            rawNonce: nonce
        )
        _ = try await user.reauthenticate(with: credential)

        guard let authorizationCode = appleCredential.authorizationCode,
              let authCodeString = String(data: authorizationCode, encoding: .utf8),
              !authCodeString.isEmpty else {
            throw AccountDeletionError.appleAuthorizationCodeMissing
        }

        try await Auth.auth().revokeToken(withAuthorizationCode: authCodeString)
    }

    private func reauthenticateWithGoogle(for user: FirebaseAuth.User) async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID, !clientID.isEmpty else {
            throw GoogleSignInError.missingClientID
        }

        let presentingViewController = try Self.resolvePresentationViewController()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        let signInResult: GIDSignInResult = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<GIDSignInResult, Error>) in
            GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: GoogleSignInError.missingResult)
                    return
                }
                continuation.resume(returning: result)
            }
        }

        guard let idToken = signInResult.user.idToken?.tokenString else {
            throw GoogleSignInError.missingIdentityToken
        }

        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: signInResult.user.accessToken.tokenString
        )
        _ = try await user.reauthenticate(with: credential)
    }

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms = (0..<16).map { _ in UInt8.random(in: 0 ... 255) }
            for random in randoms {
                if remainingLength == 0 {
                    break
                }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    fileprivate static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }

    fileprivate static func resolvePresentationViewController() throws -> UIViewController {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        let rootViewController = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController
            ?? windowScenes
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)?
                .rootViewController
            ?? windowScenes
                .flatMap(\.windows)
                .first?
                .rootViewController

        guard let rootViewController else {
            throw GoogleSignInError.presentationAnchorUnavailable
        }

        return topViewController(from: rootViewController)
    }

    private static func topViewController(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigationController = controller as? UINavigationController,
           let visibleController = navigationController.visibleViewController {
            return topViewController(from: visibleController)
        }
        if let tabBarController = controller as? UITabBarController,
           let selectedController = tabBarController.selectedViewController {
            return topViewController(from: selectedController)
        }
        return controller
    }
}

enum AppleSignInError: LocalizedError {
    case missingNonce
    case missingIdentityToken
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .missingNonce:
            return "Nonce Apple mancante. Riprova."
        case .missingIdentityToken:
            return "Token Apple non ricevuto. Riprova."
        case .invalidCredential:
            return "Credenziali Apple non valide."
        }
    }
}

enum GoogleSignInError: LocalizedError {
    case missingClientID
    case missingResult
    case missingIdentityToken
    case presentationAnchorUnavailable

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Configurazione Google mancante. Aggiorna il file GoogleService-Info.plist."
        case .missingResult:
            return "Google non ha restituito un risultato valido. Riprova."
        case .missingIdentityToken:
            return "Google non ha restituito un token valido. Riprova."
        case .presentationAnchorUnavailable:
            return "Impossibile aprire la conferma Google in questo momento. Riprova."
        }
    }
}

enum AccountDeletionError: LocalizedError {
    case notAuthenticated
    case passwordRequired
    case emailUnavailable
    case appleIdentityTokenMissing
    case appleAuthorizationCodeMissing
    case presentationAnchorUnavailable

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Nessun account attivo da eliminare."
        case .passwordRequired:
            return "Inserisci la password corrente per confermare l'eliminazione dell'account."
        case .emailUnavailable:
            return "Impossibile recuperare l'email dell'account corrente."
        case .appleIdentityTokenMissing:
            return "Apple non ha restituito un token valido. Riprova."
        case .appleAuthorizationCodeMissing:
            return "Apple non ha restituito il codice di autorizzazione necessario. Riprova."
        case .presentationAnchorUnavailable:
            return "Impossibile aprire la conferma Apple in questo momento. Riprova."
        }
    }
}

private final class AppleAccountDeletionCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var presentationWindow: UIWindow?

    func requestCredential(rawNonce: String) async throws -> ASAuthorizationAppleIDCredential {
        presentationWindow = try Self.resolvePresentationWindow()

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.nonce = AuthService.sha256(rawNonce)

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        defer { continuation = nil }

        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AppleSignInError.invalidCredential)
            return
        }

        continuation?.resume(returning: credential)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationWindow ?? ASPresentationAnchor()
    }

    private static func resolvePresentationWindow() throws -> UIWindow {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }

        if let activeWindow = windowScenes
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: \.isKeyWindow) {
            return activeWindow
        }

        if let fallbackWindow = windowScenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? windowScenes.flatMap(\.windows).first {
            return fallbackWindow
        }

        throw AccountDeletionError.presentationAnchorUnavailable
    }
}

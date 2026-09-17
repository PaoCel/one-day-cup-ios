import Foundation
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

extension Notification.Name {
    /// Phase 3c — pubblicato quando l'utente cambia torneo dal picker.
    /// Payload: object = newTid (String).
    static let tournamentChanged = Notification.Name("TMTournamentChanged")
}

/// Phase 3c — store osservabile per la selezione del torneo corrente.
///
/// Fonte di verità per `currentTournamentId`:
///  - persiste in `UserDefaults` chiave `tm.currentTournamentId`
///  - default fallback `"multipalo"`
///  - i consumer (`AppState`, `FirestoreService`) sincronizzano il proprio
///    `currentTournamentId` da qui.
///
/// La store espone anche:
///  - lista `availableTournaments` (status == "active") con cache 5 min
///  - `currentBranding` derivato dal doc del torneo selezionato
@Observable
@MainActor
final class TournamentSelectionStore {
    private static let defaultsKey = "tm.currentTournamentId"
    private static let defaultTid = "multipalo"
    private static let cacheTTL: TimeInterval = 5 * 60

    // MARK: - State

    private(set) var currentTournamentId: String
    private(set) var availableTournaments: [Tournament] = []
    private(set) var currentBranding: TournamentBranding = .none
    private(set) var isLoading: Bool = false
    private(set) var lastLoadedAt: Date?

    private let userDefaults: UserDefaults
    private var db: Firestore { Firestore.firestore() }

    // MARK: - Init

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let stored = userDefaults.string(forKey: Self.defaultsKey)
        self.currentTournamentId = (stored?.isEmpty == false ? stored! : Self.defaultTid)
    }

    // MARK: - Public API

    /// Carica la lista tornei attivi (status == "active"). Cache TTL 5 min.
    /// Se `force == true`, bypassa la cache.
    /// Se `includeAll == true`, restituisce TUTTI i tornei (per super-admin).
    @discardableResult
    func loadAvailableTournaments(force: Bool = false, includeAll: Bool = false) async -> [Tournament] {
        if !force, let last = lastLoadedAt, Date().timeIntervalSince(last) < Self.cacheTTL,
           !availableTournaments.isEmpty {
            return availableTournaments
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let query: Query = includeAll
                ? db.collection("tournaments")
                : db.collection("tournaments").whereField("status", isEqualTo: "active")

            // I tornei sandbox non sono "active": si chiedono a parte e si
            // tengono solo se l'utente è nell'allowlist. Query in più solo per
            // chi ha fatto login (l'ospite non la fa nemmeno).
            let uid = Auth.auth().currentUser?.uid
            async let activeSnap = query.getDocuments()
            async let sandboxSnap: QuerySnapshot? = {
                guard !includeAll, uid != nil else { return nil }
                return try? await db.collection("tournaments")
                    .whereField("sandbox", isEqualTo: true)
                    .getDocuments()
            }()

            let snap = try await activeSnap
            let sandboxDocs = (await sandboxSnap)?.documents.filter { doc in
                guard let uid else { return false }
                let allowed = (doc.data()["sandboxUids"] as? [String]) ?? []
                return allowed.contains(uid)
            } ?? []

            let tournaments: [Tournament] = (snap.documents + sandboxDocs).compactMap { doc in
                let data = doc.data()
                let displayName = (data["displayName"] as? String) ?? doc.documentID
                let status = (data["status"] as? String) ?? "active"
                let primary = data["primaryColor"] as? String
                let logoUrl = data["logoUrl"] as? String
                let admins = (data["adminUids"] as? [String]) ?? []
                return Tournament(
                    documentID: doc.documentID,
                    displayName: displayName,
                    status: status,
                    primaryColor: primary,
                    logoUrl: logoUrl,
                    adminUids: admins,
                    venue: data["venue"] as? String,
                    eventDate: data["eventDate"] as? String,
                    rulesText: data["rulesText"] as? String,
                    rulesUrl: data["rulesUrl"] as? String,
                    groupTieBreak: data["groupTieBreak"] as? String,
                    sandbox: (data["sandbox"] as? Bool) ?? false
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            self.availableTournaments = tournaments
            self.lastLoadedAt = Date()
            updateBrandingFromCurrent()
            return tournaments
        } catch {
            print("TournamentSelectionStore.loadAvailableTournaments error: \(error)")
            return availableTournaments
        }
    }

    /// Cambia il torneo corrente. Persiste e notifica via `NotificationCenter`.
    /// I consumer (AppState/FirestoreService) si re-sincronizzano e ricaricano
    /// i feed dati. Se non possono farlo (troppo invasivo), un alert utente
    /// suggerisce restart app.
    func setCurrentTournament(_ tid: String) {
        let trimmed = tid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != currentTournamentId else { return }
        currentTournamentId = trimmed
        userDefaults.set(trimmed, forKey: Self.defaultsKey)
        updateBrandingFromCurrent()
        NotificationCenter.default.post(name: .tournamentChanged, object: trimmed)
    }

    /// Auto-seleziona se l'utente è admin di un solo torneo, MA solo se
    /// l'utente non ha mai scelto manualmente (UserDefaults vuoto).
    /// Una volta scelto, la sua scelta è rispettata anche se cambia tra tornei.
    /// Da chiamare dopo login con `userUid` corrente.
    func autoSelectIfSingleAdminTournament(userUid: String?) {
        guard let uid = userUid, !uid.isEmpty else { return }
        // Skip se utente ha già fatto una scelta esplicita.
        let stored = userDefaults.string(forKey: Self.defaultsKey)
        if let stored = stored, !stored.isEmpty { return }
        let mine = availableTournaments.filter { $0.adminUids.contains(uid) }
        if mine.count == 1, let single = mine.first, single.id != currentTournamentId {
            setCurrentTournament(single.id)
        }
    }

    /// Cerca il doc del torneo corrente nella lista in-memory; se assente,
    /// fa fetch puntuale.
    func currentTournamentDoc() async -> Tournament? {
        if let cached = availableTournaments.first(where: { $0.id == currentTournamentId }) {
            return cached
        }
        do {
            let snap = try await db.collection("tournaments").document(currentTournamentId).getDocument()
            guard snap.exists else { return nil }
            let data = snap.data() ?? [:]
            let tournament = Tournament(
                documentID: snap.documentID,
                displayName: (data["displayName"] as? String) ?? snap.documentID,
                status: (data["status"] as? String) ?? "active",
                primaryColor: data["primaryColor"] as? String,
                logoUrl: data["logoUrl"] as? String,
                adminUids: (data["adminUids"] as? [String]) ?? [],
                venue: data["venue"] as? String,
                eventDate: data["eventDate"] as? String,
                rulesText: data["rulesText"] as? String,
                rulesUrl: data["rulesUrl"] as? String,
                groupTieBreak: data["groupTieBreak"] as? String
            )
            return tournament
        } catch {
            print("TournamentSelectionStore.currentTournamentDoc error: \(error)")
            return nil
        }
    }

    // MARK: - Private

    private func updateBrandingFromCurrent() {
        let doc = availableTournaments.first { $0.id == currentTournamentId }
        currentBranding = doc?.branding ?? .none
    }
}

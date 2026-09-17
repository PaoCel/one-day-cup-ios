import Foundation
import SwiftUI

/// Phase 3c — modello FLAT del documento `tournaments/{id}` su Firestore.
///
/// Schema FLAT (vince su qualsiasi nested legacy `branding.{...}` rimasto in DB):
///   {
///     id: String,
///     displayName: String,
///     status: String,           // "active" | "draft" | "archived"
///     primaryColor: String?,    // hex es. "#0B79F7"
///     logoUrl: String?,         // URL HTTPS asset
///     adminUids: [String]
///   }
///
/// `adminUids` viene letto qui solo per supporto auto-selezione del torneo
/// quando l'utente è admin di un solo torneo. Le scritture restano gestite
/// da super-admin console (non da app).
struct Tournament: Identifiable, Codable, Hashable {
    /// Identità stabile derivata dal document path Firestore. Non lasciamo
    /// `@DocumentID` perché ricostruiamo l'oggetto manualmente da `doc.data()`
    /// in `TournamentSelectionStore` e dobbiamo poter passare l'id al costruttore.
    var id: String
    var displayName: String
    var status: String
    var primaryColor: String?
    var logoUrl: String?
    var adminUids: [String]
    // Info evento (impostate dal pannello admin web; nil/"" = TBA "Da definire").
    var venue: String?
    var eventDate: String?
    var rulesText: String?
    var rulesUrl: String?
    /// Come si risolve il pareggio nei gironi: `"rigori"` (default) o
    /// `"shootout"` (Mormon: 1v1 col portiere a tempo). Cambia solo le stringhe
    /// mostrate, non il formato dei dati — vedi `ShootoutTerminology`.
    var groupTieBreak: String?
    /// Torneo di prova: vive in prod con `status "draft"` (quindi invisibile
    /// alle query pubbliche) e lo vede solo chi è in `sandboxUids`. Serve a
    /// simulare un torneo intero, notifiche comprese, senza toccare i dati veri.
    var sandbox: Bool = false
    /// Il retro delle figurine di questo torneo: una faccia sola per tutte le
    /// carte, col logo. Lo genera a mano il worker; la lente lo mostra al tocco.
    var cardBackUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName, status, primaryColor, logoUrl, adminUids
        case venue, eventDate, rulesText, rulesUrl, groupTieBreak, sandbox, cardBackUrl
    }

    init(documentID: String,
         displayName: String,
         status: String = "active",
         primaryColor: String? = nil,
         logoUrl: String? = nil,
         adminUids: [String] = [],
         venue: String? = nil,
         eventDate: String? = nil,
         rulesText: String? = nil,
         rulesUrl: String? = nil,
         groupTieBreak: String? = nil,
         sandbox: Bool = false,
         cardBackUrl: String? = nil) {
        self.id = documentID
        self.displayName = displayName
        self.status = status
        self.primaryColor = primaryColor
        self.logoUrl = logoUrl
        self.adminUids = adminUids
        self.venue = venue
        self.eventDate = eventDate
        self.rulesText = rulesText
        self.rulesUrl = rulesUrl
        self.groupTieBreak = groupTieBreak
        self.sandbox = sandbox
        self.cardBackUrl = cardBackUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        self.displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? ""
        self.status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "active"
        self.primaryColor = try? c.decodeIfPresent(String.self, forKey: .primaryColor)
        self.logoUrl = try? c.decodeIfPresent(String.self, forKey: .logoUrl)
        self.adminUids = (try? c.decodeIfPresent([String].self, forKey: .adminUids)) ?? []
        self.venue = try? c.decodeIfPresent(String.self, forKey: .venue)
        self.eventDate = try? c.decodeIfPresent(String.self, forKey: .eventDate)
        self.rulesText = try? c.decodeIfPresent(String.self, forKey: .rulesText)
        self.rulesUrl = try? c.decodeIfPresent(String.self, forKey: .rulesUrl)
        self.groupTieBreak = try? c.decodeIfPresent(String.self, forKey: .groupTieBreak)
        self.sandbox = (try? c.decodeIfPresent(Bool.self, forKey: .sandbox)) ?? false
        self.cardBackUrl = try? c.decodeIfPresent(String.self, forKey: .cardBackUrl)
    }

    /// Helper TBA per la UI: valore o "Da definire".
    func tbaValue(_ v: String?) -> String {
        if let v = v?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        return "Da definire"
    }

    var isActive: Bool { status == "active" || sandbox }

    /// Branding derivato — utilizzato dalla `AppState` per applicare colore e logo.
    var branding: TournamentBranding {
        TournamentBranding(
            primaryColor: Self.color(fromHex: primaryColor),
            logoURL: logoUrl.flatMap(URL.init(string:)),
            cardBackURL: cardBackUrl.flatMap(URL.init(string:))
        )
    }

    private static func color(fromHex hex: String?) -> Color? {
        guard let hex, !hex.isEmpty else { return nil }
        return Color(hex: hex)
    }

    /// Fallback hard-coded usato per il torneo di default quando il backend non
    /// ha ancora popolato `tournaments/multipalo` (caso primo deploy).
    static let multipaloFallback = Tournament(
        documentID: "multipalo",
        displayName: "Torneo Multipalo 2026",
        status: "active",
        primaryColor: nil,
        logoUrl: nil,
        adminUids: []
    )
}

/// Struct leggera consumata dalle View per applicare il branding.
/// Tenuta separata per non leggere `Tournament` da view che non sono `Codable`-ready.
struct TournamentBranding: Equatable {
    var primaryColor: Color?
    var logoURL: URL?
    var cardBackURL: URL?

    static let none = TournamentBranding(primaryColor: nil, logoURL: nil, cardBackURL: nil)
}

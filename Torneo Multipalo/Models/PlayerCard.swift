import Foundation

// MARK: - Ruolo

/// Ruolo dichiarato dal giocatore. A video restano le quattro parole di sempre;
/// il codice interno usa le sigle, che sono anche quelle stampate sulla card.
enum CardPosition: String, Codable, CaseIterable, Identifiable {
    case goalkeeper = "GK"
    case defender = "DEF"
    case midfielder = "MID"
    case attacker = "ATT"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .goalkeeper: "Portiere"
        case .defender: "Difensore"
        case .midfielder: "Centrocampista"
        case .attacker: "Attaccante"
        }
    }

    var shortLabel: String {
        switch self {
        case .goalkeeper: "POR"
        case .defender: "DIF"
        case .midfielder: "CEN"
        case .attacker: "ATT"
        }
    }

    var symbol: String {
        switch self {
        case .goalkeeper: "hand.raised.fill"
        case .defender: "shield.fill"
        case .midfielder: "arrow.triangle.branch"
        case .attacker: "target"
        }
    }
}

// MARK: - Statistiche

/// Le sei statistiche stampate sulla figurina.
struct CardStats: Codable, Equatable {
    var pac: Int
    var sho: Int
    var pas: Int
    var dri: Int
    var def: Int
    var phy: Int

    enum CodingKeys: String, CodingKey {
        case pac = "PAC", sho = "SHO", pas = "PAS", dri = "DRI", def = "DEF", phy = "PHY"
    }

    /// Ordine di lettura sulla card: due colonne da tre.
    var ordered: [(key: String, value: Int)] {
        [("PAC", pac), ("SHO", sho), ("PAS", pas), ("DRI", dri), ("DEF", def), ("PHY", phy)]
    }

    static let zero = CardStats(pac: 0, sho: 0, pas: 0, dri: 0, def: 0, phy: 0)

    subscript(key: StatKey) -> Int {
        get {
            switch key {
            case .pac: pac
            case .sho: sho
            case .pas: pas
            case .dri: dri
            case .def: def
            case .phy: phy
            }
        }
        set {
            switch key {
            case .pac: pac = newValue
            case .sho: sho = newValue
            case .pas: pas = newValue
            case .dri: dri = newValue
            case .def: def = newValue
            case .phy: phy = newValue
            }
        }
    }

    enum StatKey: String, CaseIterable {
        case pac = "PAC", sho = "SHO", pas = "PAS", dri = "DRI", def = "DEF", phy = "PHY"
    }
}

// MARK: - Rarità

/// Rarità della card. Niente Bronze: la figurina deve essere un premio, non un voto.
enum CardTier: String, Codable, CaseIterable, Identifiable {
    case gold = "Gold"
    case rareGold = "Rare Gold"
    case epic = "Epic"
    case eliteBlue = "Elite Blue"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gold: "Gold"
        case .rareGold: "Rare Gold"
        case .epic: "Epic"
        case .eliteBlue: "Elite Blue"
        }
    }

    var tagline: String {
        switch self {
        case .gold: "Solida. Da titolare fisso."
        case .rareGold: "Roba da prima pagina."
        case .epic: "Di queste ne girano poche."
        case .eliteBlue: "Una delle più rare del torneo."
        }
    }
}

// MARK: - Consenso

/// Traccia del consenso all'invio della foto al servizio di AI generativa.
/// Va scritto insieme al job: senza, la generazione non deve partire.
struct AICardConsent: Codable, Equatable {
    var accepted: Bool
    var acceptedAt: Date
    var version: String
    var provider: String
    var purpose: String

    static let currentVersion = "1.0"
    static let provider = "OpenAI"
    static let purpose = "player-card-generation"

    static func accepted(at date: Date = Date()) -> AICardConsent {
        AICardConsent(
            accepted: true,
            acceptedAt: date,
            version: currentVersion,
            provider: provider,
            purpose: purpose
        )
    }
}

// MARK: - Stato della generazione

enum CardGenerationStatus: String, Codable {
    case none
    case pending
    case processing
    case ready
    case failed

    /// Vero finché il worker non ha finito: la UI mostra la schermata di attesa.
    var isInProgress: Bool { self == .pending || self == .processing }

    /// Vero anche per `failed`: **al giocatore un fallimento non si mostra**.
    ///
    /// Quasi mai è colpa sua — il 2026-09-02 una figurina è morta perché il
    /// disco del computer che genera era pieno — e tutto quello che serve per
    /// rifarla è già sul job: foto, ruolo, risposte, stats. Fargli vedere
    /// "qualcosa non ha funzionato" gli chiede di rifare da capo un lavoro che
    /// non è andato perso, e per un guasto che non poteva evitare.
    ///
    /// Quindi la sua schermata resta "in lavorazione", l'avviso lo riceviamo
    /// noi (`onFigurinaRichiestaAvvisaAdmin`) e la rimettiamo in coda con
    /// `scripts/rimetti-in-coda-figurina.mjs`. Serve però che qualcuno guardi
    /// davvero quell'avviso: senza, la schermata aspetta per sempre.
    var pareInLavorazione: Bool { isInProgress || self == .failed }
}

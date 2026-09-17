import Foundation
import FirebaseFirestore

// MARK: - Job
/// Il documento in `playerCardJobs`. È il contratto fra app e worker: l'app
/// scrive i dati e legge lo stato, non sa nulla di come l'immagine venga creata.
struct PlayerCardJob: Codable, Identifiable {
    var jobId: String
    var playerId: String
    var tournamentId: String
    var teamId: String?

    var status: CardGenerationStatus

    var playerName: String
    var teamName: String?
    var position: CardPosition
    var jerseyNumber: Int?

    var overall: Int
    var stats: CardStats
    var cardTier: CardTier
    /// Le risposte date. Il sito e le vecchie build dell'app hanno scritto qui
    /// forme diverse (una stringa sola contro una lista), quindi si accettano
    /// entrambe: un campo di sola documentazione non deve poter impedire a
    /// qualcuno di vedere la propria figurina.
    var answers: [String: [String]]?

    var playerPhotoURL: String
    var teamLogoURL: String?
    /// Logo del torneo: sulla card fa da badge di competizione, in alto a
    /// destra. È l'unico posto dove il torneo compare sulla figurina.
    var tournamentLogoURL: String?

    var outputImageURL: String?
    /// Miniatura leggera della card: la figurina intera pesa qualche MB e per
    /// un riquadro d'anteprima non finiva mai di caricare.
    var outputThumbURL: String?
    var outputStoragePath: String?
    /// Quante generazioni sono state consumate: 1 dopo la prima, 2 dopo il
    /// secondo tentativo. Oltre non si va.
    var generationsUsed: Int?
    /// La figurina precedente, tenuta da parte quando si rifà: con due
    /// tentativi al massimo, un solo campo basta a non perdere la prima.
    var previousImageURL: String?
    var previousThumbURL: String?

    var aiCardConsent: AICardConsent?

    var attempt: Int?
    var createdAt: Timestamp?
    var startedAt: Timestamp?
    var completedAt: Timestamp?
    var error: String?

    var id: String { jobId }

    // L'init membro a membro va riscritto: dichiarando `init(from:)` Swift
    // smette di sintetizzarlo.
    init(
        jobId: String, playerId: String, tournamentId: String, teamId: String? = nil,
        status: CardGenerationStatus, playerName: String, teamName: String? = nil,
        position: CardPosition, jerseyNumber: Int? = nil,
        overall: Int, stats: CardStats, cardTier: CardTier, answers: [String: [String]]? = nil,
        playerPhotoURL: String, teamLogoURL: String? = nil, tournamentLogoURL: String? = nil,
        outputImageURL: String? = nil, outputThumbURL: String? = nil, outputStoragePath: String? = nil,
        generationsUsed: Int? = nil, previousImageURL: String? = nil, previousThumbURL: String? = nil,
        aiCardConsent: AICardConsent? = nil, attempt: Int? = nil,
        createdAt: Timestamp? = nil, startedAt: Timestamp? = nil,
        completedAt: Timestamp? = nil, error: String? = nil
    ) {
        self.jobId = jobId; self.playerId = playerId; self.tournamentId = tournamentId
        self.teamId = teamId; self.status = status; self.playerName = playerName
        self.teamName = teamName; self.position = position; self.jerseyNumber = jerseyNumber
        self.overall = overall; self.stats = stats; self.cardTier = cardTier
        self.answers = answers; self.playerPhotoURL = playerPhotoURL
        self.teamLogoURL = teamLogoURL; self.tournamentLogoURL = tournamentLogoURL
        self.outputImageURL = outputImageURL; self.outputThumbURL = outputThumbURL
        self.outputStoragePath = outputStoragePath
        self.generationsUsed = generationsUsed; self.previousImageURL = previousImageURL
        self.previousThumbURL = previousThumbURL
        self.aiCardConsent = aiCardConsent; self.attempt = attempt
        self.createdAt = createdAt; self.startedAt = startedAt
        self.completedAt = completedAt; self.error = error
    }

    // Scritto a mano: avendo un `init(from:)` custom, Swift non sintetizza piu'
    // le chiavi e il decoder tollerante non compilerebbe.
    enum CodingKeys: String, CodingKey {
        case jobId, playerId, tournamentId, teamId, status
        case playerName, teamName, position, jerseyNumber
        case overall, stats, cardTier, answers
        case playerPhotoURL, teamLogoURL, tournamentLogoURL
        case outputImageURL, outputThumbURL, outputStoragePath
        case generationsUsed, previousImageURL, previousThumbURL
        case aiCardConsent, attempt, createdAt, startedAt, completedAt, error
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try c.decode(String.self, forKey: .jobId)
        playerId = try c.decode(String.self, forKey: .playerId)
        tournamentId = try c.decode(String.self, forKey: .tournamentId)
        teamId = try c.decodeIfPresent(String.self, forKey: .teamId)
        status = (try? c.decode(CardGenerationStatus.self, forKey: .status)) ?? .pending
        playerName = (try? c.decode(String.self, forKey: .playerName)) ?? ""
        teamName = try? c.decodeIfPresent(String.self, forKey: .teamName)
        position = (try? c.decode(CardPosition.self, forKey: .position)) ?? .attacker
        jerseyNumber = try? c.decodeIfPresent(Int.self, forKey: .jerseyNumber)
        overall = (try? c.decode(Int.self, forKey: .overall)) ?? 0
        stats = (try? c.decode(CardStats.self, forKey: .stats)) ?? .zero
        cardTier = (try? c.decode(CardTier.self, forKey: .cardTier)) ?? .gold
        answers = Self.decodeAnswers(from: c)
        playerPhotoURL = (try? c.decode(String.self, forKey: .playerPhotoURL)) ?? ""
        teamLogoURL = try? c.decodeIfPresent(String.self, forKey: .teamLogoURL)
        tournamentLogoURL = try? c.decodeIfPresent(String.self, forKey: .tournamentLogoURL)
        outputImageURL = try? c.decodeIfPresent(String.self, forKey: .outputImageURL)
        outputThumbURL = try? c.decodeIfPresent(String.self, forKey: .outputThumbURL)
        outputStoragePath = try? c.decodeIfPresent(String.self, forKey: .outputStoragePath)
        generationsUsed = try? c.decodeIfPresent(Int.self, forKey: .generationsUsed)
        previousImageURL = try? c.decodeIfPresent(String.self, forKey: .previousImageURL)
        previousThumbURL = try? c.decodeIfPresent(String.self, forKey: .previousThumbURL)
        aiCardConsent = try? c.decodeIfPresent(AICardConsent.self, forKey: .aiCardConsent)
        attempt = try? c.decodeIfPresent(Int.self, forKey: .attempt)
        createdAt = try? c.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        startedAt = try? c.decodeIfPresent(Timestamp.self, forKey: .startedAt)
        completedAt = try? c.decodeIfPresent(Timestamp.self, forKey: .completedAt)
        error = try? c.decodeIfPresent(String.self, forKey: .error)
    }

    /// Accetta sia `{"q": "opt"}` (vecchie build) sia `{"q": ["a","b"]}` (attuale).
    private static func decodeAnswers(from c: KeyedDecodingContainer<CodingKeys>) -> [String: [String]]? {
        if let liste = try? c.decodeIfPresent([String: [String]].self, forKey: .answers) { return liste }
        if let singole = try? c.decodeIfPresent([String: String].self, forKey: .answers) {
            return singole.mapValues { [$0] }
        }
        return nil
    }

    /// L'id è derivato dal giocatore, non casuale: è così che il limite di una
    /// sola figurina diventa un vincolo del database invece di una promessa
    /// dell'interfaccia. Gemello worker: `cardJobId()` in card-worker/src/createJob.js.
    static func documentId(tournamentId: String, playerId: String) -> String {
        "card_\(tournamentId)_\(playerId)"
    }

    /// Due tentativi, non uno.
    ///
    /// Con un tentativo solo chi sbagliava la foto restava con quella per
    /// sempre, e la schermata di conferma diventava una minaccia invece di un
    /// avviso. Due lasciano spazio a un ripensamento senza trasformare la
    /// figurina in una cosa che si rifà finché non piace.
    static let maxGenerations = 2

    var usedGenerations: Int { generationsUsed ?? 1 }

    /// Un fallimento non è colpa del giocatore: si può riprovare senza pagarlo.
    var canRetry: Bool {
        switch status {
        case .failed: true
        case .ready: usedGenerations < Self.maxGenerations
        default: false
        }
    }

    /// Vero solo quando il nuovo tentativo consuma davvero una generazione.
    var retryCostsGeneration: Bool { status == .ready }
}

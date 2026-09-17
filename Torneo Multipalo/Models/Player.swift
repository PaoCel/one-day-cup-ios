import Foundation
import FirebaseFirestore

struct Player: Codable, Identifiable {
    @DocumentID var id: String?
    var playerId: String?
    var nomeCompleto: String
    var numeroMaglia: Int?
    var ruoloSquadra: String?
    var teamId: String?
    var pictureURL: String?
    // Foto scontornata (sfondo rimosso) generata dal worker; l'app la preferisce
    // all'originale quando è fresca. Source = da quale originale è stata derivata,
    // per accorgersi quando la foto cambia e il cutout va rifatto. Gemello PWA:
    // dbSchema.PLAYER.PICTURE_URL_NOBG + resolvePlayerPhoto (tm-helpers.js).
    var pictureURLNoBg: String?
    var pictureURLNoBgSourceUrl: String?
    var playerAuthUid: String?
    var claimedBy: String?
    var userId: String?
    var positionPrimary: String?
    var positionSecondary: String?
    var piedeDominante: String?
    var tesseramentoStatus: String?
    var stats: PlayerStats?
    /// Figurine pronte, indicizzate per torneo ("mormon", "multipalo"). Le
    /// scrive la Cloud Function su entrambe le metà del database, quindi
    /// arrivano sia dal percorso v1 (`giocatori`) che dalla proiezione v2.
    var figurine: [String: Figurina]?
    var createdAt: Timestamp?
    var updatedAt: Timestamp?

    struct PlayerStats: Codable {
        var gol: Int?
        var assist: Int?
        var ammonizioni: Int?
        var espulsioni: Int?
        var presenze: Int?
        var minutiGiocati: Int?

        enum CodingKeys: String, CodingKey {
            case gol, assist, ammonizioni, espulsioni, presenze, minutiGiocati
            case goals, assists, yellowCards, redCards, matches, minutesPlayed
        }

        init(gol: Int? = nil, assist: Int? = nil, ammonizioni: Int? = nil,
             espulsioni: Int? = nil, presenze: Int? = nil, minutiGiocati: Int? = nil) {
            self.gol = gol
            self.assist = assist
            self.ammonizioni = ammonizioni
            self.espulsioni = espulsioni
            self.presenze = presenze
            self.minutiGiocati = minutiGiocati
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            gol = Self.decodeInt(in: c, keys: [.gol, .goals])
            assist = Self.decodeInt(in: c, keys: [.assist, .assists])
            ammonizioni = Self.decodeInt(in: c, keys: [.ammonizioni, .yellowCards])
            espulsioni = Self.decodeInt(in: c, keys: [.espulsioni, .redCards])
            presenze = Self.decodeInt(in: c, keys: [.presenze, .matches])
            minutiGiocati = Self.decodeInt(in: c, keys: [.minutiGiocati, .minutesPlayed])
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encodeIfPresent(gol, forKey: .gol)
            try c.encodeIfPresent(assist, forKey: .assist)
            try c.encodeIfPresent(ammonizioni, forKey: .ammonizioni)
            try c.encodeIfPresent(espulsioni, forKey: .espulsioni)
            try c.encodeIfPresent(presenze, forKey: .presenze)
            try c.encodeIfPresent(minutiGiocati, forKey: .minutiGiocati)
        }

        private static func decodeInt<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> Int? {
            for key in keys {
                do {
                    if let value = try container.decodeIfPresent(Int.self, forKey: key) {
                        return value
                    }
                } catch {}
                do {
                    if let stringValue = try container.decodeIfPresent(String.self, forKey: key),
                       let value = Int(stringValue) {
                        return value
                    }
                } catch {
                    continue
                }
            }
            return nil
        }
    }

    var isFreeAgent: Bool {
        guard let teamId else { return true }
        return teamId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var firestoreIdentifier: String? {
        [id, playerId]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    var identityUid: String? {
        for candidate in [claimedBy, userId, playerAuthUid] {
            if let candidate,
               !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return candidate
            }
        }
        return nil
    }

    var isClaimed: Bool { identityUid != nil }

    /// URL della foto da MOSTRARE: scontornata se disponibile e "fresca" (cioè
    /// derivata dalla foto corrente), altrimenti l'originale. Gemello del
    /// resolvePlayerPhoto della PWA: il passaggio all'originale quando il cutout
    /// è stantìo evita di mostrare lo scontorno della foto sbagliata dopo un
    /// cambio foto, in attesa che il worker lo rigeneri.
    var displayPhotoURL: String? {
        let original = pictureURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutout = pictureURLNoBg?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let cutout, !cutout.isEmpty {
            let src = pictureURLNoBgSourceUrl?.trimmingCharacters(in: .whitespacesAndNewlines)
            if original == nil || original!.isEmpty || src == nil || src!.isEmpty || src == original {
                return cutout
            }
        }
        return (original?.isEmpty == false) ? original : nil
    }

    // MARK: - Custom Decoding (resiliente ai diversi nomi campo usati dalla webapp)

    enum CodingKeys: String, CodingKey {
        case nomeCompleto, numeroMaglia, ruoloSquadra, teamId, pictureURL
        case pictureURLNoBg, pictureURLNoBgSourceUrl
        case playerAuthUid, claimedBy, positionPrimary, positionSecondary
        case piedeDominante, tesseramentoStatus, stats, createdAt, updatedAt
        case playerId, figurine
        // Fallback field names utilizzati dalla webapp
        case nome, playerName, fullName
        case userId, position, preferredFoot, lastUpdated, fotoUrl, photoURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // nomeCompleto: prova "nomeCompleto", poi fallback a "nome", "playerName", "fullName"
        if let name = try? c.decodeIfPresent(String.self, forKey: .nomeCompleto), !name.isEmpty {
            nomeCompleto = name
        } else if let name = try? c.decodeIfPresent(String.self, forKey: .nome), !name.isEmpty {
            nomeCompleto = name
        } else if let name = try? c.decodeIfPresent(String.self, forKey: .playerName), !name.isEmpty {
            nomeCompleto = name
        } else if let name = try? c.decodeIfPresent(String.self, forKey: .fullName), !name.isEmpty {
            nomeCompleto = name
        } else {
            nomeCompleto = "Giocatore"
        }

        playerId = Self.decodeFirstNonEmptyString(in: c, keys: [.playerId])

        // numeroMaglia: può essere Int o String in Firestore
        if let num = try? c.decodeIfPresent(Int.self, forKey: .numeroMaglia) {
            numeroMaglia = num
        } else if let numStr = try? c.decodeIfPresent(String.self, forKey: .numeroMaglia),
                  let num = Int(numStr) {
            numeroMaglia = num
        } else {
            numeroMaglia = nil
        }

        ruoloSquadra = try? c.decodeIfPresent(String.self, forKey: .ruoloSquadra)
        teamId = Self.decodeFirstNonEmptyString(in: c, keys: [.teamId])
        pictureURL = Self.decodeFirstNonEmptyString(in: c, keys: [.pictureURL, .fotoUrl, .photoURL])
        pictureURLNoBg = Self.decodeFirstNonEmptyString(in: c, keys: [.pictureURLNoBg])
        pictureURLNoBgSourceUrl = Self.decodeFirstNonEmptyString(in: c, keys: [.pictureURLNoBgSourceUrl])
        claimedBy = Self.decodeFirstNonEmptyString(in: c, keys: [.claimedBy])
        userId = Self.decodeFirstNonEmptyString(in: c, keys: [.userId])
        playerAuthUid = Self.decodeFirstNonEmptyString(in: c, keys: [.playerAuthUid, .userId, .claimedBy])
        positionPrimary = Self.normalizedPosition(Self.decodeFirstNonEmptyString(in: c, keys: [.positionPrimary, .position]))
        positionSecondary = Self.normalizedPosition(try? c.decodeIfPresent(String.self, forKey: .positionSecondary))
        piedeDominante = Self.normalizedFoot(Self.decodeFirstNonEmptyString(in: c, keys: [.piedeDominante, .preferredFoot]))
        tesseramentoStatus = Self.decodeFirstNonEmptyString(in: c, keys: [.tesseramentoStatus]) ?? (isFreeAgent ? "libero" : "tesserato")
        stats = try? c.decodeIfPresent(PlayerStats.self, forKey: .stats)
        // `try?` sull'intera mappa: una figurina malformata non deve far
        // sparire il giocatore dalle liste.
        figurine = try? c.decodeIfPresent([String: Figurina].self, forKey: .figurine)
        createdAt = try? c.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        updatedAt = (try? c.decodeIfPresent(Timestamp.self, forKey: .updatedAt))
            ?? (try? c.decodeIfPresent(Timestamp.self, forKey: .lastUpdated))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nomeCompleto, forKey: .nomeCompleto)
        try c.encodeIfPresent(numeroMaglia, forKey: .numeroMaglia)
        try c.encodeIfPresent(ruoloSquadra, forKey: .ruoloSquadra)
        try c.encodeIfPresent(playerId, forKey: .playerId)
        try c.encodeIfPresent(teamId, forKey: .teamId)
        try c.encodeIfPresent(pictureURL, forKey: .pictureURL)
        try c.encodeIfPresent(pictureURLNoBg, forKey: .pictureURLNoBg)
        try c.encodeIfPresent(pictureURLNoBgSourceUrl, forKey: .pictureURLNoBgSourceUrl)
        try c.encodeIfPresent(playerAuthUid, forKey: .playerAuthUid)
        try c.encodeIfPresent(claimedBy, forKey: .claimedBy)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(positionPrimary, forKey: .positionPrimary)
        try c.encodeIfPresent(positionSecondary, forKey: .positionSecondary)
        try c.encodeIfPresent(piedeDominante, forKey: .piedeDominante)
        try c.encodeIfPresent(tesseramentoStatus, forKey: .tesseramentoStatus)
        try c.encodeIfPresent(stats, forKey: .stats)
        try c.encodeIfPresent(figurine, forKey: .figurine)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    // Init manuale per uso nel codice
    init(id: String? = nil, nomeCompleto: String, numeroMaglia: Int? = nil,
         ruoloSquadra: String? = nil, teamId: String? = nil, pictureURL: String? = nil,
         pictureURLNoBg: String? = nil, pictureURLNoBgSourceUrl: String? = nil,
         playerAuthUid: String? = nil, claimedBy: String? = nil, userId: String? = nil,
         positionPrimary: String? = nil,
         positionSecondary: String? = nil, piedeDominante: String? = nil,
         playerId: String? = nil,
         tesseramentoStatus: String? = nil, stats: PlayerStats? = nil,
         createdAt: Timestamp? = nil, updatedAt: Timestamp? = nil) {
        self.id = id
        self.playerId = playerId
        self.nomeCompleto = nomeCompleto
        self.numeroMaglia = numeroMaglia
        self.ruoloSquadra = ruoloSquadra
        self.teamId = teamId
        self.pictureURL = pictureURL
        self.pictureURLNoBg = pictureURLNoBg
        self.pictureURLNoBgSourceUrl = pictureURLNoBgSourceUrl
        self.playerAuthUid = playerAuthUid
        self.claimedBy = claimedBy
        self.userId = userId
        self.positionPrimary = positionPrimary
        self.positionSecondary = positionSecondary
        self.piedeDominante = piedeDominante
        self.tesseramentoStatus = tesseramentoStatus
        self.stats = stats
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private static func decodeFirstNonEmptyString<K: CodingKey>(in container: KeyedDecodingContainer<K>, keys: [K]) -> String? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(String.self, forKey: key),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func normalizedPosition(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "portiere", "goalkeeper":
            return "Portiere"
        case "difensore", "defender":
            return "Difensore"
        case "centrocampista", "midfielder":
            return "Centrocampista"
        case "attaccante", "striker", "forward":
            return "Attaccante"
        case "ala", "winger":
            return "Ala"
        default:
            return rawValue.capitalized
        }
    }

    private static func normalizedFoot(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "right", "destro":
            return "Destro"
        case "left", "sinistro":
            return "Sinistro"
        case "both", "ambidestro":
            return "Ambidestro"
        default:
            return rawValue.capitalized
        }
    }
}

extension Player {
    var stableRosterKey: String {
        let candidateIds = [firestoreIdentifier, identityUid, playerAuthUid, claimedBy, userId]
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        if let firstIdentifier = candidateIds.first {
            return firstIdentifier
        }

        let normalizedName = Self.normalizedLookupName(from: nomeCompleto) ?? nomeCompleto.lowercased()
        return "\(normalizedName)|\(teamId ?? "svincolato")|\(numeroMaglia ?? -1)"
    }

    func matches(event: MatchEvent) -> Bool {
        let candidateIds = [firestoreIdentifier, claimedBy, userId, playerAuthUid]
            .compactMap { value in
                value?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        if let eventPlayerId = event.giocatoreId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !eventPlayerId.isEmpty,
           candidateIds.contains(eventPlayerId) {
            return true
        }

        guard let playerName = Self.normalizedLookupName(from: nomeCompleto),
              let eventName = Self.normalizedLookupName(from: event.giocatoreNome) else {
            return false
        }
        return playerName == eventName
    }

    static func normalizedLookupName(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let collapsedWhitespace = trimmed
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return collapsedWhitespace.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "it_IT")
        )
    }
}

extension Player: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> Player {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        if copy.playerId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.playerId = normalizedDocumentID
        }
        return copy
    }
}

// MARK: - Carica in squadra

/// Capitano e vice. Nella v1 vivono in `ruoloSquadra` come testo
/// ("capitano" | "vice"): è il campo che la PWA scrive dal foglio Rosa (via
/// ponte) ed è da lì che lo snapshot dell'edizione deriva `isCapitano` e
/// `isVice`. Gemelli: `functions/index.js` (buildPlayerSnapshot),
/// `functions-v2/ponte.js` (giocatoriDallaRosa).
enum CaricaSquadra: String, CaseIterable {
    case capitano, vice

    var sigla: String { self == .capitano ? "C" : "VC" }
    var label: String { self == .capitano ? "Capitano" : "Vice capitano" }
    var symbol: String { self == .capitano ? "c.circle.fill" : "v.circle.fill" }
}

extension Player {
    /// `ruoloSquadra` ha due vite: carica (qui) o ruolo in campo scritto a mano
    /// dal pannello admin. Si legge come carica solo se è esattamente una.
    var carica: CaricaSquadra? {
        guard let ruoloSquadra else { return nil }
        return CaricaSquadra(rawValue: ruoloSquadra.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

import Foundation
import FirebaseFirestore

struct Team: Codable, Identifiable {
    @DocumentID var id: String?
    var nomeSquadra: String
    var email: String
    var ownerUid: String
    var rappresentante: Rappresentante
    var colori: TeamColors
    var logoSquadra: String?
    var primaEdizione: Int?
    var ultimeEdizioni: [Int]?
    var playersCount: Int?
    var createdAt: Timestamp?
    var updatedAt: Timestamp?

    struct Rappresentante: Codable {
        var nome: String
        var telefono: String

        init(nome: String = "", telefono: String = "") {
            self.nome = nome
            self.telefono = telefono
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nome = (try? c.decodeIfPresent(String.self, forKey: .nome)) ?? ""
            telefono = (try? c.decodeIfPresent(String.self, forKey: .telefono)) ?? ""
        }
    }

    struct TeamColors: Codable {
        var principale: String
        var secondario: String

        init(principale: String = "#1a73e8", secondario: String = "#ffffff") {
            self.principale = principale
            self.secondario = secondario
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            principale = (try? c.decodeIfPresent(String.self, forKey: .principale)) ?? "#1a73e8"
            secondario = (try? c.decodeIfPresent(String.self, forKey: .secondario)) ?? "#ffffff"
        }
    }

    var safePlayersCount: Int { playersCount ?? 0 }

    func hasEdition(_ edition: Int) -> Bool {
        if primaEdizione == edition { return true }
        return (ultimeEdizioni ?? []).contains(edition)
    }

    // MARK: - Custom Decoding (resiliente ai nomi campo diversi)

    enum CodingKeys: String, CodingKey {
        case nomeSquadra, email, ownerUid, rappresentante, colori
        case logoSquadra, primaEdizione, ultimeEdizioni, playersCount
        case createdAt, updatedAt
        // Fallback
        case nome, name
        case logo, fotoSquadra, dataCreazione, lastUpdateAt, legacyRoster
    }

    enum LegacyRosterKeys: String, CodingKey {
        case giocatori
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // nomeSquadra: prova "nomeSquadra", poi "nome", poi "name"
        if let n = try? c.decodeIfPresent(String.self, forKey: .nomeSquadra), !n.isEmpty {
            nomeSquadra = n
        } else if let n = try? c.decodeIfPresent(String.self, forKey: .nome), !n.isEmpty {
            nomeSquadra = n
        } else if let n = try? c.decodeIfPresent(String.self, forKey: .name), !n.isEmpty {
            nomeSquadra = n
        } else {
            nomeSquadra = "Squadra"
        }

        email = (try? c.decodeIfPresent(String.self, forKey: .email)) ?? ""
        ownerUid = (try? c.decodeIfPresent(String.self, forKey: .ownerUid)) ?? ""
        rappresentante = (try? c.decodeIfPresent(Rappresentante.self, forKey: .rappresentante)) ?? Rappresentante()
        colori = (try? c.decodeIfPresent(TeamColors.self, forKey: .colori)) ?? TeamColors()
        logoSquadra = Self.decodeFirstNonEmptyString(in: c, keys: [.logoSquadra, .logo, .fotoSquadra])
        primaEdizione = try? c.decodeIfPresent(Int.self, forKey: .primaEdizione)
        ultimeEdizioni = try? c.decodeIfPresent([Int].self, forKey: .ultimeEdizioni)
        if let value = try? c.decodeIfPresent(Int.self, forKey: .playersCount) {
            playersCount = value
        } else if let legacy = try? c.nestedContainer(keyedBy: LegacyRosterKeys.self, forKey: .legacyRoster),
                  let legacyPlayers = try? legacy.decodeIfPresent([String].self, forKey: .giocatori) {
            playersCount = legacyPlayers.count
        } else {
            playersCount = nil
        }
        createdAt = (try? c.decodeIfPresent(Timestamp.self, forKey: .createdAt))
            ?? (try? c.decodeIfPresent(Timestamp.self, forKey: .dataCreazione))
        updatedAt = (try? c.decodeIfPresent(Timestamp.self, forKey: .updatedAt))
            ?? (try? c.decodeIfPresent(Timestamp.self, forKey: .lastUpdateAt))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nomeSquadra, forKey: .nomeSquadra)
        try c.encode(email, forKey: .email)
        try c.encode(ownerUid, forKey: .ownerUid)
        try c.encode(rappresentante, forKey: .rappresentante)
        try c.encode(colori, forKey: .colori)
        try c.encodeIfPresent(logoSquadra, forKey: .logoSquadra)
        try c.encodeIfPresent(primaEdizione, forKey: .primaEdizione)
        try c.encodeIfPresent(ultimeEdizioni, forKey: .ultimeEdizioni)
        try c.encodeIfPresent(playersCount, forKey: .playersCount)
        try c.encodeIfPresent(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    init(id: String? = nil, nomeSquadra: String, email: String = "", ownerUid: String = "",
         rappresentante: Rappresentante = Rappresentante(), colori: TeamColors = TeamColors(),
         logoSquadra: String? = nil, primaEdizione: Int? = nil, ultimeEdizioni: [Int]? = nil,
         playersCount: Int? = nil, createdAt: Timestamp? = nil, updatedAt: Timestamp? = nil) {
        self.id = id
        self.nomeSquadra = nomeSquadra
        self.email = email
        self.ownerUid = ownerUid
        self.rappresentante = rappresentante
        self.colori = colori
        self.logoSquadra = logoSquadra
        self.primaEdizione = primaEdizione
        self.ultimeEdizioni = ultimeEdizioni
        self.playersCount = playersCount
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
}

struct EditionTeam: Identifiable {
    let edition: Int
    let team: Team?
    let participation: EditionParticipation?
    let fallbackParticipation: EditionParticipation?
    let preferLiveTeamData: Bool
    /// Edizioni giocate **in questo torneo**, calcolate da partecipazioni e
    /// partite già filtrate per tournamentId. Serve perché `ultimeEdizioni`
    /// sul doc squadra è globale e mescola tornei diversi: Real Capital ha
    /// `[2025, 2026, 1]`, cioè due edizioni Multipalo e la prima Mormon.
    let tournamentEditions: [Int]

    init(
        edition: Int,
        team: Team? = nil,
        participation: EditionParticipation? = nil,
        fallbackParticipation: EditionParticipation? = nil,
        preferLiveTeamData: Bool = false,
        tournamentEditions: [Int] = []
    ) {
        self.edition = edition
        self.team = team
        self.participation = participation
        self.fallbackParticipation = fallbackParticipation
        self.preferLiveTeamData = preferLiveTeamData
        self.tournamentEditions = tournamentEditions
    }

    var id: String {
        if !teamId.isEmpty {
            return "\(teamId)_\(edition)"
        }
        return "\(displayName)_\(edition)"
    }

    var teamId: String {
        participation?.squadraId ?? team?.id ?? ""
    }

    var displayName: String {
        preferredText(
            live: team?.nomeSquadra,
            snapshot: participation?.nomeSquadra,
            fallback: fallbackParticipation?.nomeSquadra
        ) ?? "Squadra"
    }

    var logoURL: String? {
        preferredText(
            live: team?.logoSquadra,
            snapshot: participation?.logoSquadra,
            fallback: fallbackParticipation?.logoSquadra
        )
    }

    var colors: Team.TeamColors {
        if preferLiveTeamData {
            return team?.colori
                ?? participation?.colori
                ?? fallbackParticipation?.colori
                ?? Team.TeamColors()
        }

        return participation?.colori
            ?? team?.colori
            ?? fallbackParticipation?.colori
            ?? Team.TeamColors()
    }

    var representative: Team.Rappresentante {
        if preferLiveTeamData {
            return team?.rappresentante
                ?? participation?.rappresentante
                ?? fallbackParticipation?.rappresentante
                ?? Team.Rappresentante()
        }

        return participation?.rappresentante
            ?? team?.rappresentante
            ?? fallbackParticipation?.rappresentante
            ?? Team.Rappresentante()
    }

    var email: String {
        preferredText(
            live: team?.email,
            snapshot: participation?.email,
            fallback: fallbackParticipation?.email
        ) ?? ""
    }

    var firstEdition: Int? {
        if let primaEdizione = team?.primaEdizione {
            return primaEdizione
        }
        let editions = team?.ultimeEdizioni?.sorted() ?? []
        if let first = editions.first {
            return first
        }
        if let fallbackEdition = fallbackParticipation?.edizione {
            return fallbackEdition
        }
        return participation?.edizione
    }

    var playedEditions: [Int] {
        // Quando le edizioni del torneo sono note si usano solo quelle: prima
        // il conteggio partiva da `ultimeEdizioni`, che è globale, e nella
        // lista squadre della Mormon compariva "7 edizioni" sommando quelle
        // del Multipalo.
        if !tournamentEditions.isEmpty {
            var editions = Set(tournamentEditions)
            editions.insert(edition)
            return editions.sorted()
        }
        var editions = Set(team?.ultimeEdizioni ?? [])
        if let primaEdizione = team?.primaEdizione {
            editions.insert(primaEdizione)
        }
        if let participationEdition = participation?.edizione {
            editions.insert(participationEdition)
        }
        if let fallbackEdition = fallbackParticipation?.edizione {
            editions.insert(fallbackEdition)
        }
        editions.insert(edition)
        return editions.sorted()
    }

    var safePlayersCount: Int {
        if preferLiveTeamData, let team, team.safePlayersCount > 0 {
            return team.safePlayersCount
        }
        if let participation, participation.safePlayersCount > 0 {
            return participation.safePlayersCount
        }
        if let team, team.safePlayersCount > 0 {
            return team.safePlayersCount
        }
        if let fallbackParticipation, fallbackParticipation.safePlayersCount > 0 {
            return fallbackParticipation.safePlayersCount
        }
        return 0
    }

    var rosterSnapshots: [EditionParticipation.PlayerSnapshot] {
        if let participation, !participation.playerSnapshots.isEmpty {
            return participation.playerSnapshots
        }
        if let fallbackParticipation, !fallbackParticipation.playerSnapshots.isEmpty {
            return fallbackParticipation.playerSnapshots
        }
        return []
    }

    var usesArchivedRoster: Bool {
        !rosterSnapshots.isEmpty
    }

    var hasCurrentTeamDocument: Bool {
        team != nil
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private func preferredText(live: String?, snapshot: String?, fallback: String?) -> String? {
        if preferLiveTeamData {
            return firstNonEmpty(live, snapshot, fallback)
        }
        return firstNonEmpty(snapshot, live, fallback)
    }
}

extension Team: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> Team {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        return copy
    }
}

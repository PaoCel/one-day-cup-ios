import Foundation
import FirebaseFirestore

struct EditionParticipation: Decodable, Identifiable {
    @DocumentID var id: String?
    var squadraId: String
    var nomeSquadra: String
    var edizione: Int
    var logoSquadra: String?
    var email: String?
    var ownerUid: String?
    var rappresentante: Team.Rappresentante?
    var colori: Team.TeamColors?
    var playersCount: Int?
    /// Piazzamento finale dell'edizione (1/2/3...). Lo scrivono gli import
    /// storici e gli script podio; serve ai "Premi" della scheda giocatore.
    var finalPosition: Int?
    var dataIscrizione: Timestamp?
    var giocatoriDettagliati: [PlayerSnapshot]?
    var legacyPlayerNames: [String]?
    var legacyPlayerPhotoURLs: [String?]?
    var legacyPlayerNumbers: [Int?]?
    var legacyPlayerCaptainFlags: [Bool?]?
    var legacyPlayerRoles: [String?]?
    var tournamentId: String?
    var group: String?

    struct PlayerSnapshot: Decodable {
        var giocatoreId: String?
        var nome: String?
        var numero: Int?
        var ruolo: String?
        var pictureURL: String?
        var isCapitano: Bool?
        var isVice: Bool?

        var carica: CaricaSquadra? {
            if isCapitano == true { return .capitano }
            if isVice == true { return .vice }
            return nil
        }

        init(giocatoreId: String? = nil, nome: String? = nil, numero: Int? = nil,
             ruolo: String? = nil, pictureURL: String? = nil, isCapitano: Bool? = nil, isVice: Bool? = nil) {
            self.giocatoreId = giocatoreId
            self.nome = nome
            self.numero = numero
            self.ruolo = ruolo
            self.pictureURL = pictureURL
            self.isCapitano = isCapitano
            self.isVice = isVice
        }

        enum CodingKeys: String, CodingKey {
            case giocatoreId, nome, numero, ruolo, pictureURL, isCapitano, isVice
            case nomeCompleto, numeroMaglia, fotoUrl
        }

        init(from decoder: Decoder) throws {
            if let singleValue = try? decoder.singleValueContainer(),
               let rawName = try? singleValue.decode(String.self) {
                giocatoreId = nil
                nome = Self.normalizedNonEmptyString(rawName)
                numero = nil
                ruolo = nil
                pictureURL = nil
                isCapitano = nil
                isVice = nil
                return
            }

            let c = try decoder.container(keyedBy: CodingKeys.self)
            giocatoreId = Self.normalizedNonEmptyString(try? c.decodeIfPresent(String.self, forKey: .giocatoreId))
            nome = Self.normalizedNonEmptyString(
                (try? c.decodeIfPresent(String.self, forKey: .nome))
                ?? (try? c.decodeIfPresent(String.self, forKey: .nomeCompleto))
            )
            if let value = try? c.decodeIfPresent(Int.self, forKey: .numero) {
                numero = value
            } else if let value = try? c.decodeIfPresent(Int.self, forKey: .numeroMaglia) {
                numero = value
            } else {
                do {
                    if let stringValue = try c.decodeIfPresent(String.self, forKey: .numeroMaglia),
                       let number = Int(stringValue) {
                        numero = number
                    } else {
                        numero = nil
                    }
                } catch {
                    numero = nil
                }
            }
            ruolo = Self.normalizedNonEmptyString(try? c.decodeIfPresent(String.self, forKey: .ruolo))
            pictureURL = Self.normalizedNonEmptyString(
                (try? c.decodeIfPresent(String.self, forKey: .pictureURL))
                ?? (try? c.decodeIfPresent(String.self, forKey: .fotoUrl))
            )
            isCapitano = try? c.decodeIfPresent(Bool.self, forKey: .isCapitano)
            isVice = try? c.decodeIfPresent(Bool.self, forKey: .isVice)
        }

        private static func normalizedNonEmptyString(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    enum CodingKeys: String, CodingKey {
        case squadraId, nomeSquadra, edizione, logoSquadra, playersCount, dataIscrizione, giocatoriDettagliati
        case finalPosition
        case id, logo, fotoSquadra, giocatori, email, ownerUid, rappresentante, colori
        case fotoGiocatori, numeriMaglia, capitani, ruoli, tournamentId, group, girone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        squadraId = Self.decodeFirstNonEmptyString(in: c, keys: [.squadraId, .id]) ?? ""
        nomeSquadra = Self.decodeFirstNonEmptyString(in: c, keys: [.nomeSquadra]) ?? "Squadra"
        edizione = Self.decodeInt(in: c, keys: [.edizione]) ?? 2026
        logoSquadra = Self.decodeFirstNonEmptyString(in: c, keys: [.logoSquadra, .logo, .fotoSquadra])
        email = Self.decodeFirstNonEmptyString(in: c, keys: [.email])
        ownerUid = Self.decodeFirstNonEmptyString(in: c, keys: [.ownerUid])
        rappresentante = try? c.decodeIfPresent(Team.Rappresentante.self, forKey: .rappresentante)
        colori = try? c.decodeIfPresent(Team.TeamColors.self, forKey: .colori)
        playersCount = Self.decodeInt(in: c, keys: [.playersCount])
        finalPosition = Self.decodeInt(in: c, keys: [.finalPosition])
        dataIscrizione = Self.decodeTimestamp(in: c, keys: [.dataIscrizione])
        let explicitSnapshots = try? c.decodeIfPresent([PlayerSnapshot].self, forKey: .giocatoriDettagliati)
        let legacySnapshots = try? c.decodeIfPresent([PlayerSnapshot].self, forKey: .giocatori)
        giocatoriDettagliati = (explicitSnapshots?.isEmpty == false ? explicitSnapshots : legacySnapshots)
        legacyPlayerNames = (try? c.decodeIfPresent([String].self, forKey: .giocatori))?
            .map { Self.normalizedNonEmptyString($0) ?? $0 }
        legacyPlayerPhotoURLs = Self.decodeOptionalStringArray(in: c, key: .fotoGiocatori)?
            .map { Self.normalizedNonEmptyString($0) }
        legacyPlayerNumbers = Self.decodeOptionalIntArray(in: c, key: .numeriMaglia)
        legacyPlayerCaptainFlags = Self.decodeOptionalBoolArray(in: c, key: .capitani)
        legacyPlayerRoles = Self.decodeOptionalStringArray(in: c, key: .ruoli)?
            .map { Self.normalizedNonEmptyString($0) }
        tournamentId = try? c.decodeIfPresent(String.self, forKey: .tournamentId)
        group = Self.decodeFirstNonEmptyString(in: c, keys: [.group, .girone])?.uppercased()
    }

    var playerSnapshots: [PlayerSnapshot] {
        if let giocatoriDettagliati, !giocatoriDettagliati.isEmpty {
            return giocatoriDettagliati.enumerated().map { index, snapshot in
                PlayerSnapshot(
                    giocatoreId: snapshot.giocatoreId,
                    nome: Self.normalizedNonEmptyString(snapshot.nome) ?? legacyName(at: index),
                    numero: snapshot.numero ?? legacyNumber(at: index),
                    ruolo: Self.normalizedNonEmptyString(snapshot.ruolo) ?? legacyRole(at: index),
                    pictureURL: Self.normalizedNonEmptyString(snapshot.pictureURL) ?? legacyPhotoURL(at: index),
                    isCapitano: snapshot.isCapitano ?? legacyCaptainFlag(at: index),
                    isVice: snapshot.isVice
                )
            }
        }
        return (legacyPlayerNames ?? []).enumerated().map { index, rawName in
            PlayerSnapshot(
                giocatoreId: nil,
                nome: Self.normalizedNonEmptyString(rawName),
                numero: legacyNumber(at: index),
                ruolo: legacyRole(at: index),
                pictureURL: legacyPhotoURL(at: index),
                isCapitano: legacyCaptainFlag(at: index)
            )
        }
    }

    var safePlayersCount: Int {
        if let playersCount, playersCount > 0 {
            return playersCount
        }
        return playerSnapshots.count
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

    private static func decodeTimestamp<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        keys: [K]
    ) -> Timestamp? {
        for key in keys {
            do {
                if let timestamp = try container.decodeIfPresent(Timestamp.self, forKey: key) {
                    return timestamp
                }
            } catch {}
            do {
                if let isoString = try container.decodeIfPresent(String.self, forKey: key) {
                    let formatter = ISO8601DateFormatter()
                    if let date = formatter.date(from: isoString) {
                        return Timestamp(date: date)
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private static func decodeOptionalStringArray<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        key: K
    ) -> [String?]? {
        if let values = try? container.decodeIfPresent([String?].self, forKey: key) {
            return values
        }
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values.map { Optional($0) }
        }
        return nil
    }

    private static func decodeOptionalIntArray<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        key: K
    ) -> [Int?]? {
        if let values = try? container.decodeIfPresent([Int?].self, forKey: key) {
            return values
        }
        if let values = try? container.decodeIfPresent([Int].self, forKey: key) {
            return values.map { Optional($0) }
        }
        if let values = try? container.decodeIfPresent([String?].self, forKey: key) {
            return values.map { value in
                guard let value else { return nil }
                return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if let values = try? container.decodeIfPresent([String].self, forKey: key) {
            return values.map { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        return nil
    }

    private static func decodeOptionalBoolArray<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        key: K
    ) -> [Bool?]? {
        if let values = try? container.decodeIfPresent([Bool?].self, forKey: key) {
            return values
        }
        if let values = try? container.decodeIfPresent([Bool].self, forKey: key) {
            return values.map { Optional($0) }
        }
        return nil
    }

    private static func normalizedNonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func legacyName(at index: Int) -> String? {
        guard let legacyPlayerNames, legacyPlayerNames.indices.contains(index) else { return nil }
        return Self.normalizedNonEmptyString(legacyPlayerNames[index])
    }

    private func legacyPhotoURL(at index: Int) -> String? {
        guard let legacyPlayerPhotoURLs, legacyPlayerPhotoURLs.indices.contains(index) else { return nil }
        return Self.normalizedNonEmptyString(legacyPlayerPhotoURLs[index] ?? nil)
    }

    private func legacyNumber(at index: Int) -> Int? {
        guard let legacyPlayerNumbers, legacyPlayerNumbers.indices.contains(index) else { return nil }
        return legacyPlayerNumbers[index]
    }

    private func legacyCaptainFlag(at index: Int) -> Bool? {
        guard let legacyPlayerCaptainFlags, legacyPlayerCaptainFlags.indices.contains(index) else { return nil }
        return legacyPlayerCaptainFlags[index]
    }

    private func legacyRole(at index: Int) -> String? {
        guard let legacyPlayerRoles, legacyPlayerRoles.indices.contains(index) else { return nil }
        return Self.normalizedNonEmptyString(legacyPlayerRoles[index] ?? nil)
    }
}

extension EditionParticipation: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> EditionParticipation {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        return copy
    }
}

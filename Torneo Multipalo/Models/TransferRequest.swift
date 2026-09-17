import Foundation
import FirebaseFirestore

struct TransferRequest: Decodable, Identifiable {
    @DocumentID var id: String?
    var type: String
    var playerId: String
    var toPlayerId: String
    var fromTeamId: String
    var createdByTeamId: String?
    var fromTeamName: String?
    var fromTeamLogoUrl: String?
    var toTeamId: String?
    var toPlayerUid: String?
    var toPlayerName: String?
    var message: String?
    var playerFromTeamIdAtRequest: String?
    var playerWasFreeAtRequest: Bool?
    var status: String
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
    var handledAt: Timestamp?
    var handledByUid: String?

    enum CodingKeys: String, CodingKey {
        case type, playerId, fromTeamId, createdByTeamId, fromTeamName, fromTeamLogoUrl
        case toTeamId, toPlayerUid, toPlayerName, message, createdAt, updatedAt, handledAt, handledByUid
        case toPlayerId, status, playerFromTeamIdAtRequest, playerWasFreeAtRequest
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        type = Self.decodeFirstNonEmptyString(in: c, keys: [.type]) ?? "transfer"
        let resolvedPlayerId = Self.decodeFirstNonEmptyString(in: c, keys: [.toPlayerId, .playerId]) ?? ""
        playerId = resolvedPlayerId
        toPlayerId = resolvedPlayerId
        fromTeamId = Self.decodeFirstNonEmptyString(in: c, keys: [.fromTeamId, .createdByTeamId]) ?? ""
        createdByTeamId = Self.decodeFirstNonEmptyString(in: c, keys: [.createdByTeamId])
        fromTeamName = Self.decodeFirstNonEmptyString(in: c, keys: [.fromTeamName])
        fromTeamLogoUrl = Self.decodeFirstNonEmptyString(in: c, keys: [.fromTeamLogoUrl])
        toTeamId = Self.decodeFirstNonEmptyString(in: c, keys: [.toTeamId])
        toPlayerUid = Self.decodeFirstNonEmptyString(in: c, keys: [.toPlayerUid])
        toPlayerName = Self.decodeFirstNonEmptyString(in: c, keys: [.toPlayerName])
        message = Self.decodeFirstNonEmptyString(in: c, keys: [.message])
        playerFromTeamIdAtRequest = Self.decodeFirstNonEmptyString(in: c, keys: [.playerFromTeamIdAtRequest])
        playerWasFreeAtRequest = Self.decodeBool(in: c, keys: [.playerWasFreeAtRequest])
        status = Self.normalizedStatus(Self.decodeFirstNonEmptyString(in: c, keys: [.status]) ?? "pending")
        createdAt = try? c.decodeIfPresent(Timestamp.self, forKey: .createdAt)
        updatedAt = try? c.decodeIfPresent(Timestamp.self, forKey: .updatedAt)
        handledAt = try? c.decodeIfPresent(Timestamp.self, forKey: .handledAt)
        handledByUid = Self.decodeFirstNonEmptyString(in: c, keys: [.handledByUid])
    }

    nonisolated private static func normalizedStatus(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "accepted", "accept", "approved":
            return "accepted"
        case "rejected", "reject", "declined", "denied":
            return "rejected"
        case "cancelled", "canceled", "withdrawn":
            return "cancelled"
        case "sent":
            return "pending"
        default:
            return "pending"
        }
    }

    nonisolated var isPendingLike: Bool {
        status == "pending"
    }

    nonisolated var isHandled: Bool {
        ["accepted", "rejected", "cancelled"].contains(status)
    }

    nonisolated private static func decodeFirstNonEmptyString<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        keys: [K]
    ) -> String? {
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

    nonisolated private static func decodeBool<K: CodingKey>(
        in container: KeyedDecodingContainer<K>,
        keys: [K]
    ) -> Bool? {
        for key in keys {
            do {
                if let value = try container.decodeIfPresent(Bool.self, forKey: key) {
                    return value
                }
            } catch {}
            do {
                if let rawValue = try container.decodeIfPresent(String.self, forKey: key) {
                    switch rawValue.lowercased() {
                    case "true", "1":
                        return true
                    case "false", "0":
                        return false
                    default:
                        break
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}

extension TransferRequest: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> TransferRequest {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        return copy
    }
}

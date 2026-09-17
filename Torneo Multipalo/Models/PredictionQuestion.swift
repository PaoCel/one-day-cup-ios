import Foundation
import FirebaseFirestore

struct PredictionQuestion: Decodable, Identifiable {
    @DocumentID var id: String?
    var edition: Int
    var kind: String
    var scope: String?
    var matchId: String?
    var title: String
    var subtitle: String?
    var status: String?
    var resolvedSelectionId: String?
    var sortIndex: Int?
    var giornata: Int?
    var phase: String?
    var matchTime: String?
    var options: [Option]
    var stats: Stats?
    var createdAt: Timestamp?
    var updatedAt: Timestamp?

    struct Option: Decodable, Identifiable {
        var id: String
        var title: String
        var subtitle: String?
        var teamId: String?
        var teamLogo: String?
        var accentHex: String?
        var sortOrder: Int?
    }

    struct Stats: Decodable {
        var totalEntries: Int?
        var optionCounts: [String: Int]?
    }

    var safeOptions: [Option] {
        options.sorted { lhs, rhs in
            let lhsOrder = lhs.sortOrder ?? .max
            let rhsOrder = rhs.sortOrder ?? .max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    var normalizedKind: String {
        kind
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    var isMatchOutcome: Bool {
        normalizedKind == "match_outcome"
    }

    var isTournamentWinner: Bool {
        normalizedKind == "tournament_winner"
    }

    var isGroupWinner: Bool {
        normalizedKind == "group_winner"
    }

    var isEditionQuestion: Bool {
        (scope?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "edition") != "match"
    }

    var usesTeamOptions: Bool {
        isTournamentWinner || isGroupWinner || safeOptions.contains { option in
            let teamId = option.teamId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !teamId.isEmpty
        }
    }

    var normalizedStatus: String {
        let normalized = status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if normalized == "resolved" || resolvedSelectionId != nil {
            return "resolved"
        }
        if normalized == "closed" {
            return "closed"
        }
        return "open"
    }

    var isOpen: Bool {
        normalizedStatus == "open"
    }

    var isClosed: Bool {
        normalizedStatus == "closed"
    }

    var isResolved: Bool {
        normalizedStatus == "resolved"
    }

    var totalEntries: Int {
        stats?.totalEntries ?? 0
    }

    func optionCount(for optionId: String) -> Int {
        stats?.optionCounts?[optionId] ?? 0
    }

    func optionPercentage(for optionId: String) -> Double {
        guard totalEntries > 0 else { return 0 }
        return Double(optionCount(for: optionId)) / Double(totalEntries)
    }
}

struct PredictionEntry: Decodable, Identifiable {
    @DocumentID var id: String?
    var uid: String
    var questionId: String
    var edition: Int
    var selectionId: String
    var createdAt: Timestamp?
    var updatedAt: Timestamp?
}

extension PredictionQuestion: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> PredictionQuestion {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        return copy
    }
}

extension PredictionEntry: FirestoreDocumentBackfillable {
    func withDocumentID(_ documentID: String) -> PredictionEntry {
        let normalizedDocumentID = documentID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDocumentID.isEmpty else { return self }

        var copy = self
        if copy.id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.id = normalizedDocumentID
        }
        return copy
    }
}

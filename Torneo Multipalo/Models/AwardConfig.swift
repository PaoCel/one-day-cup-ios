import Foundation

struct AwardConfig {
    static let supportedPhases = ["girone", "ottavi", "quarti", "semifinali", "finale"]

    private static let defaultWeights = Dictionary(
        uniqueKeysWithValues: supportedPhases.map { ($0, 1.0) }
    )

    var topScorerWeightsByPhase: [String: Double]
    var goalkeeperConcededWeightsByPhase: [String: Double]
    var mvpWeightsByPhase: [String: Double]

    init(data: [String: Any]? = nil) {
        let payload = data ?? [:]
        topScorerWeightsByPhase = Self.parseWeights(
            from: payload,
            keys: ["topScorerWeightsByPhase", "goalWeightsByPhase"]
        )
        goalkeeperConcededWeightsByPhase = Self.parseWeights(
            from: payload,
            keys: ["goalkeeperConcededWeightsByPhase", "goalkeeperWeightsByPhase"]
        )
        mvpWeightsByPhase = Self.parseWeights(
            from: payload,
            keys: ["mvpWeightsByPhase"]
        )
    }

    func topScorerWeight(for phase: String) -> Double {
        Self.weight(for: phase, in: topScorerWeightsByPhase)
    }

    func goalkeeperConcededWeight(for phase: String) -> Double {
        Self.weight(for: phase, in: goalkeeperConcededWeightsByPhase)
    }

    func mvpWeight(for phase: String) -> Double {
        Self.weight(for: phase, in: mvpWeightsByPhase)
    }

    static func normalizePhaseKey(_ phase: String) -> String {
        let normalized = phase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "group", "gironi":
            return "girone"
        case "ottavo", "ottavi di finale":
            return "ottavi"
        case "quarto", "quarti di finale":
            return "quarti"
        case "semifinale", "semi", "semifinali di finale":
            return "semifinali"
        case "final", "finalissima":
            return "finale"
        default:
            return normalized
        }
    }

    private static func parseWeights(from data: [String: Any], keys: [String]) -> [String: Double] {
        let rawMap = keys.compactMap { data[$0] as? [String: Any] }.first
        guard let rawMap else {
            return defaultWeights
        }

        var normalized = defaultWeights
        for (phase, rawValue) in rawMap {
            guard let value = numericValue(from: rawValue) else { continue }
            normalized[normalizePhaseKey(phase)] = value
        }
        return normalized
    }

    private static func numericValue(from rawValue: Any) -> Double? {
        switch rawValue {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private static func weight(for phase: String, in values: [String: Double]) -> Double {
        values[normalizePhaseKey(phase)] ?? 1.0
    }
}

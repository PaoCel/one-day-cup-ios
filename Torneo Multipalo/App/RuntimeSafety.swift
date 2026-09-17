import Foundation

struct RuntimeSafety {
    static let productionFirebaseProjectIDs: Set<String> = ["torneo-multipalo25"]
    static let shared = RuntimeSafety()

    let firebaseConfigResourceName: String
    let firebaseProjectID: String
    let allowsRiskyProductionDebugActions: Bool
    let isDebugBuild: Bool

    init(bundle: Bundle = .main) {
        firebaseConfigResourceName = FirebaseBootstrap.configResourceName(bundle: bundle)
        firebaseProjectID = Self.loadFirebaseProjectID(from: bundle) ?? "unknown"
        allowsRiskyProductionDebugActions = bundle.boolValue(forInfoDictionaryKey: "TMAllowRiskyProductionDebugActions")
#if DEBUG
        isDebugBuild = true
#else
        isDebugBuild = false
#endif
    }

    var isProductionFirebaseProject: Bool {
        Self.productionFirebaseProjectIDs.contains(firebaseProjectID)
    }

    var protectsRealData: Bool {
        isDebugBuild && isProductionFirebaseProject && !allowsRiskyProductionDebugActions
    }

    var environmentLabel: String {
        if isProductionFirebaseProject {
            return "Produzione"
        }
        if firebaseProjectID == "unknown" {
            return "Sconosciuto"
        }
        return "Separato"
    }

    var protectionSummary: String? {
        guard protectsRealData else { return nil }
        return "Build Debug collegata al Firebase reale: scritture, push e azioni di test rischiose sono bloccate per proteggere i dati esistenti."
    }

    func assertAllowsMutation(_ operation: String) throws {
        guard protectsRealData else { return }
        throw RuntimeSafetyError.blockedProductionMutation(
            operation: operation,
            projectID: firebaseProjectID
        )
    }

    private static func loadFirebaseProjectID(from bundle: Bundle) -> String? {
        guard let url = FirebaseBootstrap.configPlistURL(bundle: bundle),
              let payload = NSDictionary(contentsOf: url),
              let projectID = payload["PROJECT_ID"] as? String else {
            return nil
        }

        let normalized = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum RuntimeSafetyError: LocalizedError {
    case blockedProductionMutation(operation: String, projectID: String)

    var errorDescription: String? {
        switch self {
        case let .blockedProductionMutation(operation, projectID):
            return "Azione bloccata per proteggere i dati reali (\(projectID)): \(operation). Usa un ambiente staging oppure abilita esplicitamente TMAllowRiskyProductionDebugActions se vuoi forzare la scrittura."
        }
    }
}

private extension Bundle {
    func boolValue(forInfoDictionaryKey key: String) -> Bool {
        guard let rawValue = object(forInfoDictionaryKey: key) else { return false }

        if let boolValue = rawValue as? Bool {
            return boolValue
        }
        if let stringValue = rawValue as? String {
            return NSString(string: stringValue).boolValue
        }
        if let numberValue = rawValue as? NSNumber {
            return numberValue.boolValue
        }
        return false
    }
}

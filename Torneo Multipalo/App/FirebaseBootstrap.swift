import Foundation
import FirebaseCore

enum FirebaseBootstrapError: LocalizedError {
    case missingConfiguration(resourceName: String)

    var errorDescription: String? {
        switch self {
        case let .missingConfiguration(resourceName):
            return "Configurazione Firebase mancante: \(resourceName).plist"
        }
    }
}

enum FirebaseBootstrap {
    static let configResourceEnvironmentKey = "TM_FIREBASE_CONFIG_RESOURCE_NAME"
    static let configResourceInfoKey = "TMFirebaseConfigResourceName"
    static let defaultConfigResourceName = "GoogleService-Info"

    static func configureApp(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) throws {
        guard FirebaseApp.app() == nil else { return }

        let resourceName = configResourceName(bundle: bundle, processInfo: processInfo)
        guard let path = bundle.path(forResource: resourceName, ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else {
            throw FirebaseBootstrapError.missingConfiguration(resourceName: resourceName)
        }

        FirebaseApp.configure(options: options)
    }

    static func configPlistURL(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> URL? {
        bundle.url(
            forResource: configResourceName(bundle: bundle, processInfo: processInfo),
            withExtension: "plist"
        )
    }

    static func configResourceName(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo
    ) -> String {
        if let environmentValue = normalizedValue(
            processInfo.environment[configResourceEnvironmentKey]
        ) {
            return environmentValue
        }

        if let infoValue = normalizedValue(
            bundle.object(forInfoDictionaryKey: configResourceInfoKey) as? String
        ) {
            return infoValue
        }

        return defaultConfigResourceName
    }

    private static func normalizedValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

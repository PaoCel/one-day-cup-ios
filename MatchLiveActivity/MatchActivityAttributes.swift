import ActivityKit
import Foundation

struct MatchActivityAttributes: ActivityAttributes {
    var matchId: String
    var team1Name: String
    var team2Name: String
    var team1LogoFile: String? // filename in App Group container
    var team2LogoFile: String? // filename in App Group container
    var campo: String?
    var fase: String?

    struct ContentState: Codable, Hashable {
        var team1Goals: Int
        var team2Goals: Int
        var elapsedMinutes: Int
        var lastEvent: String?
        var isFinished: Bool
    }
}

enum SharedLogoStorage {
    static let appGroupID = "group.paolo.Torneo-Multipalo"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static func logoURL(filename: String) -> URL? {
        containerURL?.appendingPathComponent(filename)
    }

    static func loadImage(filename: String?) -> Data? {
        guard let filename, let url = logoURL(filename: filename),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func saveLogo(data: Data, teamId: String) -> String? {
        let filename = "logo_\(teamId).png"
        guard let url = logoURL(filename: filename) else { return nil }
        do {
            try data.write(to: url)
            return filename
        } catch {
            return nil
        }
    }
}

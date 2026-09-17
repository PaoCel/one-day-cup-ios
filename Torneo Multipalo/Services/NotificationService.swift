import Foundation
import UserNotifications
import UIKit

@Observable @MainActor
final class NotificationService {
    enum SubscriptionError: LocalizedError {
        case permissionDenied
        case missingMatchId
        case missingTeamId
        case missingPlayerId

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Le notifiche sono disattivate. Abilita le notifiche di Torneo Multipalo nelle impostazioni di iPhone per ricevere aggiornamenti."
            case .missingMatchId:
                return "Non riesco a identificare questa partita per salvare la notifica."
            case .missingTeamId:
                return "Non riesco a identificare questa squadra per salvare la notifica."
            case .missingPlayerId:
                return "Non riesco a identificare questo giocatore per salvare la notifica."
            }
        }
    }

    enum AuthorizationState {
        case notDetermined
        case denied
        case authorized
    }

    private enum StorageKey {
        static let installationId = "notification.installationId"
        static let subscribedEditionIds = "notification.subscribedEditionIds"
        static let subscribedMatchIds = "notification.subscribedMatchIds"
        static let mutedMatchIds = "notification.mutedMatchIds"
        static let subscribedTeamIds = "notification.subscribedTeamIds"
        static let mutedTeamIds = "notification.mutedTeamIds"
        static let subscribedPlayerIds = "notification.subscribedPlayerIds"
        static let mutedPlayerIds = "notification.mutedPlayerIds"
    }

    private let userDefaults: UserDefaults

    var fcmToken: String?
    var authorizationState: AuthorizationState = .notDetermined
    var installationId: String
    var subscribedEditionIds: [Int]
    var subscribedMatchIds: [String]
    var mutedMatchIds: [String]
    var subscribedTeamIds: [String]
    var mutedTeamIds: [String]
    var subscribedPlayerIds: [String]
    var mutedPlayerIds: [String]
    var permissionGranted: Bool { authorizationState == .authorized }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        let storedInstallationId = userDefaults.string(forKey: StorageKey.installationId)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let storedInstallationId, !storedInstallationId.isEmpty {
            installationId = storedInstallationId
        } else {
            let generatedInstallationId = UUID().uuidString
            installationId = generatedInstallationId
            userDefaults.set(generatedInstallationId, forKey: StorageKey.installationId)
        }

        subscribedEditionIds = Self.sanitizedEditionIds(
            userDefaults.array(forKey: StorageKey.subscribedEditionIds)
        )
        subscribedMatchIds = Self.sanitizedMatchIds(
            userDefaults.array(forKey: StorageKey.subscribedMatchIds)
        )
        mutedMatchIds = Self.sanitizedStringIds(
            userDefaults.array(forKey: StorageKey.mutedMatchIds)
        )
        subscribedTeamIds = Self.sanitizedStringIds(
            userDefaults.array(forKey: StorageKey.subscribedTeamIds)
        )
        mutedTeamIds = Self.sanitizedStringIds(
            userDefaults.array(forKey: StorageKey.mutedTeamIds)
        )
        subscribedPlayerIds = Self.sanitizedStringIds(
            userDefaults.array(forKey: StorageKey.subscribedPlayerIds)
        )
        mutedPlayerIds = Self.sanitizedStringIds(
            userDefaults.array(forKey: StorageKey.mutedPlayerIds)
        )
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationState = Self.authorizationState(from: settings.authorizationStatus)
    }

    func registerForRemoteNotificationsIfAuthorized() {
        guard permissionGranted, !RuntimeSafety.shared.protectsRealData else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        if RuntimeSafety.shared.protectsRealData {
            await refreshAuthorizationStatus()
            return false
        }

        await refreshAuthorizationStatus()
        if permissionGranted {
            registerForRemoteNotificationsIfAuthorized()
            return permissionGranted
        }
        guard authorizationState == .notDetermined else {
            return permissionGranted
        }

        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            registerForRemoteNotificationsIfAuthorized()
        }
        await refreshAuthorizationStatus()
        return permissionGranted
    }

    func updateToken(_ token: String) {
        fcmToken = token
    }

    func isSubscribedToTournament(edition: Int) -> Bool {
        subscribedEditionIds.contains(edition)
    }

    func isSubscribedToMatch(matchId: String?) -> Bool {
        guard let matchId = Self.normalizedMatchId(matchId) else { return false }
        return subscribedMatchIds.contains(matchId)
    }

    func isSubscribedToTeam(teamId: String?, edition: Int) -> Bool {
        guard let normalizedTeamId = Self.normalizedStringId(teamId) else { return false }

        if subscribedTeamIds.contains(normalizedTeamId) {
            return true
        }
        if mutedTeamIds.contains(normalizedTeamId) {
            return false
        }

        return isSubscribedToTournament(edition: edition)
    }

    func isSubscribedToPlayer(playerId: String?, teamId: String?, edition: Int) -> Bool {
        guard let normalizedPlayerId = Self.normalizedStringId(playerId) else { return false }

        if subscribedPlayerIds.contains(normalizedPlayerId) {
            return true
        }
        if mutedPlayerIds.contains(normalizedPlayerId) {
            return false
        }

        if let normalizedTeamId = Self.normalizedStringId(teamId) {
            if subscribedTeamIds.contains(normalizedTeamId) {
                return true
            }
            if mutedTeamIds.contains(normalizedTeamId) {
                return false
            }
        }

        return isSubscribedToTournament(edition: edition)
    }

    func isSubscribedToMatch(
        matchId: String?,
        edition: Int,
        teamIds: [String] = [],
        playerIds: [String] = []
    ) -> Bool {
        guard let normalizedMatchId = Self.normalizedMatchId(matchId) else { return false }

        if subscribedMatchIds.contains(normalizedMatchId) {
            return true
        }
        if mutedMatchIds.contains(normalizedMatchId) {
            return false
        }

        let normalizedPlayerIds = Self.sanitizedStringIds(playerIds)
        if normalizedPlayerIds.contains(where: { subscribedPlayerIds.contains($0) }) {
            return true
        }
        if normalizedPlayerIds.contains(where: { mutedPlayerIds.contains($0) }) {
            return false
        }

        let normalizedTeamIds = Self.sanitizedStringIds(teamIds)
        if normalizedTeamIds.contains(where: { subscribedTeamIds.contains($0) }) {
            return true
        }
        if normalizedTeamIds.contains(where: { mutedTeamIds.contains($0) }) {
            return false
        }

        return isSubscribedToTournament(edition: edition)
    }

    @discardableResult
    func setTournamentSubscription(
        enabled: Bool,
        edition: Int,
        cloudFunctionsService: CloudFunctionsService
    ) async throws -> Bool {
        if enabled {
            let granted = await requestPermissionIfNeeded()
            guard granted else { throw SubscriptionError.permissionDenied }
            subscribedEditionIds = Self.sanitizedEditionIds(subscribedEditionIds + [edition])
        } else {
            subscribedEditionIds.removeAll { $0 == edition }
        }

        persistPreferences()
        try await syncPreferencesIfPossible(cloudFunctionsService: cloudFunctionsService)
        return isSubscribedToTournament(edition: edition)
    }

    @discardableResult
    func setMatchSubscription(
        enabled: Bool,
        matchId: String?,
        edition: Int,
        teamIds: [String] = [],
        playerIds: [String] = [],
        cloudFunctionsService: CloudFunctionsService
    ) async throws -> Bool {
        guard let normalizedMatchId = Self.normalizedMatchId(matchId) else {
            throw SubscriptionError.missingMatchId
        }
        let normalizedTeamIds = Self.sanitizedStringIds(teamIds)
        let normalizedPlayerIds = Self.sanitizedStringIds(playerIds)

        if enabled {
            let granted = await requestPermissionIfNeeded()
            guard granted else { throw SubscriptionError.permissionDenied }
            mutedMatchIds.removeAll { $0 == normalizedMatchId }

            if isMatchEnabledViaBroaderScopes(
                edition: edition,
                teamIds: normalizedTeamIds,
                playerIds: normalizedPlayerIds
            ) {
                subscribedMatchIds.removeAll { $0 == normalizedMatchId }
            } else {
                subscribedMatchIds = Self.sanitizedStringIds(subscribedMatchIds + [normalizedMatchId])
            }
        } else {
            subscribedMatchIds.removeAll { $0 == normalizedMatchId }

            if isMatchEnabledViaBroaderScopes(
                edition: edition,
                teamIds: normalizedTeamIds,
                playerIds: normalizedPlayerIds
            ) {
                mutedMatchIds = Self.sanitizedStringIds(mutedMatchIds + [normalizedMatchId])
            } else {
                mutedMatchIds.removeAll { $0 == normalizedMatchId }
            }
        }

        persistPreferences()
        try await syncPreferencesIfPossible(cloudFunctionsService: cloudFunctionsService)
        return isSubscribedToMatch(
            matchId: normalizedMatchId,
            edition: edition,
            teamIds: normalizedTeamIds,
            playerIds: normalizedPlayerIds
        )
    }

    @discardableResult
    func setTeamSubscription(
        enabled: Bool,
        teamId: String?,
        edition: Int,
        cloudFunctionsService: CloudFunctionsService
    ) async throws -> Bool {
        guard let normalizedTeamId = Self.normalizedStringId(teamId) else {
            throw SubscriptionError.missingTeamId
        }

        if enabled {
            let granted = await requestPermissionIfNeeded()
            guard granted else { throw SubscriptionError.permissionDenied }
            mutedTeamIds.removeAll { $0 == normalizedTeamId }

            if isTeamEnabledViaBroaderScopes(edition: edition) {
                subscribedTeamIds.removeAll { $0 == normalizedTeamId }
            } else {
                subscribedTeamIds = Self.sanitizedStringIds(subscribedTeamIds + [normalizedTeamId])
            }
        } else {
            subscribedTeamIds.removeAll { $0 == normalizedTeamId }

            if isTeamEnabledViaBroaderScopes(edition: edition) {
                mutedTeamIds = Self.sanitizedStringIds(mutedTeamIds + [normalizedTeamId])
            } else {
                mutedTeamIds.removeAll { $0 == normalizedTeamId }
            }
        }

        persistPreferences()
        try await syncPreferencesIfPossible(cloudFunctionsService: cloudFunctionsService)
        return isSubscribedToTeam(teamId: normalizedTeamId, edition: edition)
    }

    @discardableResult
    func setPlayerSubscription(
        enabled: Bool,
        playerId: String?,
        teamId: String?,
        edition: Int,
        cloudFunctionsService: CloudFunctionsService
    ) async throws -> Bool {
        guard let normalizedPlayerId = Self.normalizedStringId(playerId) else {
            throw SubscriptionError.missingPlayerId
        }

        let normalizedTeamId = Self.normalizedStringId(teamId)

        if enabled {
            let granted = await requestPermissionIfNeeded()
            guard granted else { throw SubscriptionError.permissionDenied }
            mutedPlayerIds.removeAll { $0 == normalizedPlayerId }

            if isPlayerEnabledViaBroaderScopes(teamId: normalizedTeamId, edition: edition) {
                subscribedPlayerIds.removeAll { $0 == normalizedPlayerId }
            } else {
                subscribedPlayerIds = Self.sanitizedStringIds(subscribedPlayerIds + [normalizedPlayerId])
            }
        } else {
            subscribedPlayerIds.removeAll { $0 == normalizedPlayerId }

            if isPlayerEnabledViaBroaderScopes(teamId: normalizedTeamId, edition: edition) {
                mutedPlayerIds = Self.sanitizedStringIds(mutedPlayerIds + [normalizedPlayerId])
            } else {
                mutedPlayerIds.removeAll { $0 == normalizedPlayerId }
            }
        }

        persistPreferences()
        try await syncPreferencesIfPossible(cloudFunctionsService: cloudFunctionsService)
        return isSubscribedToPlayer(
            playerId: normalizedPlayerId,
            teamId: normalizedTeamId,
            edition: edition
        )
    }

    func syncPreferencesIfPossible(
        cloudFunctionsService: CloudFunctionsService
    ) async throws {
        guard !RuntimeSafety.shared.protectsRealData else { return }
        guard permissionGranted, fcmToken != nil else { return }

        try await cloudFunctionsService.syncNotificationPreferences(
            installationId: installationId,
            subscribedEditionIds: subscribedEditionIds,
            subscribedMatchIds: subscribedMatchIds,
            mutedMatchIds: mutedMatchIds,
            subscribedTeamIds: subscribedTeamIds,
            mutedTeamIds: mutedTeamIds,
            subscribedPlayerIds: subscribedPlayerIds,
            mutedPlayerIds: mutedPlayerIds
        )
    }

    private func isTeamEnabledViaBroaderScopes(edition: Int) -> Bool {
        isSubscribedToTournament(edition: edition)
    }

    private func isPlayerEnabledViaBroaderScopes(teamId: String?, edition: Int) -> Bool {
        if let teamId {
            if subscribedTeamIds.contains(teamId) {
                return true
            }
            if mutedTeamIds.contains(teamId) {
                return false
            }
        }

        return isSubscribedToTournament(edition: edition)
    }

    private func isMatchEnabledViaBroaderScopes(
        edition: Int,
        teamIds: [String],
        playerIds: [String]
    ) -> Bool {
        let normalizedPlayerIds = Self.sanitizedStringIds(playerIds)
        if normalizedPlayerIds.contains(where: { subscribedPlayerIds.contains($0) }) {
            return true
        }
        if normalizedPlayerIds.contains(where: { mutedPlayerIds.contains($0) }) {
            return false
        }

        let normalizedTeamIds = Self.sanitizedStringIds(teamIds)
        if normalizedTeamIds.contains(where: { subscribedTeamIds.contains($0) }) {
            return true
        }
        if normalizedTeamIds.contains(where: { mutedTeamIds.contains($0) }) {
            return false
        }

        return isSubscribedToTournament(edition: edition)
    }

    private static func authorizationState(from status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    private func persistPreferences() {
        userDefaults.set(subscribedEditionIds, forKey: StorageKey.subscribedEditionIds)
        userDefaults.set(subscribedMatchIds, forKey: StorageKey.subscribedMatchIds)
        userDefaults.set(mutedMatchIds, forKey: StorageKey.mutedMatchIds)
        userDefaults.set(subscribedTeamIds, forKey: StorageKey.subscribedTeamIds)
        userDefaults.set(mutedTeamIds, forKey: StorageKey.mutedTeamIds)
        userDefaults.set(subscribedPlayerIds, forKey: StorageKey.subscribedPlayerIds)
        userDefaults.set(mutedPlayerIds, forKey: StorageKey.mutedPlayerIds)
    }

    private static func sanitizedEditionIds(_ rawValues: [Any]?) -> [Int] {
        let ids = (rawValues ?? []).compactMap { rawValue -> Int? in
            if let value = rawValue as? Int { return value }
            if let value = rawValue as? NSNumber { return value.intValue }
            if let value = rawValue as? String { return Int(value) }
            return nil
        }

        return Array(Set(ids.filter { $0 > 0 })).sorted()
    }

    private static func sanitizedMatchIds(_ rawValues: [Any]?) -> [String] {
        sanitizedStringIds(rawValues)
    }

    private static func normalizedMatchId(_ rawValue: String?) -> String? {
        normalizedStringId(rawValue)
    }

    private static func sanitizedStringIds(_ rawValues: [Any]?) -> [String] {
        Array(
            Set(
                (rawValues ?? [])
                    .compactMap { rawValue -> String? in
                        if let value = rawValue as? String {
                            return normalizedStringId(value)
                        }
                        return nil
                    }
            )
        )
        .sorted()
    }

    private static func normalizedStringId(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

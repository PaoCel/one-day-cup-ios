import XCTest
@testable import TorneoMultipaloLogic

final class FirebaseConfigurationSafetyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        unsetenv("TM_FIREBASE_CONFIG_RESOURCE_NAME")
    }

    func testRuntimeSafetyBlocksMutationsWhenDefaultBundleUsesProductionConfig() throws {
        let bundleURL = try TemporaryBundleFactory.makeBundle(
            infoPlistOverrides: [:],
            resources: [
                "GoogleService-Info.plist": [
                    "PROJECT_ID": "torneo-multipalo25",
                    "BUNDLE_ID": "paolo.Torneo-Multipalo",
                    "GOOGLE_APP_ID": "1:649400894005:ios:61cfd2c029d4b0f23be77c",
                    "GCM_SENDER_ID": "649400894005"
                ],
                "GoogleService-Info-Staging.plist": [
                    "PROJECT_ID": "torneo-multiplo-staging",
                    "BUNDLE_ID": "paolo.Torneo-Multipalo",
                    "GOOGLE_APP_ID": "1:859051232262:ios:d215b17abdf9d6aa1d0787",
                    "GCM_SENDER_ID": "859051232262"
                ]
            ]
        )
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))
        let safety = RuntimeSafety(bundle: bundle)

        XCTAssertEqual(FirebaseBootstrap.configResourceName(bundle: bundle), "GoogleService-Info")
        XCTAssertEqual(safety.firebaseProjectID, "torneo-multipalo25")
        XCTAssertTrue(safety.isProductionFirebaseProject)
        XCTAssertTrue(safety.protectsRealData)
        XCTAssertEqual(safety.environmentLabel, "Produzione")

        XCTAssertThrowsError(try safety.assertAllowsMutation("test mutazione")) { error in
            XCTAssertTrue(error.localizedDescription.contains("torneo-multipalo25"))
        }
    }

    func testRuntimeSafetyUsesInfoPlistOverrideToSelectStagingConfig() throws {
        let bundleURL = try TemporaryBundleFactory.makeBundle(
            infoPlistOverrides: [
                "TMFirebaseConfigResourceName": "GoogleService-Info-Staging"
            ],
            resources: [
                "GoogleService-Info.plist": [
                    "PROJECT_ID": "torneo-multipalo25",
                    "BUNDLE_ID": "paolo.Torneo-Multipalo",
                    "GOOGLE_APP_ID": "1:649400894005:ios:61cfd2c029d4b0f23be77c",
                    "GCM_SENDER_ID": "649400894005"
                ],
                "GoogleService-Info-Staging.plist": [
                    "PROJECT_ID": "torneo-multiplo-staging",
                    "BUNDLE_ID": "paolo.Torneo-Multipalo",
                    "GOOGLE_APP_ID": "1:859051232262:ios:d215b17abdf9d6aa1d0787",
                    "GCM_SENDER_ID": "859051232262"
                ]
            ]
        )
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        let bundle = try XCTUnwrap(Bundle(path: bundleURL.path))
        let safety = RuntimeSafety(bundle: bundle)
        let plistURL = try XCTUnwrap(FirebaseBootstrap.configPlistURL(bundle: bundle))

        XCTAssertEqual(FirebaseBootstrap.configResourceName(bundle: bundle), "GoogleService-Info-Staging")
        XCTAssertEqual(plistURL.lastPathComponent, "GoogleService-Info-Staging.plist")
        XCTAssertEqual(safety.firebaseProjectID, "torneo-multiplo-staging")
        XCTAssertFalse(safety.isProductionFirebaseProject)
        XCTAssertFalse(safety.protectsRealData)
        XCTAssertEqual(safety.environmentLabel, "Separato")
        XCTAssertNoThrow(try safety.assertAllowsMutation("test mutazione staging"))
    }
}

private enum TemporaryBundleFactory {
    static func makeBundle(
        infoPlistOverrides: [String: Any],
        resources: [String: [String: Any]]
    ) throws -> URL {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("bundle")

        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        var infoPlist: [String: Any] = [
            "CFBundleIdentifier": "qa.\(UUID().uuidString)",
            "CFBundleName": "QABundle",
            "CFBundlePackageType": "BNDL"
        ]
        infoPlist.merge(infoPlistOverrides) { _, new in new }

        try writePlist(infoPlist, to: bundleURL.appendingPathComponent("Info.plist"))

        for (name, payload) in resources {
            try writePlist(payload, to: bundleURL.appendingPathComponent(name))
        }

        return bundleURL
    }

    private static func writePlist(_ payload: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: payload,
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}

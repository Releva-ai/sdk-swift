import XCTest
@testable import RelevaSDK

/// Pins `PrivacyInfo.xcprivacy`, read out of the bundle it actually ships in.
///
/// A typo that makes the manifest unparseable, or a declaration that drifts away
/// from what the tracking surface sends, is invisible until App Store review —
/// the worst possible moment to find out.
final class PrivacyManifestTests: XCTestCase {
    private var manifest: [String: Any]!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let url = try XCTUnwrap(
            PrivacyManifest.url,
            "PrivacyInfo.xcprivacy is not in the built product — is the `resources:` entry still on the RelevaSDK target in Package.swift?"
        )
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        manifest = try XCTUnwrap(parsed as? [String: Any], "the manifest is not a dictionary at the top level")
    }

    override func tearDown() {
        manifest = nil
        super.tearDown()
    }

    private func collectedDataTypes() throws -> [[String: Any]] {
        let types = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        XCTAssertFalse(types.isEmpty, "the SDK collects data, so an empty declaration is itself the bug")
        return types
    }

    // MARK: - Required-reason APIs

    func testUserDefaultsIsDeclaredWithTheAppsOwnDefaultsReason() throws {
        let apiTypes = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        XCTAssertEqual(
            apiTypes.compactMap { $0["NSPrivacyAccessedAPIType"] as? String },
            ["NSPrivacyAccessedAPICategoryUserDefaults"],
            "UserDefaults is the SDK's only required-reason API use; declaring a category the SDK does not touch is its own App Store problem"
        )

        let userDefaults = try XCTUnwrap(
            apiTypes.first { $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults" },
            "StorageService reads and writes UserDefaults, so the category has to be declared"
        )

        XCTAssertEqual(
            userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String],
            ["CA92.1"],
            "CA92.1 covers reading and writing the app's own defaults; 1C8F.1 (App Group) and C56D.1 (SDK wrapping the API for the app) do not describe StorageService"
        )
    }

    // MARK: - Collected data types

    func testCollectedDataTypesMatchTheTrackingSurface() throws {
        let declared = try collectedDataTypes().compactMap { $0["NSPrivacyCollectedDataType"] as? String }

        XCTAssertEqual(
            declared.sorted(),
            [
                // registerPushToken(_:deviceType:) and setDeviceId(_:)
                "NSPrivacyCollectedDataTypeDeviceID",
                // submitNpsResponse(token:score:comment:)'s free-text comment
                "NSPrivacyCollectedDataTypeOtherUserContent",
                // screen/product views, cart, wishlist, banner/story/NPS events
                "NSPrivacyCollectedDataTypeProductInteraction",
                // trackCheckoutSuccess(orderedCart:screenToken:)
                "NSPrivacyCollectedDataTypePurchaseHistory",
                // trackSearchView(query:...)
                "NSPrivacyCollectedDataTypeSearchHistory",
                // setProfileId(_:), sent as context.profile.id
                "NSPrivacyCollectedDataTypeUserID"
            ].sorted(),
            "add a tracking call and this list must move with it, in both directions"
        )
    }

    func testEveryCollectedTypeIsLinkedToIdentityAndNotUsedForTracking() throws {
        for entry in try collectedDataTypes() {
            let name = entry["NSPrivacyCollectedDataType"] as? String ?? "<unnamed entry>"

            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypeLinked"] as? Bool,
                true,
                "\(name): everything the SDK sends carries profileId / deviceId, so it is linked to identity"
            )
            XCTAssertEqual(
                entry["NSPrivacyCollectedDataTypeTracking"] as? Bool,
                false,
                "\(name): a type marked for tracking would contradict NSPrivacyTracking being false"
            )
        }
    }

    func testPurposesMatchTheSignedOffDeclaration() throws {
        // ProductPersonalization + AppFunctionality + Analytics. Analytics was
        // signed off by Releva (2026-08-11): Customer Insights (RFM scoring,
        // cohort analysis, funnels, audience performance) is built on exactly
        // these identifiers and events.
        let behavioural = [
            "NSPrivacyCollectedDataTypePurposeAnalytics",
            "NSPrivacyCollectedDataTypePurposeAppFunctionality",
            "NSPrivacyCollectedDataTypePurposeProductPersonalization"
        ]
        let expected: [String: [String]] = [
            "NSPrivacyCollectedDataTypeUserID": behavioural,
            "NSPrivacyCollectedDataTypeDeviceID": behavioural,
            "NSPrivacyCollectedDataTypeProductInteraction": behavioural,
            "NSPrivacyCollectedDataTypeSearchHistory": behavioural,
            "NSPrivacyCollectedDataTypePurchaseHistory": behavioural,
            // Deliberately no Analytics: the NPS free-text comment is read
            // individually by a marketer, not aggregated into an audience
            // measure, so the Analytics purpose is not justifiable for it.
            "NSPrivacyCollectedDataTypeOtherUserContent": [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ]
        ]

        for entry in try collectedDataTypes() {
            let name = try XCTUnwrap(entry["NSPrivacyCollectedDataType"] as? String)
            let purposes = try XCTUnwrap(entry["NSPrivacyCollectedDataTypePurposes"] as? [String])

            XCTAssertEqual(
                purposes.sorted(),
                expected[name]?.sorted(),
                "\(name): purposes are a signed-off declaration that flows into every host app's App Store Connect answers — changing this set should be a deliberate, reviewed edit, including removing Analytics or adding it to OtherUserContent"
            )
        }
    }

    func testContactDetailsAreNotDeclared() throws {
        let declared = try collectedDataTypes().compactMap { $0["NSPrivacyCollectedDataType"] as? String }

        for contactType in [
            "NSPrivacyCollectedDataTypeEmailAddress",
            "NSPrivacyCollectedDataTypePhoneNumber",
            "NSPrivacyCollectedDataTypeName",
            "NSPrivacyCollectedDataTypePhysicalAddress"
        ] {
            XCTAssertFalse(
                declared.contains(contactType),
                "\(contactType) must not be declared. v2.0.0 removed the profile builder that accepted contact details; they never leave the client, and declaring one here would make every host app's App Store disclosure wrong."
            )
        }
    }

    // MARK: - Tracking

    func testTrackingIsOffAndNoTrackingDomainsAreListed() throws {
        XCTAssertEqual(
            manifest["NSPrivacyTracking"] as? Bool,
            false,
            "flipping this is a product and legal determination about Releva's server-side ad-network forwarding, not a code change"
        )

        let domains = try XCTUnwrap(manifest["NSPrivacyTrackingDomains"] as? [String])
        XCTAssertTrue(
            domains.isEmpty,
            "the OS blocks every domain listed here for users who decline the ATT prompt, and the SDK talks only to its own API hosts — listing one would silently break push registration, tracking and personalisation"
        )
    }
}

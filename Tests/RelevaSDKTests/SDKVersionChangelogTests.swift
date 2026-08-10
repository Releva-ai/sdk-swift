import XCTest
@testable import RelevaSDK

/// Guards against `SDKVersion.current` drifting from the top `CHANGELOG.md`
/// entry — this has happened before: the `[2.0.0]` entry records the podspec
/// version constant having lagged at `1.0.4`.
final class SDKVersionChangelogTests: XCTestCase {
    func testSDKVersionMatchesTopChangelogEntry() throws {
        let changelogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // SDKVersionChangelogTests.swift -> RelevaSDKTests/
            .deletingLastPathComponent() // RelevaSDKTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> repo root
            .appendingPathComponent("CHANGELOG.md")

        let changelog = try String(contentsOf: changelogURL, encoding: .utf8)

        // The top-most heading looks like "## [3.0.0] - 2026-08-10".
        guard let headingRange = changelog.range(
            of: #"## \[\d+\.\d+\.\d+\]"#,
            options: .regularExpression
        ) else {
            XCTFail("Could not find a version heading in CHANGELOG.md")
            return
        }

        let heading = changelog[headingRange]
        guard let versionRange = heading.range(
            of: #"\d+\.\d+\.\d+"#,
            options: .regularExpression
        ) else {
            XCTFail("Could not parse a version out of heading: \(heading)")
            return
        }

        let changelogVersion = String(heading[versionRange])
        XCTAssertEqual(
            SDKVersion.current,
            changelogVersion,
            "SDKVersion.current (\(SDKVersion.current)) must match the top CHANGELOG.md entry (\(changelogVersion))"
        )
    }
}

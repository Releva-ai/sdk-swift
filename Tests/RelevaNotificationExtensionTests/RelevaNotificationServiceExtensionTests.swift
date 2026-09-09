import XCTest
@testable import RelevaNotificationExtension

/// `RelevaNotificationServiceExtension` itself needs a real notification-extension host to run
/// (`didReceive`/`serviceExtensionTimeWillExpire` are exercised on device only), but
/// `fileExtension(for:)` and `typeHint(for:)` are pure lookups the transcode path depends on,
/// and cost nothing to pin here.
final class RelevaNotificationServiceExtensionTests: XCTestCase {
    func testFileExtensionForKnownMimeTypes() {
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/jpeg"), "jpg")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/jpg"), "jpg")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/png"), "png")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/gif"), "gif")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/webp"), "webp")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/heic"), "heic")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "image/heif"), "heif")
    }

    func testFileExtensionIsCaseInsensitiveAndDefaultsToJpg() {
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "IMAGE/PNG"), "png")
        XCTAssertEqual(RelevaNotificationServiceExtension.fileExtension(for: "application/octet-stream"), "jpg")
    }

    func testTypeHintForKnownExtensions() {
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "jpg"), "public.jpeg")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "jpeg"), "public.jpeg")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "png"), "public.png")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "gif"), "com.compuserve.gif")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "webp"), "public.webp")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "heic"), "public.heic")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "heif"), "public.heif")
    }

    func testTypeHintIsCaseInsensitiveAndDefaultsToPublicImage() {
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "JPG"), "public.jpeg")
        XCTAssertEqual(RelevaNotificationServiceExtension.typeHint(for: "bmp"), "public.image")
    }

    // MARK: - Releva message detection

    func testIsRelevaMessageChecksRootLevelClickAction() {
        XCTAssertTrue(RelevaNotificationServiceExtension.isRelevaMessage(["click_action": "RELEVA_NOTIFICATION_CLICK"]))
        XCTAssertFalse(RelevaNotificationServiceExtension.isRelevaMessage(["click_action": "SOMETHING_ELSE"]))
    }

    func testIsRelevaMessageChecksTheDataWrapper() {
        XCTAssertTrue(RelevaNotificationServiceExtension.isRelevaMessage([
            "data": ["click_action": "RELEVA_NOTIFICATION_CLICK"]
        ]))
    }

    func testIsRelevaMessageFalseWithNoClickAction() {
        XCTAssertFalse(RelevaNotificationServiceExtension.isRelevaMessage(["aps": ["alert": "hi"]]))
    }
}

import Foundation

/// Where a notification tap asked the app to go, as `RelevaClient.onNavigation` reports it.
///
/// The same three destinations the SDK posts through `NotificationCenter`
/// (`RelevaNavigateToScreen`, `RelevaNavigateToURL`, `RelevaNavigateToInbox`), carrying what
/// those posts carry: the screen name and its parsed parameters, the deep link, and the inbox
/// message the parameters name, if any.
public enum RelevaNavigation {
    /// `target: "screen"`. `parameters` is the parsed `navigate_to_parameters` JSON object, empty
    /// when the push carried none.
    case screen(name: String, parameters: [String: Any])
    /// `target: "url"` with a scheme the app owns. An http/https URL the SDK opens externally is
    /// not reported here, and neither is one `RelevaClient.urlHandler` claims.
    case url(URL)
    /// `target: "inbox"`, with the `inboxMessageId` from the parsed parameters when there is one.
    case inbox(messageId: Int?)
}

extension RelevaNavigation {
    /// The typed form of a navigation the SDK posted, or `nil` for a post with no destination in
    /// it — which is also what makes this the one place the post's `userInfo` keys are read.
    init?(_ pending: NotificationService.PendingNavigation) {
        let userInfo = pending.userInfo
        let parameters = userInfo["parsedParameters"] as? [String: Any]

        switch pending.name {
        case Notification.Name("RelevaNavigateToScreen"):
            guard let screen = userInfo["screen"] as? String else { return nil }
            self = .screen(name: screen, parameters: parameters ?? [:])
        case Notification.Name("RelevaNavigateToURL"):
            guard let url = userInfo["url"] as? URL else { return nil }
            self = .url(url)
        case Notification.Name("RelevaNavigateToInbox"):
            self = .inbox(messageId: (parameters?["inboxMessageId"] as? NSNumber)?.intValue)
        default:
            return nil
        }
    }
}

// `[String: Any]` parameters aren't provably `Sendable`, exactly as in
// `NotificationService.PendingNavigation`, which this is built from: the SDK only fills the
// payload with `JSONSerialization` output, which is immutable Foundation values.
extension RelevaNavigation: @unchecked Sendable {}

import SwiftUI

/// Renders an inbox message body using the Unlayer DesignRenderer.
///
/// Automatically tracks message actions (link taps) via InboxService.
/// Use this in your message detail screen to render the message content.
public struct InboxMessageView: View {
    let message: InboxMessage
    let onLinkTap: ((String) -> Void)?

    public init(message: InboxMessage, onLinkTap: ((String) -> Void)? = nil) {
        self.message = message
        self.onLinkTap = onLinkTap
    }

    public var body: some View {
        DesignRenderer.render(design: message.design, onLinkTap: { url in
            InboxService.shared.trackAction(message.id)
            onLinkTap?(url)
        })
    }
}

import SwiftUI

/// Simple SwiftUI row for displaying an `InboxMessage`.
public struct InboxMessageRow: View {
    public var message: InboxMessage
    public var onTap: (() -> Void)?

    public init(message: InboxMessage, onTap: (() -> Void)? = nil) {
        self.message = message
        self.onTap = onTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let urlString = message.imageUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.gray.frame(width: 50, height: 50)
                    case .success(let image):
                        image.resizable().scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipped()
                    case .failure:
                        Color.red.frame(width: 50, height: 50)
                    @unknown default:
                        EmptyView()
                    }
                }
                .cornerRadius(4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.headline)
                if let preview = message.previewText {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Text(message.createdAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .background(message.isRead ? Color.clear : Color.blue.opacity(0.1))
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }
}

/// Sample list view that observes the inbox service.
public struct InboxListView: View {
    @ObservedObject private var service = InboxService.shared

    public init() {}

    public var body: some View {
        List {
            ForEach(service.state.messages) { msg in
                InboxMessageRow(message: msg) {
                    Task {
                        await InboxService.shared.markAsRead(msg.id)
                        if let action = msg.actionUrl {
                            // track click
                            await InboxService.shared.trackAction(messageId: msg.id)
                            if let url = URL(string: action) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Inbox")
        .refreshable {
            await service.refresh()
        }
    }
}

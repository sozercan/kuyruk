import SwiftUI

/// Individual notification row in the list.
struct NotificationRowView: View {
    @Environment(NotificationsViewModel.self) private var viewModel

    let notification: GitHubNotification
    var snoozedUntil: Date?

    var body: some View {
        HStack(spacing: 12) {
            // Unread indicator
            Circle()
                .fill(self.notification.unread ? .blue : .clear)
                .frame(width: 8, height: 8)

            // Subject type icon
            SubjectTypeBadge(type: self.notification.subject.type)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(self.notification.subject.title)
                    .font(.body)
                    .fontWeight(self.notification.unread ? .medium : .regular)
                    .lineLimit(2)
                    .foregroundStyle(self.notification.unread ? .primary : .secondary)

                HStack(spacing: 8) {
                    // Relative time
                    Text(self.notification.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    // Issue/PR number if available
                    if let number = notification.subjectNumber {
                        Text("#\(number)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Snoozed badge if applicable
                    if let snoozedUntil {
                        SnoozedBadge(snoozedUntil: snoozedUntil)
                    }
                }

                // Reason badge
                ReasonBadge(reason: self.notification.reason)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            self.contextMenuContent
        }
    }

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            Task {
                await self.viewModel.markAsRead(self.notification)
            }
        } label: {
            Label("Mark as Read", systemImage: "checkmark.circle")
        }
        .disabled(!self.notification.unread)

        Divider()

        if self.snoozedUntil != nil {
            Button {
                self.viewModel.unsnoozeNotification(self.notification)
            } label: {
                Label("Unsnooze", systemImage: "bell")
            }
        } else {
            SnoozeMenu { date in
                self.viewModel.snoozeNotification(self.notification, until: date)
            }
        }

        Divider()

        if let webUrl = notification.webUrl {
            Button {
                NSWorkspace.shared.open(webUrl)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
        }
    }
}

#Preview {
    let mockRepo = Repository(
        id: 1,
        nodeId: "test",
        name: "kuyruk",
        fullName: "sozercan/kuyruk",
        owner: RepositoryOwner(
            login: "sozercan",
            id: 1,
            nodeId: "test",
            avatarUrl: "https://github.com/sozercan.png",
            url: "https://api.github.com/users/sozercan",
            htmlUrl: "https://github.com/sozercan",
            type: "User"),
        isPrivate: false,
        htmlUrl: "https://github.com/sozercan/kuyruk",
        description: "GitHub Notifications client",
        fork: false,
        url: "https://api.github.com/repos/sozercan/kuyruk")

    let mockNotification = GitHubNotification(
        id: "123",
        repository: mockRepo,
        subject: NotificationSubject(
            title: "Add Liquid Glass support for macOS 26",
            url: "https://api.github.com/repos/sozercan/kuyruk/issues/42",
            latestCommentUrl: nil,
            type: .pullRequest),
        reason: .reviewRequested,
        unread: true,
        updatedAt: Date().addingTimeInterval(-3600),
        lastReadAt: nil,
        url: "https://api.github.com/notifications/threads/123",
        subscriptionUrl: "https://api.github.com/notifications/threads/123/subscription")

    List {
        NotificationRowView(notification: mockNotification)
    }
    .frame(width: 400, height: 150)
}

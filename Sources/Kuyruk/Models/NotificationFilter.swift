import Foundation

/// Represents a filter for displaying notifications.
enum NotificationFilter: Hashable, Identifiable, Sendable {
    // Smart filters
    case inbox
    case unread
    case participating
    case mentioned
    case assigned
    case reviewRequested
    case snoozed

    // Repository filter
    case repository(Repository)

    var id: String {
        switch self {
        case .inbox:
            "inbox"
        case .unread:
            "unread"
        case .participating:
            "participating"
        case .mentioned:
            "mentioned"
        case .assigned:
            "assigned"
        case .reviewRequested:
            "review_requested"
        case .snoozed:
            "snoozed"
        case let .repository(repo):
            "repo_\(repo.id)"
        }
    }

    /// Display name for the filter
    var displayName: String {
        switch self {
        case .inbox:
            "Inbox"
        case .unread:
            "Unread"
        case .participating:
            "Participating"
        case .mentioned:
            "Mentioned"
        case .assigned:
            "Assigned"
        case .reviewRequested:
            "Review Requested"
        case .snoozed:
            "Snoozed"
        case let .repository(repo):
            repo.name
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .inbox:
            "tray"
        case .unread:
            "circle.fill"
        case .participating:
            "person.2"
        case .mentioned:
            "at"
        case .assigned:
            "person.badge.plus"
        case .reviewRequested:
            "eye"
        case .snoozed:
            "moon.zzz"
        case .repository:
            "folder"
        }
    }

    /// Empty state title when no notifications match this filter
    var emptyStateTitle: String {
        switch self {
        case .inbox:
            "No Notifications"
        case .unread:
            "No Unread Notifications"
        case .participating:
            "No Participating Threads"
        case .mentioned:
            "No Mentions"
        case .assigned:
            "No Assignments"
        case .reviewRequested:
            "No Review Requests"
        case .snoozed:
            "No Snoozed Notifications"
        case let .repository(repo):
            "No Notifications in \(repo.name)"
        }
    }

    /// Empty state description when no notifications match this filter
    var emptyStateDescription: String {
        switch self {
        case .inbox:
            "You're all caught up! New notifications will appear here."
        case .unread:
            "All notifications have been read. Nice work!"
        case .participating:
            "No threads where you're a participant."
        case .mentioned:
            "No one has @mentioned you recently."
        case .assigned:
            "No issues or PRs are assigned to you."
        case .reviewRequested:
            "No pull requests waiting for your review."
        case .snoozed:
            "No snoozed notifications. Snooze items to deal with later."
        case .repository:
            "No notifications from this repository."
        }
    }

    /// Returns the smart filters for the sidebar
    static var smartFilters: [NotificationFilter] {
        [.inbox, .unread, .participating, .mentioned, .assigned, .reviewRequested, .snoozed]
    }

    /// Checks if a notification matches this filter
    func matches(_ notification: GitHubNotification) -> Bool {
        switch self {
        case .inbox:
            // Inbox shows only unread notifications (like GitHub's default view)
            notification.unread
        case .unread:
            notification.unread
        case .participating:
            [.author, .comment, .mention, .teamMention, .reviewRequested, .assign]
                .contains(notification.reason)
        case .mentioned:
            notification.reason == .mention || notification.reason == .teamMention
        case .assigned:
            notification.reason == .assign
        case .reviewRequested:
            notification.reason == .reviewRequested
        case .snoozed:
            // Snoozed filter only applies to cached notifications
            false
        case let .repository(repo):
            notification.repository.id == repo.id
        }
    }

    /// Checks if a cached notification matches this filter
    func matches(_ notification: CachedNotification) -> Bool {
        switch self {
        case .inbox:
            // Inbox shows unread, non-snoozed notifications
            return notification.unread && !notification.isSnoozed
        case .unread:
            return notification.unread && !notification.isSnoozed
        case .participating:
            let reason = notification.notificationReason
            let isParticipating = [.author, .comment, .mention, .teamMention, .reviewRequested, .assign]
                .contains(reason)
            return isParticipating && !notification.isSnoozed
        case .mentioned:
            let reason = notification.notificationReason
            return (reason == .mention || reason == .teamMention) && !notification.isSnoozed
        case .assigned:
            return notification.notificationReason == .assign && !notification.isSnoozed
        case .reviewRequested:
            return notification.notificationReason == .reviewRequested && !notification.isSnoozed
        case .snoozed:
            return notification.isSnoozed
        case let .repository(repo):
            return notification.repositoryId == repo.id && !notification.isSnoozed
        }
    }
}

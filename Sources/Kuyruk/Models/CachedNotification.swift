import Foundation
import SwiftData

/// SwiftData model for caching GitHub notifications locally.
/// Enables offline viewing and faster app startup.
@Model
final class CachedNotification {
    /// Unique identifier from GitHub API
    @Attribute(.unique)
    var id: String

    /// Notification subject title
    var title: String

    /// Repository full name (owner/repo)
    var repositoryFullName: String

    /// Repository ID for filtering
    var repositoryId: Int

    /// Repository name (short)
    var repositoryName: String

    /// Owner avatar URL for display
    var ownerAvatarUrl: String

    /// Notification reason (raw value)
    var reason: String

    /// Subject type (Issue, PullRequest, etc.)
    var subjectType: String

    /// Whether the notification is unread
    var unread: Bool

    /// When the notification was last updated on GitHub
    var updatedAt: Date

    /// When the notification was last read (if ever)
    var lastReadAt: Date?

    /// API URL for the notification thread
    var url: String

    /// Web URL for opening in browser
    var webUrl: String?

    /// Subject URL from GitHub API
    var subjectUrl: String?

    // MARK: - Sync Metadata

    /// When this cache entry was last synced
    var lastSyncedAt: Date

    /// Whether this notification has been deleted on GitHub
    var isDeleted: Bool

    // MARK: - Snooze Support

    /// When the notification is snoozed until (nil = not snoozed)
    var snoozedUntil: Date?

    /// Whether the notification is currently snoozed
    var isSnoozed: Bool {
        guard let snoozedUntil else { return false }
        return snoozedUntil > Date()
    }

    init(
        id: String,
        title: String,
        repositoryFullName: String,
        repositoryId: Int,
        repositoryName: String,
        ownerAvatarUrl: String,
        reason: String,
        subjectType: String,
        unread: Bool,
        updatedAt: Date,
        lastReadAt: Date?,
        url: String,
        webUrl: String?,
        subjectUrl: String?,
        lastSyncedAt: Date = Date(),
        isDeleted: Bool = false,
        snoozedUntil: Date? = nil) {
        self.id = id
        self.title = title
        self.repositoryFullName = repositoryFullName
        self.repositoryId = repositoryId
        self.repositoryName = repositoryName
        self.ownerAvatarUrl = ownerAvatarUrl
        self.reason = reason
        self.subjectType = subjectType
        self.unread = unread
        self.updatedAt = updatedAt
        self.lastReadAt = lastReadAt
        self.url = url
        self.webUrl = webUrl
        self.subjectUrl = subjectUrl
        self.lastSyncedAt = lastSyncedAt
        self.isDeleted = isDeleted
        self.snoozedUntil = snoozedUntil
    }
}

// MARK: - Conversion Extensions

extension CachedNotification {
    /// Creates a cached notification from a GitHub API notification.
    convenience init(from notification: GitHubNotification) {
        self.init(
            id: notification.id,
            title: notification.subject.title,
            repositoryFullName: notification.repository.fullName,
            repositoryId: notification.repository.id,
            repositoryName: notification.repository.name,
            ownerAvatarUrl: notification.repository.owner.avatarUrl,
            reason: notification.reason.rawValue,
            subjectType: notification.subject.type.rawValue,
            unread: notification.unread,
            updatedAt: notification.updatedAt,
            lastReadAt: notification.lastReadAt,
            url: notification.url,
            webUrl: notification.webUrl?.absoluteString,
            subjectUrl: notification.subject.url)
    }

    /// Updates this cached notification with fresh data from GitHub.
    func update(from notification: GitHubNotification) {
        self.title = notification.subject.title
        self.repositoryFullName = notification.repository.fullName
        self.repositoryId = notification.repository.id
        self.repositoryName = notification.repository.name
        self.ownerAvatarUrl = notification.repository.owner.avatarUrl
        self.reason = notification.reason.rawValue
        self.subjectType = notification.subject.type.rawValue
        self.unread = notification.unread
        self.updatedAt = notification.updatedAt
        self.lastReadAt = notification.lastReadAt
        self.url = notification.url
        self.webUrl = notification.webUrl?.absoluteString
        self.subjectUrl = notification.subject.url
        self.lastSyncedAt = Date()
        self.isDeleted = false
    }

    /// Parsed notification reason
    var notificationReason: NotificationReason {
        NotificationReason(rawValue: self.reason) ?? .unknown
    }

    /// Parsed subject type
    var notificationSubjectType: SubjectType {
        SubjectType(rawValue: self.subjectType) ?? .unknown
    }
}

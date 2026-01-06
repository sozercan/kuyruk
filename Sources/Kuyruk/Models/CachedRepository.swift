import Foundation
import SwiftData

/// SwiftData model for caching repository information.
@Model
final class CachedRepository {
    /// Unique identifier from GitHub API
    @Attribute(.unique)
    var id: Int

    /// Repository name (short)
    var name: String

    /// Full name (owner/repo)
    var fullName: String

    /// Owner login name
    var ownerLogin: String

    /// Owner avatar URL
    var ownerAvatarUrl: String

    /// Whether the repository is private
    var isPrivate: Bool

    /// Repository description
    var repositoryDescription: String?

    /// Web URL
    var htmlUrl: String

    /// Count of unread notifications for this repo
    var unreadCount: Int

    /// When this cache entry was last synced
    var lastSyncedAt: Date

    init(
        id: Int,
        name: String,
        fullName: String,
        ownerLogin: String,
        ownerAvatarUrl: String,
        isPrivate: Bool,
        repositoryDescription: String?,
        htmlUrl: String,
        unreadCount: Int = 0,
        lastSyncedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.ownerLogin = ownerLogin
        self.ownerAvatarUrl = ownerAvatarUrl
        self.isPrivate = isPrivate
        self.repositoryDescription = repositoryDescription
        self.htmlUrl = htmlUrl
        self.unreadCount = unreadCount
        self.lastSyncedAt = lastSyncedAt
    }
}

extension CachedRepository {
    /// Creates a cached repository from a GitHub API repository.
    convenience init(from repository: Repository) {
        self.init(
            id: repository.id,
            name: repository.name,
            fullName: repository.fullName,
            ownerLogin: repository.owner.login,
            ownerAvatarUrl: repository.owner.avatarUrl,
            isPrivate: repository.isPrivate,
            repositoryDescription: repository.description,
            htmlUrl: repository.htmlUrl)
    }

    /// Updates this cached repository with fresh data.
    func update(from repository: Repository) {
        self.name = repository.name
        self.fullName = repository.fullName
        self.ownerLogin = repository.owner.login
        self.ownerAvatarUrl = repository.owner.avatarUrl
        self.isPrivate = repository.isPrivate
        self.repositoryDescription = repository.description
        self.htmlUrl = repository.htmlUrl
        self.lastSyncedAt = Date()
    }
}

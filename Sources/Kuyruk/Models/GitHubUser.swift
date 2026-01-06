import Foundation

/// Represents the authenticated GitHub user.
struct GitHubUser: Codable, Sendable, Identifiable {
    let id: Int
    let login: String
    let nodeId: String
    let avatarUrl: String
    let name: String?
    let email: String?
    let bio: String?
    let publicRepos: Int
    let followers: Int
    let following: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case nodeId = "node_id"
        case avatarUrl = "avatar_url"
        case name
        case email
        case bio
        case publicRepos = "public_repos"
        case followers
        case following
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

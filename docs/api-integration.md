# GitHub API Integration

This document describes how Kuyruk integrates with the GitHub REST API.

## Authentication

### OAuth 2.0 with PKCE

Kuyruk uses OAuth 2.0 with PKCE (Proof Key for Code Exchange) for secure authentication.

#### Required Scopes

```
notifications    - Access notifications
repo             - Access private repository notifications
read:user        - Read user profile information
```

#### OAuth Flow

```
1. Generate code_verifier and code_challenge (PKCE)
2. Open browser to GitHub authorization URL:
   https://github.com/login/oauth/authorize
   ?client_id={CLIENT_ID}
   &redirect_uri=kuyruk://oauth/callback
   &scope=notifications+repo+read:user
   &state={random_state}
   &code_challenge={code_challenge}
   &code_challenge_method=S256

3. User authorizes in browser
4. GitHub redirects to kuyruk://oauth/callback?code={code}&state={state}
5. App validates state and exchanges code for token:
   POST https://github.com/login/oauth/access_token
   Content-Type: application/json
   {
     "client_id": "{CLIENT_ID}",
     "code": "{code}",
     "redirect_uri": "kuyruk://oauth/callback",
     "code_verifier": "{code_verifier}"
   }

6. Store token securely in Keychain
```

#### Token Storage

Tokens are stored in the macOS Keychain:

```swift
final class KeychainManager {
    static let service = "com.kuyruk.oauth"
    
    func saveToken(_ token: String) throws
    func getToken() throws -> String?
    func deleteToken() throws
}
```

## API Endpoints

### Base URL

```
https://api.github.com
```

### Headers

All requests include:

```
Authorization: Bearer {access_token}
Accept: application/vnd.github+json
X-GitHub-Api-Version: 2022-11-28
User-Agent: Kuyruk-macOS/1.0
```

### Rate Limiting

GitHub API limits:
- **Authenticated**: 5,000 requests/hour
- **Conditional requests**: Don't count against limit if response is 304

Handle rate limits gracefully:
- Check `X-RateLimit-Remaining` header
- If rate limited, check `X-RateLimit-Reset` for retry time
- Show user-friendly message with countdown

## Endpoints Used

### List Notifications

```
GET /notifications
```

**Query Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `all` | boolean | Include read notifications |
| `participating` | boolean | Only participating notifications |
| `since` | string | ISO 8601 timestamp |
| `before` | string | ISO 8601 timestamp |
| `per_page` | integer | Results per page (max 100) |
| `page` | integer | Page number |

**Response:**
```json
[
  {
    "id": "1",
    "repository": {
      "id": 1296269,
      "full_name": "octocat/Hello-World",
      "owner": {
        "login": "octocat",
        "avatar_url": "https://github.com/images/error/octocat_happy.gif"
      }
    },
    "subject": {
      "title": "Greetings",
      "url": "https://api.github.com/repos/octocat/Hello-World/issues/1",
      "type": "Issue"
    },
    "reason": "subscribed",
    "unread": true,
    "updated_at": "2024-01-15T12:00:00Z",
    "last_read_at": "2024-01-14T12:00:00Z",
    "url": "https://api.github.com/notifications/threads/1"
  }
]
```

### Mark Thread as Read

```
PATCH /notifications/threads/{thread_id}
```

**Response:** 205 Reset Content (success) or 304 Not Modified

### Mark All as Read

```
PUT /notifications
```

**Request Body:**
```json
{
  "last_read_at": "2024-01-15T12:00:00Z"
}
```

**Response:** 202 Accepted

### Get Issue Details

```
GET /repos/{owner}/{repo}/issues/{issue_number}
```

**Response:**
```json
{
  "number": 1,
  "title": "Found a bug",
  "state": "open",
  "body": "Description of the issue...",
  "user": {
    "login": "octocat",
    "avatar_url": "https://..."
  },
  "labels": [
    { "name": "bug", "color": "d73a4a" }
  ],
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-16T12:00:00Z"
}
```

### Get Pull Request Details

```
GET /repos/{owner}/{repo}/pulls/{pull_number}
```

**Response:**
```json
{
  "number": 123,
  "title": "Add feature X",
  "state": "open",
  "body": "Description...",
  "user": {
    "login": "octocat",
    "avatar_url": "https://..."
  },
  "draft": false,
  "mergeable": true,
  "merged": false,
  "head": { "ref": "feature-branch" },
  "base": { "ref": "main" },
  "created_at": "2024-01-15T12:00:00Z",
  "updated_at": "2024-01-16T12:00:00Z"
}
```

### Get Current User

```
GET /user
```

**Response:**
```json
{
  "login": "octocat",
  "id": 1,
  "avatar_url": "https://github.com/images/error/octocat_happy.gif",
  "name": "monalisa octocat",
  "email": "octocat@github.com"
}
```

## Notification Reasons

| Reason | Description |
|--------|-------------|
| `assign` | You were assigned to the issue |
| `author` | You created the thread |
| `ci_activity` | A workflow run triggered by you |
| `comment` | You commented on the thread |
| `invitation` | You accepted an invitation |
| `manual` | Subscribed manually |
| `mention` | You were @mentioned |
| `review_requested` | Requested to review a PR |
| `security_alert` | Security vulnerability detected |
| `state_change` | Thread state changed |
| `subscribed` | Watching the repository |
| `team_mention` | Your team was @mentioned |

## Subject Types

| Type | Icon | Description |
|------|------|-------------|
| `Issue` | `exclamationmark.circle` | GitHub Issue |
| `PullRequest` | `arrow.triangle.branch` | Pull Request |
| `Commit` | `point.topleft.down.curvedto.point.bottomright.up` | Commit |
| `Release` | `tag` | Release |
| `Discussion` | `bubble.left.and.bubble.right` | Discussion |
| `CheckSuite` | `checkmark.circle` | CI Check Suite |
| `RepositoryInvitation` | `envelope` | Repo invitation |
| `RepositoryVulnerabilityAlert` | `exclamationmark.shield` | Security alert |

## Error Responses

### 401 Unauthorized

```json
{
  "message": "Bad credentials",
  "documentation_url": "https://docs.github.com/rest"
}
```

**Action:** Prompt user to re-authenticate.

### 403 Forbidden

```json
{
  "message": "API rate limit exceeded for user ID 1234567",
  "documentation_url": "https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"
}
```

**Action:** Check `X-RateLimit-Reset` header and retry after reset time.

### 404 Not Found

```json
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest"
}
```

**Action:** Resource doesn't exist or user lacks access.

## Polling Strategy

### Active State
- Poll every 60 seconds when app is in foreground
- Use `If-Modified-Since` header to reduce data transfer
- Update immediately when user triggers refresh

### Background State
- Reduce polling to every 5 minutes
- Use scheduled background refresh (if supported)

### Optimization
- Use `Last-Modified` / `If-Modified-Since` for conditional requests
- Cache responses locally
- Only fetch full details for selected notifications

## Models

### GitHubNotification

```swift
struct GitHubNotification: Identifiable, Codable, Hashable {
    let id: String
    let repository: Repository
    let subject: Subject
    let reason: NotificationReason
    let unread: Bool
    let updatedAt: Date
    let lastReadAt: Date?
    let url: URL
    
    struct Subject: Codable, Hashable {
        let title: String
        let url: URL?
        let type: SubjectType
    }
}
```

### Repository

```swift
struct Repository: Identifiable, Codable, Hashable {
    let id: Int
    let fullName: String
    let owner: Owner
    
    struct Owner: Codable, Hashable {
        let login: String
        let avatarUrl: URL
    }
}
```

### NotificationReason

```swift
enum NotificationReason: String, Codable, CaseIterable {
    case assign
    case author
    case ciActivity = "ci_activity"
    case comment
    case invitation
    case manual
    case mention
    case reviewRequested = "review_requested"
    case securityAlert = "security_alert"
    case stateChange = "state_change"
    case subscribed
    case teamMention = "team_mention"
    
    var displayName: String { ... }
    var icon: String { ... }
    var tintColor: Color { ... }
}
```

## References

- [GitHub REST API Documentation](https://docs.github.com/en/rest)
- [Notifications API](https://docs.github.com/en/rest/activity/notifications)
- [OAuth Apps](https://docs.github.com/en/apps/oauth-apps)
- [Rate Limiting](https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)

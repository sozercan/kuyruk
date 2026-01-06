# ADR-0002: GitHub OAuth Authentication

## Status

Accepted

## Context

Kuyruk needs to authenticate with GitHub to access the Notifications API. Options include:

1. **Personal Access Tokens (PAT)**: User generates token on GitHub, pastes into app
2. **OAuth 2.0 Web Flow**: Standard OAuth with browser redirect
3. **OAuth 2.0 with PKCE**: Enhanced OAuth with Proof Key for Code Exchange
4. **GitHub App Installation**: App installs on user's account

Key considerations:
- Security (tokens should not be exposed)
- User experience (minimal friction to sign in)
- Scope requirements (notifications, repo access)
- Token refresh capabilities

## Decision

We will use **OAuth 2.0 with PKCE** for authentication.

### Implementation

1. **URL Scheme Registration**:
   ```xml
   <!-- Info.plist -->
   <key>CFBundleURLTypes</key>
   <array>
       <dict>
           <key>CFBundleURLSchemes</key>
           <array>
               <string>kuyruk</string>
           </array>
       </dict>
   </array>
   ```

2. **PKCE Flow**:
   ```swift
   @MainActor
   @Observable
   final class AuthService {
       private var codeVerifier: String?
       
       func startOAuth() async throws {
           // Generate PKCE parameters
           codeVerifier = generateCodeVerifier()
           let codeChallenge = generateCodeChallenge(from: codeVerifier!)
           
           // Build authorization URL
           var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
           components.queryItems = [
               URLQueryItem(name: "client_id", value: clientId),
               URLQueryItem(name: "redirect_uri", value: "kuyruk://oauth/callback"),
               URLQueryItem(name: "scope", value: "notifications repo read:user"),
               URLQueryItem(name: "state", value: generateState()),
               URLQueryItem(name: "code_challenge", value: codeChallenge),
               URLQueryItem(name: "code_challenge_method", value: "S256")
           ]
           
           // Open in browser
           NSWorkspace.shared.open(components.url!)
       }
       
       func handleCallback(url: URL) async throws {
           // Exchange code for token with code_verifier
       }
   }
   ```

3. **Token Storage**:
   ```swift
   final class KeychainManager {
       func saveToken(_ token: String) throws {
           let query: [String: Any] = [
               kSecClass as String: kSecClassGenericPassword,
               kSecAttrService as String: "com.kuyruk.oauth",
               kSecAttrAccount as String: "github_token",
               kSecValueData as String: token.data(using: .utf8)!
           ]
           SecItemAdd(query as CFDictionary, nil)
       }
   }
   ```

### Why OAuth with PKCE over PAT?

- Better UX: User doesn't need to navigate to GitHub settings
- More secure: PKCE prevents authorization code interception
- Standard flow: Familiar "Sign in with GitHub" experience
- Scoped access: Can request only needed permissions

### Why not GitHub App?

- More complex setup (requires GitHub App creation)
- Overkill for a personal notification client
- PAT-like experience without the token management benefits

## Consequences

### Positive

- ✅ Secure token exchange with PKCE
- ✅ Familiar OAuth flow for users
- ✅ Tokens stored securely in Keychain
- ✅ Easy to revoke access from GitHub settings
- ✅ Can request granular scopes

### Negative

- ❌ Requires registering OAuth App on GitHub
- ❌ Redirect flow momentarily leaves the app
- ❌ Token refresh not automatic (GitHub tokens don't expire)

### Neutral

- Client ID stored in app (not sensitive)
- No client secret needed with PKCE
- User sees authorization page in browser

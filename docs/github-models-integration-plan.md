# GitHub Models Integration Plan for Kuyruk

## Executive Summary

Integrate GitHub Models AI to provide on-demand TL;DR summaries of notifications in the detail pane. Users can select their preferred model from Settings. Since Kuyruk already authenticates via GitHub OAuth Device Flow, we can reuse the existing token for GitHub Models API calls.

**Key Design Decisions:**

- **On-demand generation** (button-triggered) to conserve rate limits
- **SwiftData persistence** for summary caching across app restarts
- **Separate URLSession** config for `models.github.ai` domain

---

## Phase 0: API Discovery (Mandatory Gate)

> ⚠️ **MANDATORY:** Per AGENTS.md, all new API integrations must be explored via API Explorer before implementation.

### Exit Criteria

- [ ] API Explorer extended with Models commands
- [ ] Existing token tested against `models.github.ai/catalog/models`
- [ ] Certificate pins discovered for `models.github.ai`
- [ ] Rate limit headers documented
- [ ] `docs/api-integration.md` updated with verified payloads

### Tasks

#### 0.1 Extend API Explorer

File: `Sources/APIExplorer/main.swift`

**New commands to add:**

```swift
case "models":
    await Self.listModels(verbose: verbose)
    
case "models-chat":
    guard arguments.count > 2 else {
        print("❌ Error: Missing prompt")
        return
    }
    await Self.chatCompletion(prompt: arguments[2], verbose: verbose)
```

**New helper:**

```swift
static func modelsRequest(_ path: String, method: String = "GET") async throws -> (Data, HTTPURLResponse)
// Target: https://models.github.ai
```

#### 0.2 Run Discovery Commands

```bash
# Test if existing token works with Models API
swift run api-explorer models -v

# Test chat completion
swift run api-explorer models-chat "Summarize: Test notification" -v
```

#### 0.3 Capture Certificate Pins

Run with verbose logging to capture SPKI hashes for `models.github.ai`.

#### 0.4 Document Findings

Update `docs/api-integration.md` with:

- Verified endpoints and response schemas
- Actual rate limit headers and values
- Required scopes (confirmed by testing)

---

## Phase 1: Research & Understanding ✓

### Key Findings

| Aspect | Detail |
|--------|--------|
| **API Endpoint** | `https://models.github.ai/inference/chat/completions` |
| **Authentication** | Bearer token using existing GitHub OAuth access token |
| **Required Headers** | `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28` |
| **Models Catalog** | `https://models.github.ai/catalog/models` |
| **Rate Limits** | To be verified in Phase 0 (approx 15-50 requests/day depending on tier) |
| **Token Scope** | Current scope (`notifications read:user`) - verify in Phase 0 if `models:read` needed |

### Reference Implementation (from Ayna)

| File | Purpose |
|------|---------|
| `GitHubOAuthService.swift` | OAuth with PKCE, model catalog fetching, rate limit tracking |
| `GitHubModelsProvider.swift` | Chat completions API wrapper |
| `OpenAIRequestBuilder.swift` | Request construction with proper headers |

> **Note:** Ayna uses OAuth Web Flow with PKCE. Kuyruk uses **Device Flow** - patterns must be adapted accordingly.

---

## Phase 2: Scope & OAuth Verification

### Exit Criteria

- [ ] Scope compatibility confirmed via Phase 0 testing
- [ ] If needed: scope upgrade flow implemented
- [ ] Certificate pinning configured for `models.github.ai`

### Tasks

#### 2.1 Verify OAuth Scope Compatibility

> **Current Kuyruk scope:** `notifications read:user` (from `AuthService.swift`)
>
> **Note:** `docs/api-integration.md` mentions `notifications repo read:user` - reconcile and update docs.

**Action:** Phase 0 testing will confirm if existing token works. Only proceed with scope changes if 403 errors indicate insufficient scope.

#### 2.2 Scope Upgrade Flow (if required)

**Important:** Kuyruk uses **Device Flow** (not PKCE). Token scopes are fixed at issuance.

If `models:read` is required:

1. Update `OAuthConfig.scope` in `AuthService.swift`:

   ```swift
   static let scope = "notifications read:user models:read"
   ```

2. Add scope detection in `AISettingsView`:

   ```swift
   // If user is authenticated but Models API returns 403
   if authService.state.isAuthenticated && modelsService.scopeInsufficient {
       Button("Re-authenticate to Enable AI") {
           await authService.logout()
           await authService.login()
       }
   }
   ```

3. Update scope audit comment in `OAuthConfig`

#### 2.3 Certificate Pinning for models.github.ai

File: `Sources/Kuyruk/Services/API/CertificatePinningDelegate.swift`

**Option A: Extend existing delegate** (Recommended if same CA chain)

```swift
// Add to allowed hosts check
guard host.hasSuffix("github.com") || 
      host.hasSuffix("githubusercontent.com") ||
      host == "models.github.ai" else {
    completionHandler(.performDefaultHandling, nil)
    return
}
```

**Option B: Separate URLSession for Models**

Create `GitHubModelsService` with its own `URLSession` config if pinning differs.

---

## Phase 3: SwiftData Model for Summary Caching

### Exit Criteria

- [ ] `CachedSummary` SwiftData model created
- [ ] `DataStore` extended with summary methods
- [ ] `swift build` succeeds

### Tasks

#### 3.1 Create `Sources/Kuyruk/Models/CachedSummary.swift`

```swift
import Foundation
import SwiftData

@Model
final class CachedSummary {
    @Attribute(.unique) var notificationId: String
    var notificationUpdatedAt: Date
    var summary: String
    var modelUsed: String
    var generatedAt: Date
    
    init(notificationId: String, notificationUpdatedAt: Date, 
         summary: String, modelUsed: String) {
        self.notificationId = notificationId
        self.notificationUpdatedAt = notificationUpdatedAt
        self.summary = summary
        self.modelUsed = modelUsed
        self.generatedAt = Date()
    }
    
    /// Check if summary is still valid (notification hasn't been updated)
    func isValid(for notification: GitHubNotification) -> Bool {
        notificationUpdatedAt >= notification.updatedAt
    }
}
```

#### 3.2 Extend `Sources/Kuyruk/Services/Persistence/DataStore.swift`

Add to schema:

```swift
let schema = Schema([
    CachedNotification.self,
    CachedRepository.self,
    CachedSummary.self,  // Add this
])
```

Add methods:

```swift
func saveSummary(_ summary: String, for notification: GitHubNotification, model: String) throws
func fetchSummary(for notificationId: String) throws -> CachedSummary?
func invalidateSummary(for notificationId: String) throws
func cleanupOldSummaries(olderThan days: Int = 7) throws
```

---

## Phase 4: Create GitHub Models Service

### Exit Criteria

- [ ] `GitHubModelsService` compiles with stub implementations
- [ ] Model selection persists to UserDefaults/AppStorage
- [ ] Cancellation/single-flight pattern implemented
- [ ] `swift build` succeeds

### New Files to Create

#### 4.1 `Sources/Kuyruk/Services/AI/GitHubModelsService.swift`

**Responsibilities:**

- Fetch available models from catalog (`/catalog/models`)
- Send chat completion requests (on-demand only)
- Handle rate limiting and errors
- Persist selected model preference
- Cancel in-flight requests on new selections
- Single-flight pattern for deduplication

**Key Types:**

```swift
@MainActor @Observable
final class GitHubModelsService {
    // State
    var selectedModel: String? // AppStorage
    var availableModels: [GitHubModel] = []
    var isLoadingModels: Bool = false
    var modelsError: String?
    var scopeInsufficient: Bool = false  // For scope upgrade flow
    
    // Rate Limit State
    var rateLimitRemaining: Int?
    var rateLimitReset: Date?
    
    // Cancellation / Single-flight
    private var currentGenerationTask: Task<String, Error>?
    private var currentNotificationId: String?
    
    // Dependencies
    private let authService: AuthService
    private let dataStore: DataStore
    private let session: URLSession  // Separate from GitHubClient
    
    // Methods
    func fetchAvailableModels() async
    func generateSummary(for notification: GitHubNotification) async throws -> String
    func cancelCurrentGeneration()
}
```

**Cancellation Pattern:**

```swift
func generateSummary(for notification: GitHubNotification) async throws -> String {
    // Cancel previous if different notification
    if currentNotificationId != notification.id {
        currentGenerationTask?.cancel()
    }
    
    // Check SwiftData cache first
    if let cached = try? dataStore.fetchSummary(for: notification.id),
       cached.isValid(for: notification) {
        return cached.summary
    }
    
    // Single-flight: reuse existing task for same notification
    if currentNotificationId == notification.id,
       let existingTask = currentGenerationTask {
        return try await existingTask.value
    }
    
    // Create new task
    currentNotificationId = notification.id
    let task = Task {
        try await performGeneration(for: notification)
    }
    currentGenerationTask = task
    
    return try await task.value
}
```

#### 4.2 `Sources/Kuyruk/Models/GitHubModel.swift`

**Model for catalog response:**

```swift
struct GitHubModel: Codable, Identifiable, Hashable {
    let name: String
    let displayName: String
    let publisher: String
    let modelType: String?
    
    var id: String { name }
}
```

---

## Phase 5: Settings UI Integration

### Exit Criteria

- [ ] New "AI" tab in Settings
- [ ] Model picker shows available models
- [ ] Rate limit status displayed
- [ ] Scope upgrade button if needed
- [ ] `swift build` succeeds

### Files to Modify

#### 5.1 `Sources/Kuyruk/Views/Settings/SettingsView.swift`

**Changes:**

- Add new `AISettingsView` tab
- Environment inject `GitHubModelsService`

**New View: `AISettingsView`**

```swift
struct AISettingsView: View {
    @Environment(GitHubModelsService.self) private var modelsService
    @Environment(AuthService.self) private var authService
    
    @AppStorage("aiSummariesEnabled") private var summariesEnabled: Bool = true
    
    var body: some View {
        Form {
            Section("GitHub Account") {
                // Reuse account status from AccountSettingsView
                // Show "Re-authenticate" button if scopeInsufficient
            }
            
            Section("AI Summaries") {
                Toggle("Enable TL;DR Summaries", isOn: $summariesEnabled)
                
                Picker("Model", selection: $modelsService.selectedModel) {
                    ForEach(modelsService.availableModels) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                .disabled(!summariesEnabled || modelsService.availableModels.isEmpty)
            }
            
            Section("Usage") {
                if let remaining = modelsService.rateLimitRemaining {
                    Label("\(remaining) summaries remaining today", 
                          systemImage: "chart.bar")
                }
                
                if let reset = modelsService.rateLimitReset {
                    Text("Resets at \(reset.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await modelsService.fetchAvailableModels()
        }
    }
}
```

---

## Phase 6: Detail View Integration (On-Demand)

### Exit Criteria

- [ ] "Generate TL;DR" button appears in `NotificationDetailView`
- [ ] Loading/error states handled
- [ ] Summary cached via SwiftData
- [ ] Button disabled when rate limited
- [ ] `swift build` succeeds

### Files to Modify

#### 6.1 `Sources/Kuyruk/Views/Detail/NotificationDetailView.swift`

**Changes:**

- Add `@Environment(GitHubModelsService.self)`
- Add new section: `summarySectionView(for:)`
- **Button-triggered generation** (not auto on selection)
- Cancel generation on notification change via `.task(id:)`

**UI States:**

1. **Disabled** - No model selected or feature disabled, show "Enable AI summaries in Settings"
2. **Ready** - Show "Generate TL;DR" button
3. **Loading** - Show `ProgressView` with "Generating summary..."
4. **Success** - Show summary text in glass card
5. **Error** - Show error with retry button
6. **Rate Limited** - Show when resets, disable button

**Implementation:**

```swift
@State private var isGenerating = false
@State private var summaryError: String?

var summarySection: some View {
    Section {
        if let cached = viewModel.cachedSummary(for: notification) {
            // Show cached summary
            Text(cached.summary)
                .font(.body)
        } else if isGenerating {
            ProgressView("Generating summary...")
        } else if modelsService.rateLimitRemaining == 0 {
            // Rate limited
            Label("Rate limit reached", systemImage: "exclamationmark.triangle")
            if let reset = modelsService.rateLimitReset {
                Text("Resets at \(reset.formatted())")
                    .font(.caption)
            }
        } else {
            // Ready to generate
            Button("Generate TL;DR") {
                Task {
                    isGenerating = true
                    defer { isGenerating = false }
                    do {
                        _ = try await modelsService.generateSummary(for: notification)
                    } catch {
                        summaryError = error.localizedDescription
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    } header: {
        Label("AI Summary", systemImage: "sparkles")
    }
}
```

**Cancellation on selection change:**

```swift
.task(id: notification.id) {
    // Auto-cancels when notification.id changes
    // Reset state for new notification
    isGenerating = false
    summaryError = nil
}
```

**Prompt Engineering:**

```text
System: You are a helpful assistant that summarizes GitHub notifications concisely.
User: Summarize this GitHub notification in 2-3 sentences:
Title: {subject.title}
Type: {subject.type}
Repository: {repository.fullName}
Reason: {reason.displayName}
```

---

## Phase 7: ViewModel Integration

### Exit Criteria

- [ ] `NotificationsViewModel` provides summary access
- [ ] Summaries fetched from SwiftData cache
- [ ] Background refresh doesn't re-summarize

### Files to Modify

#### 7.1 `Sources/Kuyruk/ViewModels/NotificationsViewModel.swift`

**Add:**

```swift
// Summary access (delegates to DataStore)
func cachedSummary(for notification: GitHubNotification) -> CachedSummary? {
    try? dataStore.fetchSummary(for: notification.id)
}

func invalidateSummaryCache() {
    try? dataStore.cleanupOldSummaries(olderThan: 0)
}
```

---

## Phase 8: Environment & App Setup

### Exit Criteria

- [ ] `GitHubModelsService` available in environment
- [ ] Service initialized with `AuthService` and `DataStore`
- [ ] Available in both main window and Settings scenes
- [ ] App compiles and runs

### Files to Modify

#### 8.1 `Sources/Kuyruk/KuyrukApp.swift`

**Add:**

```swift
@State private var modelsService: GitHubModelsService

// In init:
_modelsService = State(initialValue: GitHubModelsService(
    authService: authService,
    dataStore: dataStore
))

// In body, add to environment chain:
.environment(modelsService)
```

**Ensure available in Settings scene** (if separate window).

---

## Phase 9: Quality Assurance

### Exit Criteria

- [ ] All lint/format checks pass
- [ ] Unit tests for `GitHubModelsService` using Swift Testing
- [ ] No rate limit leaks (ensure tracking)
- [ ] Error handling complete

### Tasks

#### 9.1 Run Quality Checks

```bash
swiftformat . && swiftlint --strict
swift build && swift test
```

#### 9.2 Write Unit Tests (Swift Testing)

File: `Tests/KuyrukTests/GitHubModelsServiceTests.swift`

```swift
import Foundation
import Testing

@testable import Kuyruk

@Suite("GitHub Models Service Tests")
struct GitHubModelsServiceTests {
    @Test("Fetches available models")
    func fetchModels() async throws {
        let mockSession = MockURLSession()
        mockSession.mockData = Self.mockModelsResponse
        let service = GitHubModelsService(
            session: mockSession, 
            authService: MockAuthService()
        )
        
        await service.fetchAvailableModels()
        
        #expect(service.availableModels.count > 0)
        #expect(service.isLoadingModels == false)
    }
    
    @Test("Generates summary successfully")
    func generateSummary() async throws {
        let mockSession = MockURLSession()
        mockSession.mockData = Self.mockCompletionResponse
        let service = GitHubModelsService(
            session: mockSession, 
            authService: MockAuthService()
        )
        
        let notification = Self.makeNotification()
        let summary = try await service.generateSummary(for: notification)
        
        #expect(!summary.isEmpty)
    }
    
    @Test("Handles rate limit error")
    func handleRateLimit() async {
        let mockSession = MockURLSession()
        mockSession.mockStatusCode = 429
        mockSession.mockHeaders = [
            "X-RateLimit-Reset": "\(Date().timeIntervalSince1970 + 3600)"
        ]
        let service = GitHubModelsService(
            session: mockSession, 
            authService: MockAuthService()
        )
        
        let notification = Self.makeNotification()
        
        await #expect(throws: GitHubError.rateLimited) {
            try await service.generateSummary(for: notification)
        }
        
        #expect(service.rateLimitReset != nil)
    }
    
    @Test("Cancels in-flight request on new selection")
    func cancellation() async throws {
        let mockSession = SlowMockURLSession(delay: .seconds(5))
        let service = GitHubModelsService(
            session: mockSession, 
            authService: MockAuthService()
        )
        
        let notification1 = Self.makeNotification(id: "1")
        let notification2 = Self.makeNotification(id: "2")
        
        // Start first request
        async let _ = service.generateSummary(for: notification1)
        
        // Immediately request second (should cancel first)
        let summary = try await service.generateSummary(for: notification2)
        
        #expect(!summary.isEmpty)
    }
    
    @Test("Returns cached summary without API call")
    func cacheHit() async throws {
        let mockSession = MockURLSession()
        let mockDataStore = MockDataStore()
        mockDataStore.cachedSummary = CachedSummary(
            notificationId: "test-id",
            notificationUpdatedAt: Date(),
            summary: "Cached summary",
            modelUsed: "gpt-4o"
        )
        
        let service = GitHubModelsService(
            session: mockSession, 
            authService: MockAuthService(),
            dataStore: mockDataStore
        )
        
        let notification = Self.makeNotification(id: "test-id")
        let summary = try await service.generateSummary(for: notification)
        
        #expect(summary == "Cached summary")
        #expect(mockSession.requestCount == 0) // No API call made
    }
}

@Suite(.serialized)
@MainActor
struct GitHubModelsServiceMainActorTests {
    @Test("Updates state on main actor")
    func stateUpdates() async {
        let service = GitHubModelsService(
            session: MockURLSession(), 
            authService: MockAuthService()
        )
        
        #expect(service.isLoadingModels == false)
        await service.fetchAvailableModels()
        #expect(service.isLoadingModels == false)
    }
}

// MARK: - Test Fixtures

extension GitHubModelsServiceTests {
    static let mockModelsResponse = """
    [{"name": "gpt-4o", "displayName": "GPT-4o", "publisher": "OpenAI"}]
    """.data(using: .utf8)!
    
    static let mockCompletionResponse = """
    {"choices": [{"message": {"content": "Test summary"}}]}
    """.data(using: .utf8)!
    
    static func makeNotification(id: String = "test") -> GitHubNotification {
        // Create mock notification
    }
}
```

**Mocking Strategy (no third-party deps):**

- Use `URLProtocol` subclass for session mocking
- Or inject protocol-based session wrapper
- Fixtures derived from API Explorer output with tokens redacted

#### 9.3 Performance Verification

- [ ] Summaries cached in SwiftData (no duplicate API calls)
- [ ] Rate limit checked before requests
- [ ] No `await` inside `ForEach` or list rendering
- [ ] `.task(id:)` used for automatic cancellation
- [ ] Loading states don't block UI

---

## Architecture Decision Record (ADR)

Create: `docs/adr/0006-github-models-integration.md`

**Content:**

- **Decision:** Use GitHub Models for AI-powered notification summaries
- **Context:** Users want quick understanding of notifications without opening browser
- **Rationale:** 
  - GitHub Models reuses existing OAuth, no additional API key needed
  - Native Swift networking, no third-party AI SDKs
  - On-demand generation conserves rate limits
- **Consequences:** 
  - Rate limits apply (verify in Phase 0)
  - Model availability may vary
  - Users must re-authenticate if scope upgrade needed

---

## File Summary

| Action | Path |
|--------|------|
| Modify | `Sources/APIExplorer/main.swift` (add Models commands) |
| Create | `Sources/Kuyruk/Models/GitHubModel.swift` |
| Create | `Sources/Kuyruk/Models/CachedSummary.swift` |
| Create | `Sources/Kuyruk/Services/AI/GitHubModelsService.swift` |
| Create | `Sources/Kuyruk/Views/Settings/AISettingsView.swift` |
| Create | `Tests/KuyrukTests/GitHubModelsServiceTests.swift` |
| Create | `docs/adr/0006-github-models-integration.md` |
| Modify | `Sources/Kuyruk/Services/Auth/AuthService.swift` (scope, if needed) |
| Modify | `Sources/Kuyruk/Services/API/CertificatePinningDelegate.swift` (add models.github.ai) |
| Modify | `Sources/Kuyruk/Services/Persistence/DataStore.swift` (add CachedSummary) |
| Modify | `Sources/Kuyruk/Views/Settings/SettingsView.swift` (add AI tab) |
| Modify | `Sources/Kuyruk/Views/Detail/NotificationDetailView.swift` (summary button) |
| Modify | `Sources/Kuyruk/ViewModels/NotificationsViewModel.swift` (cache access) |
| Modify | `Sources/Kuyruk/KuyrukApp.swift` (environment) |
| Modify | `docs/api-integration.md` (document Models API) |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Rate limits (verify in Phase 0) | On-demand button (not auto), show remaining count, cache in SwiftData |
| OAuth scope change | Scope upgrade flow with "Re-authenticate" button; test first |
| Model availability | Fetch catalog on launch, show graceful fallback |
| Response latency | Show loading state, don't block detail view |
| Token expiration | Reuse existing token validation from `AuthService` |
| Certificate pinning | Discover pins via API Explorer, extend existing delegate |
| Rapid selection changes | `.task(id:)` auto-cancellation + single-flight pattern |

---

## Dependencies

**None required** - The implementation uses only Foundation and native Swift networking without third-party AI SDKs.

---

## Estimated Effort

| Phase | Effort |
|-------|--------|
| Phase 0: API Discovery | 0.5 day |
| Phase 2: OAuth/Pinning | 0.5 day |
| Phase 3: SwiftData Model | 0.5 day |
| Phase 4: Models Service | 1 day |
| Phase 5: Settings UI | 0.5 day |
| Phase 6: Detail View | 1 day |
| Phase 7: ViewModel | 0.25 day |
| Phase 8: App Setup | 0.25 day |
| Phase 9: QA & Tests | 1 day |
| **Total** | **~5.5 days** |

---

## Reviewer Feedback Incorporated

| Reviewer Point | Action Taken |
|----------------|--------------|
| Mandatory API discovery | Added Phase 0 as gate before implementation |
| Device Flow (not PKCE) | Corrected references, added scope upgrade flow |
| On-demand generation | Changed to button-triggered, not auto on selection |
| Separate URLSession for models.github.ai | Added to Phase 2 with pinning options |
| SwiftData for caching | Added Phase 3, `CachedSummary` model |
| Cancellation/single-flight | Added pattern in Phase 4 service design |
| Swift Testing patterns | Updated Phase 9 with `@Suite`, `@Test`, `#expect` |
| Scope inconsistency in docs | Added reconciliation task in Phase 2 |

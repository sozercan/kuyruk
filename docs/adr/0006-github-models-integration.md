# ADR-0006: GitHub Models Integration for AI Summaries

## Status

Accepted

## Context

Users of Kuyruk receive many GitHub notifications daily, and understanding the context of each notification often requires clicking through to GitHub. This creates friction in the workflow, especially for high-volume contributors who need to quickly triage their notification inbox.

We identified an opportunity to provide AI-generated TL;DR summaries directly within the notification detail view, allowing users to quickly understand the essence of each notification without leaving the app.

Key considerations:

1. **Authentication**: We need a way to authenticate with an AI service
2. **API Selection**: Multiple AI providers exist (OpenAI, Anthropic, local models, GitHub Models)
3. **Rate Limits**: AI APIs typically have rate limits that need to be managed
4. **Caching**: Summaries should be cached to avoid redundant API calls
5. **User Control**: Users should control when summaries are generated (cost/rate concerns)

## Decision

We will integrate **GitHub Models API** for AI-powered notification summaries with the following design:

### 1. Use GitHub Models API

- **Endpoint**: `https://models.github.ai/inference/chat/completions`
- **Authentication**: Reuse existing GitHub OAuth access token (no additional API key required)
- **Model Catalog**: Fetch available models from `/catalog/models`

### 2. On-Demand Generation (Button-Triggered)

- Summaries are **not** generated automatically when selecting a notification
- Users must click "Generate TL;DR" button to request a summary
- This conserves rate limits and gives users control over API usage

### 3. SwiftData Persistence for Caching

- Create `CachedSummary` SwiftData model to persist summaries across app restarts
- Cache invalidation based on notification `updatedAt` timestamp
- Automatic cleanup of summaries older than 7 days

### 4. Single-Flight Pattern with Cancellation

- Only one summary generation request can be in-flight at a time
- Selecting a different notification cancels the previous request
- Prevents wasted API calls and ensures responsive UI

### 5. Dedicated URLSession

- Separate `URLSession` configuration for `models.github.ai` domain
- Certificate pinning configuration shared with existing GitHub API patterns
- Rate limit tracking via response headers

### 6. Settings UI

- New "AI" tab in Settings for model selection
- Display available models from catalog
- Show rate limit remaining/reset information
- Toggle to enable/disable AI summaries feature

## Alternatives Considered

### OpenAI API Directly

**Pros:**
- Well-documented, reliable API
- Wide model selection

**Cons:**
- Requires separate API key management
- Additional authentication flow for users
- Cost implications for users

### Local LLM (e.g., llama.cpp, Ollama)

**Pros:**
- No API costs
- Privacy (data stays local)
- No rate limits

**Cons:**
- Significant binary size increase
- Requires model downloads (several GB)
- Performance varies by hardware
- Complex integration

### Anthropic Claude API

**Pros:**
- High-quality summaries
- Good rate limits

**Cons:**
- Requires separate API key
- No existing authentication integration

### GitHub Copilot Extensions

**Pros:**
- Deep GitHub integration

**Cons:**
- Requires Copilot subscription
- Complex extension architecture
- Not suitable for simple summarization

## Consequences

### Positive

1. **Zero Configuration**: Users don't need to obtain or manage separate API keys
2. **Consistent Authentication**: Reuses existing OAuth token flow
3. **Native Swift**: No third-party AI SDKs required, just URLSession
4. **Cached Summaries**: SwiftData persistence means summaries survive app restarts
5. **User Control**: On-demand generation respects user's rate limits
6. **Model Choice**: Users can select their preferred model from the catalog

### Negative

1. **Rate Limits**: GitHub Models API has usage limits (varies by model tier)
2. **Token Scope**: May require users to re-authenticate if `models:read` scope is needed
3. **Model Availability**: Available models may change over time
4. **Latency**: API calls add latency to the UX (mitigated by loading states)
5. **GitHub Dependency**: Feature requires GitHub Models service availability

### Neutral

1. **Prompt Engineering**: Summary quality depends on prompt design (documented in code)
2. **Error Handling**: Graceful degradation when API unavailable or rate limited

## Implementation Notes

### Files Created/Modified

| File | Purpose |
|------|---------|
| `Sources/Kuyruk/Models/GitHubModel.swift` | Model catalog response type |
| `Sources/Kuyruk/Models/CachedSummary.swift` | SwiftData cache model |
| `Sources/Kuyruk/Services/AI/GitHubModelsService.swift` | API client for GitHub Models |
| `Sources/Kuyruk/Views/Settings/AISettingsView.swift` | Settings UI for AI configuration |
| `Tests/KuyrukTests/GitHubModelsServiceTests.swift` | Unit tests |

### Rate Limit Strategy

1. Check `X-RateLimit-Remaining` header after each request
2. Display remaining count in Settings and near generate button
3. Disable generate button when rate limited
4. Show reset time to user

### Cache Invalidation Logic

```swift
func isValid(for notification: GitHubNotification) -> Bool {
    notificationUpdatedAt >= notification.updatedAt
}
```

A cached summary is considered stale if the notification has been updated since the summary was generated.

## References

- [GitHub Models Documentation](https://docs.github.com/en/github-models)
- [ADR-0005: SwiftData Persistence](0005-swiftdata-persistence.md)
- [ADR-0002: GitHub OAuth Authentication](0002-github-oauth-authentication.md)

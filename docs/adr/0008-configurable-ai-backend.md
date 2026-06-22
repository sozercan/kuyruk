# ADR-0008: Configurable AI Backend (BYO OpenAI-compatible proxy)

## Status

Accepted

## Context

[ADR-0006](0006-github-models-integration.md) established the GitHub Models API
(`https://models.github.ai`) as Kuyruk's AI backend, authenticated with the user's
existing GitHub OAuth token. Users asked whether the app could instead use the **GitHub
Copilot API** (e.g. to use their Copilot subscription / a wider model catalog).

Investigation (verified against `sozercan/vekil`, a Go reverse proxy that exposes Copilot
over an OpenAI-compatible API) found that a *direct, in-app* Copilot integration is
problematic:

- The Copilot token exchange (`api.github.com/copilot_internal/v2/token`) is gated to
  GitHub's first-party Copilot OAuth client id; Kuyruk's own app id is not allow-listed.
  Using it would require adopting the first-party client id and spoofing VS Code editor
  headers — **client impersonation** that plausibly violates the Copilot Terms /
  Acceptable Use and risks account action.
- It requires an active Copilot entitlement (GitHub Models requires none).
- The `notifications` scope Kuyruk needs and Copilot's `read:user` cannot share one token,
  forcing a second parallel auth flow.

We did not want to ship that risk in Kuyruk's binary, but we did want to unblock users who
have their own way to reach Copilot (or any other model server).

## Decision

Make the AI backend **user-configurable**, keeping **GitHub Models as the default**.

- Add an `AIBackend` setting: `githubModels` (default) or `custom`.
- For `custom`, the user supplies an **OpenAI-compatible base URL** (e.g. a locally-run
  `vekil` instance, `http://localhost:1337/v1`) and an optional API key. The app appends
  the standard `/chat/completions` and `/models` paths.
- The existing inference path is already OpenAI-shaped
  (`{model, messages, max_tokens}` → `choices[].message.content`), so the change is
  confined to base URL, catalog endpoint shape, headers, and the auth token. Backend
  selection is resolved once per request in `GitHubModelsService`.
- The API key is stored in the **Keychain** (a secret), the backend choice and base URL in
  `UserDefaults`.
- `NSAllowsLocalNetworking` is enabled so a `localhost` proxy works without weakening App
  Transport Security or certificate pinning for the real GitHub hosts (pinning is
  host-scoped and already falls through to system trust for non-GitHub hosts).

Switching backends invalidates cached summaries, because analyses are keyed by notification
id (not by backend/model) and would otherwise show the previous backend's output until each
thread next updates.

### Why BYO-proxy rather than in-app Copilot

The proxy approach moves *all* of the impersonation / token-exchange / certificate-pinning
risk **out of Kuyruk** and onto a server the user runs by explicit choice. `vekil` (same
author) is itself that proxy. Kuyruk ships no Copilot-specific code, no first-party client
id, and no editor-header spoofing.

## Consequences

### Easier

- Users with their own OpenAI-compatible endpoint (vekil/Copilot, a self-hosted model
  server, etc.) can use it with a base URL + key.
- No Terms-of-Service or account-suspension exposure in the shipped app.
- GitHub Models remains the zero-config default; existing users are unaffected.

### More difficult / trade-offs

- Custom endpoints are unpinned (system TLS only); a self-signed HTTPS proxy is out of
  scope (use HTTP loopback or a valid certificate).
- The custom base URL is not validated beyond URL parsing; a bad endpoint surfaces as a
  model-fetch/generation error in Settings.
- Responsibility for any Copilot ToS implications shifts to the user running the proxy.

## References

- [ADR-0006: GitHub Models Integration for AI Summaries](0006-github-models-integration.md)
- `Sources/Kuyruk/Models/AIBackend.swift`
- `Sources/Kuyruk/Services/AI/GitHubModelsService.swift` — backend resolution, request building
- `Sources/Kuyruk/Views/Settings/AISettingsView.swift` — backend picker + custom fields
- [sozercan/vekil](https://github.com/sozercan/vekil) — OpenAI-compatible Copilot proxy

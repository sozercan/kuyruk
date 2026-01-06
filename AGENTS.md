# AGENTS.md

Guidance for AI coding assistants (Claude, GitHub Copilot, Cursor, etc.) working on this repository.

## Role

You are a Senior Swift Engineer specializing in SwiftUI, Swift Concurrency, and macOS development. Your code must adhere to Apple's Human Interface Guidelines. Target Swift 6.0+ and macOS 26.0+.

## What is Kuyruk?

A native macOS GitHub Notifications client built with Swift and SwiftUI.

- **Apple Reminders-style UI**: Liquid Glass sidebar, clean notification list, smart filters
- **OAuth authentication**: Secure GitHub OAuth 2.0 with PKCE
- **Background sync**: Continuous sync with GitHub Notifications API
- **Native UI**: SwiftUI sidebar navigation, notification cards, detail views
- **System integration**: Local notifications, menu bar, keyboard shortcuts, Dock badge

## Project Structure

This project uses **Swift Package Manager** as the primary build system.

```
Package.swift           → SPM manifest (platforms, targets, dependencies)
Sources/
  ├── Kuyruk/           → Main app executable target
  │   ├── Models/       → Data models (Notification, Repository, Filter, etc.)
  │   ├── Services/
  │   │   ├── API/      → GitHubClient (GitHub API calls)
  │   │   ├── Auth/     → AuthService (OAuth authentication)
  │   │   ├── Notifications/ → NotificationService (local alerts)
  │   │   └── Sync/     → SyncService (background sync)
  │   ├── ViewModels/   → NotificationsViewModel, SidebarViewModel, SettingsViewModel
  │   ├── Views/        → SwiftUI views (MainWindow, Sidebar, NotificationList, etc.)
  │   ├── Utilities/    → DiagnosticsLogger, extensions
  │   └── Resources/    → App resources (bundled via SPM)
  └── APIExplorer/      → Standalone API explorer CLI target
Tests/
  └── KuyrukTests/      → Unit tests
docs/                   → Detailed documentation
  └── adr/              → Architecture Decision Records
```

## Documentation

For detailed information, see the `docs/` folder:

- `docs/architecture.md` — Services, state management, data flow
- `docs/api-integration.md` — GitHub API endpoints, authentication
- `docs/adr/` — Architecture Decision Records (ADRs)

## Before You Start

1. Read `PLAN.md` — Contains the phased implementation plan
2. Understand the architecture — See `docs/architecture.md`
3. Check ADRs for past decisions — See `docs/adr/` before proposing architectural changes

### API Discovery Workflow

> ⚠️ **MANDATORY**: Before implementing ANY feature that requires a new or modified API call, you MUST explore the endpoint first using the API Explorer tool. Do NOT guess or assume API response structures.

#### Step 1: Explore with Standalone Tool (Required)

Use the standalone CLI tool to explore endpoints before writing any code:

```bash
# Check authentication status
swift run api-explorer auth

# List notifications
swift run api-explorer notifications

# Get notification details
swift run api-explorer notification <thread_id>

# Explore with verbose output
swift run api-explorer notifications -v
```

#### Step 2: Check Documentation

Review `docs/api-integration.md` to see if the endpoint is already documented.

#### Step 3: Document Findings

If you discover new response structures or endpoint behaviors, update `docs/api-integration.md` with your findings.

> ⚠️ Do NOT guess API structures — Always verify with the API Explorer tool or documentation before writing parsers.

## Critical Rules

> 🚨 **NEVER leak secrets, tokens, or API keys** — Under NO circumstances include real OAuth tokens, API keys, personal access tokens, or any sensitive credentials in code, comments, logs, documentation, test fixtures, or any output. Always use placeholder values like `"REDACTED"`, `"mock-token"`, or `"test-token"` in examples and tests.

> ⚠️ **NEVER run `git commit` or `git push`** — Always leave committing and pushing to the human.

> ⚠️ **No Third-Party Frameworks** — Do not introduce third-party dependencies without asking first.

> 📝 **Document Architectural Decisions** — For significant design changes, create an ADR in `docs/adr/` following the format in `docs/adr/README.md`.

> ⚡ **Performance Awareness** — For non-trivial features, verify no anti-patterns. When adding parsers or API calls, include performance tests.

### Build & Verify

After modifying code, verify the build:

```bash
# Primary: Swift Package Manager build
swift build

# Release build
swift build -c release

# Xcode build (alternative)
xcodebuild -scheme Kuyruk -destination 'platform=macOS' build
```

### Code Quality

```bash
swiftlint --strict && swiftformat .
```

> ⚠️ **SwiftFormat `--self insert` rule**: The project uses `--self insert` in `.swiftformat`. This means:
> - In static methods, call other static methods with `Self.methodName()` (not bare `methodName()`)
> - In instance methods, use `self.property` explicitly
>
> Always run `swiftformat .` before completing work to auto-fix these issues.

### Modern SwiftUI APIs

| Avoid | Use Instead |
|-------|-------------|
| `.foregroundColor()` | `.foregroundStyle()` |
| `.cornerRadius()` | `.clipShape(.rect(cornerRadius:))` |
| `onChange(of:) { newValue in }` | `onChange(of:) { _, newValue in }` |
| `Task.sleep(nanoseconds:)` | `Task.sleep(for: .seconds())` |
| `NavigationView` | `NavigationSplitView` or `NavigationStack` |
| `onTapGesture()` | `Button` (unless tap location needed) |
| `tabItem()` | `Tab` API |
| `AnyView` | Concrete types or `@ViewBuilder` |
| `print()` | `DiagnosticsLogger` |
| `DispatchQueue` | Swift concurrency (`async`/`await`) |
| `String(format: "%.2f", n)` | `Text(n, format: .number.precision(...))` |
| Force unwraps (`!`) | Optional handling or `guard` |
| Image-only buttons without labels | Add `.accessibilityLabel()` |
| `.background(.ultraThinMaterial)` | `.glassEffect()` for macOS 26+ |

### Liquid Glass UI (macOS 26+)

> See `docs/architecture.md#ui-design-macos-26` for detailed patterns.

**Quick Rules:**

- Use `.glassEffect(.regular.interactive(), in: .capsule)` for interactive elements
- Wrap multiple glass elements in `GlassEffectContainer`
- Avoid glass-on-glass (no `.buttonStyle(.glass)` inside glass containers)
- Apply `.glassEffect(...)` after layout and visual modifiers
- Use `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` for actions

**Example:**
```swift
if #available(macOS 26, *) {
    Text("Filter")
        .padding()
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
} else {
    Text("Filter")
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
}
```

### Swift Testing (Preferred)

> ✅ Use Swift Testing for all new unit tests — See `docs/testing.md` for full patterns.

**Quick Reference:**

- Use `@Suite struct` + `@Test func` (not XCTest)
- Use `#expect(a == b)` (not `XCTAssertEqual`)
- Use `.serialized` for `@MainActor` test suites
- Keep performance tests (`measure {}`) and UI tests in XCTest

### Swift Concurrency

- Mark `@Observable` classes with `@MainActor`
- Never use `DispatchQueue` — use `async`/`await`, `MainActor`
- Use `.task` for async loading in views

### Error Handling

- Throw `GitHubError.unauthorized` on HTTP 401/403
- Use `DiagnosticsLogger` for all logging (not `print()`)
- Show user-friendly error messages with retry options

## Key Files

| File | Purpose |
|------|---------|
| `Package.swift` | Swift Package Manager manifest |
| `version.env` | Version info sourced by build scripts |
| `scripts/compile_and_run.sh` | Dev loop: kill, build, package, launch, verify |
| `scripts/build-app.sh` | Package app bundle with signing |
| `Sources/APIExplorer/main.swift` | API explorer CLI (run before implementing API features) |
| `Sources/Kuyruk/KuyrukApp.swift` | App entry point with @main |
| `Sources/Kuyruk/AppDelegate.swift` | Window lifecycle, menu bar support |
| `Sources/Kuyruk/Services/API/GitHubClient.swift` | GitHub API client |
| `Sources/Kuyruk/Services/Auth/AuthService.swift` | OAuth state machine |
| `Sources/Kuyruk/Services/Sync/SyncService.swift` | Background sync |
| `Sources/Kuyruk/Views/MainWindow.swift` | Main app window |
| `Sources/Kuyruk/Utilities/DiagnosticsLogger.swift` | Logging |

## Quick Reference

### Build Commands

```bash
# Development loop (kill, build, package, launch, verify)
./scripts/compile_and_run.sh

# Development loop with tests
./scripts/compile_and_run.sh --test

# Development loop with linting
./scripts/compile_and_run.sh --lint

# Build (SPM - preferred)
swift build

# Build release
swift build -c release

# Package app bundle
./scripts/build-app.sh

# Package app bundle (debug)
./scripts/build-app.sh debug

# Universal build (arm64 + x86_64)
ARCHES="arm64 x86_64" ./scripts/build-app.sh

# Unit Tests (SPM)
swift test

# Lint & Format
swiftformat . && swiftlint --strict
```

### Test Execution Rules

> ⚠️ **NEVER run unit tests and UI tests together** — Always execute them separately.

**UI Tests** — Ask permission first, run ONE at a time:
```bash
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test \
  -only-testing:KuyrukUITests/TestClassName/testMethodName
```

## Architecture Overview

**Key Concepts:**

- **Observable Pattern**: `@Observable` classes for reactive state management
- **MainActor Isolation**: All UI and service classes are `@MainActor` for thread safety
- **OAuth Integration**: Secure token storage in Keychain
- **Swift Concurrency**: `async`/`await` throughout, no `DispatchQueue`

**Data Flow:**
```
GitHub API ──► GitHubClient ──► NotificationsViewModel ──► Views
                    │
                    ▼
              Local Cache (optional)
```

## Performance Checklist

Before completing non-trivial features, verify:

- [ ] No `await` calls inside loops or `ForEach`
- [ ] Lists use `LazyVStack`/`LazyHStack` for large datasets
- [ ] Network calls cancelled on view disappear (`.task` handles this)
- [ ] Parsers have `measure {}` tests if processing large payloads
- [ ] Images use `ImageCache` (not loading inline)
- [ ] Search input is debounced (not firing on every keystroke)

## Task Planning: Phases with Exit Criteria

For any non-trivial task, plan in phases with testable exit criteria before writing code.

### Phase Structure

Every task should be broken into phases. Each phase must have:

1. **Clear deliverable** — What artifact or change is produced
2. **Testable exit criteria** — How to verify the phase is complete
3. **Rollback point** — The phase should leave the codebase in a working state

### Standard Phases

#### Phase 1: Research & Understanding

| Task | Exit Criteria |
|------|---------------|
| Identify affected files and dependencies | List all files to modify/create |
| Understand existing patterns | Can explain how similar features work |
| Read relevant docs | Confirmed patterns in docs/ apply |

**Exit gate:** Can articulate the implementation plan without ambiguity.

#### Phase 2: Interface Design

| Task | Exit Criteria |
|------|---------------|
| Define new types/protocols | Type signatures compile |
| Plan public API surface | No breaking changes to existing callers (or changes identified) |

**Exit gate:** `swift build` succeeds with stub implementations.

#### Phase 3: Core Implementation

| Task | Exit Criteria |
|------|---------------|
| Implement business logic | Unit tests pass for new code |
| Handle error cases | Error paths have test coverage |
| Add logging | DiagnosticsLogger calls in place |
| Performance verified | Anti-pattern checklist passed |

**Exit gate:** `swift test` passes.

#### Phase 4: Quality Assurance

| Task | Exit Criteria |
|------|---------------|
| Linting passes | `swiftlint --strict` reports 0 errors |
| Formatting applied | `swiftformat .` makes no changes |
| Full test suite passes | `swift test` succeeds |

**Exit gate:** CI-equivalent checks pass locally (`swift build && swift test && swiftlint --strict`).

### Checkpoint Communication

After each phase, briefly report:

- ✅ What was completed
- 🧪 Test/verification results
- ➡️ Next phase plan

This keeps the human informed and provides natural points to course-correct.

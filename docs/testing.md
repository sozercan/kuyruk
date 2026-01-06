# Testing

This document describes testing patterns and commands for Kuyruk.

## Quick Reference

```bash
# Run all unit tests
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test -only-testing:KuyrukTests

# Run specific test class
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test \
  -only-testing:KuyrukTests/GitHubClientTests

# Run specific test method
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test \
  -only-testing:KuyrukTests/GitHubClientTests/testFetchNotifications

# Run tests with verbose output
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test \
  -only-testing:KuyrukTests 2>&1 | xcpretty
```

## Swift Testing (Preferred)

All new tests should use Swift Testing framework instead of XCTest.

### Basic Test Structure

```swift
import Testing
@testable import Kuyruk

@Suite("GitHub Client Tests")
struct GitHubClientTests {
    @Test("Fetches notifications successfully")
    func fetchNotifications() async throws {
        let mockSession = MockURLSession()
        mockSession.mockData = mockNotificationsJSON.data(using: .utf8)
        
        let client = GitHubClient(session: mockSession)
        let notifications = try await client.fetchNotifications()
        
        #expect(notifications.count == 2)
        #expect(notifications[0].unread == true)
    }
    
    @Test("Handles unauthorized error")
    func handleUnauthorized() async {
        let mockSession = MockURLSession()
        mockSession.mockStatusCode = 401
        
        let client = GitHubClient(session: mockSession)
        
        await #expect(throws: GitHubError.unauthorized) {
            try await client.fetchNotifications()
        }
    }
}
```

### MainActor Tests

For tests that require MainActor isolation, use `.serialized`:

```swift
@Suite(.serialized)
@MainActor
struct NotificationsViewModelTests {
    @Test("Updates notifications on fetch")
    func updateNotifications() async throws {
        let viewModel = NotificationsViewModel(client: MockGitHubClient())
        
        await viewModel.fetchNotifications()
        
        #expect(viewModel.notifications.count > 0)
        #expect(viewModel.isLoading == false)
    }
}
```

### Parameterized Tests

```swift
@Test("Maps notification reason correctly", arguments: [
    ("mention", NotificationReason.mention),
    ("review_requested", NotificationReason.reviewRequested),
    ("assign", NotificationReason.assign)
])
func mapReason(rawValue: String, expected: NotificationReason) {
    let reason = NotificationReason(rawValue: rawValue)
    #expect(reason == expected)
}
```

## Mocking

### MockURLSession

```swift
final class MockURLSession: URLSessionProtocol {
    var mockData: Data?
    var mockStatusCode: Int = 200
    var mockError: Error?
    
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
        }
        
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: mockStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        
        return (mockData ?? Data(), response)
    }
}
```

### MockGitHubClient

```swift
@MainActor
final class MockGitHubClient: GitHubClientProtocol {
    var mockNotifications: [GitHubNotification] = []
    var shouldThrow: Error?
    
    func fetchNotifications(all: Bool) async throws -> [GitHubNotification] {
        if let error = shouldThrow {
            throw error
        }
        return mockNotifications
    }
}
```

## Test Fixtures

Store test fixtures in `Tests/KuyrukTests/Fixtures/`:

```
Tests/
└── KuyrukTests/
    ├── Fixtures/
    │   ├── notifications.json
    │   ├── issue.json
    │   └── pull_request.json
    └── ...
```

Load fixtures:

```swift
extension XCTestCase {
    func loadFixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw TestError.fixtureNotFound(name)
        }
        return try Data(contentsOf: url)
    }
}
```

## UI Tests

> ⚠️ **Always ask permission before running UI tests** — They launch the app and can be disruptive.

### Running UI Tests

```bash
# Run ONE specific UI test
xcodebuild -scheme Kuyruk -destination 'platform=macOS' test \
  -only-testing:KuyrukUITests/SidebarUITests/testFilterSelection
```

### UI Test Structure

```swift
import XCTest

final class SidebarUITests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    func testFilterSelection() throws {
        let inbox = app.outlineRows["Inbox"]
        XCTAssertTrue(inbox.exists)
        
        inbox.click()
        
        let list = app.tables["NotificationList"]
        XCTAssertTrue(list.exists)
    }
}
```

## Performance Tests

Keep performance tests in XCTest (not Swift Testing):

```swift
final class PerformanceTests: XCTestCase {
    func testParsingPerformance() throws {
        let data = try loadFixture("large_notifications")
        
        measure {
            _ = try? JSONDecoder().decode([GitHubNotification].self, from: data)
        }
    }
}
```

## Test Categories

### Unit Tests (KuyrukTests/)

| Category | Description |
|----------|-------------|
| `GitHubClientTests` | API client, parsing, error handling |
| `AuthServiceTests` | OAuth flow, token management |
| `NotificationsViewModelTests` | View model state, filtering |
| `ModelTests` | Data model encoding/decoding |

### UI Tests (KuyrukUITests/)

| Category | Description |
|----------|-------------|
| `SidebarUITests` | Filter selection, navigation |
| `NotificationListUITests` | Scrolling, selection, swipe actions |
| `SettingsUITests` | Settings screen interactions |

## Debugging Tests

### Print Test Output

```bash
xcodebuild test ... 2>&1 | tee test_output.log
```

### Run in Xcode

1. Open `Kuyruk.xcodeproj`
2. Select test file in Project Navigator
3. Click diamond icon next to test method
4. Use breakpoints for debugging

### Common Issues

**Tests fail with MainActor errors:**
- Ensure test class is marked with `@MainActor`
- Use `.serialized` trait for the suite
- Don't call `super.setUp()` in async context

**Mocks not being used:**
- Verify dependency injection is correct
- Check that protocols are used, not concrete types

**Flaky tests:**
- Add explicit waits for async operations
- Use `#expect` with proper async handling
- Avoid time-dependent assertions

## Coverage

```bash
# Generate coverage report
xcodebuild test \
  -scheme Kuyruk \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult

# View coverage in Xcode
open TestResults.xcresult
```

Target: **>70% code coverage** for services and view models.

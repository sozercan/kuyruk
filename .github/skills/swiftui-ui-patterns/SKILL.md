---
name: swiftui-ui-patterns
description: Best practices and example-driven guidance for building SwiftUI views and components. Use when creating or refactoring SwiftUI UI, designing navigation architecture with NavigationSplitView, composing screens, or needing component-specific patterns and examples.
---

# SwiftUI UI Patterns

## Quick start

Choose a track based on your goal:

### Existing project

- Identify the feature or screen and the primary interaction model (list, detail, editor, settings, tabbed).
- Find a nearby example in the repo with `rg "NavigationSplitView"` or similar, then read the closest SwiftUI view.
- Apply local conventions: prefer SwiftUI-native state, keep state local when possible, and use environment injection for shared dependencies.
- Build the view with small, focused subviews and SwiftUI-native data flow.

### New feature scaffolding

- Start with the navigation pattern that fits (NavigationSplitView for sidebar apps, NavigationStack for linear flows).
- Choose the relevant component pattern based on the UI you need first.
- Expand as new screens are added.

## General rules to follow

- Use modern SwiftUI state (`@State`, `@Binding`, `@Observable`, `@Environment`) and avoid unnecessary view models.
- Prefer composition; keep views small and focused.
- Use async/await with `.task` and explicit loading/error states.
- Maintain existing project patterns when editing files.
- Follow the project's formatter and style guide.
- **Sheets**: Prefer `.sheet(item:)` over `.sheet(isPresented:)` when state represents a selected model. Avoid `if let` inside a sheet body. Sheets should own their actions and call `dismiss()` internally instead of forwarding `onCancel`/`onConfirm` closures.

## Workflow for a new SwiftUI view

1. Define the view's state and its ownership location.
2. Identify dependencies to inject via `@Environment`.
3. Sketch the view hierarchy and extract repeated parts into subviews.
4. Implement async loading with `.task` and explicit state enum if needed.
5. Add accessibility labels or identifiers when the UI is interactive.
6. Validate with a build and update usage callsites if needed.

## Component patterns

### NavigationSplitView (macOS sidebar apps)

```swift
NavigationSplitView {
    SidebarView()
} content: {
    ContentListView()
} detail: {
    DetailView()
}
```

### NavigationStack (linear flows)

```swift
NavigationStack(path: $path) {
    RootView()
        .navigationDestination(for: Route.self) { route in
            destination(for: route)
        }
}
```

### Sheet patterns

#### Item-driven sheet (preferred)

```swift
@State private var selectedItem: Item?

.sheet(item: $selectedItem) { item in
    EditItemSheet(item: item)
}
```

#### Sheet owns its actions

```swift
struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Store.self) private var store

    let item: Item
    @State private var isSaving = false

    var body: some View {
        VStack {
            Button(isSaving ? "Saving..." : "Save") {
                Task { await save() }
            }
        }
    }

    private func save() async {
        isSaving = true
        await store.save(item)
        dismiss()
    }
}
```

### Form and Settings

```swift
Form {
    Section("General") {
        Toggle("Enable notifications", isOn: $enableNotifications)
        Picker("Theme", selection: $theme) {
            ForEach(Theme.allCases) { theme in
                Text(theme.rawValue).tag(theme)
            }
        }
    }
    
    Section("About") {
        LabeledContent("Version", value: appVersion)
    }
}
```

### List and Section

```swift
List {
    Section("Recent") {
        ForEach(recentItems) { item in
            ItemRow(item: item)
        }
    }
    
    Section("All") {
        ForEach(allItems) { item in
            ItemRow(item: item)
        }
    }
}
```

### LazyVStack for large datasets

```swift
ScrollView {
    LazyVStack(spacing: 8) {
        ForEach(items) { item in
            ItemRow(item: item)
        }
    }
}
```

## macOS-specific patterns

### Settings scene

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        
        Settings {
            SettingsView()
        }
    }
}
```

### Menu bar support

```swift
MenuBarExtra("App Name", systemImage: "bell.fill") {
    MenuBarView()
}
.menuBarExtraStyle(.window)
```

### Keyboard shortcuts

```swift
Button("Refresh") {
    refresh()
}
.keyboardShortcut("r", modifiers: .command)
```

## State management patterns

### Loading state enum

```swift
enum LoadingState<T> {
    case idle
    case loading
    case loaded(T)
    case error(Error)
}

@State private var state: LoadingState<[Item]> = .idle

var body: some View {
    Group {
        switch state {
        case .idle:
            Color.clear.onAppear { Task { await load() } }
        case .loading:
            ProgressView()
        case .loaded(let items):
            ItemList(items: items)
        case .error(let error):
            ErrorView(error: error, retry: { Task { await load() } })
        }
    }
}
```

### Environment injection

```swift
// At app root
ContentView()
    .environment(authService)
    .environment(notificationService)

// In child views
@Environment(AuthService.self) private var authService
```

## Pitfalls to avoid

- Avoid `AnyView` - use concrete types or `@ViewBuilder`.
- Avoid `onTapGesture` when `Button` would work - buttons provide accessibility.
- Avoid inline closures that capture large state - extract to methods.
- Avoid deeply nested view hierarchies - flatten with composition.
- Avoid `id: \.self` in ForEach unless the type is truly stable.

## References

- Apple Human Interface Guidelines
- SwiftUI documentation
- Project-specific patterns in existing views

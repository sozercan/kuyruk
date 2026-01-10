---
name: swiftui-performance-audit
description: Audit and improve SwiftUI runtime performance from code review and architecture. Use for requests to diagnose slow rendering, janky scrolling, high CPU/memory usage, excessive view updates, or layout thrash in SwiftUI apps, and to provide guidance for user-run Instruments profiling when code review alone is insufficient.
---

# SwiftUI Performance Audit

## Overview

Audit SwiftUI view performance end-to-end, from instrumentation and baselining to root-cause analysis and concrete remediation steps.

## Workflow Decision Tree

- If the user provides code, start with "Code-First Review."
- If the user only describes symptoms, ask for minimal code/context, then do "Code-First Review."
- If code review is inconclusive, go to "Guide the User to Profile" and ask for a trace or screenshots.

## 1. Code-First Review

Collect:
- Target view/feature code.
- Data flow: state, environment, observable models.
- Symptoms and reproduction steps.

Focus on:
- View invalidation storms from broad state changes.
- Unstable identity in lists (`id` churn, `UUID()` per render).
- Heavy work in `body` (formatting, sorting, image decoding).
- Layout thrash (deep stacks, `GeometryReader`, preference chains).
- Large images without downsampling or resizing.
- Over-animated hierarchies (implicit animations on large trees).

Provide:
- Likely root causes with code references.
- Suggested fixes and refactors.
- If needed, a minimal repro or instrumentation suggestion.

## 2. Guide the User to Profile

Explain how to collect data with Instruments:
- Use the SwiftUI template in Instruments (Release build).
- Reproduce the exact interaction (scroll, navigation, animation).
- Capture SwiftUI timeline and Time Profiler.
- Export or screenshot the relevant lanes and the call tree.

Ask for:
- Trace export or screenshots of SwiftUI lanes + Time Profiler call tree.
- Device/OS/build configuration.

## 3. Analyze and Diagnose

Prioritize likely SwiftUI culprits:
- View invalidation storms from broad state changes.
- Unstable identity in lists (`id` churn, `UUID()` per render).
- Heavy work in `body` (formatting, sorting, image decoding).
- Layout thrash (deep stacks, `GeometryReader`, preference chains).
- Large images without downsampling or resizing.
- Over-animated hierarchies (implicit animations on large trees).

Summarize findings with evidence from traces/logs.

## 4. Remediate

Apply targeted fixes:
- Narrow state scope (`@State`/`@Observable` closer to leaf views).
- Stabilize identities for `ForEach` and lists.
- Move heavy work out of `body` (precompute, cache, `@State`).
- Use `equatable()` or value wrappers for expensive subtrees.
- Downsample images before rendering.
- Reduce layout complexity or use fixed sizing where possible.

## Common Code Smells (and Fixes)

Look for these patterns during code review.

### Expensive formatters in `body`

```swift
// Bad: Creates formatter on every render
var body: some View {
    let formatter = NumberFormatter()
    Text(formatter.string(from: value))
}

// Good: Cached formatter
static let formatter = NumberFormatter()
var body: some View {
    Text(Self.formatter.string(from: value))
}
```

### Computed properties that do heavy work

```swift
// Bad: Runs on every body eval
var filtered: [Item] {
    items.filter { $0.isEnabled }
}

// Good: Precompute or cache on change
@State private var filtered: [Item] = []
// update filtered when inputs change
```

### Sorting/filtering in `body` or `ForEach`

```swift
// Bad: Sorts on every render
ForEach(items.sorted(by: sortRule)) { item in
    Row(item)
}

// Good: Pre-sorted collection
let sortedItems = items.sorted(by: sortRule)
ForEach(sortedItems) { item in
    Row(item)
}
```

### Inline filtering in `ForEach`

```swift
// Bad
ForEach(items.filter { $0.isEnabled }) { item in
    Row(item)
}

// Good: Prefiltered collection with stable identity
```

### Unstable identity

```swift
// Bad: Uses \.self for non-stable values
ForEach(items, id: \.self) { item in
    Row(item)
}

// Good: Uses stable identifier
ForEach(items, id: \.id) { item in
    Row(item)
}
```

### Image decoding on main thread

```swift
// Bad: Decodes inline
Image(nsImage: NSImage(data: data)!)

// Good: Pre-decoded and cached via ImageCache
```

### Broad dependencies in observable models

```swift
// Bad: Entire model observed
@Observable class Model {
    var items: [Item] = []
}

var body: some View {
    Row(isFavorite: model.items.contains(item))
}

// Good: Granular view models or per-item state to reduce update fan-out
```

## 5. Verify

Ask the user to re-run the same capture and compare with baseline metrics.
Summarize the delta (CPU, frame drops, memory peak) if provided.

## Outputs

Provide:
- A short metrics table (before/after if available).
- Top issues (ordered by impact).
- Proposed fixes with estimated effort.

## References

- Optimizing SwiftUI performance with Instruments
- Understanding and improving SwiftUI performance
- Understanding hangs in your app
- Demystify SwiftUI performance (WWDC23)

---
name: swiftui-performance-audit
description: Audit and improve SwiftUI runtime performance from code review and architecture. Use for requests to diagnose slow rendering, janky scrolling, high CPU/memory usage, excessive view updates, or layout thrash in SwiftUI apps.
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

## 3. Remediate

Apply targeted fixes:
- Narrow state scope (`@State`/`@Observable` closer to leaf views).
- Stabilize identities for `ForEach` and lists.
- Move heavy work out of `body` (precompute, cache, `@State`).
- Use `equatable()` or value wrappers for expensive subtrees.
- Downsample images before rendering.
- Reduce layout complexity or use fixed sizing where possible.

## Common Code Smells (and Fixes)

### Expensive formatters in `body`

```swift
// ❌ Bad: Creates formatter on every render
var body: some View {
    let formatter = NumberFormatter()
    Text(formatter.string(from: value))
}

// ✅ Good: Cached formatter
static let formatter = NumberFormatter()
var body: some View {
    Text(Self.formatter.string(from: value))
}
```

### Sorting/filtering in `body` or `ForEach`

```swift
// ❌ Bad: Sorts on every render
ForEach(items.sorted(by: sortRule)) { item in
    Row(item)
}

// ✅ Good: Pre-sorted collection
let sortedItems = items.sorted(by: sortRule)
ForEach(sortedItems) { item in
    Row(item)
}
```

### Unstable identity

```swift
// ❌ Bad: Uses \.self for non-stable values
ForEach(items, id: \.self) { item in
    Row(item)
}

// ✅ Good: Uses stable identifier
ForEach(items, id: \.id) { item in
    Row(item)
}
```

### Image decoding on main thread

```swift
// ❌ Bad: Decodes inline
Image(uiImage: UIImage(data: data)!)

// ✅ Good: Pre-decoded and cached
AsyncImage(url: url) { image in
    image.resizable()
}
```

## 4. Verify

Ask the user to re-run the same capture and compare with baseline metrics.
Summarize the delta (CPU, frame drops, memory peak) if provided.

## Outputs

Provide:
- A short metrics table (before/after if available).
- Top issues (ordered by impact).
- Proposed fixes with estimated effort.

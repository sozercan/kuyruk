# ADR-0003: Liquid Glass Design Language

## Status

Accepted

## Context

macOS 26 introduces Liquid Glass, a new design language that provides translucent, dynamic surfaces. We need to decide how to adopt this in Kuyruk.

Options:
1. **Full Liquid Glass adoption**: Use glass effects throughout the app
2. **Selective adoption**: Use glass for key interactive elements only
3. **Fallback design**: Use traditional materials with glass as enhancement
4. **No adoption**: Stick with traditional macOS design

Key considerations:
- macOS 26+ target (Liquid Glass is available)
- Apple Reminders-inspired design goal
- Performance impact of glass effects
- Consistency with system apps

## Decision

We will adopt **Liquid Glass throughout the app** following Apple's design patterns.

### Implementation

1. **GlassEffectContainer for grouped elements**:
   ```swift
   GlassEffectContainer(spacing: 8) {
       VStack(spacing: 8) {
           ForEach(filters) { filter in
               FilterRow(filter: filter)
                   .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
           }
       }
   }
   ```

2. **Interactive glass for tappable elements**:
   ```swift
   Button(action: refresh) {
       Image(systemName: "arrow.clockwise")
   }
   .buttonStyle(.glass)
   ```

3. **Tinted glass for categories**:
   ```swift
   Text(reason.displayName)
       .padding(.horizontal, 8)
       .padding(.vertical, 4)
       .glassEffect(.regular.tint(reason.tintColor), in: .capsule)
   ```

4. **Modifier ordering**:
   ```swift
   // Correct: glass after layout modifiers
   NotificationRow(notification: notification)
       .padding()                                    // Layout first
       .foregroundStyle(.primary)                    // Appearance
       .glassEffect(.regular, in: .rect(cornerRadius: 12))  // Glass last
   ```

### Design Patterns

| Element | Glass Treatment |
|---------|-----------------|
| Sidebar filter items | `.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))` |
| Notification cards | `.glassEffect(.regular, in: .rect(cornerRadius: 12))` |
| Reason badges | `.glassEffect(.regular.tint(color), in: .capsule)` |
| Toolbar buttons | `.buttonStyle(.glass)` |
| Primary actions | `.buttonStyle(.glassProminent)` |
| Selected items | `.glassEffect(.regular.tint(.accentColor).interactive())` |

### Avoid Glass-on-Glass

```swift
// ❌ Wrong: glass button inside glass container
GlassEffectContainer {
    VStack {
        Button("Action") { }
            .buttonStyle(.glass)  // Glass inside glass!
    }
    .glassEffect()
}

// ✅ Correct: plain button inside glass
GlassEffectContainer {
    VStack {
        Button("Action") { }
            .buttonStyle(.plain)
    }
    .glassEffect()
}
```

### Fallback for Testing on Older Systems

While we target macOS 26, developers may test on older systems:

```swift
extension View {
    @ViewBuilder
    func adaptiveGlass(in shape: some Shape = .rect(cornerRadius: 12)) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}
```

## Consequences

### Positive

- ✅ Modern, native macOS 26 appearance
- ✅ Consistent with system apps (Reminders, Notes)
- ✅ Familiar to users of new macOS
- ✅ Interactive feedback on hover/press
- ✅ Dynamic blending with content behind

### Negative

- ❌ Requires macOS 26+ (acceptable for our target)
- ❌ Learning curve for glass patterns
- ❌ Must avoid glass-on-glass anti-pattern
- ❌ Potential performance impact with many glass layers

### Neutral

- Glass effects are GPU-accelerated
- Need to test on various backgrounds
- Color tints should be subtle

## References

- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [GlassEffectContainer](https://developer.apple.com/documentation/SwiftUI/GlassEffectContainer)
- [SwiftUI Liquid Glass skill](https://github.com/Dimillian/Skills/tree/main/swiftui-liquid-glass)

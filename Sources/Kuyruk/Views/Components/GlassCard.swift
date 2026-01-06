import SwiftUI

/// Reusable glass card component for wrapping content with Liquid Glass effect.
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let isInteractive: Bool
    @ViewBuilder let content: () -> Content

    init(
        cornerRadius: CGFloat = 12,
        isInteractive: Bool = false,
        @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.isInteractive = isInteractive
        self.content = content
    }

    var body: some View {
        if #available(macOS 26, *) {
            self.content()
                .glassEffect(
                    self.isInteractive ? .regular.interactive() : .regular,
                    in: .rect(cornerRadius: self.cornerRadius))
        } else {
            self.content()
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: self.cornerRadius))
        }
    }
}

#Preview {
    GlassCard {
        Text("Hello Glass")
            .padding()
    }
}

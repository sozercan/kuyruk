import AppKit
import SwiftUI

/// Displays a user or organization avatar with persistent caching.
struct AvatarView: View {
    let url: String
    let size: CGFloat

    @State private var image: NSImage?
    @State private var isLoading = true

    init(url: String, size: CGFloat = 32) {
        self.url = url
        self.size = size
    }

    var body: some View {
        Group {
            if let image = self.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if self.isLoading {
                self.placeholder
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }
            } else {
                self.placeholder
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: self.size * 0.5))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(Circle())
        .task(id: self.url) {
            await self.loadImage()
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: self.size, height: self.size)
    }

    private func loadImage() async {
        self.isLoading = true
        self.image = await ImageCache.shared.image(for: self.url)
        self.isLoading = false
    }
}

#Preview {
    HStack(spacing: 16) {
        AvatarView(url: "https://github.com/github.png", size: 32)
        AvatarView(url: "https://github.com/apple.png", size: 48)
        AvatarView(url: "invalid-url", size: 32)
    }
    .padding()
}

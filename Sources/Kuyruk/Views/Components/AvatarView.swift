import SwiftUI

/// Displays a user or organization avatar with caching.
struct AvatarView: View {
    let url: String
    let size: CGFloat

    init(url: String, size: CGFloat = 32) {
        self.url = url
        self.size = size
    }

    var body: some View {
        AsyncImage(url: URL(string: self.url)) { phase in
            switch phase {
            case .empty:
                self.placeholder
                    .overlay {
                        ProgressView()
                            .controlSize(.small)
                    }

            case let .success(image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)

            case .failure:
                self.placeholder
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: self.size * 0.5))
                            .foregroundStyle(.secondary)
                    }

            @unknown default:
                self.placeholder
            }
        }
        .frame(width: self.size, height: self.size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: self.size, height: self.size)
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

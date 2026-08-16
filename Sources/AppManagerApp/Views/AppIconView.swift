import SwiftUI
import AppKit
import AppManagerCore

/// Displays the native macOS application bundle icon with in-memory caching and non-blocking asynchronous loading.
public struct AppIconView: View {
    public let bundleURL: URL
    public let size: CGFloat

    @State private var icon: NSImage?

    public init(bundleURL: URL, size: CGFloat = 28) {
        self.bundleURL = bundleURL
        self.size = size
        self._icon = State(initialValue: AppIconCache.shared.cachedIcon(for: bundleURL))
    }

    public var body: some View {
        Group {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .fill(Color.gray.opacity(0.15))
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.2)
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .cornerRadius(size * 0.22)
        .task(id: bundleURL) {
            if icon == nil {
                let loaded = await AppIconCache.shared.loadIcon(for: bundleURL)
                self.icon = loaded
            }
        }
    }
}

import SwiftUI
import AppKit

/// Displays the native macOS application bundle icon.
public struct AppIconView: View {
    public let bundleURL: URL
    public let size: CGFloat

    public init(bundleURL: URL, size: CGFloat = 28) {
        self.bundleURL = bundleURL
        self.size = size
    }

    public var body: some View {
        let icon = NSWorkspace.shared.icon(forFile: bundleURL.path)
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .cornerRadius(size * 0.22)
    }
}

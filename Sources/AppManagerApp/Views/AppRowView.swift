import SwiftUI
import AppManagerCore

public struct AppRowView: View {
    public let app: AppItem
    @ObservedObject var viewModel: MenuBarViewModel

    @State private var isHovered: Bool = false

    public var body: some View {
        HStack(spacing: 10) {
            // App Icon
            AppIconView(bundleURL: app.bundleURL, size: 28)

            // App Name and Status
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if app.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                    }

                    if app.customConfig != nil {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 9))
                            .foregroundColor(.blue)
                    }
                }

                HStack(spacing: 6) {
                    if app.isRunning {
                        if let proxyURL = app.activeProxyURLString {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text(app.pid != nil ? "PID \(app.pid!)" : "Running")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)

                            Text("Proxy")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(3)
                                .help("Routing over Proxy: \(proxyURL)")
                        } else {
                            Circle()
                                .fill(Color.yellow)
                                .frame(width: 6, height: 6)
                            Text(app.pid != nil ? "PID \(app.pid!) · Direct" : "Direct")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: 6, height: 6)
                        Text("Stopped")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    if app.isElectronOrChromium {
                        Text("Electron/Chrome")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(3)
                    }
                }
            }

            Spacer()

            // Action Buttons
            HStack(spacing: 4) {
                if app.isRunning {
                    Button {
                        viewModel.stopApp(app: app)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: 24, height: 24)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Stop Application")
                } else {
                    Button {
                        viewModel.launchAppNormally(app: app)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                            .frame(width: 24, height: 24)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .help("Start Application")
                }

                // Proxy Launch Action
                Button {
                    viewModel.launchAppWithProxy(app: app)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Launch over HTTP Proxy")

                // Pin / Unpin Button
                Button {
                    viewModel.togglePin(app: app)
                } label: {
                    Image(systemName: app.isPinned ? "pin.slash" : "pin")
                        .font(.system(size: 11))
                        .foregroundColor(app.isPinned ? .orange : .secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help(app.isPinned ? "Unpin Application" : "Pin Application")

                // Config Settings Button
                Button {
                    viewModel.openAppConfig(for: app)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.gray.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
                .help("Configure Proxy & Launch Settings")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isHovered ? Color.gray.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .onHover { isHovered = $0 }
    }
}

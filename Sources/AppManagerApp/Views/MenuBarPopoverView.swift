import SwiftUI
import AppKit
import AppManagerCore

public struct MenuBarPopoverView: View {
    @StateObject private var viewModel = MenuBarViewModel()

    public init() {}

    public var body: some View {
        Group {
            switch viewModel.activeScreen {
            case .mainList:
                mainListView
            case .globalSettings:
                GlobalSettingsView(viewModel: viewModel)
            case .appConfig(let app):
                AppConfigView(app: app, viewModel: viewModel)
            }
        }
        .frame(width: 380)
    }

    // MARK: - Main Application List View

    private var mainListView: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            // Status message toast
            if let status = viewModel.statusMessage {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
            }

            Divider()

            // Application List Scroll View
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if viewModel.isLoading && viewModel.discoveredApps.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Discovering applications...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        // 1. Pinned Apps Section
                        PinnedAppsSection(viewModel: viewModel)

                        // 2. Running Apps Section (if any unpinned running)
                        if !viewModel.runningApps.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                    Text("RUNNING APPS (\(viewModel.runningApps.count))")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 4)

                                ForEach(viewModel.runningApps) { app in
                                    AppRowView(app: app, viewModel: viewModel)
                                }

                                Divider()
                                    .padding(.vertical, 4)
                            }
                        }

                        // 3. All / Other Installed Apps Section
                        if !viewModel.unpinnedInstalledApps.isEmpty {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text("ALL INSTALLED APPS (\(viewModel.unpinnedInstalledApps.count))")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 10)
                                .padding(.top, 4)

                                ForEach(viewModel.unpinnedInstalledApps) { app in
                                    AppRowView(app: app, viewModel: viewModel)
                                }
                            }
                        }

                        // Empty state when search produces no results
                        if viewModel.filteredApps.isEmpty && !viewModel.isLoading {
                            VStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                                Text("No applications found")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 460)

            Divider()

            // Footer Bar
            footerBar
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack {
                // Global Proxy Quick Toggle (Circle Indicator)
                Button {
                    viewModel.toggleGlobalProxy()
                } label: {
                    Circle()
                        .fill(viewModel.globalProxy.isEnabled ? Color.blue : Color.gray)
                        .frame(width: 10, height: 10)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(viewModel.globalProxy.isEnabled
                    ? "Global Proxy: Enabled (\(viewModel.globalProxy.urlString)) — Click to disable"
                    : "Global Proxy: Disabled — Click to enable")
                .accessibilityLabel("Toggle Global Proxy")
                .accessibilityValue(viewModel.globalProxy.isEnabled ? "Enabled" : "Disabled")

                Spacer()

                // Reload Applications Button
                Button {
                    viewModel.reloadApplications()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Rescan Applications")

                // Global Settings Button
                Button {
                    viewModel.openGlobalSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Settings")
            }

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                TextField("Search applications...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(10)
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text("Scanning...")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.discoveredApps.count) apps discovered")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Quit AppManager") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

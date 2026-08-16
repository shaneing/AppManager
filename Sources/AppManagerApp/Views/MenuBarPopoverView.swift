import SwiftUI
import AppKit
import AppManagerCore

public struct MenuBarPopoverView: View {
    @StateObject private var viewModel = MenuBarViewModel()

    public init() {}

    public var body: some View {
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
                VStack(alignment: .leading, spacing: 6) {
                    // 1. Pinned Apps Section
                    PinnedAppsSection(viewModel: viewModel)

                    // 2. Running Apps Section (if any unpinned running)
                    if !viewModel.runningApps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
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
                        VStack(alignment: .leading, spacing: 4) {
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
                    if viewModel.filteredApps.isEmpty {
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
                .padding(.vertical, 6)
            }
            .frame(maxHeight: 460)

            Divider()

            // Footer Bar
            footerBar
        }
        .frame(width: 380)
        .sheet(item: $viewModel.selectedAppForConfig) { app in
            AppConfigSheet(app: app, viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.isShowingSettings) {
            GlobalSettingsView(viewModel: viewModel)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        VStack(spacing: 8) {
            HStack {
                // Global Proxy Status Indicator & Quick Toggle
                Button {
                    viewModel.toggleGlobalProxy()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.globalProxy.isEnabled ? Color.blue : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(viewModel.globalProxy.isEnabled ? "Proxy: \(viewModel.globalProxy.urlString)" : "Proxy: Disabled")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(viewModel.globalProxy.isEnabled ? .blue : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(viewModel.globalProxy.isEnabled ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .help("Toggle Global Proxy On/Off")

                Spacer()

                // Reload Applications Button
                Button {
                    viewModel.reloadApplications()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Rescan Applications")

                // Global Settings Button
                Button {
                    viewModel.isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
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
            Text("\(viewModel.discoveredApps.count) apps discovered")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

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

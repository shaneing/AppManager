import SwiftUI
import AppManagerCore

public struct GlobalSettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel

    @State private var proxyEndpoint: String
    @State private var isEnabled: Bool
    @State private var scanUserApps: Bool
    @State private var scanSystemApps: Bool
    @State private var quitProxiedAppsOnExit: Bool
    @State private var relaunchProxiedAppsOnProxyChange: Bool

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        let current = viewModel.globalProxy
        let initialEndpoint = current.urlString.isEmpty ? "\(current.host):\(current.port)" : current.urlString
        _proxyEndpoint = State(initialValue: initialEndpoint)
        _isEnabled = State(initialValue: current.isEnabled)

        let settings = ConfigurationStore.shared.settings
        _scanUserApps = State(initialValue: settings.scanUserApplications)
        _scanSystemApps = State(initialValue: settings.scanSystemApplications)
        _quitProxiedAppsOnExit = State(initialValue: settings.quitProxiedAppsOnExit)
        _relaunchProxiedAppsOnProxyChange = State(initialValue: settings.relaunchProxiedAppsOnProxyChange)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with Back Button
            HStack(spacing: 8) {
                Button {
                    viewModel.navigateBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.blue)
                    Text("Global Settings")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                // Balance the back button
                Color.clear
                    .frame(width: 44, height: 16)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    // Global Proxy Configuration
                    GroupBox("Default Global Proxy") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Enable Global Proxy", isOn: $isEnabled)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Proxy Server URL")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextField("http://127.0.0.1:7890", text: $proxyEndpoint)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Text("Example: http://127.0.0.1:7890 or 127.0.0.1:7890")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

                    // Lifecycle & Proxy Automation
                    GroupBox("Lifecycle & Proxy Automation") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Quit proxied apps on AppManager exit", isOn: $quitProxiedAppsOnExit)
                            Toggle("Relaunch proxied apps on Global Proxy change", isOn: $relaunchProxiedAppsOnProxyChange)

                            Text("Direct (unproxied) applications will remain running and are not affected.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }

                    // Application Discovery Directories
                    GroupBox("Application Discovery") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("Scan ~/Applications (User)", isOn: $scanUserApps)
                            Toggle("Scan /System/Applications (System)", isOn: $scanSystemApps)
                            Text("/Applications is always scanned by default.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(4)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 380)

            Divider()

            // Footer Actions
            HStack {
                Button("Cancel") {
                    viewModel.navigateBack()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

                Spacer()

                Button("Save Settings") {
                    save()
                    viewModel.navigateBack()
                }
                .buttonStyle(.borderedProminent)
                .font(.system(size: 12))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 380)
    }

    private func save() {
        let current = viewModel.globalProxy
        let parsed = ProxyConfig.parse(from: proxyEndpoint)
        let proxy = ProxyConfig(
            host: parsed?.host ?? current.host,
            port: parsed?.port ?? current.port,
            proxyProtocol: parsed?.proxyProtocol ?? current.proxyProtocol,
            isEnabled: isEnabled,
            authUsername: parsed?.authUsername ?? current.authUsername,
            authPassword: parsed?.authPassword ?? current.authPassword
        )

        ConfigurationStore.shared.update { settings in
            settings.scanUserApplications = scanUserApps
            settings.scanSystemApplications = scanSystemApps
            settings.quitProxiedAppsOnExit = quitProxiedAppsOnExit
            settings.relaunchProxiedAppsOnProxyChange = relaunchProxiedAppsOnProxyChange
        }

        viewModel.updateGlobalProxy(proxy)

        viewModel.reloadApplications()
    }
}

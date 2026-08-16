import SwiftUI
import AppManagerCore

public struct GlobalSettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var proxyEndpoint: String
    @State private var isEnabled: Bool
    @State private var scanUserApps: Bool
    @State private var scanSystemApps: Bool

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        let current = viewModel.globalProxy
        let initialEndpoint = current.urlString.isEmpty ? "\(current.host):\(current.port)" : current.urlString
        _proxyEndpoint = State(initialValue: initialEndpoint)
        _isEnabled = State(initialValue: current.isEnabled)

        let settings = ConfigurationStore.shared.settings
        _scanUserApps = State(initialValue: settings.scanUserApplications)
        _scanSystemApps = State(initialValue: settings.scanSystemApplications)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title
            HStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Global Settings")
                    .font(.headline)
                Spacer()
            }

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
            }

            Divider()

            // Actions
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Settings") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 380, height: 420)
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

        viewModel.updateGlobalProxy(proxy)

        ConfigurationStore.shared.update { settings in
            settings.scanUserApplications = scanUserApps
            settings.scanSystemApplications = scanSystemApps
        }

        viewModel.reloadApplications()
    }
}


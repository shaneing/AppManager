import SwiftUI
import AppManagerCore

public struct GlobalSettingsView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var host: String
    @State private var port: String
    @State private var proxyProtocol: ProxyProtocol
    @State private var isEnabled: Bool
    @State private var scanUserApps: Bool
    @State private var scanSystemApps: Bool

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
        let current = viewModel.globalProxy
        _host = State(initialValue: current.host)
        _port = State(initialValue: String(current.port))
        _proxyProtocol = State(initialValue: current.proxyProtocol)
        _isEnabled = State(initialValue: current.isEnabled)

        let settings = ConfigurationStore.shared.settings
        _scanUserApps = State(initialValue: settings.scanUserApplications)
        _scanSystemApps = State(initialValue: settings.scanSystemApplications)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Title
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Global AppManager Settings")
                    .font(.title3).bold()
                Spacer()
            }

            Divider()

            // Global Proxy Configuration
            GroupBox("Default Global Proxy") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Global Proxy", isOn: $isEnabled)

                    HStack(spacing: 8) {
                        Picker("Protocol", selection: $proxyProtocol) {
                            Text("HTTP").tag(ProxyProtocol.http)
                            Text("HTTPS").tag(ProxyProtocol.https)
                            Text("SOCKS5").tag(ProxyProtocol.socks5)
                        }
                        .frame(width: 130)

                        TextField("Host", text: $host)
                            .textFieldStyle(.roundedBorder)

                        TextField("Port", text: $port)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                    }

                    Text("Example: 127.0.0.1 : 7890 for Clash / Mihomo / Shadowsocks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            // Application Discovery Directories
            GroupBox("Application Discovery") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Scan ~/Applications (User Apps)", isOn: $scanUserApps)
                    Toggle("Scan /System/Applications (System Apps)", isOn: $scanSystemApps)
                    Text("/Applications is always scanned by default.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }

            Spacer()

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
        .padding(20)
        .frame(width: 440, height: 380)
    }

    private func save() {
        let portInt = Int(port) ?? 7890
        let proxy = ProxyConfig(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portInt,
            proxyProtocol: proxyProtocol,
            isEnabled: isEnabled
        )

        viewModel.updateGlobalProxy(proxy)

        ConfigurationStore.shared.update { settings in
            settings.scanUserApplications = scanUserApps
            settings.scanSystemApplications = scanSystemApps
        }

        viewModel.reloadApplications()
    }
}

import SwiftUI
import AppManagerCore

public struct AppConfigSheet: View {
    public let app: AppItem
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AppCustomProxyConfig.Mode
    @State private var strategy: ProxyStrategy
    @State private var customHost: String
    @State private var customPort: String
    @State private var customProtocol: ProxyProtocol
    @State private var extraArgs: String
    @State private var extraEnvKey: String = ""
    @State private var extraEnvVal: String = ""
    @State private var extraEnvVars: [String: String]

    public init(app: AppItem, viewModel: MenuBarViewModel) {
        self.app = app
        self.viewModel = viewModel

        let currentConfig = app.customConfig
        _mode = State(initialValue: currentConfig?.mode ?? .inheritGlobal)
        _strategy = State(initialValue: currentConfig?.strategy ?? .auto)

        let proxy = currentConfig?.customProxy
        _customHost = State(initialValue: proxy?.host ?? "127.0.0.1")
        _customPort = State(initialValue: String(proxy?.port ?? 7890))
        _customProtocol = State(initialValue: proxy?.proxyProtocol ?? .http)

        _extraArgs = State(initialValue: currentConfig?.extraLaunchArgs.joined(separator: " ") ?? "")
        _extraEnvVars = State(initialValue: currentConfig?.extraEnvVars ?? [:])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                AppIconView(bundleURL: app.bundleURL, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.headline)
                    Text(app.bundleIdentifier)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Proxy Mode
            VStack(alignment: .leading, spacing: 6) {
                Text("Proxy Routing Mode")
                    .font(.subheadline).bold()
                Picker("", selection: $mode) {
                    Text("Use Global Default Proxy").tag(AppCustomProxyConfig.Mode.inheritGlobal)
                    Text("Custom Proxy Configuration").tag(AppCustomProxyConfig.Mode.customProxy)
                    Text("Direct (No Proxy)").tag(AppCustomProxyConfig.Mode.direct)
                }
                .pickerStyle(.radioGroup)
            }

            // Custom Proxy Settings (if mode == .customProxy)
            if mode == .customProxy {
                GroupBox("Custom Proxy Endpoint") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Protocol", selection: $customProtocol) {
                                Text("HTTP").tag(ProxyProtocol.http)
                                Text("HTTPS").tag(ProxyProtocol.https)
                                Text("SOCKS5").tag(ProxyProtocol.socks5)
                            }
                            .frame(width: 140)

                            TextField("Host", text: $customHost)
                                .textFieldStyle(.roundedBorder)

                            TextField("Port", text: $customPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                    .padding(6)
                }
            }

            // Strategy Override
            VStack(alignment: .leading, spacing: 6) {
                Text("Proxy Injection Strategy")
                    .font(.subheadline).bold()
                Picker("", selection: $strategy) {
                    ForEach(ProxyStrategy.allCases, id: \.self) { strat in
                        Text(strat.displayName).tag(strat)
                    }
                }
                .pickerStyle(.menu)
            }

            // Extra Launch Arguments
            VStack(alignment: .leading, spacing: 4) {
                Text("Extra Launch Arguments (Space Separated)")
                    .font(.subheadline).bold()
                TextField("--flag1 --flag2=value", text: $extraArgs)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer()

            // Footer / Actions
            HStack {
                Button("Reset to Default") {
                    viewModel.saveAppCustomConfig(nil, for: app)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Configuration") {
                    save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440, height: 460)
    }

    private func save() {
        let portInt = Int(customPort) ?? 7890
        let proxy = ProxyConfig(
            host: customHost.trimmingCharacters(in: .whitespacesAndNewlines),
            port: portInt,
            proxyProtocol: customProtocol,
            isEnabled: true
        )

        let parsedArgs = extraArgs
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let config = AppCustomProxyConfig(
            mode: mode,
            customProxy: (mode == .customProxy ? proxy : nil),
            strategy: strategy,
            extraLaunchArgs: parsedArgs,
            extraEnvVars: extraEnvVars
        )

        viewModel.saveAppCustomConfig(config, for: app)
    }
}

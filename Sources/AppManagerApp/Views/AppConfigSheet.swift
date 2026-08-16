import SwiftUI
import AppManagerCore

public struct AppConfigSheet: View {
    public let app: AppItem
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AppCustomProxyConfig.Mode
    @State private var strategy: ProxyStrategy
    @State private var customEndpoint: String
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
        let initialCustomEndpoint = proxy?.urlString ?? "http://127.0.0.1:7890"
        _customEndpoint = State(initialValue: initialCustomEndpoint)

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Proxy Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("http://127.0.0.1:7890", text: $customEndpoint)
                            .textFieldStyle(.roundedBorder)

                        Text("Example: http://127.0.0.1:7890 or 127.0.0.1:7890")
                            .font(.caption2)
                            .foregroundColor(.secondary)
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
        .padding(14)
        .frame(width: 380, height: 440)
    }

    private func save() {
        let parsed = ProxyConfig.parse(from: customEndpoint)
        let proxy = ProxyConfig(
            host: parsed?.host ?? "127.0.0.1",
            port: parsed?.port ?? 7890,
            proxyProtocol: parsed?.proxyProtocol ?? .http,
            isEnabled: true,
            authUsername: parsed?.authUsername,
            authPassword: parsed?.authPassword
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

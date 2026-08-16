import SwiftUI
import AppManagerCore

public struct AppConfigView: View {
    public let app: AppItem
    @ObservedObject var viewModel: MenuBarViewModel

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

                HStack(spacing: 8) {
                    AppIconView(bundleURL: app.bundleURL, size: 20)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(app.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
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
                VStack(alignment: .leading, spacing: 14) {
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
                            .padding(4)
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
                }
                .padding(12)
            }
            .frame(maxHeight: 380)

            Divider()

            // Footer Actions
            HStack {
                Button("Reset to Default") {
                    viewModel.saveAppCustomConfig(nil, for: app)
                    viewModel.navigateBack()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.red)

                Spacer()

                Button("Cancel") {
                    viewModel.navigateBack()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

                Button("Save Configuration") {
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

/// Typealias for backward compatibility
public typealias AppConfigSheet = AppConfigView

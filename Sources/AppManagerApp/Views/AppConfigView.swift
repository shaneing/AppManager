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
    @State private var codeSigningInfo: CodeSigningInfo? = nil
    @State private var isResigning: Bool = false

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

                        if strategy == .dynamicLibHook {
                            VStack(alignment: .leading, spacing: 6) {
                                if let info = codeSigningInfo {
                                    if info.isCompatibleWithDynamicHook {
                                        HStack(spacing: 6) {
                                            Image(systemName: "checkmark.seal.fill")
                                                .foregroundColor(.green)
                                            Text("Ready for Dynamic Hooking")
                                                .font(.caption)
                                                .foregroundColor(.primary)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.green.opacity(0.12))
                                        .cornerRadius(6)
                                    } else {
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundColor(.orange)
                                                Text("Hardened Runtime Detected")
                                                    .font(.caption).bold()
                                                    .foregroundColor(.orange)
                                            }
                                            Text("This app enforces macOS Hardened Runtime which strips DYLD hooks on launch.")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            Button {
                                                isResigning = true
                                                Task {
                                                    _ = await viewModel.resignAppAdHoc(app: app)
                                                    codeSigningInfo = viewModel.checkCodeSigning(for: app)
                                                    isResigning = false
                                                }
                                            } label: {
                                                HStack(spacing: 4) {
                                                    if isResigning {
                                                        ProgressView()
                                                            .scaleEffect(0.6)
                                                            .frame(width: 12, height: 12)
                                                    } else {
                                                        Image(systemName: "signature")
                                                    }
                                                    Text(isResigning ? "Re-signing..." : "Prepare for Hooking (Ad-hoc Re-sign)")
                                                }
                                                .font(.caption)
                                            }
                                            .buttonStyle(.bordered)
                                            .disabled(isResigning)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.orange.opacity(0.12))
                                        .cornerRadius(6)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
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
        .onAppear {
            checkSigning()
        }
        .onChange(of: strategy) { _ in
            checkSigning()
        }
    }

    private func checkSigning() {
        if strategy == .dynamicLibHook {
            codeSigningInfo = viewModel.checkCodeSigning(for: app)
        }
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

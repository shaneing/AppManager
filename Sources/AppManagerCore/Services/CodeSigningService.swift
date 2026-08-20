import Foundation

/// Represents the code signing and Hardened Runtime status of a macOS application bundle.
public struct CodeSigningInfo: Equatable, Sendable {
    public let isSigned: Bool
    public let hasHardenedRuntime: Bool
    public let allowsDyldEnvironmentVariables: Bool
    public let signatureAuthority: String?

    public init(
        isSigned: Bool = false,
        hasHardenedRuntime: Bool = false,
        allowsDyldEnvironmentVariables: Bool = false,
        signatureAuthority: String? = nil
    ) {
        self.isSigned = isSigned
        self.hasHardenedRuntime = hasHardenedRuntime
        self.allowsDyldEnvironmentVariables = allowsDyldEnvironmentVariables
        self.signatureAuthority = signatureAuthority
    }

    /// Indicates whether the binary allows dynamic library injection (DYLD_INSERT_LIBRARIES).
    public var isCompatibleWithDynamicHook: Bool {
        // If not hardened, or if hardened but has allow-dyld entitlement, injection works.
        return !hasHardenedRuntime || allowsDyldEnvironmentVariables
    }
}

public enum CodeSigningError: LocalizedError {
    case processExecutionFailed(String)
    case bundleNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .processExecutionFailed(let msg):
            return "Code signing operation failed: \(msg)"
        case .bundleNotFound(let path):
            return "Application bundle not found at: \(path)"
        }
    }
}

/// Service to inspect and adjust macOS application code signatures for dynamic library injection.
public final class CodeSigningService: Sendable {
    public static let shared = CodeSigningService()

    public init() {}

    /// Inspects the code signature and Hardened Runtime flags of an application bundle.
    public func inspectCodeSigning(bundleURL: URL) -> CodeSigningInfo {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            return CodeSigningInfo()
        }

        // Run codesign -dvvv <bundlePath>
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dvvv", bundleURL.path]
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 && !output.contains("Signature") {
                return CodeSigningInfo(isSigned: false)
            }

            let isSigned = output.contains("Signed by") || output.contains("Signature size") || output.contains("Format=app bundle with Mach-O")
            let hasHardenedRuntime = output.contains("runtime") || output.contains("flags=0x10000(runtime)") || output.contains("flags=0x10002(runtime,kill)")

            // Check entitlements for allow-dyld
            let allowsDyld = inspectAllowsDyldEntitlement(bundleURL: bundleURL)

            var authority: String? = nil
            for line in output.components(separatedBy: "\n") {
                if line.starts(with: "Authority=") {
                    authority = line.replacingOccurrences(of: "Authority=", with: "").trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            return CodeSigningInfo(
                isSigned: isSigned,
                hasHardenedRuntime: hasHardenedRuntime,
                allowsDyldEnvironmentVariables: allowsDyld,
                signatureAuthority: authority
            )
        } catch {
            return CodeSigningInfo()
        }
    }

    private func inspectAllowsDyldEntitlement(bundleURL: URL) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "--entitlements", ":-", bundleURL.path]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains("com.apple.security.cs.allow-dyld-environment-variables")
        } catch {
            return false
        }
    }

    /// Re-signs the application bundle with an ad-hoc local signature without Hardened Runtime flags.
    public func performAdHocResign(bundleURL: URL) async throws {
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw CodeSigningError.bundleNotFound(bundleURL.path)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
                process.arguments = ["--force", "--deep", "--sign", "-", bundleURL.path]
                process.standardError = pipe
                process.standardOutput = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: ())
                    } else {
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let errOutput = String(data: data, encoding: .utf8) ?? "Unknown codesign error"
                        continuation.resume(throwing: CodeSigningError.processExecutionFailed(errOutput))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

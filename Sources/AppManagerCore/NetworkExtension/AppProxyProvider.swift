import Foundation
import NetworkExtension
import Network

/// Native Apple NEAppProxyProvider implementation for Strategy C socket-level proxying.
open class AppProxyProvider: NEAppProxyProvider, @unchecked Sendable {
    private var proxyHost: String = "127.0.0.1"
    private var proxyPort: Int = 7890
    private var targetBundleIds: Set<String> = []

    open override func startProxy(options: [String : Any]?, completionHandler: @escaping (Error?) -> Void) {
        guard let config = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration else {
            completionHandler(nil)
            return
        }

        if let host = config["proxyHost"] as? String {
            self.proxyHost = host
        }
        if let port = config["proxyPort"] as? Int {
            self.proxyPort = port
        }
        if let bundleIds = config["targetBundleIds"] as? [String] {
            self.targetBundleIds = Set(bundleIds)
        }

        print("[AppProxyProvider] Started proxy provider -> \(proxyHost):\(proxyPort) for bundles: \(targetBundleIds)")
        completionHandler(nil)
    }

    open override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        print("[AppProxyProvider] Stopped proxy provider. Reason: \(reason.rawValue)")
        completionHandler()
    }

    open override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NEAppProxyTCPFlow else {
            return false
        }

        // Open local flow and stream to HTTP CONNECT proxy tunnel
        tcpFlow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self = self, error == nil else {
                tcpFlow.closeReadWithError(error)
                tcpFlow.closeWriteWithError(error)
                return
            }

            self.handleTCPFlow(tcpFlow)
        }

        return true
    }

    private func handleTCPFlow(_ tcpFlow: NEAppProxyTCPFlow) {
        guard let remoteEndpoint = tcpFlow.remoteEndpoint as? NWHostEndpoint else {
            tcpFlow.closeReadWithError(nil)
            tcpFlow.closeWriteWithError(nil)
            return
        }

        let proxyEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(self.proxyHost),
            port: NWEndpoint.Port(rawValue: UInt16(self.proxyPort)) ?? 7890
        )

        let params = NWParameters.tcp
        let connection = NWConnection(to: proxyEndpoint, using: params)

        connection.stateUpdateHandler = { [weak self, weak tcpFlow] state in
            guard let tcpFlow = tcpFlow else { return }
            switch state {
            case .ready:
                // Send HTTP CONNECT tunnel request
                let connectReq = "CONNECT \(remoteEndpoint.hostname):\(remoteEndpoint.port) HTTP/1.1\r\nHost: \(remoteEndpoint.hostname):\(remoteEndpoint.port)\r\n\r\n"
                if let reqData = connectReq.data(using: .utf8) {
                    connection.send(content: reqData, completion: .contentProcessed { sendErr in
                        if sendErr == nil {
                            self?.bridgeFlow(tcpFlow, connection: connection)
                        } else {
                            tcpFlow.closeReadWithError(sendErr)
                            tcpFlow.closeWriteWithError(sendErr)
                        }
                    })
                }
            case .failed(let err):
                tcpFlow.closeReadWithError(err)
                tcpFlow.closeWriteWithError(err)
            case .cancelled:
                tcpFlow.closeReadWithError(nil)
                tcpFlow.closeWriteWithError(nil)
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
    }

    private func bridgeFlow(_ flow: NEAppProxyTCPFlow, connection: NWConnection) {
        // Read from app -> write to proxy connection
        func readFromApp() {
            flow.readData { data, error in
                guard let data = data, !data.isEmpty, error == nil else {
                    connection.cancel()
                    return
                }
                connection.send(content: data, completion: .contentProcessed { err in
                    if err == nil {
                        readFromApp()
                    } else {
                        flow.closeReadWithError(err)
                        connection.cancel()
                    }
                })
            }
        }

        // Read from proxy connection -> write to app
        func readFromProxy() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                guard let data = data, !data.isEmpty, error == nil else {
                    flow.closeWriteWithError(error)
                    return
                }
                flow.write(data) { writeErr in
                    if writeErr == nil && !isComplete {
                        readFromProxy()
                    } else {
                        flow.closeWriteWithError(writeErr)
                        connection.cancel()
                    }
                }
            }
        }

        readFromApp()
        readFromProxy()
    }
}

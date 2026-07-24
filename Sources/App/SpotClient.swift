import Foundation
import Observation

/// Telnet-style DX cluster connection: logs in with the station callsign,
/// then streams parsed spots via `onSpot`. Socket callbacks arrive on a
/// background queue and hop to the main actor for state + parsing.
@MainActor
@Observable
final class SpotClient {

    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
    }

    private(set) var status: Status = .disconnected
    private(set) var lastError: String?
    var onSpot: ((Spot) -> Void)?

    private var transport: TCPTransport?
    private var buffer = ""
    private var loginSent = false
    private var loginFallback: Task<Void, Never>?

    func connect(host: String, port: UInt16, callsign: String) {
        disconnect()
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let call = callsign.trimmingCharacters(in: .whitespaces).uppercased()
        guard !trimmedHost.isEmpty else {
            lastError = "Enter a cluster host."
            return
        }
        guard !call.isEmpty else {
            lastError = "Set your callsign in Contest Setup first — clusters need a login call."
            return
        }

        let tcp = TCPTransport(host: trimmedHost, port: port)
        tcp.onReceive = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.ingest(data, callsign: call)
            }
        }
        tcp.onDisconnect = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.status != .disconnected else { return }
                self.lastError = reason
                self.teardown()
            }
        }
        tcp.onWaiting = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.status == .connecting else { return }
                self.lastError = "Still trying: \(reason)"
            }
        }
        transport = tcp
        status = .connecting
        try? tcp.open(baudRate: 0)

        // Some clusters prompt without a newline, some not at all — if no
        // recognizable prompt shows up, send the callsign anyway.
        loginFallback = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.sendLoginIfNeeded(callsign: call)
        }
    }

    func disconnect() {
        teardown()
        lastError = nil
    }

    private func teardown() {
        loginFallback?.cancel()
        loginFallback = nil
        transport?.close()
        transport = nil
        buffer = ""
        loginSent = false
        status = .disconnected
    }

    private func sendLoginIfNeeded(callsign: String) {
        guard !loginSent, let transport, status == .connecting else { return }
        loginSent = true
        transport.write("\(callsign)\r\n")
        status = .connected
    }

    private func ingest(_ data: Data, callsign: String) {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return }
        buffer += text

        // Login prompts ("login:", "Please enter your call") usually arrive
        // without a trailing newline — scan the raw buffer.
        if !loginSent {
            let lower = buffer.lowercased()
            if lower.contains("login") || lower.contains("call") {
                sendLoginIfNeeded(callsign: callsign)
            }
        }

        while let nl = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[buffer.index(after: nl)...])
            if let spot = SpotParser.parse(line, receivedAt: Date()) {
                status = .connected
                onSpot?(spot)
            }
        }
        if buffer.count > 4096 { buffer = "" }
    }
}

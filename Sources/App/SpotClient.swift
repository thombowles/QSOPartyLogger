import Foundation
import Observation

/// Telnet-style DX cluster connection: waits for the node's login prompt,
/// answers with the station callsign, runs the startup commands, then streams
/// parsed spots via `onSpot`. Socket callbacks arrive on a background queue
/// and hop to the main actor for state + parsing.
///
/// Everything the node says is kept in `console` — a node that rejects a
/// login or wants a different command is otherwise invisible, which is
/// exactly how "connected but no spots" happens.
@MainActor
@Observable
final class SpotClient {

    enum Status: Equatable {
        case disconnected
        case connecting
        /// Prompt answered; waiting to see whether the node accepted it.
        case loggingIn
        case connected
    }

    private(set) var status: Status = .disconnected
    private(set) var lastError: String?
    /// Recent node output, newest last (capped).
    private(set) var console: [String] = []
    private(set) var spotsReceived = 0
    var onSpot: ((Spot) -> Void)?

    private static let maxConsoleLines = 300
    /// A node that keeps re-prompting is rejecting the callsign.
    private static let maxLoginAttempts = 3

    private var transport: TCPTransport?
    private var buffer = ""
    private var callsign = ""
    private var loginAttempts = 0
    private var pendingCommands: [String] = []
    private var commandsSent = false
    private var watchdog: Task<Void, Never>?

    func connect(host: String, port: UInt16, callsign: String, initialCommands: String = "") {
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
        self.callsign = call
        pendingCommands = initialCommands
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let tcp = TCPTransport(host: trimmedHost, port: port)
        tcp.onReceive = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.ingest(data)
            }
        }
        tcp.onDisconnect = { [weak self] reason in
            Task { @MainActor [weak self] in
                guard let self, self.status != .disconnected else { return }
                self.lastError = reason
                self.log("*** disconnected: \(reason)")
                self.teardown(keepConsole: true)
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
        console = []
        spotsReceived = 0
        loginAttempts = 0
        lastError = nil
        log("*** connecting to \(trimmedHost):\(port)")
        try? tcp.open(baudRate: 0)
        startWatchdog(host: trimmedHost)
    }

    func disconnect() {
        teardown(keepConsole: false)
        lastError = nil
    }

    /// Send a command typed by the operator (or a saved startup command).
    func send(_ command: String) {
        let text = command.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let transport, status != .disconnected else { return }
        transport.write("\(text)\r\n")
        log("> \(text)")
    }

    private func teardown(keepConsole: Bool) {
        watchdog?.cancel()
        watchdog = nil
        transport?.close()
        transport = nil
        buffer = ""
        loginAttempts = 0
        commandsSent = false
        status = .disconnected
        if !keepConsole { console = [] }
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > Self.maxConsoleLines {
            console.removeFirst(console.count - Self.maxConsoleLines)
        }
    }

    /// Nothing at all from a node within 20 s means something is wrong that
    /// the operator needs to know about — most nodes greet immediately.
    private func startWatchdog(host: String) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, !Task.isCancelled, self.status != .disconnected else { return }
            if self.spotsReceived == 0 {
                switch self.status {
                case .connecting:
                    self.lastError = "\(host) hasn't sent anything. Check the host and port."
                case .loggingIn:
                    self.lastError = "\(host) hasn't accepted the login. Some nodes refuse "
                        + "unknown callsigns or connections from certain networks — see the "
                        + "node output below."
                case .connected:
                    self.lastError = "Logged in, but no spots yet. Quiet band, or the node's "
                        + "filters may need a command like SET/SKIMMER — type one below."
                case .disconnected:
                    break
                }
            }
        }
    }

    private func ingest(_ data: Data) {
        let (text, negotiationReply) = ClusterProtocol.stripTelnet(data)
        if !negotiationReply.isEmpty {
            transport?.write(negotiationReply)
        }
        guard !text.isEmpty else { return }
        buffer += text

        // Complete lines go to the console and the spot parser.
        let lines = ClusterProtocol.takeLines(from: &buffer)
        for line in lines {
            log(line)
            if let spot = SpotParser.parse(line, receivedAt: Date()) {
                spotsReceived += 1
                markConnected()
                onSpot?(spot)
            }
        }

        // The prompt may trail the last newline (DXSpider's "login: ") or be a
        // whole CRLF-terminated line (SDC's "Please enter your callsign:") —
        // by this point `takeLines` has consumed the second kind, so both the
        // lines and the remainder have to be offered to the check.
        if ClusterProtocol.isAwaitingLogin(lines: lines, remainder: buffer) {
            answerLoginPrompt()
        } else if status == .loggingIn, !lines.isEmpty {
            // The node answered the callsign with something other than another
            // prompt, so it took us. Waiting for a first spot instead would
            // leave a quiet feed — a local skimmer between decodes — stuck on
            // "Logging in…" and trip the watchdog's login-rejected warning.
            markConnected()
        }
        if buffer.count > 4096 { buffer = "" }
    }

    private func markConnected() {
        guard status != .connected else { return }
        status = .connected
        lastError = nil
    }

    private func answerLoginPrompt() {
        guard let transport else { return }
        loginAttempts += 1
        guard loginAttempts <= Self.maxLoginAttempts else {
            lastError = "\(callsign) was not accepted — the node keeps asking for a login. "
                + "Check the callsign, or try another node."
            log("*** login rejected after \(Self.maxLoginAttempts) attempts")
            teardown(keepConsole: true)
            return
        }
        log("> \(callsign)")
        transport.write("\(callsign)\r\n")
        buffer = ""
        status = .loggingIn
        sendInitialCommands()
    }

    /// Fire the startup commands a moment after login — nodes ignore input
    /// sent while they're still printing their post-login banner.
    private func sendInitialCommands() {
        guard !commandsSent, !pendingCommands.isEmpty else { return }
        commandsSent = true
        let commands = pendingCommands
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.status != .disconnected else { return }
            for command in commands {
                self.send(command)
            }
        }
    }
}

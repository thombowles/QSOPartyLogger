import Foundation

/// FlexRadio Signature (6000/8000 series) driver over the SmartSDR TCP API
/// (default port 4992). Unlike the K3's poll loop, Flex status is push-based:
/// subscribe once at start, then parse `S<handle>|…` status lines as they
/// arrive. CW is keyed through CWX, the radio's built-in macro keyer.
///
/// Wire format (SmartSDR TCP/IP API):
///   → `C<seq>|<command>`            command
///   ← `R<seq>|<code>|<message>`     response (0 = OK)
///   ← `S<handle>|<status text>`     subscribed status update
///   ← `V…` / `H…` / `M…`            version / handle / message on connect
///
/// Phone messages recorded on the Mac go to the radio over its own network
/// link — `AudioStreamTransmitCapable` — as DAX transmit audio: VITA-49
/// packets to UDP 4991, one every 128/24000 s, after the client has
/// registered its UDP port, claimed the DAX transmit source and created a
/// `dax_tx` stream; `transmit set dax=1` and `xmit 1` around the clip. Every
/// command is from the SmartSDR TCP/IP API wiki and the packet from FlexLib
/// 3.2.37, both banked — see `docs/research/voice_transports.md`, which also
/// names what a bench has not yet confirmed. Nothing network-side happens
/// until the first play (Article 11: never key, or open, on connect).
final class FlexRadioDriver: InternalKeyerDriver, AudioStreamTransmitCapable, @unchecked Sendable {

    static let defaultPort: UInt16 = 4992
    /// The port the radio takes VITA-49 packets on (FlexLib: `VitaSocket(4991, …, IP, 4991)`).
    static let daxUDPPort: UInt16 = 4991
    /// Silence streamed before the clip, so the first syllable is not lost in
    /// the interlock's PTT_REQUESTED → TRANSMITTING transition, and after it,
    /// so the last is not cut by `xmit 0`.
    static let leadSeconds: TimeInterval = 0.12
    static let tailSeconds: TimeInterval = 0.10

    private let lock = NSLock()
    private var transport: (any SerialTransport)?
    private var rxBuffer = ""
    private var seq = 0
    private var slices: [Int: SliceState] = [:]
    private var transmitting = false
    private var lastPublished: RadioState?
    private var lastWPM: Int?
    private var pingTimer: (any DispatchSourceTimer)?
    private let timerQueue = DispatchQueue(label: "org.b5n.QSOPartyLogger.flexping")

    var onStateChange: (@Sendable (RadioState) -> Void)?
    var onKeyerSpeedChange: (@Sendable (Int) -> Void)?
    var onTransmitAudioEvent: (@Sendable (TransmitAudioEvent) -> Void)?

    // MARK: Transmit-audio state (all under `lock`)

    /// Our own client handle from the `H<handle>` prologue — the way to tell
    /// our `dax_tx` stream's status from another client's.
    private var clientHandle: UInt32?
    /// `transmit … dax=<0|1>`: whether DAX is the transmit audio source right
    /// now, so it can be put back after a message. Nil until reported.
    private var transmitDAXOn: Bool?
    private var udp: (any UDPSending)?
    private var daxStreamID: UInt32?
    /// The radio's `tx=1` on our stream — the confirmation that packets we
    /// send are the ones it will modulate. Never key without it.
    private var daxStreamTX = false
    /// Whether `stream set <id> tx=1` has been sent for the current stream.
    /// The radio modulates only the dax_tx stream that has claimed transmit
    /// and drops packets from every other one — "PTT keys with silence" is
    /// what a stream that never claimed looks like.
    private var daxStreamTXClaimed = false
    private var pendingStreamCreateSeq: Int?
    /// The path's own log, most recent last, capped — see `transmitAudioTranscript`.
    private var transcript: [String] = []
    private static let transcriptCap = 120
    /// The clip waiting for the stream to be confirmed, or in flight.
    private var pendingClip: VoiceAudio?
    private var streamer: FlexDAXStreamer?
    private var isStreaming = false
    private var restoreDAXOffAfterPlay = false
    private var packetSequence = 0
    private var confirmTimer: (any DispatchSourceTimer)?
    /// Injected in tests; the app opens a real socket to the transport's host.
    var makeUDPSender: (String, UInt16) throws -> any UDPSending = { try UDPSender(host: $0, port: $1) }
    /// How long the first play waits for the radio to confirm the stream and
    /// mark it the transmit source before refusing.
    var streamConfirmTimeout: TimeInterval = 2

    private struct SliceState {
        var frequencyHz: Int?
        var rawMode: String?
        var active: Bool?
        var tx: Bool?
        var daxChannel: Int?
    }

    /// Parsed fields of one slice status delta (nil = key absent, keep old).
    struct SliceUpdate: Equatable {
        var index: Int
        var frequencyHz: Int?
        var rawMode: String?
        var active: Bool?
        /// `tx=<0|1>` — this slice is the transmitter.
        var tx: Bool?
        /// `dax=<n>` — the DAX channel assigned to the slice, 0 for none.
        var daxChannel: Int?
    }

    // MARK: Lifecycle

    func start(transport: any SerialTransport) {
        lock.withLock { self.transport = transport }
        transport.onReceive = { [weak self] data in
            self?.ingest(data)
        }
        // No `client program` handshake: the radio rejects unregistered
        // program names ("unknown client program"), and nothing needs it.
        sendCommand("sub slice all")
        sendCommand("sub tx all")
        sendCommand("sub cwx all")
        // Stream status for the DAX transmit path — the `tx=1` that says our
        // packets are the ones the radio will modulate. Subscribed here, not
        // at first play, so it is in place before the stream exists.
        sendCommand("sub dax all")

        // Heartbeat: keeps NAT/idle timeouts away on quiet receivers.
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 15, repeating: 15)
        timer.setEventHandler { [weak self] in
            self?.sendCommand("ping")
        }
        timer.resume()
        lock.withLock { pingTimer = timer }
    }

    func stop() {
        // A message still streaming comes down first — `xmit 0` while the
        // transport is still there to carry it.
        stopTransmitAudio()
        lock.lock()
        pingTimer?.cancel()
        pingTimer = nil
        confirmTimer?.cancel()
        confirmTimer = nil
        let streamID = daxStreamID
        let socket = udp
        daxStreamID = nil
        daxStreamTX = false
        daxStreamTXClaimed = false
        pendingStreamCreateSeq = nil
        pendingClip = nil
        udp = nil
        clientHandle = nil
        transmitDAXOn = nil
        packetSequence = 0
        lock.unlock()
        if let streamID { sendCommand(Self.cmdStreamRemove(streamID)) }
        socket?.close()
        lock.lock()
        transport = nil
        rxBuffer = ""
        slices = [:]
        transmitting = false
        lastPublished = nil
        lastWPM = nil
        lock.unlock()
    }

    /// Writes `C<seq>|<body>` and returns the sequence number, so a reply can
    /// be matched to the command that provoked it.
    @discardableResult
    private func sendCommand(_ body: String) -> Int {
        let n: Int = lock.withLock {
            seq += 1
            return seq
        }
        currentTransport()?.write("C\(n)|\(body)\n")
        return n
    }

    private func currentTransport() -> (any SerialTransport)? {
        lock.withLock { transport }
    }

    // MARK: RadioDriver commands

    func setFrequency(hz: Int) {
        let idx = activeSliceIndexOrDefault()
        sendCommand(Self.cmdTune(sliceIndex: idx, hz: hz))
        // SmartSDR broadcasts status for changes made elsewhere (VFO knob,
        // other clients) but does NOT echo back to the commanding client —
        // like FlexLib, we apply our own commands to our model directly.
        applyLocal(index: idx) { $0.frequencyHz = hz }
    }

    func setMode(rawMode: String) {
        let freq: Int = lock.withLock { lastPublished?.frequencyHz ?? 14_000_000 }
        guard let flexMode = Self.flexMode(forAppMode: rawMode, frequencyHz: freq) else { return }
        let idx = activeSliceIndexOrDefault()
        sendCommand(Self.cmdSetMode(sliceIndex: idx, flexMode: flexMode))
        applyLocal(index: idx) { $0.rawMode = Self.appRawMode(flexMode: flexMode) }
    }

    /// Apply a self-commanded change to the local slice model and publish —
    /// a later radio echo (if any) dedupes against `lastPublished`.
    private func applyLocal(index: Int, _ mutate: (inout SliceState) -> Void) {
        lock.lock()
        var slice = slices[index] ?? SliceState()
        mutate(&slice)
        slices[index] = slice
        let state = publishableStateLocked()
        lock.unlock()
        if let state { onStateChange?(state) }
    }

    func setKeyerSpeed(wpm: Int) {
        sendCommand(Self.cmdKeyerSpeed(wpm: wpm))
    }

    func sendInternalKeyerText(_ text: String) {
        sendCommand(Self.cmdSendCW(text))
    }

    func stopInternalKeyer() {
        sendCommand("cwx clear")
    }

    private func activeSliceIndexOrDefault() -> Int {
        lock.withLock { slices.first(where: { $0.value.active == true })?.key ?? 0 }
    }

    // MARK: Command builders (pure — unit tested)

    static func cmdTune(sliceIndex: Int, hz: Int) -> String {
        String(format: "slice tune %d %.6f", sliceIndex, Double(hz) / 1_000_000)
    }

    static func cmdSetMode(sliceIndex: Int, flexMode: String) -> String {
        "slice set \(sliceIndex) mode=\(flexMode)"
    }

    /// `cw wpm`, **not** `cwx wpm`. Every other verb the CWX page documents is
    /// `cwx <verb>`; WPM alone is not, and it is printed the same way on the
    /// `cw` page — see `docs/research/flex_smartsdr_tcpip_api_cw.txt`. The
    /// radio answers an unknown command with an error rather than a complaint
    /// the app would notice, so the `cwx wpm` this used to send simply meant
    /// speed never changed at all.
    static func cmdKeyerSpeed(wpm: Int) -> String {
        "cw wpm \(min(50, max(8, wpm)))"
    }

    /// CWX rejects embedded quotes — strip rather than escape.
    static func cmdSendCW(_ text: String) -> String {
        "cwx send \"\(text.replacingOccurrences(of: "\"", with: ""))\""
    }

    // MARK: Command builders — transmit audio (SmartSDR TCP/IP API wiki, banked)

    /// `client udpport <port>` — "the UDP port that should be used on the
    /// client to receive streaming VITA-49 UDP data … entered once at the
    /// start of a session". Ours is the port our packets leave from.
    static func cmdClientUDPPort(_ port: UInt16) -> String { "client udpport \(port)" }

    /// `dax audio set <channel> [slice=<slice>] tx=1` — "enable … the client
    /// as transmit source for DAX channel … It uses the client ID for the
    /// sender of this command". `slice=` only when the channel is being
    /// assigned to a slice that had none.
    static func cmdDAXAudioSetTX(channel: Int, slice: Int?) -> String {
        "dax audio set \(channel)" + (slice.map { " slice=\($0)" } ?? "") + " tx=1"
    }

    static let cmdStreamCreateDAXTX = "stream create type=dax_tx"

    static func hexID(_ streamID: UInt32) -> String {
        "0x\(String(streamID, radix: 16, uppercase: true))"
    }

    static func cmdStreamRemove(_ streamID: UInt32) -> String {
        "stream remove \(hexID(streamID))"
    }

    /// `stream set <stream_id> tx=1` — claims transmit for our dax_tx stream.
    /// The wiki documents the command; two working clients (and FlexLib's
    /// later `RequestTX`) show it is what makes the radio modulate *this*
    /// stream rather than another client's.
    static func cmdStreamSetTX(_ streamID: UInt32) -> String {
        "stream set \(hexID(streamID)) tx=1"
    }

    /// `transmit set dax=<0|1>` — "enable (dax=1) or disable (dax=0) DAX as
    /// the primary transmit audio source".
    static func cmdTransmitDAX(_ on: Bool) -> String { "transmit set dax=\(on ? 1 : 0)" }

    /// `xmit <state>` — "Instructs the radio to start or stop transmitting".
    static func cmdXmit(_ on: Bool) -> String { "xmit \(on ? 1 : 0)" }

    /// The wiki's meanings for the reply codes this path can meet, so the
    /// operator reads "no UDP port registered" and not only a hex number.
    static func replyMeaning(_ code: UInt32) -> String? {
        switch code {
        case 0x50000025: "client stream id not found"
        case 0x5000002C: "incorrect number of parameters"
        case 0x5000003D: "transmit not supported in this radio"
        case 0x50000042: "not ready to transmit"
        case 0x50000043: "no transmitter"
        case 0x50000059: "invalid stream id"
        case 0x50000064: "no UDP port registered"
        case 0x50000065: "invalid DAX channel"
        default: nil
        }
    }

    static func streamRefusedText(code: UInt32) -> String {
        let meaning = replyMeaning(code).map { " — \($0)" } ?? ""
        return String(format: "The radio refused the transmit audio stream (0x%08X%@).", code, meaning)
    }

    // MARK: Mode mapping

    /// Flex mode → ADIF-style app mode.
    static func appRawMode(flexMode: String) -> String {
        switch flexMode.uppercased() {
        case "DIGU", "DIGL": "RTTY"
        default: flexMode.uppercased()
        }
    }

    /// App mode → Flex mode; "SSB" resolves to the conventional sideband for
    /// the frequency (USB at/above 10 MHz, LSB below).
    static func flexMode(forAppMode mode: String, frequencyHz: Int) -> String? {
        switch mode.uppercased() {
        case "CW": "CW"
        case "USB": "USB"
        case "LSB": "LSB"
        case "SSB": frequencyHz >= 10_000_000 ? "USB" : "LSB"
        case "RTTY", "DIGI": "DIGU"
        case "AM": "AM"
        case "FM": "FM"
        default: nil
        }
    }

    // MARK: Status parsing (pure — unit tested)

    /// `slice <n> key=value …` → delta of the fields the app cares about.
    static func parseSlice(_ status: String) -> SliceUpdate? {
        let tokens = status.split(separator: " ")
        guard tokens.count >= 2, tokens[0] == "slice", let index = Int(tokens[1]) else { return nil }
        var update = SliceUpdate(index: index)
        for token in tokens.dropFirst(2) {
            let kv = token.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "RF_frequency":
                if let mhz = Double(kv[1]) {
                    update.frequencyHz = Int((mhz * 1_000_000).rounded())
                }
            case "mode":
                update.rawMode = appRawMode(flexMode: String(kv[1]))
            case "active":
                update.active = kv[1] == "1"
            case "tx":
                update.tx = kv[1] == "1"
            case "dax":
                update.daxChannel = Int(kv[1])
            default:
                break
            }
        }
        return update
    }

    /// `H<handle>` from the connection prologue → our client handle.
    static func parseHandle(_ line: String) -> UInt32? {
        guard line.hasPrefix("H"), line.count > 1 else { return nil }
        return UInt32(line.dropFirst(), radix: 16)
    }

    /// `R<seq>|<hex code>|<message>[|debug]` → the pieces the driver acts on.
    static func parseReply(_ line: String) -> (seq: Int, code: UInt32, message: String)? {
        guard line.hasPrefix("R") else { return nil }
        let parts = line.dropFirst().split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count >= 2, let seq = Int(parts[0]), let code = UInt32(parts[1], radix: 16) else { return nil }
        let message = parts.count >= 3 ? String(parts[2]) : ""
        return (seq, code, message)
    }

    /// One `stream <id> …` status line, as the driver reads it.
    struct StreamUpdate: Equatable {
        var id: UInt32
        var type: String?
        var clientHandle: UInt32?
        var tx: Bool?
        var removed: Bool
    }

    /// `stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1`, or
    /// `stream 0x84000001 removed`. Ids and handles are hex with or without
    /// the `0x` — FlexLib's `TryParseInteger` accepts both.
    static func parseStreamStatus(_ status: String) -> StreamUpdate? {
        let tokens = status.split(separator: " ")
        guard tokens.count >= 2, tokens[0] == "stream", let id = parseHex(tokens[1]) else { return nil }
        var update = StreamUpdate(id: id, removed: false)
        for token in tokens.dropFirst(2) {
            if token == "removed" { update.removed = true; continue }
            let kv = token.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "type": update.type = String(kv[1])
            case "client_handle": update.clientHandle = parseHex(kv[1])
            case "tx": update.tx = kv[1] == "1"
            default: break
            }
        }
        return update
    }

    /// `transmit … dax=<0|1> …` → whether DAX is the transmit audio source;
    /// nil when the line is not a transmit status or carries no `dax`.
    static func parseTransmitDAX(_ status: String) -> Bool? {
        guard status == "transmit" || status.hasPrefix("transmit ") else { return nil }
        guard let token = status.split(separator: " ").first(where: { $0.hasPrefix("dax=") }) else { return nil }
        return token.dropFirst("dax=".count) == "1"
    }

    private static func parseHex(_ text: Substring) -> UInt32? {
        let body = text.hasPrefix("0x") || text.hasPrefix("0X") ? text.dropFirst(2) : text
        return UInt32(body, radix: 16)
    }

    /// `interlock … state=<STATE> …` → is the radio transmitting?
    static func parseInterlockTransmitting(_ status: String) -> Bool? {
        guard status == "interlock" || status.hasPrefix("interlock ") else { return nil }
        guard let stateToken = status.split(separator: " ").first(where: { $0.hasPrefix("state=") }) else {
            return nil
        }
        return stateToken.dropFirst("state=".count) == "TRANSMITTING"
    }

    /// `cwx … wpm=<n> …` → keyer speed (radio-side changes sync the app).
    static func parseCWXSpeed(_ status: String) -> Int? {
        guard status == "cwx" || status.hasPrefix("cwx ") else { return nil }
        guard let wpmToken = status.split(separator: " ").first(where: { $0.hasPrefix("wpm=") }) else {
            return nil
        }
        return Int(wpmToken.dropFirst("wpm=".count))
    }

    // MARK: RX plumbing

    private func ingest(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else { return }
        lock.lock()
        rxBuffer += text
        var lines: [String] = []
        while let nl = rxBuffer.firstIndex(of: "\n") {
            lines.append(String(rxBuffer[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines))
            rxBuffer = String(rxBuffer[rxBuffer.index(after: nl)...])
        }
        if rxBuffer.count > 8192 { rxBuffer = "" }
        lock.unlock()

        for line in lines where !line.isEmpty {
            handle(line: line)
        }
    }

    private func handle(line: String) {
        // The prologue's handle and the replies matter to the transmit-audio
        // path; V and M lines do not.
        if let handle = Self.parseHandle(line) {
            lock.withLock { clientHandle = handle }
            return
        }
        if let reply = Self.parseReply(line) {
            handleReply(reply)
            return
        }
        guard line.hasPrefix("S"), let bar = line.firstIndex(of: "|") else { return }
        let status = String(line[line.index(after: bar)...])

        if let update = Self.parseSlice(status) {
            apply(update: update)
        } else if let tx = Self.parseInterlockTransmitting(status) {
            lock.lock()
            transmitting = tx
            let state = publishableStateLocked()
            lock.unlock()
            if let state { onStateChange?(state) }
        } else if let wpm = Self.parseCWXSpeed(status) {
            lock.lock()
            let changed = wpm != lastWPM
            lastWPM = wpm
            lock.unlock()
            if changed { onKeyerSpeedChange?(wpm) }
        } else if let dax = Self.parseTransmitDAX(status) {
            let changed: Bool = lock.withLock {
                defer { transmitDAXOn = dax }
                return transmitDAXOn != dax
            }
            if changed { note("← transmit dax=\(dax ? 1 : 0)") }
        } else if let stream = Self.parseStreamStatus(status) {
            handleStreamStatus(stream)
        }
    }

    private func apply(update: SliceUpdate) {
        lock.lock()
        var slice = slices[update.index] ?? SliceState()
        if let f = update.frequencyHz { slice.frequencyHz = f }
        if let m = update.rawMode { slice.rawMode = m }
        if let a = update.active { slice.active = a }
        if let t = update.tx { slice.tx = t }
        if let d = update.daxChannel { slice.daxChannel = d }
        slices[update.index] = slice
        let state = publishableStateLocked()
        lock.unlock()
        if let state { onStateChange?(state) }
    }

    /// Build the app-facing state from the active slice; nil when nothing
    /// changed or no slice is active yet. Caller must hold the lock.
    private func publishableStateLocked() -> RadioState? {
        guard let active = slices.values.first(where: { $0.active == true }),
              let freq = active.frequencyHz else { return nil }
        let state = RadioState(
            frequencyHz: freq,
            rawMode: active.rawMode ?? "USB",
            isTransmitting: transmitting
        )
        guard state != lastPublished else { return nil }
        lastPublished = state
        return state
    }

    // MARK: Transmit audio over DAX (AudioStreamTransmitCapable)

    var transmitSampleRate: Double { FlexDAXPacketizer.sampleRate }

    var transmitAudioTranscript: [String] { lock.withLock { transcript } }

    /// One line in the path's own log — timestamped, capped, readable from the
    /// Phone tab. Called with the lock *not* held.
    private func note(_ line: String) {
        let stamp = Self.transcriptClock.string(from: Date())
        lock.withLock {
            transcript.append("\(stamp)  \(line)")
            if transcript.count > Self.transcriptCap { transcript.removeFirst(transcript.count - Self.transcriptCap) }
        }
    }

    private static let transcriptClock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// A command on the voice path: sent and noted.
    @discardableResult
    private func sendVoiceCommand(_ body: String) -> Int {
        let seq = sendCommand(body)
        note("→ C\(seq)|\(body)")
        return seq
    }

    /// Key the radio, stream `audio`, unkey. The first play of a session
    /// sets the stream up — socket, `client udpport`, the transmit-source
    /// claim, `stream create` — and waits for the radio to confirm the
    /// stream is ours and marked `tx=1` before anything is keyed. A second
    /// call while one is in flight replaces it.
    func transmitAudio(_ audio: VoiceAudio) {
        stopTransmitAudio()
        let (needsSocket, needsStream): (Bool, Bool) = lock.withLock {
            pendingClip = audio
            return (udp == nil, daxStreamID == nil)
        }
        note(String(format: "play requested: %.2f s of audio at %.0f Hz", audio.duration, audio.sampleRate))

        if needsSocket {
            guard let host = (currentTransport() as? any NetworkTransport)?.hostName else {
                fail("This radio was not reached over the network, so it cannot take audio from the Mac.")
                return
            }
            let socket: any UDPSending
            do {
                socket = try makeUDPSender(host, Self.daxUDPPort)
            } catch {
                fail(error.localizedDescription)
                return
            }
            let (channel, sliceToAssign): (Int, Int?) = lock.withLock {
                udp = socket
                // The transmit slice's own DAX channel, or channel 1 assigned
                // to it when it has none — nothing is reassigned when a
                // channel is already there.
                let tx = slices.first(where: { $0.value.tx == true })
                if let tx, let dax = tx.value.daxChannel, dax > 0 { return (dax, nil) }
                return (1, tx?.key)
            }
            note("udp: from \(socket.localDescription) → \(host):\(Self.daxUDPPort)")
            sendVoiceCommand(Self.cmdClientUDPPort(socket.localPort))
            sendVoiceCommand(Self.cmdDAXAudioSetTX(channel: channel, slice: sliceToAssign))
        }
        if needsSocket || needsStream {
            // First play, or the radio removed our stream since: create (again).
            let created = sendVoiceCommand(Self.cmdStreamCreateDAXTX)
            lock.withLock {
                pendingStreamCreateSeq = created
                daxStreamTXClaimed = false
            }
        }
        // Armed before the readiness check, which cancels it the moment it
        // starts streaming — so a stream the radio never confirms fails
        // rather than leaving a clip pending forever.
        armConfirmTimer()
        claimTransmitIfNeeded()
        beginStreamingIfReady()
    }

    func stopTransmitAudio() {
        lock.lock()
        confirmTimer?.cancel()
        confirmTimer = nil
        let wasStreaming = isStreaming
        let hadPending = pendingClip != nil
        let restore = restoreDAXOffAfterPlay
        let running = streamer
        isStreaming = false
        pendingClip = nil
        streamer = nil
        restoreDAXOffAfterPlay = false
        lock.unlock()
        running?.stop()
        guard wasStreaming || hadPending else { return }
        if wasStreaming {
            sendVoiceCommand(Self.cmdXmit(false))
            if restore { sendVoiceCommand(Self.cmdTransmitDAX(false)) }
        }
        note("stopped by the operator")
        onTransmitAudioEvent?(.stopped)
    }

    // MARK: Setup replies and confirmations

    private func handleReply(_ reply: (seq: Int, code: UInt32, message: String)) {
        let isStreamCreate: Bool = lock.withLock { reply.seq == pendingStreamCreateSeq }
        guard isStreamCreate else { return }
        note(String(format: "← R%d|%08X|%@", reply.seq, reply.code, reply.message))
        lock.withLock { pendingStreamCreateSeq = nil }
        guard reply.code == 0 else {
            lock.withLock { confirmTimer?.cancel(); confirmTimer = nil }
            fail(Self.streamRefusedText(code: reply.code))
            return
        }
        // The reply carries the id in its message field; the status line
        // that follows carries it too, and `tx=`. Take whichever lands first.
        if let id = Self.parseHex(Substring(reply.message.trimmingCharacters(in: .whitespaces))) {
            lock.withLock { if daxStreamID == nil { daxStreamID = id } }
        }
        claimTransmitIfNeeded()
        beginStreamingIfReady()
    }

    private func handleStreamStatus(_ update: StreamUpdate) {
        lock.lock()
        let mine: Bool
        if update.removed {
            mine = update.id == daxStreamID
            if mine {
                daxStreamID = nil
                daxStreamTX = false
                daxStreamTXClaimed = false
            }
            lock.unlock()
            if mine { note("← stream \(Self.hexID(update.id)) removed by the radio") }
            return
        }
        // Ours if it names our handle, or if it is the id our create returned.
        let handleMatches = update.clientHandle != nil && update.clientHandle == clientHandle
        mine = update.type == "dax_tx" && (update.id == daxStreamID || (daxStreamID == nil && handleMatches))
        if mine {
            if daxStreamID == nil { daxStreamID = update.id }
            if let tx = update.tx { daxStreamTX = tx }
        }
        lock.unlock()
        if update.type == "dax_tx" {
            note("← stream \(Self.hexID(update.id)) type=dax_tx"
                 + (update.clientHandle.map { " client_handle=\(Self.hexID($0))" } ?? "")
                 + (update.tx.map { " tx=\($0 ? 1 : 0)" } ?? "")
                 + (mine ? "  (ours)" : "  (another client's)"))
        }
        if mine {
            claimTransmitIfNeeded()
            beginStreamingIfReady()
        }
    }

    /// Once the stream id is known, claim transmit for it — once per stream,
    /// and whatever the status line said: the bench showed the radio
    /// reporting `tx=1` on a fresh stream by itself and still modulating
    /// nothing, and the clients that work send the claim unconditionally.
    /// The radio modulates only the dax_tx stream that has *called* this and
    /// drops packets from every other; without it a message keys the radio
    /// and puts silence on it.
    private func claimTransmitIfNeeded() {
        let claim: UInt32? = lock.withLock {
            guard let id = daxStreamID, !daxStreamTXClaimed, pendingClip != nil else { return nil }
            daxStreamTXClaimed = true
            return id
        }
        guard let claim else { return }
        sendVoiceCommand(Self.cmdStreamSetTX(claim))
    }

    /// The window a first play waits for the radio to answer the create and
    /// mark the stream as ours to transmit on. Nothing is keyed meanwhile.
    private func armConfirmTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + streamConfirmTimeout)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let stillWaiting: Bool = self.lock.withLock {
                guard self.pendingClip != nil, !self.isStreaming else { return false }
                self.confirmTimer = nil
                return true
            }
            guard stillWaiting else { return }
            self.fail("The radio did not confirm the transmit audio stream in time. If another program on "
                      + "the network holds the radio's transmit audio (its transmit channel enabled), turn "
                      + "that off and try again.")
        }
        timer.resume()
        lock.withLock {
            confirmTimer?.cancel()
            confirmTimer = timer
        }
    }

    /// Stream id known, `tx=1` seen, a clip waiting: key and go.
    private func beginStreamingIfReady() {
        lock.lock()
        guard !isStreaming, let clip = pendingClip, let streamID = daxStreamID, daxStreamTX,
              let socket = udp else {
            lock.unlock()
            return
        }
        confirmTimer?.cancel()
        confirmTimer = nil
        isStreaming = true
        let daxWasOn = transmitDAXOn == true
        restoreDAXOffAfterPlay = !daxWasOn
        let start = packetSequence
        // Registered under the lock, so a stop that lands before the first
        // packet finds it and ends it — the streamer is single-use.
        let streamer = FlexDAXStreamer(sender: socket, intervalSeconds: FlexDAXPacketizer.packetInterval)
        self.streamer = streamer
        lock.unlock()

        let rate = FlexDAXPacketizer.sampleRate
        var samples = VoiceAudio.silence(seconds: Self.leadSeconds, sampleRate: rate).samples
        samples += clip.samples
        samples += VoiceAudio.silence(seconds: Self.tailSeconds, sampleRate: rate).samples
        let packets = FlexDAXPacketizer.packets(for: VoiceAudio(sampleRate: rate, samples: samples),
                                                streamID: streamID, startingSequence: start)
        lock.withLock { packetSequence = FlexDAXPacketizer.nextSequence(after: start, packetCount: packets.count) }
        note(String(format: "stream %@ confirmed tx=1; %d packets to send (peak %.2f), transmit source dax was %@",
                    Self.hexID(streamID), packets.count, clip.peak, daxWasOn ? "on" : "off"))

        if !daxWasOn { sendVoiceCommand(Self.cmdTransmitDAX(true)) }
        sendVoiceCommand(Self.cmdXmit(true))
        streamer.stream(
            packets,
            onFirstPacket: { [weak self] in
                self?.note("first packet sent")
                self?.onTransmitAudioEvent?(.started)
            },
            onFinished: { [weak self] in
                guard let self else { return }
                // Nil when a stop already unkeyed and reported this play —
                // then there is nothing left to send or say.
                let restore: Bool? = self.lock.withLock {
                    guard self.isStreaming, self.streamer === streamer else { return nil }
                    self.isStreaming = false
                    self.pendingClip = nil
                    self.streamer = nil
                    defer { self.restoreDAXOffAfterPlay = false }
                    return self.restoreDAXOffAfterPlay
                }
                guard let restore else { return }
                let failures = socket.sendFailures
                if failures.count == 0 {
                    self.note("all \(packets.count) packets handed to the kernel from \(socket.localDescription), no send errors")
                } else {
                    let reason = failures.lastErrno.map { String(cString: strerror($0)) } ?? "?"
                    self.note("\(failures.count) of \(packets.count) sends failed — last error: \(reason)")
                }
                self.sendVoiceCommand(Self.cmdXmit(false))
                if restore { self.sendVoiceCommand(Self.cmdTransmitDAX(false)) }
                self.onTransmitAudioEvent?(.finished)
            }
        )
    }

    /// Nothing was keyed, or it has already been unkeyed: report and clear.
    private func fail(_ reason: String) {
        lock.withLock {
            pendingClip = nil
            pendingStreamCreateSeq = nil
            confirmTimer?.cancel()
            confirmTimer = nil
        }
        note("failed: \(reason)")
        onTransmitAudioEvent?(.failed(reason))
    }
}

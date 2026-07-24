import Foundation

/// Something that can transmit CW text: the direct DTR/RTS keyer or the
/// radio's internal keyer.
protocol CWSender: AnyObject {
    var wpm: Int { get set }
    func send(_ text: String)
    func abort()
}

/// How serial control lines are wired for keying.
struct KeyerLineConfig: Codable, Equatable, Sendable {
    /// Line that keys CW. K3 CONFIG:PTT-KEY maps DTR and/or RTS.
    var keyLine: SerialLine = .dtr
    /// Optional PTT line asserted around transmissions.
    var pttLine: SerialLine? = .rts
    var pttEnabled: Bool = false
    var pttLeadMs: Int = 50
    var pttTailMs: Int = 50
}

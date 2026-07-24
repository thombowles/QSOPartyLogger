import Foundation

/// K3 mode digits (MD command). Raw values are the CAT protocol digits.
enum K3Mode: Character, Sendable {
    case lsb = "1"
    case usb = "2"
    case cw = "3"
    case fm = "4"
    case am = "5"
    case data = "6"
    case cwReverse = "7"
    case dataReverse = "9"

    /// ADIF-style mode string for logging.
    var rawMode: String {
        switch self {
        case .lsb: "LSB"
        case .usb: "USB"
        case .cw, .cwReverse: "CW"
        case .fm: "FM"
        case .am: "AM"
        case .data, .dataReverse: "RTTY"
        }
    }

    var modeClass: ModeClass {
        ModeClass.classify(rawMode: rawMode)
    }
}

struct RadioState: Equatable, Sendable {
    var frequencyHz: Int
    var mode: K3Mode
    var isTransmitting: Bool

    var frequencyKHz: Int { frequencyHz / 1000 }
    var band: Band? { Band.from(freqKHz: frequencyKHz) }

    var displayFrequency: String {
        let mhz = Double(frequencyHz) / 1_000_000.0
        return String(format: "%.5f", mhz)
    }
}

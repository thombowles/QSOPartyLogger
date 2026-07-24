import Foundation

/// A radio command typed into the callsign field — frequency, band, or mode —
/// so QSY never requires leaving the keyboard. Enter executes the command
/// instead of logging; anything that could be a callsign parses as nil.
enum EntryCommand: Equatable {
    case frequency(kHz: Double)
    case band(Band)
    case mode(String)

    static let modeTokens: Set<String> = ["CW", "SSB", "USB", "LSB", "RTTY", "AM", "FM", "DIGI"]

    static func parse(_ text: String) -> EntryCommand? {
        let token = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !token.isEmpty else { return nil }

        if modeTokens.contains(token) {
            return .mode(token)
        }
        if let band = Band.allCases.first(where: { $0.rawValue.uppercased() == token }) {
            return .band(band)
        }

        // Frequency: "14025" / "14025.5" (kHz) or "14.025" (MHz). Accepted
        // only when it lands inside a known amateur band — "599" is an RST,
        // not a QSY, and a bare "14" is too ambiguous to act on.
        guard token.allSatisfy({ $0.isNumber || $0 == "." }),
              let value = Double(token) else { return nil }
        let kHz: Double
        if value < 100 {
            guard token.contains(".") else { return nil }
            kHz = (value * 10_000).rounded() / 10  // MHz → kHz at 0.1 kHz resolution
        } else {
            kHz = value
        }
        guard Band.from(freqKHz: Int(kHz.rounded())) != nil else { return nil }
        return .frequency(kHz: kHz)
    }
}

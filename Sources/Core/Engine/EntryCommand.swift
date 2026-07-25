import Foundation

/// A radio command typed into the callsign field — frequency, band, or mode —
/// so QSY never requires leaving the keyboard. Enter executes the command
/// instead of logging; anything that could be a callsign parses as nil.
enum EntryCommand: Equatable {
    case frequency(kHz: Double)
    case band(Band)
    case mode(String)

    static let modeTokens: Set<String> = ["CW", "SSB", "USB", "LSB", "RTTY", "AM", "FM", "DIGI"]

    /// Spoken band names that are not the ADIF band string. Only 1.25 m needs
    /// one: nobody says "one point two five meters" on the air, and "222" is
    /// otherwise read as 222 kHz and rejected as out of band. Bare band numbers
    /// deliberately do not work for the other bands — "160" stays an unparsed
    /// token, exactly as before.
    static let bandAliases: [String: Band] = ["222": .cm125]

    static func parse(_ text: String) -> EntryCommand? {
        let token = text.trimmingCharacters(in: .whitespaces).uppercased()
        guard !token.isEmpty else { return nil }

        if modeTokens.contains(token) {
            return .mode(token)
        }
        if let band = Band.allCases.first(where: { $0.rawValue.uppercased() == token }) {
            return .band(band)
        }
        // Before the numeric branch below — "222" is numeric and would
        // otherwise be read as a frequency and rejected.
        if let band = bandAliases[token] {
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

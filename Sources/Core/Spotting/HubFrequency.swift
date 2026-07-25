import Foundation

/// Reading the hub's operator-typed frequency column.
///
/// The field is free text with a `14150` placeholder, and operators fill it
/// however they think in: `14045.25` and `14226` in kHz, `14.041` in MHz,
/// `143095` with the decimal point dropped altogether. All of those are real
/// values from the captured corpus.
///
/// Each reading is tried in turn and the first that lands on an amateur band
/// wins. The order matters and the design is safe by construction: the later
/// readings are only ever reached by a value no earlier one accepts, so a
/// perfectly good kHz frequency can never be re-interpreted as something else.
enum HubFrequency {

    enum Confidence: String, Sendable, Equatable {
        /// Read as typed.
        case reported
        /// Recovered from a value that was not a valid frequency as written.
        /// Worth showing differently, and worth a warning before the radio is
        /// tuned there — this is inference, not information.
        case reconstructed
    }

    struct Resolved: Equatable, Sendable {
        let kHz: Double
        let confidence: Confidence
    }

    static func normalize(_ raw: String) -> Resolved? {
        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value > 0 else { return nil }

        // As typed, in kHz — what the form asks for.
        if isAmateurBand(value) {
            return Resolved(kHz: value, confidence: .reported)
        }
        // Typed in MHz: "14.041".
        if isAmateurBand(value * 1000) {
            return Resolved(kHz: value * 1000, confidence: .reconstructed)
        }
        // Decimal point dropped: "143095" for 14309.5. Only reachable when the
        // value is not a band frequency in either reading above — 143.095 MHz
        // falls in the gap below 2 m, which is exactly why this is safe.
        if isAmateurBand(value / 10) {
            return Resolved(kHz: value / 10, confidence: .reconstructed)
        }
        return nil
    }

    private static func isAmateurBand(_ kHz: Double) -> Bool {
        guard kHz > 0, kHz < Double(Int.max) else { return false }
        return Band.from(freqKHz: Int(kHz.rounded())) != nil
    }
}

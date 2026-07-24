import Foundation

/// Parses DX cluster spot lines in the two layouts a node emits:
///
///   broadcast:  DX de W3LPL:     14026.1  K5ABC     loud in VA      1523Z
///   sh/dx reply:  14026.1  K5ABC     24-Jul-2026 1523Z  loud in VA  <W3LPL>
///
/// Everything that isn't a well-formed spot on a known amateur band is nil —
/// cluster chatter (WWV, talk, prompts, column headers) never reaches the store.
enum SpotParser {

    static func parse(_ line: String, receivedAt: Date) -> Spot? {
        parseBroadcast(line, receivedAt: receivedAt) ?? parseShowDX(line, receivedAt: receivedAt)
    }

    /// Live `DX de …` broadcast line.
    static func parseBroadcast(_ line: String, receivedAt: Date) -> Spot? {
        let tokens = line.split(separator: " ").map(String.init)
        guard tokens.count >= 5, tokens[0] == "DX", tokens[1] == "de" else { return nil }

        let spotter = tokens[2].hasSuffix(":") ? String(tokens[2].dropLast()) : tokens[2]
        guard let freqKHz = Double(tokens[3]),
              Band.from(freqKHz: Int(freqKHz.rounded())) != nil else { return nil }

        let call = tokens[4].uppercased()
        guard call.count >= 3, call.contains(where: \.isNumber) else { return nil }

        // Trailing "1523Z" time stamp is metadata, not comment.
        var rest = Array(tokens.dropFirst(5))
        if let last = rest.last, last.count == 5, last.hasSuffix("Z"),
           last.dropLast().allSatisfy(\.isNumber) {
            rest.removeLast()
        }

        return Spot(
            call: call,
            freqKHz: freqKHz,
            spotter: spotter.uppercased(),
            comment: rest.joined(separator: " "),
            receivedAt: receivedAt
        )
    }

    /// Columnar `sh/dx` reply, identified by its trailing `<spotter>`. The
    /// embedded date/time is the spot's real age — a batch reply can contain
    /// spots that are already hours old.
    static func parseShowDX(_ line: String, receivedAt: Date) -> Spot? {
        var tokens = line.split(separator: " ").map(String.init)
        guard tokens.count >= 4,
              let last = tokens.last,
              last.hasPrefix("<"), last.hasSuffix(">") else { return nil }
        let spotter = String(last.dropFirst().dropLast()).uppercased()
        tokens.removeLast()
        guard !spotter.isEmpty else { return nil }

        guard let freqKHz = Double(tokens[0]),
              Band.from(freqKHz: Int(freqKHz.rounded())) != nil else { return nil }

        let call = tokens[1].uppercased()
        guard call.count >= 3, call.contains(where: \.isNumber) else { return nil }

        // tokens[2..3] are the date and HHMMZ time; the rest is the comment.
        var comment = Array(tokens.dropFirst(2))
        var timestamp = receivedAt
        if comment.count >= 2,
           let date = parseShowDXDate(day: comment[0], time: comment[1]) {
            timestamp = date
            comment.removeFirst(2)
        }

        return Spot(
            call: call,
            freqKHz: freqKHz,
            spotter: spotter,
            comment: comment.joined(separator: " "),
            receivedAt: timestamp
        )
    }

    /// "24-Jul-2026" + "1523Z" → Date (UTC), or nil if it isn't that shape.
    private static func parseShowDXDate(day: String, time: String) -> Date? {
        guard time.hasSuffix("Z"), time.count == 5 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "d-MMM-yyyy HHmm"
        return formatter.date(from: "\(day) \(time.dropLast())")
    }
}

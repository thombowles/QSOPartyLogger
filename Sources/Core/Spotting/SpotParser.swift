import Foundation

/// Parses DX cluster spot lines (DXSpider / AR-Cluster / CC Cluster style):
///
///     DX de W3LPL:     14026.1  K5ABC        loud in VA          1523Z
///
/// Everything that isn't a well-formed spot on a known amateur band is nil —
/// cluster chatter (WWV, talk, prompts) never reaches the store.
enum SpotParser {

    static func parse(_ line: String, receivedAt: Date) -> Spot? {
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
}

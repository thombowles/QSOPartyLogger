import Foundation

/// Kilohertz the way every board's own form asks for it — `14150`, or
/// `14045.25` — with no trailing zeros and never more than two decimals. Ten
/// hertz is the finest any spot carries; below that is noise, and the hub's
/// frequency field only accepts ten characters.
///
/// Not `%g`: its six significant digits turn 14045.25 into 14045.2, which
/// would broadcast a frequency 50 Hz off to everyone reading the board.
enum SpotFrequency {
    static func text(kHz: Double) -> String {
        if kHz == kHz.rounded() { return String(Int(kHz)) }
        var text = String(format: "%.2f", kHz)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}

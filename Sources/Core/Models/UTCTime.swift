import Foundation

/// One spelling of a UTC time and one of a duration, for every line of copy
/// that quotes either.
///
/// Contest operators read Zulu times as four digits — "0112Z", not "01:12" —
/// and a second spelling appearing in one advisory and not another is the kind
/// of drift nobody notices until it looks like two different clocks.
enum UTCTime {

    /// `0112Z`.
    static func zulu(_ date: Date) -> String {
        formatter("HHmm'Z'").string(from: date)
    }

    /// `10 h 20 m`, `45 m`, `2 h` — a span in the units it is worth reading in.
    /// Rounded down to the minute, because "opens in 10 h 20 m" reading a
    /// minute early is the error that matters.
    static func span(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        let (hours, remainder) = (minutes / 60, minutes % 60)
        if hours == 0 { return "\(remainder) m" }
        if remainder == 0 { return "\(hours) h" }
        return "\(hours) h \(remainder) m"
    }

    /// `90 min` — for spans an operator thinks about in minutes flat, like the
    /// tail of an operating window.
    static func minutes(_ seconds: TimeInterval) -> String {
        "\(max(0, Int(seconds / 60))) min"
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }
}

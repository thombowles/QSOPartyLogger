import Foundation

/// The CQ WPX prefix of a callsign, per rule V.C.1 (docs/research/cqwpx_rules_2026.txt):
/// "the letter/numeral combination which forms the first part of the amateur
/// call … In cases of portable operation, the portable designator will then
/// become the prefix … Portable designators without numbers will be assigned a
/// zero (Ø) after the second letter … All calls without numbers will be
/// assigned a zero (Ø) after the first two letters … Maritime mobile, mobile,
/// /A, /E, /J, /P, or other license class identifiers do not count as prefixes."
enum WPXPrefix {
    /// Suffixes that are class identifiers, not designators. `MM`, mobile
    /// (`M`), `/A /E /J /P` are the sponsor's list; `AM` and `QRP` are read
    /// as "other license class identifiers" — an inference, like the
    /// bare-digit rule below.
    static let ignoredSuffixes: Set<String> = ["MM", "AM", "M", "A", "E", "J", "P", "QRP"]

    /// - Parameter isKnownPrefix: Answers "is this whole part an authorized
    ///   prefix?" Rule V.C.1 says a portable prefix "must be an authorized
    ///   prefix of the country/call area of operation", so a part that is a
    ///   listed cty prefix key is a designator even when it ends in a letter
    ///   (`VK9C`, `PY0F`, `CE0Y`). Defaults to the bundled cty table.
    static func of(_ raw: String, isKnownPrefix: (String) -> Bool = { CTYTable.shared?.hasPrefix($0) ?? false }) -> String? {
        let parts = raw.uppercased().split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        let candidates = parts.filter { !ignoredSuffixes.contains($0) }
        // A call that is nothing but class identifiers (/QRP, MM/AM) has no prefix.
        if candidates.isEmpty { return nil }
        if candidates.count == 1 { return prefix(of: candidates[0]) }
        // A bare digit designator keeps the base prefix with its trailing
        // digit run dropped, then appends the new digit (NOT STATED — inference).
        if let digit = candidates.first(where: { $0.allSatisfy(\.isNumber) }),
           let home = candidates.first(where: { !$0.allSatisfy(\.isNumber) }),
           let base = prefix(of: home) {
            var chars = Array(base)
            while chars.last?.isNumber == true { chars.removeLast() }
            return String(chars) + digit
        }
        // A part is a designator if it doesn't read as a full call (no
        // letters after its digits), or if it is itself an authorized
        // prefix per V.C.1; ties go to the shorter, then the first.
        let designators = candidates.filter { isDesignator($0, isKnownPrefix: isKnownPrefix) }
        // candidates.count >= 2 here (count == 0 and count == 1 both return
        // above), so `designators.isEmpty ? candidates : designators` is
        // never empty and `.min` cannot be nil.
        let pick = (designators.isEmpty ? candidates : designators)
            .enumerated()
            .min { ($0.element.count, $0.offset) < ($1.element.count, $1.offset) }!
            .element
        return prefix(of: pick)
    }

    /// Letters and digits through the last digit that is followed by a letter
    /// (`OL25LP` → `OL25`, `9A800VZ` → `9A800`); a part with no such digit
    /// keeps its whole self (`WK9`, `OE25`); a part with no digit at all takes
    /// its first two letters and a zero (`XEFTJW` → `XE0`, `PA` → `PA0`).
    static func prefix(of part: String) -> String? {
        guard !part.isEmpty else { return nil }
        let chars = Array(part)
        guard chars.contains(where: \.isNumber) else {
            return String(chars.prefix(2)) + "0"
        }
        var cut: Int?
        for i in chars.indices where chars[i].isNumber && chars[(i + 1)...].contains(where: \.isLetter) { cut = i }
        guard let cut else { return part }
        return String(chars[...cut])
    }

    /// A part is a designator if it has no digit, or its last digit is not
    /// followed by a letter, or `isKnownPrefix` recognizes the whole part as
    /// an authorized prefix (the letter-ending case, e.g. `VK9C`).
    private static func isDesignator(_ part: String, isKnownPrefix: (String) -> Bool) -> Bool {
        let chars = Array(part)
        guard let lastDigit = chars.lastIndex(where: \.isNumber) else { return true }
        guard chars[(lastDigit + 1)...].contains(where: \.isLetter) else { return true }
        return isKnownPrefix(part)
    }
}

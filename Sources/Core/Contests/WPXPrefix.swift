import Foundation

/// The CQ WPX prefix of a callsign, per rule V.C.1 (docs/research/cqwpx_rules_2026.txt):
/// "the letter/numeral combination which forms the first part of the amateur
/// call … In cases of portable operation, the portable designator will then
/// become the prefix … Portable designators without numbers will be assigned a
/// zero (Ø) after the second letter … All calls without numbers will be
/// assigned a zero (Ø) after the first two letters … Maritime mobile, mobile,
/// /A, /E, /J, /P, or other license class identifiers do not count as prefixes."
enum WPXPrefix {
    /// Suffixes that are class identifiers, not designators.
    static let ignoredSuffixes: Set<String> = ["MM", "AM", "M", "A", "E", "J", "P", "QRP"]

    static func of(_ raw: String) -> String? {
        let parts = raw.uppercased().split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var candidates = parts.filter { !ignoredSuffixes.contains($0) }
        if candidates.isEmpty { candidates = [parts[0]] }
        if candidates.count == 1 { return prefix(of: candidates[0]) }
        // A bare digit designator replaces the number (NOT STATED — inference).
        if let digit = candidates.first(where: { $0.allSatisfy(\.isNumber) }),
           let home = candidates.first(where: { !$0.allSatisfy(\.isNumber) }),
           let base = prefix(of: home) {
            let letters = base.prefix { $0.isLetter }
            return String(letters) + digit
        }
        // The designator is the part that does not read as a full call
        // (no letters after its digits); ties go to the shorter, then the first.
        let designators = candidates.filter { !looksLikeFullCall($0) }
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

    private static func looksLikeFullCall(_ part: String) -> Bool {
        let chars = Array(part)
        guard let lastDigit = chars.lastIndex(where: \.isNumber) else { return false }
        return chars[(lastDigit + 1)...].contains(where: \.isLetter)
    }
}

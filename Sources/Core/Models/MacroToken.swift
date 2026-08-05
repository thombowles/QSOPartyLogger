import Foundation

/// The macros an operator can type into an F1–F8 CW message.
///
/// One definition on purpose. These tokens used to be string literals in four
/// places — the expander, the party defaults, the messages editor's help line
/// and the README — with nothing to catch a miss, and the help line duly
/// drifted: it omitted `{SERIAL}` for as long as that macro existed, so the
/// one token CQP and PAQP operators need was undiscoverable. Everything that
/// names a macro now spells it as a case, and the editor lists `allCases`.
///
/// Case order is expansion order — `AppSettings.expandMacros` iterates
/// `allCases` — and the order the editor lists them in.
enum MacroToken: String, CaseIterable, Sendable {
    /// The operator's own callsign, from the station profile.
    case myCall = "{MYCALL}"
    /// The callsign in the entry field.
    case call = "{CALL}"
    /// The report being sent. Cut when cut numbers are on.
    case rst = "{RST}"
    /// The QSO number being sent, for parties that exchange one (CQP, PAQP).
    /// Cut when cut numbers are on, and empty for every other party.
    case serial = "{SERIAL}"
    /// The operator name being sent, for parties whose exchange carries one
    /// (NAQP, MNQP) — the log's single contest-long name. Empty elsewhere.
    case name = "{NAME}"
    /// The exchange being sent — county, section, or whatever this party's
    /// rules ask for.
    case exchange = "{EXCH}"
    /// The member-number-or-power element being sent, for parties whose
    /// exchange carries one (Skeeter Hunt) — the log's contest-long value.
    /// Self-shaping: a member number expands as `NR 13` (the on-air
    /// convention in the sponsor's own sample QSO), a power as `5W` verbatim.
    /// Last because it is sent last ("559 NJ NR 13"); never cut. Empty
    /// elsewhere.
    case member = "{MEMBER}"

    /// The macros as the messages editor lists them, in case order:
    /// `{MYCALL} {CALL} {RST} {SERIAL} {NAME} {EXCH} {MEMBER}`. Derived from
    /// `allCases` so that list can never again be missing one.
    static var helpList: String {
        allCases.map(\.rawValue).joined(separator: " ")
    }
}

extension MacroToken: CustomStringConvertible {
    /// The token itself, so a message template can be written as
    /// `"CQ TEST \(MacroToken.myCall)"` and read like the text it keys.
    var description: String { rawValue }
}

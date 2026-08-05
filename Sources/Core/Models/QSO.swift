import Foundation

/// One logged line. County-line contacts produce multiple `QSO` rows sharing a `groupID`
/// (N1MM-style: a separate line per county, per KSQP rule 11).
struct QSO: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Shared by all rows created from a single on-air contact.
    var groupID: UUID
    var timestampUTC: Date
    var call: String
    var band: Band
    var modeClass: ModeClass
    /// Concrete ADIF mode: CW, SSB, RTTY, FT8…
    var rawMode: String
    /// From CAT when connected; nil when logged manually.
    var freqKHz: Int?
    var rstSent: String
    var rstRcvd: String
    /// QSO numbers sent and received, for parties whose exchange carries one
    /// (CQP: "QSO number = contact serial number starting with 1 for the first
    /// contact"). `nil` wherever the exchange carries a signal report instead —
    /// which is every party but CQP, and is why these are optional: logs written
    /// before serial support decode unchanged.
    ///
    /// A county-line contact is **one** contact and carries **one** number,
    /// shared by every row it expands into (see `CountyLineExpander`).
    var serialSent: Int?
    var serialRcvd: Int?
    /// Operator names sent and received, for parties whose exchange carries
    /// one (NAQP: "Operator name and station location"; MNQP: "First name &
    /// county"). `nil` everywhere else, so logs written before name support
    /// decode unchanged. The sent name is the log's single contest-long name
    /// (both sponsors require one), stamped per row so the record shows what
    /// went out.
    var nameSent: String?
    var nameRcvd: String?
    /// Member-number-or-power elements sent and received, for parties whose
    /// exchange carries one (Skeeter Hunt: "RST, S/P/C, Skeeter number" for
    /// Skeeters, "RST, S/P/C, Output power" for everyone else). Strings,
    /// because the element is a number for members and "5W" for the rest —
    /// see `MemberExchange.parse`. `nil` everywhere else, so logs written
    /// before member support decode unchanged. The sent value is the log's
    /// single contest-long element, stamped per row so the record shows what
    /// went out.
    var memberSent: String?
    var memberRcvd: String?
    /// My sent location for this row: county abbreviation (in-state) or state/province.
    var myLoc: String
    /// Their location for this row: county abbreviation, state, province, or "DX".
    var theirLoc: String

    init(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        timestampUTC: Date = Date(),
        call: String,
        band: Band,
        modeClass: ModeClass,
        rawMode: String,
        freqKHz: Int? = nil,
        rstSent: String,
        rstRcvd: String,
        serialSent: Int? = nil,
        serialRcvd: Int? = nil,
        nameSent: String? = nil,
        nameRcvd: String? = nil,
        memberSent: String? = nil,
        memberRcvd: String? = nil,
        myLoc: String,
        theirLoc: String
    ) {
        self.id = id
        self.groupID = groupID
        self.timestampUTC = timestampUTC
        self.call = call
        self.band = band
        self.modeClass = modeClass
        self.rawMode = rawMode
        self.freqKHz = freqKHz
        self.rstSent = rstSent
        self.rstRcvd = rstRcvd
        self.serialSent = serialSent
        self.serialRcvd = serialRcvd
        self.nameSent = nameSent
        self.nameRcvd = nameRcvd
        self.memberSent = memberSent
        self.memberRcvd = memberRcvd
        self.myLoc = myLoc
        self.theirLoc = theirLoc
    }
}

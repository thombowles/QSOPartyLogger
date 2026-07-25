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
        self.myLoc = myLoc
        self.theirLoc = theirLoc
    }
}

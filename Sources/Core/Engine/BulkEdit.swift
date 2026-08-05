import Foundation

/// A one-field change applied to every selected row of the log.
///
/// N1MM's Log window offers five bulk change types — operator, mode, frequency,
/// station name and X-QSO status — and every one of them is a station-side or
/// administrative fact rather than something the other station sent. This holds
/// the same line: what *I* transmitted can be wrong across a whole stretch of
/// rows and right to fix in one action (a rover who left the county twenty
/// contacts ago), while what *they* sent is a different fact per station and is
/// only ever editable one row at a time.
enum BulkEdit {

    /// The fields a bulk change may touch. Received elements — `theirLoc`,
    /// `nameRcvd`, `serialRcvd`, `rstRcvd` — are deliberately absent: there is
    /// no single correct value for them across fifteen different stations.
    enum Field: String, Hashable, CaseIterable, Identifiable, Sendable {
        case band
        case mode
        case myLoc
        case nameSent
        case memberSent

        var id: String { rawValue }
    }

    /// The value a change carries. One case per control the sheet can show, so
    /// a field and its value cannot disagree.
    enum Value: Equatable, Sendable {
        case band(Band)
        case mode(String)
        case text(String)
    }

    /// Why a change was refused, in the words the sheet shows. Nothing is
    /// written when one of these comes back.
    struct Failure: Error, Equatable {
        var message: String
    }

    /// Which of the selected rows a change may touch, and which it must leave
    /// alone.
    struct Partition: Equatable {
        var changing: [QSO] = []
        /// County-line rows a `myLoc` change would turn into duplicates.
        var excluded: [QSO] = []
    }

    /// The fields this party can offer. Band, mode and my own location exist
    /// in every log; the two sent elements exist only where the exchange
    /// carries them.
    static func fields(for party: PartyDefinition?) -> [Field] {
        var fields: [Field] = [.band, .mode, .myLoc]
        if party?.exchangeIncludesName == true { fields.append(.nameSent) }
        if party?.memberExchange != nil { fields.append(.memberSent) }
        return fields
    }

    /// The party names its own member element ("Skeeter # sent"), so the picker
    /// never says "member" to an operator whose sponsor calls it something else.
    static func label(_ field: Field, party: PartyDefinition?) -> String {
        switch field {
        case .band: "Band"
        case .mode: "Mode"
        case .myLoc: "My exchange"
        case .nameSent: "Name sent"
        case .memberSent:
            party?.memberExchange.map { "\($0.shortTerm) sent" } ?? "Member element sent"
        }
    }

    /// Splits a selection into the rows a change may write and the rows it must
    /// not.
    ///
    /// Only `myLoc` can damage anything. `CountyLineExpander` builds a contact's
    /// rows as the product of my location(s) × theirs, so a group logged while
    /// straddling a line differs **only** in `myLoc` — and setting one value
    /// across it collapses those rows into literal duplicates, which the dupe
    /// checker then flags. The app would be manufacturing the defect it exists
    /// to catch.
    ///
    /// A row is safe when its group is a single row, or when the whole group is
    /// selected *and* already carries one location — then the rows stay distinct
    /// by what the other station sent. A partly selected group is excluded too:
    /// changing half of one contact's rows leaves that contact claiming two of
    /// my locations.
    ///
    /// `allRows` is the whole log, not the selection, because a group's other
    /// rows are exactly what the selection may be missing.
    static func partition(_ selected: [QSO], field: Field, allRows: [QSO]) -> Partition {
        guard field == .myLoc else { return Partition(changing: selected) }
        let byGroup = Dictionary(grouping: allRows, by: \.groupID)
        let selectedIDs = Set(selected.map(\.id))
        var partition = Partition()
        for row in selected {
            let group = byGroup[row.groupID] ?? [row]
            let wholeGroupSelected = group.allSatisfy { selectedIDs.contains($0.id) }
            let oneLocation = Set(group.map(\.myLoc)).count == 1
            if group.count == 1 || (wholeGroupSelected && oneLocation) {
                partition.changing.append(row)
            } else {
                partition.excluded.append(row)
            }
        }
        return partition
    }

    /// Applies `value` to every row, or refuses the whole change.
    ///
    /// Validation runs before anything is written, exactly as the single-row
    /// editor does — a rejected value leaves the log untouched rather than
    /// half-changed.
    ///
    /// `isInState` is the log's own answer from Contest Setup, not a role in
    /// `ExchangeParser`'s sense. That distinction matters: `Role` decides what
    /// may be *received*, and for an in-state entrant that includes every state
    /// and province in the party's table — none of which this operator can be
    /// transmitting from. My own location is validated against what Contest
    /// Setup itself would accept.
    static func apply(
        _ value: Value,
        field: Field,
        to rows: [QSO],
        party: PartyDefinition?,
        isInState: Bool
    ) -> Result<[QSO], Failure> {
        switch (field, value) {
        case (.band, .band(let band)):
            return .success(rows.map { row in
                var row = row
                row.band = band
                return row
            })

        case (.mode, .mode(let rawMode)):
            return .success(rows.map { row in
                var row = row
                row.rawMode = rawMode
                row.modeClass = ModeClass.classify(rawMode: rawMode)
                return row
            })

        case (.myLoc, .text(let raw)):
            let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
            if let party, let failure = myLocFailure(token, party: party, isInState: isInState) {
                return .failure(failure)
            }
            if party == nil && token.isEmpty {
                return .failure(Failure(message: "Enter the location you sent."))
            }
            return .success(rows.map { row in
                var row = row
                row.myLoc = token
                return row
            })

        case (.nameSent, .text(let raw)):
            let name = raw.trimmingCharacters(in: .whitespaces).uppercased()
            guard !name.isEmpty else {
                return .failure(Failure(message: "Enter the name you sent."))
            }
            return .success(rows.map { row in
                var row = row
                row.nameSent = name
                return row
            })

        case (.memberSent, .text(let raw)):
            let element = raw.trimmingCharacters(in: .whitespaces).uppercased()
            guard MemberExchange.parse(element) != nil else {
                let term = party?.memberExchange?.term ?? "member number"
                return .failure(
                    Failure(message: "Not a readable \(term) — a number, "
                            + "or an output power like 5W.")
                )
            }
            return .success(rows.map { row in
                var row = row
                row.memberSent = element
                return row
            })

        // A field and a value of another shape cannot be produced by the sheet,
        // which builds both from the same selection.
        default:
            return .failure(Failure(message: "That value doesn't belong to this field."))
        }
    }

    /// What Contest Setup would refuse for this log's own location: a county
    /// from the party's list when the entry is in-state, one of the party's
    /// entrant tokens when it is not.
    private static func myLocFailure(
        _ token: String, party: PartyDefinition, isInState: Bool
    ) -> Failure? {
        guard !token.isEmpty else {
            return Failure(message: isInState
                           ? "Enter the \(party.countyTerm) you were operating from."
                           : "Enter the location you sent.")
        }
        if isInState && party.hasHomeRegion {
            guard party.counties.contains(where: { $0.abbr == token }) else {
                let suggestions = ExchangeParser.suggestions(
                    for: token, party: party, role: .inState
                )
                return Failure(message: suggestions.isEmpty
                    ? "'\(token)' is not one of this party's \(party.countyTermPlural)."
                    : "'\(token)' is not valid. Did you mean "
                        + "\(suggestions.joined(separator: ", "))?")
            }
            return nil
        }
        guard party.validEntrantTokens.contains(token) else {
            return Failure(message: "'\(token)' is not a location this party's "
                           + "entrants can send.")
        }
        return nil
    }
}

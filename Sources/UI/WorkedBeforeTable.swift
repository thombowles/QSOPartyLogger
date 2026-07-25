import SwiftUI

/// Every prior contact with the station whose call is in the entry field,
/// between the F-key row and the log.
///
/// It exists only while there is history to show, and its height comes out of
/// the log table rather than out of the window — see `height` and
/// `logTableMin`. Rows are deliberately not interactive: there is nothing
/// useful to click, and a live row directly above the log table is a mis-click
/// waiting to happen mid-run.
struct WorkedBeforeTable: View {
    let call: String
    let contacts: [DupeChecker.WorkedContact]
    /// "KSQP 2025 — JO" when the archive knows the station and this log does
    /// not. Nil otherwise, including while the index is still loading.
    let archiveLine: String?
    let currentBand: Band
    let currentModeClass: ModeClass

    // MARK: Height arithmetic

    /// Row and header heights are layout constants so the table's footprint is
    /// arithmetic rather than a measurement. `MainView` subtracts exactly this
    /// from the log table's minimum height, which is what stops macOS growing
    /// the window the first time a match appears.
    static let rowHeight: CGFloat = 15
    static let headerHeight: CGFloat = 14
    /// Padding above and below the rows, plus the gap over the card.
    static let chrome: CGFloat = 16
    /// Past this the table scrolls. A station can only be worked bands × modes
    /// times, and six covers any realistic weekend.
    static let visibleRowCap = 6
    /// The log table's minimum with no history table above it.
    static let logTableMinAlone: CGFloat = 240

    static func height(contacts: Int, hasArchiveLine: Bool) -> CGFloat {
        guard contacts > 0 || hasArchiveLine else { return 0 }
        let rows = min(contacts, visibleRowCap) + (hasArchiveLine ? 1 : 0)
        return headerHeight + rowHeight * CGFloat(rows) + chrome
    }

    static func logTableMin(tableHeight: CGFloat) -> CGFloat {
        logTableMinAlone - tableHeight
    }

    private var totalHeight: CGFloat {
        Self.height(contacts: contacts.count, hasArchiveLine: archiveLine != nil)
    }

    private var scrollHeight: CGFloat {
        totalHeight - Self.headerHeight - Self.chrome
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(contacts) { row($0) }
                    if let archiveLine {
                        archiveRow(archiveLine)
                    }
                }
            }
            .scrollDisabled(contacts.count <= Self.visibleRowCap)
            .frame(height: scrollHeight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(height: totalHeight, alignment: .top)
    }

    /// The last column names the station, so the table needs no title line —
    /// which would cost a row to say nothing.
    private var header: some View {
        columns(
            Text("Band"), Text("Mode"), Text("Time"),
            Text("Worked \(call) as")
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(height: Self.headerHeight)
    }

    /// Bold and orange for the band and mode the radio is on right now: there
    /// is nothing left to work here. Weight as well as colour, so the cue does
    /// not rest on colour alone.
    private func row(_ contact: DupeChecker.WorkedContact) -> some View {
        let here = contact.band == currentBand && contact.modeClass == currentModeClass
        return columns(
            Text(contact.band.rawValue),
            Text(contact.modeClass.displayName),
            Text(Self.utc.string(from: contact.timestampUTC)),
            Text(contact.theirLoc)
        )
        .font(.system(size: 10, design: .monospaced).weight(here ? .semibold : .regular))
        .foregroundStyle(here ? Color.orange : Color.secondary)
        .frame(height: Self.rowHeight)
    }

    private func archiveRow(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(height: Self.rowHeight, alignment: .leading)
    }

    private func columns(
        _ a: Text, _ b: Text, _ c: Text, _ d: Text
    ) -> some View {
        HStack(spacing: 6) {
            a.frame(width: 42, alignment: .leading)
            b.frame(width: 40, alignment: .leading)
            c.frame(width: 52, alignment: .leading)
            d.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let utc: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

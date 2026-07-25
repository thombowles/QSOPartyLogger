import Foundation

/// Where each spot's label goes on the band map.
///
/// The problem is a pile-up: six spots inside 2 kHz want the same few pixels.
/// Pushing each one below the last (the obvious fix) drags the sixth label far
/// from its own frequency and every label after it inherits the offset, with
/// nothing on screen admitting the label moved.
///
/// So labels stay at their true frequency and a collision moves *sideways*
/// instead — into a second column, then a third, as far as the panel is wide:
///
///     14050 ─────────────────
///              ● K5CW   ● W5ZN   ● N5AW
///     14045 ─────────────────
///              ● AA5B
///
/// Pure and free of SwiftUI so the placement can be tested directly.
enum BandMapLayout {

    struct Placement: Identifiable, Equatable {
        let spot: Spot
        /// Vertical position in points from the top of the map.
        let y: Double
        /// 0 is the leftmost label column.
        let column: Int

        var id: String { spot.id }
    }

    /// Place every spot inside the scale's window.
    ///
    /// - Parameters:
    ///   - rowHeight: vertical clearance one label needs.
    ///   - columnWidth: horizontal pitch between label columns.
    ///   - availableWidth: room for labels — panel width less the ruler.
    static func place(
        spots: [Spot],
        scale: BandMapScale,
        height: Double,
        rowHeight: Double,
        columnWidth: Double,
        availableWidth: Double
    ) -> [Placement] {
        let maxColumns = max(1, Int(availableWidth / columnWidth))
        // Top of the map first, which is the *high* frequency end.
        let visible = spots
            .filter { $0.freqKHz >= scale.lowKHz && $0.freqKHz <= scale.highKHz }
            .sorted { $0.freqKHz > $1.freqKHz }

        var placements: [Placement] = []
        /// The y of the lowest label placed so far in each open column.
        var columnBottom: [Double] = []

        for spot in visible {
            let trueY = scale.y(forKHz: spot.freqKHz, height: height)

            // Leftmost column with clearance, so a spot returns to column 0 as
            // soon as the pile-up above it has been left behind.
            if let column = columnBottom.indices.first(where: { trueY >= columnBottom[$0] + rowHeight }) {
                columnBottom[column] = trueY
                placements.append(Placement(spot: spot, y: trueY, column: column))
                continue
            }

            if columnBottom.count < maxColumns {
                placements.append(Placement(spot: spot, y: trueY, column: columnBottom.count))
                columnBottom.append(trueY)
                continue
            }

            // Every column is busy at this frequency: push down in the last one
            // rather than drop the spot. A 20-deep pile-up on one frequency
            // still shows all 20 calls.
            let column = maxColumns - 1
            let y = columnBottom[column] + rowHeight
            columnBottom[column] = y
            placements.append(Placement(spot: spot, y: y, column: column))
        }
        return placements
    }
}

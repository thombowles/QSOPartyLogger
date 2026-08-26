import Foundation

/// The one-line advisory the entry row shows for a looked-up station.
/// Pure — the view renders whatever this says, and the tests read it here.
enum CallbookCaption {
    /// "Bob · MO · EM48ss · 412 mi ↗" — each piece only when known; nil
    /// when nothing is known at all. Distance and bearing need both grids;
    /// miles because that is the unit the README already speaks.
    static func line(for record: CallbookRecord, stationGrid: String) -> String? {
        var parts: [String] = []
        if let name = record.name, !name.isEmpty { parts.append(name) }
        if let state = record.state, !state.isEmpty { parts.append(state) }
        if let grid = record.grid, !grid.isEmpty {
            parts.append(grid)
            if let here = Maidenhead.center(of: stationGrid),
               let there = Maidenhead.center(of: grid) {
                let km = PotaParkDirectory.distanceKm(
                    from: (here.latitude, here.longitude),
                    to: (there.latitude, there.longitude))
                let miles = Int((km * 0.621371).rounded())
                let arrow = Self.arrow(bearingDegrees(
                    fromLat: here.latitude, lon: here.longitude,
                    toLat: there.latitude, lon: there.longitude))
                parts.append("\(miles) mi \(arrow)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Initial great-circle bearing, degrees clockwise from north.
    static func bearingDegrees(fromLat: Double, lon fromLon: Double,
                               toLat: Double, lon toLon: Double) -> Double {
        let phi1 = fromLat * .pi / 180
        let phi2 = toLat * .pi / 180
        let deltaLambda = (toLon - fromLon) * .pi / 180
        let y = sin(deltaLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda)
        let theta = atan2(y, x) * 180 / .pi
        return (theta + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The eight-point arrow for a bearing — ↑ is north.
    static func arrow(_ degrees: Double) -> String {
        let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return arrows[index]
    }
}

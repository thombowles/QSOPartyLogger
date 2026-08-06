import Foundation

/// Maidenhead grid locator conversions, 6-character field–square–subsquare
/// form (EM13LE). Fills Contest Setup's grid square from the Mac's location
/// and places the operator for the park picker's nearest-first sort.
///
/// Cell sizes per the IARU locator system: 18×18 fields of 20°×10°, 10×10
/// squares of 2°×1°, 24×24 subsquares of 5'×2.5'.
enum Maidenhead {

    private static let fields = Array("ABCDEFGHIJKLMNOPQR")
    private static let subsquares = Array("ABCDEFGHIJKLMNOPQRSTUVWX")

    /// The 6-character locator containing a coordinate, upper case the way
    /// the rest of the app stores grids. `nil` off the globe.
    static func locator(latitude: Double, longitude: Double) -> String? {
        guard latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else { return nil }
        // Shift to all-positive degrees from the south-west corner. The north
        // pole and the antimeridian sit exactly on the far edge of the last
        // cell, so they are nudged inside it rather than indexing past the
        // end of the tables.
        let lon = min(longitude + 180, 359.999999)
        let lat = min(latitude + 90, 179.999999)
        let fieldLon = fields[Int(lon / 20)]
        let fieldLat = fields[Int(lat / 10)]
        let squareLon = Int(lon.truncatingRemainder(dividingBy: 20) / 2)
        let squareLat = Int(lat.truncatingRemainder(dividingBy: 10))
        let subLon = subsquares[Int(lon.truncatingRemainder(dividingBy: 2) * 12)]
        let subLat = subsquares[Int(lat.truncatingRemainder(dividingBy: 1) * 24)]
        return "\(fieldLon)\(fieldLat)\(squareLon)\(squareLat)\(subLon)\(subLat)"
    }

    /// The center of a 4- or 6-character locator — where the operator is when
    /// the position comes from a typed grid square rather than Core Location.
    /// `nil` for anything that is not a locator.
    static func center(of locator: String) -> (latitude: Double, longitude: Double)? {
        let grid = Array(locator.trimmingCharacters(in: .whitespaces).uppercased())
        guard grid.count == 4 || grid.count == 6 else { return nil }
        guard let fieldLon = fields.firstIndex(of: grid[0]),
              let fieldLat = fields.firstIndex(of: grid[1]),
              let squareLon = grid[2].wholeNumberValue, grid[2].isASCII, grid[2].isNumber,
              let squareLat = grid[3].wholeNumberValue, grid[3].isASCII, grid[3].isNumber
        else { return nil }
        var lon = Double(fieldLon) * 20 + Double(squareLon) * 2
        var lat = Double(fieldLat) * 10 + Double(squareLat)
        if grid.count == 6 {
            guard let subLon = subsquares.firstIndex(of: grid[4]),
                  let subLat = subsquares.firstIndex(of: grid[5]) else { return nil }
            // Half a subsquare past its south-west corner.
            lon += Double(subLon) * (2.0 / 24) + (2.0 / 48)
            lat += Double(subLat) * (1.0 / 24) + (1.0 / 48)
        } else {
            // Half a square, for the coarser form.
            lon += 1
            lat += 0.5
        }
        return (lat - 90, lon - 180)
    }
}

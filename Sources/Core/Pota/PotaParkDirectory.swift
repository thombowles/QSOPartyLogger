import Foundation

/// The searchable park list: parse, name-or-number search, nearest sort.
/// Pure — no disk, no network; `PotaParkStore` and `PotaParkClient` own
/// those.
struct PotaParkDirectory: Equatable, Sendable {
    let parks: [PotaPark]

    /// A park and how far away it is, for the nearest list.
    struct Ranked: Equatable, Sendable {
        let park: PotaPark
        let km: Double
    }

    /// `nil` for anything that is not a non-empty park array. An empty list
    /// would silently disable search, and that must read as a failed
    /// download rather than as a successful empty one.
    static func parse(data: Data) -> PotaParkDirectory? {
        guard let parks = try? JSONDecoder().decode([PotaPark].self, from: data),
              !parks.isEmpty else { return nil }
        return PotaParkDirectory(parks: parks)
    }

    /// Name-or-number search: every whitespace-separated term must match the
    /// name, the reference, or the location tag — so "lake tx" finds Texas
    /// lakes, "0088" finds US-0088, and "cedar hill" finds the park.
    /// Case-insensitive, and capped so the sheet never lays out thousands of
    /// rows.
    func search(_ query: String, limit: Int = 30) -> [PotaPark] {
        let terms = query.uppercased()
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var out: [PotaPark] = []
        for park in parks {
            let name = park.name.uppercased()
            let location = (park.locationDesc ?? "").uppercased()
            let matches = terms.allSatisfy { term in
                name.contains(term) || park.reference.contains(term)
                    || location.contains(term)
            }
            if matches {
                out.append(park)
                if out.count == limit { break }
            }
        }
        return out
    }

    /// The parks nearest a coordinate — the "you are here" list the picker
    /// shows before anything is typed. Parks without coordinates never rank.
    func nearest(latitude: Double, longitude: Double, limit: Int = 12) -> [Ranked] {
        parks
            .compactMap { park -> Ranked? in
                guard let parkLat = park.latitude, let parkLon = park.longitude
                else { return nil }
                return Ranked(park: park,
                              km: Self.distanceKm(from: (latitude, longitude),
                                                  to: (parkLat, parkLon)))
            }
            .sorted { $0.km < $1.km }
            .prefix(limit)
            .map { $0 }
    }

    /// Haversine on a spherical Earth — sorting accuracy, not survey
    /// accuracy.
    static func distanceKm(from a: (Double, Double), to b: (Double, Double)) -> Double {
        let radius = 6371.0
        let dLat = (b.0 - a.0) * .pi / 180
        let dLon = (b.1 - a.1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.0 * .pi / 180) * cos(b.0 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}

import Foundation

struct County: Codable, Hashable, Sendable, Identifiable {
    let abbr: String
    let name: String

    var id: String { abbr }
}

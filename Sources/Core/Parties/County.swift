import Foundation

struct County: Codable, Hashable, Sendable, Identifiable {
    let abbr: String
    let name: String

    /// The state this county belongs to, for **multi-state parties only** — the
    /// 7th Call Area's seven and New England's six, where one log covers every
    /// member state and `PartyDefinition.homeState` cannot name them all.
    ///
    /// `nil` everywhere else, which is every single-state party: they read the
    /// party's `homeState` instead and are byte-for-byte unchanged. Resolve it
    /// through `PartyDefinition.state(forCounty:)` rather than reading it
    /// directly, so the fallback stays in one place.
    let state: String?

    var id: String { abbr }

    init(abbr: String, name: String, state: String? = nil) {
        self.abbr = abbr
        self.name = name
        self.state = state
    }
}

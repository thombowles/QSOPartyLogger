import Foundation

/// What a spot is worth right now — the band map's three colours, and the
/// colour of the ghost call in the entry field.
///
/// N1MM Logger+ (Bandmap window, "Colors of the Incoming Spots", fetched
/// 2026-08-15): "Blue: Will be a good QSO, not a multiplier / Red: Single
/// Multiplier / Gray: Dupe". Green (double multiplier) is not drawn: a QSO
/// party contact carries one location.
enum SpotStatus: Equatable, Sendable {
    /// Worked on this band and mode, or superseded by a later spot — grey.
    case worked
    /// Unworked, and the location the app knows for the station would still
    /// add a multiplier — red.
    case neededMultiplier
    /// Unworked, not a multiplier — or location unknown — blue.
    case unworked
}

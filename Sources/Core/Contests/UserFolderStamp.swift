import Foundation

/// A cheap fingerprint of a user definition folder: every `.json` file's
/// name, size and modification time, name-sorted. Two equal stamps mean the
/// folder's contents have not moved, so the catalogs can serve their cached
/// decode instead of re-reading, re-validating and re-lowering every file on
/// every lookup — which the save path used to do once per logged contact.
///
/// Per-file mtime on purpose, not the directory's: editing a file in place
/// moves the file's own stamp while the directory's mtime stands still, and
/// a stale definition silently scoring a contest is exactly the failure the
/// catalogs exist to prevent. Listing and stat'ing stays on every call; only
/// the decode is saved.
struct UserFolderStamp: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let name: String
        let size: Int
        let mtime: Date
    }

    let entries: [Entry]

    /// The folder's stamp right now. A missing or unreadable folder stamps
    /// empty — the same answer the loaders give for it.
    static func of(_ dir: URL) -> UserFolderStamp {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return UserFolderStamp(entries: []) }
        let entries = urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url -> Entry? in
                guard let values = try? url.resourceValues(
                    forKeys: [.fileSizeKey, .contentModificationDateKey]
                ) else { return nil }
                return Entry(
                    name: url.lastPathComponent,
                    size: values.fileSize ?? 0,
                    mtime: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.name < $1.name }
        return UserFolderStamp(entries: entries)
    }
}

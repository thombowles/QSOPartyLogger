import AppKit
import Foundation

/// The logs folder: a user-chosen directory (iCloud Drive recommended) where
/// new contests are auto-saved and copies are mirrored. iCloud Drive syncs it
/// across the user's Macs, so a contest can be picked up on another machine.
///
/// Sandbox notes: access comes from a security-scoped bookmark granted once
/// via the open panel (`files.bookmarks.app-scope` entitlement — no iCloud
/// container/provisioning needed). The scope is started once and **held for
/// the app's lifetime**: documents auto-saved into the folder keep receiving
/// NSDocument autosave writes long after the initial save, so access must not
/// be dropped after each operation.
enum CloudMirror {

    private static let bookmarkKey = "iCloudFolderBookmark"
    private static let enabledKey = "iCloudMirrorEnabled"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var heldFolderURL: URL?

    nonisolated static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    nonisolated static var isEnabled: Bool {
        get { isConfigured && UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    nonisolated static var folderDisplayPath: String? {
        activeFolder()?.path(percentEncoded: false)
    }

    /// Resolve the bookmark once and hold security-scoped access from then on.
    nonisolated static func activeFolder() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        if let held = heldFolderURL { return held }

        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ), url.startAccessingSecurityScopedResource() else { return nil }

        if stale, let fresh = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        heldFolderURL = url
        return url
    }

    /// Drop the held folder access (unit tests swap bookmarks between cases).
    nonisolated static func _resetHeldAccessForTesting() {
        lock.lock()
        heldFolderURL?.stopAccessingSecurityScopedResource()
        heldFolderURL = nil
        lock.unlock()
    }

    /// One-time folder selection. Suggests creating a dedicated folder inside
    /// iCloud Drive; stores the bookmark and switches held access to it.
    @MainActor
    static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Pick (or create) a folder in iCloud Drive for your contest logs — e.g. iCloud Drive ▸ QSO Party Logs. It will sync to your other Macs automatically."
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            lock.lock()
            heldFolderURL?.stopAccessingSecurityScopedResource()
            heldFolderURL = nil
            lock.unlock()
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(true, forKey: enabledKey)
            _ = activeFolder()
            return true
        } catch {
            NSLog("CloudMirror: bookmark failed: \(error)")
            return false
        }
    }

    @MainActor
    static func openFolderInFinder() {
        guard let url = activeFolder() else { return }
        NSWorkspace.shared.open(url)
    }

    /// Write one log copy. Safe from any thread; failures are logged, never
    /// user-blocking (the primary document save has already succeeded).
    nonisolated static func mirror(data: Data, fileName: String) {
        guard isEnabled, let folder = activeFolder() else { return }
        let sanitized = fileName.replacingOccurrences(of: "/", with: "-")
        let target = folder.appendingPathComponent(sanitized).appendingPathExtension("qplog")
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            NSLog("CloudMirror: write failed: \(error)")
        }
    }

    /// Is this file inside the logs folder? (Documents living there don't
    /// need mirroring — they ARE the synced copy.)
    nonisolated static func folderContains(_ url: URL?) -> Bool {
        guard let url, let folder = activeFolder() else { return false }
        let base = folder.standardizedFileURL.path(percentEncoded: false)
        let candidate = url.standardizedFileURL.path(percentEncoded: false)
        return candidate.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    /// A non-clobbering target URL in the logs folder for a new contest:
    /// "name.qplog", then "name 2.qplog", …
    nonisolated static func uniqueSaveURL(baseName: String) -> URL? {
        guard let folder = activeFolder() else { return nil }
        let sanitized = baseName.replacingOccurrences(of: "/", with: "-")
        var candidate = folder.appendingPathComponent(sanitized).appendingPathExtension("qplog")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = folder
                .appendingPathComponent("\(sanitized) \(counter)")
                .appendingPathExtension("qplog")
            counter += 1
        }
        return candidate
    }
}

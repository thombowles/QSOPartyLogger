import AppKit
import Foundation

/// Automatic copies of every contest log into a user-chosen iCloud Drive
/// folder. iCloud Drive syncs the folder across the user's Macs, so a contest
/// can be picked up on another machine by opening the log from that folder.
///
/// Sandbox note: access is held via a security-scoped bookmark (the
/// `files.bookmarks.app-scope` entitlement), granted once through the open
/// panel — no iCloud container entitlement or provisioning profile required.
enum CloudMirror {

    private static let bookmarkKey = "iCloudFolderBookmark"
    private static let enabledKey = "iCloudMirrorEnabled"

    nonisolated static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    nonisolated static var isEnabled: Bool {
        get { isConfigured && UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    nonisolated static var folderDisplayPath: String? {
        resolvedFolder()?.url.path(percentEncoded: false)
    }

    /// One-time folder selection. Suggests creating a dedicated folder inside
    /// iCloud Drive; stores a security-scoped bookmark for background writes.
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
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(true, forKey: enabledKey)
            return true
        } catch {
            NSLog("CloudMirror: bookmark failed: \(error)")
            return false
        }
    }

    @MainActor
    static func openFolderInFinder() {
        guard let access = resolvedFolder() else { return }
        defer { access.url.stopAccessingSecurityScopedResource() }
        NSWorkspace.shared.open(access.url)
    }

    /// Write one log copy. Safe from any thread; failures are logged, never
    /// user-blocking (the primary document save has already succeeded).
    nonisolated static func mirror(data: Data, fileName: String) {
        guard isEnabled, let access = resolvedFolder() else { return }
        defer { access.url.stopAccessingSecurityScopedResource() }
        let sanitized = fileName.replacingOccurrences(of: "/", with: "-")
        let target = access.url.appendingPathComponent(sanitized).appendingPathExtension("qplog")
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            NSLog("CloudMirror: write failed: \(error)")
        }
    }

    /// Resolve the bookmark and begin security-scoped access. Callers must
    /// call `stopAccessingSecurityScopedResource()` when done.
    private nonisolated static func resolvedFolder() -> (url: URL, stale: Bool)? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }
        guard url.startAccessingSecurityScopedResource() else { return nil }
        if stale, let fresh = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return (url, stale)
    }
}

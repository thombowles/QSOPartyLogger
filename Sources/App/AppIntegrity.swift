import Foundation
import Security

/// Whether this running copy of the app can still prove what it is.
///
/// A build launched from DerivedData and rebuilt underneath itself keeps
/// running, but the code identity the kernel recorded at launch — path, slice
/// offset in the fat file, CDHash — no longer describes the file on disk. Every
/// sandbox service that validates its caller then refuses this process: the
/// save-panel service (`openAndSavePanelService`) faults with -67049 and AppKit
/// logs "Unable to display save panel"; ScopedBookmarkAgent cannot read the
/// signature; the app's own `SecCodeCopySelf` fails. Seen live on 2026-08-15:
/// ⌘E and ⇧⌘E did nothing, silently, for a whole session, twelve presses in a
/// row, because the sheet never appeared and nothing said why.
///
/// `SecCodeCopySelf` plus `SecCodeCheckValidity` is the same question the
/// services ask about us, so it fails exactly when they will — which is what
/// makes it worth asking before opening a save panel.
enum AppIntegrity {

    /// A one-line notice for the operator when this copy can no longer verify
    /// itself, or nil when it can.
    static func check() -> String? {
        var code: SecCode?
        let copied = SecCodeCopySelf(SecCSFlags(), &code)
        guard copied == errSecSuccess, let code else { return notice(for: copied) }
        return notice(for: SecCodeCheckValidity(code, SecCSFlags(), nil))
    }

    /// The pure half: success is nothing to say; anything else names the
    /// status (for the log), the usual cause, and the remedy.
    static func notice(for status: OSStatus) -> String? {
        guard status != errSecSuccess else { return nil }
        return "This copy of the app can no longer verify itself (SecCodeCopySelf \(status)) — "
            + "usually because it was rebuilt while it was running. Save panels and exports "
            + "will fail until you quit and reopen it (⌘Q)."
    }
}

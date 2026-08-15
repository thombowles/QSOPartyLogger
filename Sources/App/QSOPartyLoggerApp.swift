import SwiftUI

@main
struct QSOPartyLoggerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { LogDocument() }) { configuration in
            MainView(document: configuration.document)
        }
        .defaultSize(width: 1280, height: 800)
        .commands {
            // Help › Keyboard Shortcut Hints (⌘/): every button wears its key,
            // and the log window lists the keys that have no button. From the
            // log window itself the key monitor answers ⌘/ first; this item is
            // what answers it from a sheet or the dashboard, and where a new
            // operator finds it at all.
            //
            // A Button, not a Toggle with a checkmark: SwiftUI reads a menu
            // Toggle's binding while it builds the main menu at launch, and the
            // test bundle is hosted inside this executable — that read built
            // `AppSettings.shared` on the operator's real preference domain
            // before `TestBundleSetup` could redirect it, and a full test run
            // wrote into the live prefs (2026-08-15). Nothing here may touch
            // `AppSettings.shared` until the operator clicks.
            CommandGroup(after: .help) {
                Button("Keyboard Shortcut Hints") {
                    AppSettings.shared.showShortcutHints.toggle()
                }
                .keyboardShortcut("/", modifiers: .command)
            }
        }

        // Season history + State QSO Party Challenge progress (⌘⇧D; also in
        // the Window menu). Independent of any open contest document.
        Window("Contest Dashboard", id: "dashboard") {
            DashboardView()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .defaultSize(width: 1120, height: 860)
    }
}

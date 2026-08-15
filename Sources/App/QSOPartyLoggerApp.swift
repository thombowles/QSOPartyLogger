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
            CommandGroup(after: .help) {
                Toggle("Keyboard Shortcut Hints", isOn: Binding(
                    get: { AppSettings.shared.showShortcutHints },
                    set: { AppSettings.shared.showShortcutHints = $0 }
                ))
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

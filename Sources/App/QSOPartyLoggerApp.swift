import SwiftUI

@main
struct QSOPartyLoggerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { LogDocument() }) { configuration in
            MainView(document: configuration.document)
        }
        .defaultSize(width: 1280, height: 800)

        // Season history + State QSO Party Challenge progress (⌘⇧D; also in
        // the Window menu). Independent of any open contest document.
        Window("Contest Dashboard", id: "dashboard") {
            DashboardView()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .defaultSize(width: 1120, height: 860)
    }
}

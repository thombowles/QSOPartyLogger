import SwiftUI

@main
struct QSOPartyLoggerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { LogDocument() }) { configuration in
            MainView(document: configuration.document)
        }
        .defaultSize(width: 1280, height: 800)
    }
}

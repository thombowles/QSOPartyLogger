import SwiftUI

@main
struct QSOPartyLoggerApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: {
            // DocumentGroup invokes this on the main thread; assumeIsolated
            // bridges to LogDocument's main-actor initializer.
            MainActor.assumeIsolated { LogDocument() }
        }) { configuration in
            MainView(document: configuration.document)
        }
        .defaultSize(width: 1280, height: 800)
    }
}

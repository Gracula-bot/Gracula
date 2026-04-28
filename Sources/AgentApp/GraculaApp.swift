import AppShell
import SwiftUI

@main
struct GraculaApp: App {
    private let compositionRoot = AppCompositionRoot()

    var body: some Scene {
        WindowGroup {
            compositionRoot.makeAgentView()
        }
    }
}


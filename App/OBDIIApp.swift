import SwiftUI

@main
struct OBDIIApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("OBD-II Reader") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1000, height: 680)
        .commands {
            CommandGroup(after: .toolbar) {
                Button(model.console.isVisible ? "Hide Console" : "Show Console") { model.console.isVisible.toggle() }
                    .keyboardShortcut("`", modifiers: .command)
            }
        }
    }
}

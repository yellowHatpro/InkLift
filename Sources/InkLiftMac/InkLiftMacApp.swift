import SwiftUI
import AppKit

@main
struct InkLiftMacApp: App {
    @StateObject private var model = MacModel()

    init() {
        // A bare SwiftPM executable has no Info.plist; make it a regular foreground app.
        if Bundle.main.bundleIdentifier == nil {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    var body: some Scene {
        WindowGroup("InkLift") {
            MacContentView(model: model)
                .onOpenURL { url in model.open(url) }
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    if let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
                        model.open(URL(fileURLWithPath: path))
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Photo...") { model.chooseFile() }.keyboardShortcut("o")
            }
        }
    }
}

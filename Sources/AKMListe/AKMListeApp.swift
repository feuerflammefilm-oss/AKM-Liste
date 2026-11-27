import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CLI.runIfRequested() { return }
        AKMListeApp.main()
    }
}

struct AKMListeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("FuFF AKM-Liste") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 720, minHeight: 440)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Neu") { ContentView.newList(model) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Öffnen …") { ContentView.openPanel(model) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Sichern") { ContentView.save(model, asNew: false) }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(model.edls.isEmpty)
                Button("Sichern unter …") { ContentView.save(model, asNew: true) }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(model.edls.isEmpty)
            }
        }
    }
}

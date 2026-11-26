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
                Button("EDL öffnen …") { ContentView.openPanel(model) }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

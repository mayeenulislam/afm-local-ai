import SwiftUI

@main
struct LocalAIApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1180, minHeight: 760)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Workspace...") {
                    appState.openWorkspace()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }

            CommandMenu("Task") {
                Button("Run") {
                    appState.runActiveTask()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!appState.canRunActiveTask)

                Button("Stop Task") {
                    appState.cancelActiveTask()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!appState.canCancelActiveTask)
            }
        }
    }
}

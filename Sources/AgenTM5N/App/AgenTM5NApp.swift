import SwiftUI

@main
struct AgenTM5NApp: App {
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup("AgenTM5N") {
      StartupGateView()
        .environmentObject(appState)
        .frame(minWidth: 760, minHeight: 520)
    }
    .defaultSize(width: 1_280, height: 820)
    .commands {
      ANEMLLRuntimeCommands()
    }

    Window("Qwen3 ANE Runtime Lab", id: "anemll-qwen3-runtime") {
      ANEMLLQwenLabView()
        .frame(minWidth: 780, minHeight: 620)
    }
    .defaultSize(width: 980, height: 820)

    Settings {
      SettingsView()
        .environmentObject(appState)
        .frame(minWidth: 620, minHeight: 500)
    }
    .defaultSize(width: 760, height: 620)
  }
}

private struct ANEMLLRuntimeCommands: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandMenu("Neural") {
      Button("Qwen3 ANE Runtime Lab") {
        openWindow(id: "anemll-qwen3-runtime")
      }
      .keyboardShortcut("q", modifiers: [.command, .option])
    }
  }
}

import SwiftUI

@main
struct AgenTM5NApp: App {
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup("AgenTM5N") {
      RootView()
        .environmentObject(appState)
        .frame(minWidth: 760, minHeight: 520)
        .task {
          await appState.bootstrap()
        }
    }
    .defaultSize(width: 1_280, height: 820)

    Settings {
      SettingsView()
        .environmentObject(appState)
        .frame(minWidth: 620, minHeight: 500)
    }
    .defaultSize(width: 760, height: 620)
  }
}

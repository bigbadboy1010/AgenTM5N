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

    Settings {
      SettingsView()
        .environmentObject(appState)
        .frame(minWidth: 620, minHeight: 500)
    }
    .defaultSize(width: 760, height: 620)
  }
}

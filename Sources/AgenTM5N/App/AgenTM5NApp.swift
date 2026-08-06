import SwiftUI

@main
struct AgenTM5NApp: App {
  @StateObject private var appState = AppState()

  var body: some Scene {
    WindowGroup("AgenTM5N") {
      RootView()
        .environmentObject(appState)
        .frame(minWidth: 1_100, minHeight: 720)
        .task {
          await appState.bootstrap()
        }
    }
    .windowResizability(.contentMinSize)

    Settings {
      SettingsView()
        .environmentObject(appState)
        .frame(width: 720, height: 560)
    }
  }
}

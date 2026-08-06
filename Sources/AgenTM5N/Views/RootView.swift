import SwiftUI

struct RootView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    NavigationSplitView {
      List(AppSection.allCases, selection: $appState.selectedSection) { section in
        Label(section.rawValue, systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle("AgenTM5N")
      .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 260)
    } detail: {
      Group {
        switch appState.selectedSection {
        case .chat:
          ChatView()
        case .terminal:
          TerminalWorkspaceView()
        case .ssh:
          SSHHostsView()
        case .vault:
          VaultView()
        case .neuralEngine:
          NeuralEngineView()
        case .settings:
          SettingsView()
        }
      }
      .environmentObject(appState)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .navigationSplitViewStyle(.balanced)
    .alert(
      "Fehler",
      isPresented: Binding(
        get: { appState.errorMessage != nil },
        set: { visible in
          if !visible {
            appState.dismissError()
          }
        }
      )
    ) {
      Button("OK", role: .cancel) {
        appState.dismissError()
      }
    } message: {
      Text(appState.errorMessage ?? "Unbekannter Fehler")
    }
  }
}

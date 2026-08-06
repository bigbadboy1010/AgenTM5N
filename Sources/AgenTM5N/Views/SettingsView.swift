import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    Form {
      Section("Model Provider") {
        Picker(
          "Provider",
          selection: Binding(
            get: { appState.configuration.providerKind },
            set: { appState.providerChanged(to: $0) }
          )
        ) {
          ForEach(ProviderKind.allCases) { provider in
            Text(provider.displayName).tag(provider)
          }
        }

        if appState.configuration.providerKind != .appleOnDevice {
          TextField("Base URL", text: $appState.configuration.baseURL)
          TextField("Modell", text: $appState.configuration.model)
          Toggle("Thinking anfordern", isOn: $appState.configuration.thinkingEnabled)
        }

        if appState.configuration.providerKind == .ollamaCloud {
          if appState.vaultUnlocked {
            Picker("Ollama API Key", selection: $appState.configuration.apiKeySecretID) {
              Text("Nicht ausgewählt").tag(UUID?.none)
              ForEach(apiKeySecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }
          } else {
            Text("Vault entsperren, um einen Ollama API Key auszuwählen.")
              .foregroundStyle(.secondary)
          }
        }
      }

      Section("System Prompt") {
        TextEditor(text: $appState.configuration.systemPrompt)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 220)
      }

      Section("Datenablage") {
        LabeledContent("Application Support", value: AppPaths.applicationSupportDirectory.path)
        LabeledContent("Vault", value: AppPaths.vaultFile.path)
        Text(
          "Konfiguration, Chat-History und SSH-Profile werden lokal gespeichert. Secret-Werte liegen ausschließlich im verschlüsselten Vault."
        )
        .foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button("Speichern") {
          Task { await appState.saveConfiguration() }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .navigationTitle("Settings")
  }

  private var apiKeySecrets: [VaultSecret] {
    appState.secrets.filter { $0.kind == .apiKey || $0.kind == .token }
  }
}

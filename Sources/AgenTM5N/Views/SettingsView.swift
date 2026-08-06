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

      Section("Agent Runtime") {
        Toggle(
          "Tool Calling aktivieren",
          isOn: $appState.configuration.agentEnabled
        )
        .disabled(appState.configuration.providerKind == .appleOnDevice)

        Picker(
          "Berechtigungsmodus",
          selection: $appState.configuration.permissionMode
        ) {
          ForEach(AgentPermissionMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .disabled(!appState.configuration.agentEnabled)

        Text(appState.configuration.permissionMode.explanation)
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          TextField(
            "Workspace",
            text: $appState.configuration.workspacePath
          )
          .textFieldStyle(.roundedBorder)

          Button("Auswählen") {
            appState.selectWorkspace()
          }
        }
        .disabled(!appState.configuration.agentEnabled)

        Stepper(
          "Maximale Tool-Runden: \(appState.configuration.maxToolIterations)",
          value: $appState.configuration.maxToolIterations,
          in: 1...24
        )
        .disabled(!appState.configuration.agentEnabled)

        if appState.configuration.permissionMode == .fullAccess {
          Label(
            "Full Access erlaubt Dateioperationen außerhalb des Workspace und uneingeschränkte Shell-Kommandos.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(.orange)
        }

        if appState.configuration.providerKind == .appleOnDevice {
          Text(
            "Der erste Agent-Loop verwendet Ollamas Tool-Calling-API. Apple On-Device bleibt in diesem Milestone ein reiner Chat-Provider."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
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
          "Konfiguration, Chat-History, Tool-Audit und SSH-Profile werden lokal gespeichert. Secret-Werte liegen ausschließlich im verschlüsselten Vault."
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

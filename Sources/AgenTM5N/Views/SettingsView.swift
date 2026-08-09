import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    Form {
      Section(L10n.text(de: "Modellanbieter", en: "Model Provider", fr: "Fournisseur de modèle")) {
        Picker(
          L10n.text(de: "Anbieter", en: "Provider", fr: "Fournisseur"),
          selection: Binding(
            get: { appState.configuration.providerKind },
            set: { appState.providerChanged(to: $0) }
          )
        ) {
          ForEach(ProviderKind.allCases) { provider in
            Text(providerTitle(provider)).tag(provider)
          }
        }

        if appState.configuration.providerKind != .appleOnDevice {
          TextField("Basis-URL", text: $appState.configuration.baseURL)
          TextField(
            L10n.text(de: "Modell", en: "Model", fr: "Modèle"),
            text: $appState.configuration.model
          )
          Toggle(
            L10n.text(
              de: "Denkprozess anfordern",
              en: "Request Thinking",
              fr: "Demander le raisonnement"
            ),
            isOn: $appState.configuration.thinkingEnabled
          )
        }

        if appState.configuration.providerKind == .ollamaCloud {
          if appState.vaultUnlocked {
            Picker("Ollama API Key", selection: $appState.configuration.apiKeySecretID) {
              Text(L10n.text(de: "Nicht ausgewählt", en: "Not selected", fr: "Non sélectionné"))
                .tag(UUID?.none)
              ForEach(apiKeySecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }
          } else {
            Text(
              L10n.text(
                de: "Tresor entsperren, um einen Ollama API Key auszuwählen.",
                en: "Unlock the vault to select an Ollama API key.",
                fr: "Déverrouillez le coffre pour sélectionner une clé API Ollama."
              )
            )
            .foregroundStyle(.secondary)
          }
        }
      }

      Section(L10n.text(de: "Agent-Laufzeit", en: "Agent Runtime", fr: "Exécution de l’agent")) {
        Toggle(
          L10n.text(
            de: "Werkzeugaufrufe aktivieren",
            en: "Enable Tool Calling",
            fr: "Activer les appels d’outils"
          ),
          isOn: $appState.configuration.agentEnabled
        )

        Picker(
          L10n.text(de: "Berechtigungsmodus", en: "Permission Mode", fr: "Mode d’autorisation"),
          selection: $appState.configuration.permissionMode
        ) {
          ForEach(AgentPermissionMode.allCases) { mode in
            Text(permissionTitle(mode)).tag(mode)
          }
        }
        .disabled(!appState.configuration.agentEnabled)

        Text(permissionExplanation(appState.configuration.permissionMode))
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack {
          TextField(
            L10n.text(de: "Arbeitsbereich", en: "Workspace", fr: "Espace de travail"),
            text: $appState.configuration.workspacePath
          )
          .textFieldStyle(.roundedBorder)

          Button(L10n.text(de: "Auswählen", en: "Select", fr: "Sélectionner")) {
            appState.selectWorkspace()
          }
        }
        .disabled(!appState.configuration.agentEnabled)

        Stepper(
          L10n.text(
            de: "Maximale Werkzeugrunden: \(appState.configuration.maxToolIterations)",
            en: "Maximum Tool Rounds: \(appState.configuration.maxToolIterations)",
            fr: "Cycles d’outils maximum : \(appState.configuration.maxToolIterations)"
          ),
          value: $appState.configuration.maxToolIterations,
          in: 1...24
        )
        .disabled(!appState.configuration.agentEnabled)

        if appState.configuration.permissionMode == .fullAccess {
          Label(
            L10n.text(
              de: "Vollzugriff hebt die normale Arbeitsbereichs- und Freigabegrenze auf. Capability-Sandboxes, Audit und Secret-Schutz bleiben aktiv.",
              en: "Full Access removes the normal workspace and approval boundary. Capability sandboxes, audit, and secret protections remain active.",
              fr: "L’accès complet supprime les limites normales d’espace de travail et d’autorisation. Les sandboxes de capacités, l’audit et la protection des secrets restent actifs."
            ),
            systemImage: "exclamationmark.triangle.fill"
          )
          .foregroundStyle(.orange)
        }

        if appState.configuration.providerKind == .appleOnDevice {
          Text(
            L10n.text(
              de: "Apple lokal verwendet bei aktiviertem Agent-Modus den gemeinsamen AgenTM5N-Tool-Router. SSH, macOS-Werkzeuge und weitere freigegebene Tool-Pakete laufen durch dieselbe Berechtigungs- und Audit-Schicht wie Ollama.",
              en: "With Agent mode enabled, Apple on-device uses the shared AgenTM5N tool router. SSH, macOS tools, and other enabled tool packs use the same permission and audit layer as Ollama.",
              fr: "Lorsque le mode Agent est activé, Apple local utilise le routeur d’outils AgenTM5N partagé. SSH, les outils macOS et les autres packs activés utilisent la même couche d’autorisation et d’audit qu’Ollama."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      Section(L10n.text(de: "Systemanweisung", en: "System Prompt", fr: "Instruction système")) {
        TextEditor(text: $appState.configuration.systemPrompt)
          .font(.system(.body, design: .monospaced))
          .frame(minHeight: 220)

        Text(
          L10n.text(
            de: "Die bevorzugte macOS-Sprache wird bei jedem Modellaufruf zusätzlich verbindlich gesetzt.",
            en: "The preferred macOS language is also enforced for every model request.",
            fr: "La langue macOS préférée est également imposée pour chaque requête de modèle."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Section(L10n.text(de: "Datenablage", en: "Data Storage", fr: "Stockage des données")) {
        LabeledContent(
          L10n.text(de: "Anwendungsdaten", en: "Application Data", fr: "Données d’application"),
          value: AppPaths.applicationSupportDirectory.path
        )
        LabeledContent(L10n.text(de: "Tresor", en: "Vault", fr: "Coffre"), value: AppPaths.vaultFile.path)
        LabeledContent("Core ML", value: AppPaths.coreMLModelsDirectory.path)
        Text(
          L10n.text(
            de: "Konfiguration, Chat-Verlauf, Werkzeugprotokoll und SSH-Profile werden lokal gespeichert. Geheimwerte liegen ausschließlich im verschlüsselten Tresor.",
            en: "Configuration, chat history, tool audit, and SSH profiles are stored locally. Secret values exist only in the encrypted vault.",
            fr: "La configuration, l’historique du chat, l’audit des outils et les profils SSH sont stockés localement. Les valeurs secrètes se trouvent uniquement dans le coffre chiffré."
          )
        )
        .foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button(L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer")) {
          Task { await appState.saveConfiguration() }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .navigationTitle(L10n.text(de: "Einstellungen", en: "Settings", fr: "Réglages"))
  }

  private var apiKeySecrets: [VaultSecret] {
    appState.secrets.filter { $0.kind == .apiKey || $0.kind == .token }
  }

  private func providerTitle(_ provider: ProviderKind) -> String {
    switch provider {
    case .ollamaLocal:
      return "Ollama Local"
    case .ollamaCloud:
      return "Ollama Cloud"
    case .appleOnDevice:
      return L10n.text(de: "Apple lokal", en: "Apple On-Device", fr: "Apple local")
    }
  }

  private func permissionTitle(_ mode: AgentPermissionMode) -> String {
    switch mode {
    case .confirm:
      return L10n.text(de: "Bestätigen", en: "Confirm", fr: "Confirmer")
    case .workspaceTrusted:
      return L10n.text(
        de: "Vertrauenswürdiger Arbeitsbereich",
        en: "Workspace Trusted",
        fr: "Espace de travail approuvé"
      )
    case .fullAccess:
      return L10n.text(de: "Vollzugriff", en: "Full Access", fr: "Accès complet")
    }
  }

  private func permissionExplanation(_ mode: AgentPermissionMode) -> String {
    switch mode {
    case .confirm:
      return L10n.text(
        de: "Lesezugriffe laufen direkt. Schreib-, Ausführungs- und andere verändernde Aktionen benötigen eine Freigabe.",
        en: "Read actions run directly. Write, execution, and other mutating actions require approval.",
        fr: "Les lectures s’exécutent directement. Les écritures, exécutions et autres actions de modification nécessitent une autorisation."
      )
    case .workspaceTrusted:
      return L10n.text(
        de: "Normale, begrenzte Workspace-Dateioperationen dürfen automatisch laufen. Shell/Terminal, Remote/Browser/HTTP, Shortcuts/Toolsmith, persönliche macOS-Daten sowie System-, Agenten- und Workflow-Mutationen bleiben freigabepflichtig.",
        en: "Normal bounded workspace file operations may run automatically. Shell/terminal, remote/browser/HTTP, Shortcuts/Toolsmith, personal macOS data, and system/agent/workflow mutations still require approval.",
        fr: "Les opérations de fichiers normales et limitées à l’espace de travail peuvent s’exécuter automatiquement. Le shell/terminal, les actions distantes/navigateur/HTTP, Raccourcis/Toolsmith, les données macOS personnelles ainsi que les mutations système/agent/workflow nécessitent toujours une autorisation."
      )
    case .fullAccess:
      return L10n.text(
        de: "Lokale und Remote-Werkzeuge dürfen automatisch arbeiten und unterstützte Dateitools dürfen außerhalb des Workspace zugreifen. Explizite Agenten-Sandboxes, Audit und Secret-Schutz bleiben aktiv.",
        en: "Local and remote tools may run automatically and supported file tools may access paths outside the workspace. Explicit agent sandboxes, audit, and secret protections remain active.",
        fr: "Les outils locaux et distants peuvent s’exécuter automatiquement et les outils de fichiers pris en charge peuvent accéder hors de l’espace de travail. Les sandboxes explicites des agents, l’audit et la protection des secrets restent actifs."
      )
    }
  }
}
import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var operatingLayer = AgentOperatingLayerSettings.shared

  var body: some View {
    Form {
      providerSection
      modelRuntimeSection
      agentRuntimeSection
      capabilitySection
      systemPromptSection
      storageSection

      HStack {
        Spacer()
        Button(L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer")) {
          Task { await operatingLayer.saveAndApply(to: appState) }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .formStyle(.grouped)
    .padding()
    .navigationTitle(L10n.text(de: "Einstellungen", en: "Settings", fr: "Réglages"))
    .onAppear {
      operatingLayer.applyRuntimeCompatibility(to: appState)
      if appState.configuration.providerKind == .ollamaLocal,
        operatingLayer.configuration.localInferenceRuntime == .anemll
      {
        appState.configuration.baseURL = LocalInferenceRuntime.anemll.defaultBaseURL
      }
    }
    .onChange(of: operatingLayer.configuration.toolRoundMode) { _, _ in
      operatingLayer.applyRuntimeCompatibility(to: appState)
    }
    .onChange(of: operatingLayer.configuration.maxToolRounds) { _, _ in
      operatingLayer.applyRuntimeCompatibility(to: appState)
    }
    .onChange(of: operatingLayer.configuration.localInferenceRuntime) { _, runtime in
      guard appState.configuration.providerKind == .ollamaLocal else { return }
      appState.configuration.baseURL = runtime.defaultBaseURL
      appState.availableModels = []
      if runtime == .anemll,
        let meta = ANEMLLRuntimeStore.load().metaPath.nonEmpty,
        let descriptor = try? ANEMLLModelBundleInspector.inspect(metaPath: meta)
      {
        appState.configuration.model = descriptor.modelName
      }
    }
  }

  private var providerSection: some View {
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

      if appState.configuration.providerKind == .ollamaLocal {
        Picker(
          L10n.text(de: "Lokale Inference Runtime", en: "Local Inference Runtime", fr: "Runtime d’inférence locale"),
          selection: $operatingLayer.configuration.localInferenceRuntime
        ) {
          Text("Ollama").tag(LocalInferenceRuntime.ollama)
          Text("MLX / mlx_lm.server").tag(LocalInferenceRuntime.mlxServer)
          Text("ANEMLL / Neural Engine").tag(LocalInferenceRuntime.anemll)
        }

        if operatingLayer.configuration.localInferenceRuntime == .mlxServer {
          Text(
            L10n.text(
              de: "MLX verwendet den lokalen OpenAI-kompatiblen mlx_lm.server. AgenTM5N behält Tool-Approval, Audit, Vault und Tool-Ausführung; nur die lokale Modell-Inference läuft über MLX/Metal.",
              en: "MLX uses the local OpenAI-compatible mlx_lm.server. AgenTM5N keeps tool approval, audit, vault, and execution; only local model inference runs through MLX/Metal.",
              fr: "MLX utilise le serveur local compatible OpenAI mlx_lm.server. AgenTM5N conserve les autorisations, l’audit, le coffre et l’exécution des outils ; seule l’inférence locale passe par MLX/Metal."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else if operatingLayer.configuration.localInferenceRuntime == .anemll {
          Text(
            L10n.text(
              de: "ANEMLL verwendet Qwen3 als persistenten nativen Swift/Core-ML-Prozess. Das Modell bleibt zwischen Chat-Nachrichten geladen. Build 37 bietet normalen lokalen Chat; Tool Calling folgt in Build 39.",
              en: "ANEMLL uses Qwen3 through a persistent native Swift/Core ML process. The model stays loaded between chat messages. Build 37 provides normal local chat; tool calling follows in Build 39.",
              fr: "ANEMLL utilise Qwen3 via un processus Swift/Core ML natif persistant. Le modèle reste chargé entre les messages. Le Build 37 fournit le chat local ; les appels d’outils suivront au Build 39."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if appState.configuration.providerKind != .appleOnDevice {
        if appState.configuration.providerKind != .ollamaLocal
          || operatingLayer.configuration.localInferenceRuntime != .anemll
        {
          TextField("Basis-URL", text: $appState.configuration.baseURL)
        } else {
          LabeledContent(
            L10n.text(de: "Transport", en: "Transport", fr: "Transport"),
            value: "Persistent Swift / ANEMLL"
          )
        }

        TextField(
          L10n.text(de: "Modell", en: "Model", fr: "Modèle"),
          text: $appState.configuration.model
        )

        if appState.configuration.providerKind == .ollamaLocal,
          operatingLayer.configuration.localInferenceRuntime == .anemll
        {
          Toggle(
            L10n.text(de: "Qwen3 Thinking", en: "Qwen3 Thinking", fr: "Réflexion Qwen3"),
            isOn: anemllThinkingBinding
          )
        } else if appState.configuration.providerKind != .ollamaLocal
          || operatingLayer.configuration.localInferenceRuntime == .ollama
        {
          Picker(
            L10n.text(de: "Denkmodus", en: "Thinking Mode", fr: "Mode de réflexion"),
            selection: $operatingLayer.configuration.thinkingMode
          ) {
            ForEach(OllamaThinkingMode.allCases) { mode in
              Text(thinkingTitle(mode)).tag(mode)
            }
          }
        } else {
          Text(
            L10n.text(
              de: "Bei MLX wird Reasoning vom geladenen Modell und dessen Chat-Template gesteuert; die Ollama-Denkmodi werden nicht übertragen.",
              en: "With MLX, reasoning is controlled by the loaded model and its chat template; Ollama thinking modes are not forwarded.",
              fr: "Avec MLX, le raisonnement est contrôlé par le modèle chargé et son template de chat ; les modes de réflexion Ollama ne sont pas transmis."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
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
  }

  @ViewBuilder
  private var modelRuntimeSection: some View {
    Section(L10n.text(de: "Modell-Laufzeit", en: "Model Runtime", fr: "Runtime du modèle")) {
      if appState.configuration.providerKind == .appleOnDevice {
        Text(
          L10n.text(
            de: "Apple Foundation Models verwendet die native System-Runtime. Die folgenden Sampling-Parameter gelten für Ollama und MLX.",
            en: "Apple Foundation Models uses the native system runtime. The sampling parameters below apply to Ollama and MLX.",
            fr: "Apple Foundation Models utilise le runtime système natif. Les paramètres ci-dessous s’appliquent à Ollama et MLX."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      runtimeNumberField(
        L10n.text(de: "Context Window", en: "Context Window", fr: "Fenêtre de contexte"),
        value: $operatingLayer.configuration.numContext,
        range: 512...1_048_576
      )
      runtimeNumberField(
        L10n.text(de: "Max. Ausgabe-Tokens", en: "Max Output Tokens", fr: "Tokens de sortie max."),
        value: $operatingLayer.configuration.numPredict,
        range: -1...131_072
      )

      LabeledContent("Temperature") {
        TextField(
          "0.2",
          value: $operatingLayer.configuration.temperature,
          format: .number.precision(.fractionLength(0...3))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 110)
      }
      LabeledContent("Top K") {
        TextField("40", value: $operatingLayer.configuration.topK, format: .number)
          .multilineTextAlignment(.trailing)
          .frame(width: 110)
      }
      LabeledContent("Top P") {
        TextField(
          "0.9",
          value: $operatingLayer.configuration.topP,
          format: .number.precision(.fractionLength(0...4))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 110)
      }
      LabeledContent("Min P") {
        TextField(
          "0.0",
          value: $operatingLayer.configuration.minP,
          format: .number.precision(.fractionLength(0...4))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 110)
      }
      LabeledContent("Repeat Penalty") {
        TextField(
          "1.1",
          value: $operatingLayer.configuration.repeatPenalty,
          format: .number.precision(.fractionLength(0...3))
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 110)
      }
      LabeledContent("Repeat Last N") {
        TextField("64", value: $operatingLayer.configuration.repeatLastN, format: .number)
          .multilineTextAlignment(.trailing)
          .frame(width: 110)
      }
      LabeledContent("Seed") {
        TextField(
          L10n.text(de: "zufällig", en: "random", fr: "aléatoire"),
          text: seedBinding
        )
        .multilineTextAlignment(.trailing)
        .frame(width: 110)
      }

      if appState.configuration.providerKind != .ollamaLocal
        || operatingLayer.configuration.localInferenceRuntime == .ollama
      {
        LabeledContent("Keep Alive") {
          TextField("5m", text: $operatingLayer.configuration.keepAlive)
            .multilineTextAlignment(.trailing)
            .frame(width: 110)
        }
      }

      Stepper(
        L10n.text(
          de: "Request-Timeout: \(operatingLayer.configuration.requestTimeoutSeconds) s",
          en: "Request Timeout: \(operatingLayer.configuration.requestTimeoutSeconds) s",
          fr: "Timeout requête : \(operatingLayer.configuration.requestTimeoutSeconds) s"
        ),
        value: $operatingLayer.configuration.requestTimeoutSeconds,
        in: 30...3_600,
        step: 30
      )

      if appState.configuration.providerKind == .ollamaLocal,
        operatingLayer.configuration.localInferenceRuntime == .mlxServer
      {
        Text(
          L10n.text(
            de: "MLX übernimmt Sampling, Max Output und Repetition-Parameter pro Request. Das maximale KV-/Context-Budget des MLX-Servers wird beim Start von mlx_lm.server festgelegt; der Context-Window-Wert oben wird daher nur von Ollama verwendet.",
            en: "MLX consumes sampling, max-output, and repetition parameters per request. The MLX server KV/context budget is configured when mlx_lm.server starts; therefore Context Window above is used only by Ollama.",
            fr: "MLX utilise les paramètres d’échantillonnage, de sortie maximale et de répétition par requête. Le budget KV/contexte du serveur MLX est défini au démarrage de mlx_lm.server ; la fenêtre de contexte ci-dessus est donc utilisée uniquement par Ollama."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else if appState.configuration.providerKind == .ollamaLocal,
        operatingLayer.configuration.localInferenceRuntime == .anemll
      {
        Text(
          L10n.text(
            de: "Qwen3/ANEMLL besitzt ein modellfestes Context-Limit aus meta.yaml. Build 37 überträgt Max Output, Temperature, Thinking und Request-Timeout; weitere Sampling-Felder werden noch nicht an die native ANEMLL-Runtime weitergereicht.",
            en: "Qwen3/ANEMLL uses the model-fixed context limit from meta.yaml. Build 37 forwards max output, temperature, thinking, and request timeout; the remaining sampling fields are not yet forwarded to the native ANEMLL runtime.",
            fr: "Qwen3/ANEMLL utilise la limite de contexte fixée dans meta.yaml. Le Build 37 transmet la sortie max., la température, le mode réflexion et le timeout ; les autres paramètres ne sont pas encore transmis au runtime natif ANEMLL."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .disabled(appState.configuration.providerKind == .appleOnDevice)
  }

  private var agentRuntimeSection: some View {
    Section(L10n.text(de: "Agent-Laufzeit", en: "Agent Runtime", fr: "Exécution de l’agent")) {
      Toggle(
        L10n.text(
          de: "Werkzeugaufrufe aktivieren",
          en: "Enable Tool Calling",
          fr: "Activer les appels d’outils"
        ),
        isOn: $appState.configuration.agentEnabled
      )

      if appState.configuration.providerKind == .ollamaLocal,
        operatingLayer.configuration.localInferenceRuntime == .anemll
      {
        Text(
          L10n.text(
            de: "Qwen3/ANEMLL läuft in Build 37 als persistenter Chat-Provider. Die zentrale Tool-Sicherheitsarchitektur bleibt aktiv, aber Qwen3 erhält noch keine Tool-Definitionen. Tool Calling ist Roadmap Build 39.",
            en: "Qwen3/ANEMLL runs as a persistent chat provider in Build 37. The central tool-security architecture remains active, but Qwen3 does not receive tool definitions yet. Tool calling is planned for Build 39.",
            fr: "Qwen3/ANEMLL fonctionne comme fournisseur de chat persistant au Build 37. L’architecture centrale de sécurité des outils reste active, mais Qwen3 ne reçoit pas encore les définitions d’outils. Les appels d’outils sont prévus au Build 39."
          )
        )
        .font(.caption)
        .foregroundStyle(.orange)
      }

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

      Picker(
        L10n.text(de: "Tool-Runden", en: "Tool Rounds", fr: "Cycles d’outils"),
        selection: $operatingLayer.configuration.toolRoundMode
      ) {
        Text(L10n.text(de: "Feste Grenze", en: "Fixed Limit", fr: "Limite fixe"))
          .tag(AgentToolRoundMode.fixed)
        Text(L10n.text(de: "Unbegrenzt", en: "Unlimited", fr: "Illimité"))
          .tag(AgentToolRoundMode.unlimited)
      }
      .disabled(!appState.configuration.agentEnabled)

      if operatingLayer.configuration.toolRoundMode == .fixed {
        LabeledContent(
          L10n.text(de: "Maximale Tool-Runden", en: "Maximum Tool Rounds", fr: "Cycles d’outils maximum")
        ) {
          TextField(
            "64",
            value: $operatingLayer.configuration.maxToolRounds,
            format: .number
          )
          .multilineTextAlignment(.trailing)
          .frame(width: 120)
        }
        Text(
          L10n.text(
            de: "Frei wählbar von 1 bis 1.000.000. Die bisherige feste 24-Runden-Grenze wird nicht mehr verwendet.",
            en: "Freely selectable from 1 to 1,000,000. The previous fixed 24-round ceiling is no longer used.",
            fr: "Sélection libre de 1 à 1 000 000. L’ancienne limite fixe de 24 cycles n’est plus utilisée."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Label(
          L10n.text(
            de: "Unbegrenzt beendet den Agenten nur bei Abschluss, Abbruch oder Fehler. Der Stop-Button bleibt jederzeit aktiv.",
            en: "Unlimited stops only on completion, cancellation, or failure. The Stop button remains available at all times.",
            fr: "Le mode illimité s’arrête uniquement à la fin, à l’annulation ou en cas d’erreur. Le bouton Stop reste disponible."
          ),
          systemImage: "infinity"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Toggle(
        L10n.text(
          de: "Stagnation Guard aktivieren",
          en: "Enable Stagnation Guard",
          fr: "Activer Stagnation Guard"
        ),
        isOn: $operatingLayer.configuration.stagnationGuardEnabled
      )
      if operatingLayer.configuration.stagnationGuardEnabled {
        Stepper(
          L10n.text(
            de: "Identische Tool-Wiederholungen: \(operatingLayer.configuration.maxIdenticalToolRounds)",
            en: "Identical tool repetitions: \(operatingLayer.configuration.maxIdenticalToolRounds)",
            fr: "Répétitions d’outil identiques : \(operatingLayer.configuration.maxIdenticalToolRounds)"
          ),
          value: $operatingLayer.configuration.maxIdenticalToolRounds,
          in: 2...20
        )
      }

      Picker(
        L10n.text(de: "Tool-Auswahl", en: "Tool Selection", fr: "Sélection d’outils"),
        selection: $operatingLayer.configuration.toolSelectionMode
      ) {
        Text(L10n.text(de: "Alle aktiven Tools", en: "All Enabled Tools", fr: "Tous les outils actifs"))
          .tag(AgentToolSelectionMode.all)
        Text(L10n.text(de: "Adaptiver Router", en: "Adaptive Router", fr: "Routeur adaptatif"))
          .tag(AgentToolSelectionMode.adaptive)
        Text(L10n.text(de: "Nur Capabilities", en: "Capabilities Only", fr: "Capabilities uniquement"))
          .tag(AgentToolSelectionMode.capabilityFiltered)
      }
      .disabled(!appState.configuration.agentEnabled)

      if operatingLayer.configuration.toolSelectionMode == .adaptive {
        Stepper(
          L10n.text(
            de: "Max. beworbene Tools pro Modellaufruf: \(operatingLayer.configuration.maxAdvertisedTools)",
            en: "Max advertised tools per model call: \(operatingLayer.configuration.maxAdvertisedTools)",
            fr: "Outils max. par appel modèle : \(operatingLayer.configuration.maxAdvertisedTools)"
          ),
          value: $operatingLayer.configuration.maxAdvertisedTools,
          in: 4...256
        )
      }

      Toggle(
        L10n.text(
          de: "AgenTM5N Built-in Tool Packs aktivieren",
          en: "Enable AgenTM5N Built-in Tool Packs",
          fr: "Activer les packs d’outils AgenTM5N"
        ),
        isOn: $operatingLayer.configuration.bundledToolsEnabled
      )

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
            de: "Apple lokal verwendet den gemeinsamen AgenTM5N-Tool-Router. Die Foundation-Models-Runtime fokussiert Tools bereits nativ nach Anfrage und Capability-Scope.",
            en: "Apple on-device uses the shared AgenTM5N tool router. The Foundation Models runtime already focuses tools natively by request and capability scope.",
            fr: "Apple local utilise le routeur d’outils AgenTM5N partagé. Foundation Models cible déjà les outils selon la requête et le scope de capacités."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }

  private var capabilitySection: some View {
    Section(L10n.text(de: "Tool-Capabilities", en: "Tool Capabilities", fr: "Capacités d’outils")) {
      Text(
        L10n.text(
          de: "Capabilities begrenzen, welche Tool-Familien an lokale oder Cloud-Modelle weitergegeben werden. Spezialisierte gespeicherte Agenten dürfen diesen Scope zusätzlich nur weiter einschränken.",
          en: "Capabilities limit which tool families are advertised to local or cloud models. Specialized saved agents may only narrow this scope further.",
          fr: "Les capacités limitent les familles d’outils annoncées aux modèles locaux ou cloud. Les agents spécialisés ne peuvent que réduire davantage ce scope."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      HStack {
        Button(L10n.text(de: "Alle aktivieren", en: "Enable All", fr: "Tout activer")) {
          operatingLayer.configuration.enabledCapabilities = Set(AgentToolCapability.allCases)
        }
        Button(L10n.text(de: "Alle deaktivieren", en: "Disable All", fr: "Tout désactiver")) {
          operatingLayer.configuration.enabledCapabilities = []
        }
      }

      ForEach(AgentToolCapability.allCases, id: \.self) { capability in
        Toggle(
          capabilityTitle(capability),
          isOn: capabilityBinding(capability)
        )
      }
    }
    .disabled(!appState.configuration.agentEnabled)
  }

  private var systemPromptSection: some View {
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
  }

  private var storageSection: some View {
    Section(L10n.text(de: "Datenablage", en: "Data Storage", fr: "Stockage des données")) {
      LabeledContent(
        L10n.text(de: "Anwendungsdaten", en: "Application Data", fr: "Données d’application"),
        value: AppPaths.applicationSupportDirectory.path
      )
      LabeledContent(L10n.text(de: "Tresor", en: "Vault", fr: "Coffre"), value: AppPaths.vaultFile.path)
      LabeledContent("Core ML", value: AppPaths.coreMLModelsDirectory.path)
      Text(
        L10n.text(
          de: "Konfiguration, Chat-Verlauf, Tool-Audit, Operating-Layer-Einstellungen und SSH-Profile werden lokal gespeichert. Geheimwerte liegen ausschließlich im verschlüsselten Tresor.",
          en: "Configuration, chat history, tool audit, operating-layer settings, and SSH profiles are stored locally. Secret values exist only in the encrypted vault.",
          fr: "La configuration, l’historique, l’audit des outils, les réglages Operating Layer et les profils SSH sont stockés localement. Les secrets restent dans le coffre chiffré."
        )
      )
      .foregroundStyle(.secondary)
    }
  }

  private var apiKeySecrets: [VaultSecret] {
    appState.secrets.filter { $0.kind == .apiKey || $0.kind == .token }
  }

  private var seedBinding: Binding<String> {
    Binding(
      get: { operatingLayer.configuration.seed.map(String.init) ?? "" },
      set: { value in
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        operatingLayer.configuration.seed = trimmed.isEmpty ? nil : Int(trimmed)
      }
    )
  }

  private var anemllThinkingBinding: Binding<Bool> {
    Binding(
      get: { operatingLayer.configuration.thinkingMode != .off },
      set: { enabled in
        operatingLayer.configuration.thinkingMode = enabled ? .standard : .off
        operatingLayer.applyRuntimeCompatibility(to: appState)
      }
    )
  }

  private func runtimeNumberField(
    _ title: String,
    value: Binding<Int>,
    range: ClosedRange<Int>
  ) -> some View {
    LabeledContent(title) {
      TextField("", value: value, format: .number)
        .multilineTextAlignment(.trailing)
        .frame(width: 120)
        .onSubmit {
          value.wrappedValue = max(range.lowerBound, min(value.wrappedValue, range.upperBound))
        }
    }
  }

  private func capabilityBinding(_ capability: AgentToolCapability) -> Binding<Bool> {
    Binding(
      get: { operatingLayer.configuration.enabledCapabilities.contains(capability) },
      set: { enabled in
        if enabled {
          operatingLayer.configuration.enabledCapabilities.insert(capability)
        } else {
          operatingLayer.configuration.enabledCapabilities.remove(capability)
        }
      }
    )
  }

  private func providerTitle(_ provider: ProviderKind) -> String {
    switch provider {
    case .ollamaLocal:
      return "Local Runtime"
    case .ollamaCloud:
      return "Ollama Cloud"
    case .appleOnDevice:
      return L10n.text(de: "Apple lokal", en: "Apple On-Device", fr: "Apple local")
    }
  }

  private func thinkingTitle(_ mode: OllamaThinkingMode) -> String {
    switch mode {
    case .off:
      return L10n.text(de: "Aus", en: "Off", fr: "Désactivé")
    case .standard:
      return L10n.text(de: "Standard", en: "Standard", fr: "Standard")
    case .low:
      return "Low"
    case .medium:
      return "Medium"
    case .high:
      return "High"
    case .max:
      return "Max"
    }
  }

  private func capabilityTitle(_ capability: AgentToolCapability) -> String {
    switch capability {
    case .workspace: "Workspace / Files"
    case .terminal: "Terminal / Toolsmith / MCP"
    case .ssh: "SSH"
    case .edge: "Edge Nodes"
    case .browser: "Browser"
    case .git: "Git"
    case .macPersonal: "Calendar / Contacts / Mail"
    case .secrets: "Vault Metadata"
    case .http: "HTTP / APIs"
    case .system: "macOS / Containers / Kubernetes / Network"
    case .reminders: "Reminders"
    case .coreML: "Core ML / Neural Engine"
    case .memory: "Workspace Memory / Context"
    case .knowledge: "Knowledge Library"
    case .attachments: "Conversation Attachments"
    case .documents: "Document Studio"
    case .agents: "Persistent Agents / Delegation"
    case .workflows: "Workflows"
    case .updates: "App Updates"
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
        de: "Normale, begrenzte Workspace-Dateioperationen dürfen automatisch laufen. Shell/Terminal, Remote/Browser/HTTP, Shortcuts/Toolsmith/MCP, persönliche macOS-Daten sowie System-, Agenten- und Workflow-Mutationen bleiben freigabepflichtig.",
        en: "Normal bounded workspace file operations may run automatically. Shell/terminal, remote/browser/HTTP, Shortcuts/Toolsmith/MCP, personal macOS data, and system/agent/workflow mutations still require approval.",
        fr: "Les opérations de fichiers normales et limitées à l’espace de travail peuvent s’exécuter automatiquement. Le shell/terminal, les actions distantes/navigateur/HTTP, Raccourcis/Toolsmith/MCP, les données macOS personnelles ainsi que les mutations système/agent/workflow nécessitent toujours une autorisation."
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

private extension String {
  var nonEmpty: String? {
    isEmpty ? nil : self
  }
}

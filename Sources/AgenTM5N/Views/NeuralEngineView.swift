import AppKit
import SwiftUI

struct NeuralEngineView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isImportingModel = false
  @State private var computeMode = CoreMLRuntimePolicyStore.currentMode
  @State private var computePlanReport: CoreMLComputePlanReport?
  @State private var isAnalyzingComputePlan = false
  @State private var persistentSessionEnabled = false
  @State private var sessionID = UUID().uuidString

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        languageCard
        hardwareCard
        appleModelCard
        neuralRuntimeCard
        coreMLCard
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Neural Engine")
  }

  private var languageCard: some View {
    GroupBox(L10n.text(de: "Sprache", en: "Language", fr: "Langue")) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "character.bubble")
          .font(.title2)
          .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 4) {
          Text(SystemLanguage.current.displayName)
            .font(.headline)
          Text(
            L10n.text(
              de: "Agent-Antworten, Diagnosen und Statusmeldungen folgen automatisch der aktuell bevorzugten macOS-Sprache.",
              en: "Agent replies, diagnostics, and status messages automatically follow the currently preferred macOS language.",
              fr: "Les réponses de l’agent, les diagnostics et les messages d’état suivent automatiquement la langue macOS actuellement préférée."
            )
          )
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var hardwareCard: some View {
    GroupBox(L10n.text(de: "Hardware", en: "Hardware", fr: "Matériel")) {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
        GridRow {
          Text("Chip").foregroundStyle(.secondary)
          Text(appState.hardwareProfile.chipName)
        }
        GridRow {
          Text(L10n.text(de: "Gemeinsamer Speicher", en: "Unified Memory", fr: "Mémoire unifiée"))
            .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.memoryDescription)
        }
        GridRow {
          Text("macOS").foregroundStyle(.secondary)
          Text(appState.hardwareProfile.operatingSystem)
        }
        GridRow {
          Text(L10n.text(de: "Core-ML-Modus", en: "Core ML Mode", fr: "Mode Core ML"))
            .foregroundStyle(.secondary)
          Text(computeMode.displayName)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var appleModelCard: some View {
    GroupBox(
      L10n.text(
        de: "Lokales Apple Foundation Model",
        en: "Apple On-Device Foundation Model",
        fr: "Modèle Foundation local d’Apple"
      )
    ) {
      VStack(alignment: .leading, spacing: 10) {
        LabeledContent(
          L10n.text(de: "Status", en: "Status", fr: "État"),
          value: appState.hardwareProfile.appleFoundationModelStatus
        )
        Text(
          L10n.text(
            de: "Der Chat-Provider „Apple lokal“ verwendet Apples System-Sprachmodell. Apple entscheidet intern über die tatsächliche Hardware-Verteilung.",
            en: "The Apple on-device chat provider uses Apple’s system language model. Apple decides the actual hardware placement internally.",
            fr: "Le fournisseur de chat Apple local utilise le modèle linguistique système d’Apple. Apple décide en interne de l’affectation matérielle réelle."
          )
        )
        .foregroundStyle(.secondary)
        Button(L10n.text(de: "Im Chat auswählen", en: "Select in Chat", fr: "Sélectionner dans le chat")) {
          appState.providerChanged(to: .appleOnDevice)
          appState.selectedSection = .chat
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var neuralRuntimeCard: some View {
    GroupBox(
      L10n.text(
        de: "Neural Compute Runtime 2.0",
        en: "Neural Compute Runtime 2.0",
        fr: "Neural Compute Runtime 2.0"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Picker(
          L10n.text(de: "Rechenrichtlinie", en: "Compute Policy", fr: "Politique de calcul"),
          selection: $computeMode
        ) {
          ForEach(CoreMLComputeMode.allCases) { mode in
            Text(mode.displayName).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: computeMode) { _, newMode in
          CoreMLRuntimePolicyStore.set(newMode)
          computePlanReport = nil
          Task { await CoreMLPredictionRunner.shared.clearCache() }
        }

        Text(computeMode.explanation)
          .font(.callout)
          .foregroundStyle(.secondary)

        if computeMode == .neuralEnginePreferred {
          Label(
            L10n.text(
              de: "Dieser Modus bedeutet CPU + Apple Neural Engine, nicht „ANE only“. Nicht unterstützte Operatoren dürfen weiterhin auf der CPU laufen.",
              en: "This mode means CPU + Apple Neural Engine, not ANE-only. Unsupported operators may still run on the CPU.",
              fr: "Ce mode signifie CPU + Apple Neural Engine, et non ANE uniquement. Les opérateurs non pris en charge peuvent toujours utiliser le CPU."
            ),
            systemImage: "info.circle"
          )
          .font(.callout)
        }

        if let descriptor = appState.coreMLDescriptor {
          Divider()
          HStack {
            Button {
              Task { await analyzeComputePlan(descriptor) }
            } label: {
              if isAnalyzingComputePlan {
                ProgressView().controlSize(.small)
              } else {
                Label(
                  L10n.text(
                    de: "Execution Plan analysieren",
                    en: "Analyze Execution Plan",
                    fr: "Analyser le plan d’exécution"
                  ),
                  systemImage: "waveform.path.ecg"
                )
              }
            }
            .disabled(isAnalyzingComputePlan)

            if let report = computePlanReport {
              Text(
                L10n.text(
                  de: "\(report.totalOperations) Operatoren analysiert",
                  en: "\(report.totalOperations) operations analyzed",
                  fr: "\(report.totalOperations) opérations analysées"
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }

          if let report = computePlanReport {
            computePlanDetails(report)
          }
        } else {
          Text(
            L10n.text(
              de: "Importiere ein Core-ML-Modell, um den erwarteten Device-Plan pro Operator zu analysieren.",
              en: "Import a Core ML model to analyze its expected device plan per operator.",
              fr: "Importez un modèle Core ML pour analyser son plan de périphériques attendu par opérateur."
            )
          )
          .foregroundStyle(.secondary)
        }
      }
      .padding(8)
    }
  }

  private func computePlanDetails(_ report: CoreMLComputePlanReport) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
        GridRow {
          Text(L10n.text(de: "Modellstruktur", en: "Model Structure", fr: "Structure du modèle"))
            .foregroundStyle(.secondary)
          Text(report.modelType)
        }
        GridRow {
          Text("ANE preferred").foregroundStyle(.secondary)
          Text("\(report.preferredNeuralEngineOperations) · \(percent(report.neuralEnginePreferredPercentage))")
        }
        GridRow {
          Text("ANE supported").foregroundStyle(.secondary)
          Text("\(report.neuralEngineSupportedOperations) · \(percent(report.neuralEngineSupportedPercentage))")
        }
        GridRow {
          Text("CPU / GPU / ANE").foregroundStyle(.secondary)
          Text("\(report.preferredCPUOperations) / \(report.preferredGPUOperations) / \(report.preferredNeuralEngineOperations)")
        }
        GridRow {
          Text(L10n.text(de: "Stateful", en: "Stateful", fr: "Avec état"))
            .foregroundStyle(.secondary)
          Text(report.stateful ? "Ja" : "Nein")
        }
        GridRow {
          Text(L10n.text(de: "Verfügbare Devices", en: "Available Devices", fr: "Périphériques disponibles"))
            .foregroundStyle(.secondary)
          Text(report.availableDevices.map(\.displayName).joined(separator: ", "))
        }
      }

      let totalWeight = report.cpuEstimatedWeight
        + report.gpuEstimatedWeight
        + report.neuralEngineEstimatedWeight
        + report.unknownEstimatedWeight
      if totalWeight > 0 {
        VStack(alignment: .leading, spacing: 5) {
          Text(L10n.text(de: "Geschätzte relative Rechenlast", en: "Estimated Relative Compute Cost", fr: "Coût de calcul relatif estimé"))
            .font(.headline)
          Text("CPU \(weight(report.cpuEstimatedWeight)) · GPU \(weight(report.gpuEstimatedWeight)) · ANE \(weight(report.neuralEngineEstimatedWeight))")
            .font(.system(.caption, design: .monospaced))
          Text(
            L10n.text(
              de: "Diese Werte stammen aus dem Core-ML-Compute-Plan. Sie beschreiben die erwartete Planung und relative Kosten, nicht eine gemessene Hardware-Auslastung.",
              en: "These values come from the Core ML compute plan. They describe expected scheduling and relative cost, not measured hardware utilization.",
              fr: "Ces valeurs proviennent du plan de calcul Core ML. Elles décrivent la planification attendue et le coût relatif, pas une utilisation matérielle mesurée."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }

      if !report.stateFeatureNames.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("MLState")
            .font(.headline)
          ForEach(report.stateFeatureNames, id: \.self) { name in
            Text(name)
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
        }
      }

      if !report.topOperations.isEmpty {
        DisclosureGroup(
          L10n.text(
            de: "Top-Operatoren anzeigen",
            en: "Show Top Operations",
            fr: "Afficher les principales opérations"
          )
        ) {
          VStack(alignment: .leading, spacing: 5) {
            ForEach(report.topOperations) { operation in
              HStack(alignment: .firstTextBaseline) {
                Text(operation.name)
                  .font(.system(.caption, design: .monospaced))
                Spacer()
                Text(operation.preferredDevice.displayName)
                  .font(.caption)
                if let estimatedWeight = operation.estimatedWeight {
                  Text(weight(estimatedWeight))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
          .padding(.top, 6)
        }
      }
    }
    .padding(12)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  private var coreMLCard: some View {
    GroupBox("Core ML") {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          Button(action: selectCoreMLModel) {
            if isImportingModel {
              ProgressView().controlSize(.small)
            } else {
              Label(
                L10n.text(de: "Core-ML-Modell importieren", en: "Import Core ML Model", fr: "Importer un modèle Core ML"),
                systemImage: "square.and.arrow.down"
              )
            }
          }
          .disabled(isImportingModel)

          if let descriptor = appState.coreMLDescriptor {
            Label(L10n.text(de: "Registriert", en: "Registered", fr: "Enregistré"), systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
            Text(descriptor.sourceURL.lastPathComponent)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }

        if let descriptor = appState.coreMLDescriptor {
          modelDetails(descriptor)
          predictionEditor(descriptor)
        } else {
          VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(de: "Unterstützte Formate", en: "Supported Formats", fr: "Formats pris en charge"))
              .font(.headline)
            Text(".mlmodel  ·  .mlpackage  ·  .mlmodelc")
              .font(.system(.body, design: .monospaced))
            Text(
              L10n.text(
                de: "Modelle werden transaktional in den verwalteten AgenTM5N-Speicher übernommen, bei Bedarf kompiliert und vor der Registrierung durch Core ML validiert.",
                en: "Models are transactionally imported into AgenTM5N managed storage, compiled when necessary, and validated by Core ML before registration.",
                fr: "Les modèles sont importés transactionnellement dans le stockage géré par AgenTM5N, compilés si nécessaire et validés par Core ML avant enregistrement."
              )
            )
            .foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private func modelDetails(_ descriptor: CoreMLModelDescriptor) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      LabeledContent(
        L10n.text(de: "Aktive Rechenrichtlinie", en: "Active Compute Policy", fr: "Politique de calcul active"),
        value: computeMode.computePolicyDescription
      )

      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.text(de: "Importierte Quelle", en: "Imported Source", fr: "Source importée"))
          .font(.headline)
        Text(descriptor.sourceURL.path)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(L10n.text(de: "Kompiliertes Modell", en: "Compiled Model", fr: "Modèle compilé"))
          .font(.headline)
        Text(descriptor.compiledURL.path)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 32) {
          featureList(title: L10n.text(de: "Eingaben", en: "Inputs", fr: "Entrées"), values: descriptor.inputs)
          featureList(title: L10n.text(de: "Ausgaben", en: "Outputs", fr: "Sorties"), values: descriptor.outputs)
        }
        VStack(alignment: .leading, spacing: 14) {
          featureList(title: L10n.text(de: "Eingaben", en: "Inputs", fr: "Entrées"), values: descriptor.inputs)
          featureList(title: L10n.text(de: "Ausgaben", en: "Outputs", fr: "Sorties"), values: descriptor.outputs)
        }
      }
    }
  }

  private func featureList(title: String, values: [String]) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title).font(.headline)
      if values.isEmpty {
        Text("–").foregroundStyle(.secondary)
      } else {
        ForEach(values, id: \.self) { value in
          Text(value)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func predictionEditor(_ descriptor: CoreMLModelDescriptor) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(L10n.text(de: "Eingaben als JSON", en: "Inputs as JSON", fr: "Entrées JSON"))
        .font(.headline)

      TextEditor(text: $appState.coreMLPredictionInput)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 120)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }

      Toggle(
        L10n.text(
          de: "Persistente MLState-Session verwenden",
          en: "Use Persistent MLState Session",
          fr: "Utiliser une session MLState persistante"
        ),
        isOn: $persistentSessionEnabled
      )

      if persistentSessionEnabled {
        HStack {
          Text("Session")
            .foregroundStyle(.secondary)
          Text(sessionID)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
          Spacer()
          Button(L10n.text(de: "State zurücksetzen", en: "Reset State", fr: "Réinitialiser l’état")) {
            Task {
              await CoreMLPredictionRunner.shared.resetSession(
                compiledURL: descriptor.compiledURL,
                sessionID: sessionID
              )
              sessionID = UUID().uuidString
            }
          }
        }
        Text(
          L10n.text(
            de: "Bei stateful Core-ML-Modellen bleibt MLState zwischen Vorhersagen erhalten. Das ist die Basis für KV-Cache-/autoregressive Sessions; ein modellspezifischer Tokenizer und Generation-Adapter ist weiterhin erforderlich.",
            en: "For stateful Core ML models, MLState persists between predictions. This is the substrate for KV-cache/autoregressive sessions; a model-specific tokenizer and generation adapter is still required.",
            fr: "Pour les modèles Core ML avec état, MLState persiste entre les prédictions. C’est la base des sessions KV-cache/autoregressives ; un tokenizer et un adaptateur de génération spécifiques au modèle restent nécessaires."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Button {
        Task { await runPrediction(descriptor) }
      } label: {
        if appState.isRunningCoreML {
          ProgressView().controlSize(.small)
        } else {
          Label(
            L10n.text(de: "Vorhersage ausführen", en: "Run Prediction", fr: "Exécuter la prédiction"),
            systemImage: "play.fill"
          )
        }
      }
      .disabled(appState.isRunningCoreML)

      if let result = appState.coreMLPredictionResult {
        VStack(alignment: .leading, spacing: 6) {
          Text(
            L10n.text(
              de: "Ergebnis – \(result.durationMilliseconds.formatted(.number.precision(.fractionLength(3)))) ms",
              en: "Result – \(result.durationMilliseconds.formatted(.number.precision(.fractionLength(3)))) ms",
              fr: "Résultat – \(result.durationMilliseconds.formatted(.number.precision(.fractionLength(3)))) ms"
            )
          )
          .font(.headline)
          ForEach(result.values.keys.sorted(), id: \.self) { key in
            HStack(alignment: .top) {
              Text(key).font(.system(.caption, design: .monospaced).bold())
              Text(result.values[key] ?? "")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            }
          }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      }
    }
  }

  @MainActor
  private func runPrediction(_ descriptor: CoreMLModelDescriptor) async {
    if !persistentSessionEnabled {
      await appState.runCoreMLPrediction()
      return
    }

    appState.isRunningCoreML = true
    defer { appState.isRunningCoreML = false }
    do {
      appState.coreMLPredictionResult = try await CoreMLPredictionRunner.shared.predict(
        compiledURL: descriptor.compiledURL,
        jsonInput: appState.coreMLPredictionInput,
        sessionID: sessionID
      )
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  @MainActor
  private func analyzeComputePlan(_ descriptor: CoreMLModelDescriptor) async {
    isAnalyzingComputePlan = true
    defer { isAnalyzingComputePlan = false }
    do {
      computePlanReport = try await CoreMLComputePlanAnalyzer.analyze(
        compiledURL: descriptor.compiledURL,
        mode: computeMode
      )
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  private func percent(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) %"
  }

  private func weight(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(4)))
  }

  private func selectCoreMLModel() {
    let panel = NSOpenPanel()
    panel.title = L10n.text(de: "Core-ML-Modell auswählen", en: "Select Core ML Model", fr: "Sélectionner un modèle Core ML")
    panel.prompt = L10n.text(de: "Importieren", en: "Import", fr: "Importer")
    panel.message = L10n.text(
      de: "Wähle eine .mlmodel-, .mlpackage- oder .mlmodelc-Datei beziehungsweise ein entsprechendes Paketverzeichnis aus.",
      en: "Select an .mlmodel, .mlpackage, or .mlmodelc file or package directory.",
      fr: "Sélectionnez un fichier ou paquet .mlmodel, .mlpackage ou .mlmodelc."
    )
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.resolvesAliases = true
    panel.treatsFilePackagesAsDirectories = false

    guard panel.runModal() == .OK, let url = panel.url else { return }
    let supportedExtensions: Set<String> = ["mlmodel", "mlpackage", "mlmodelc"]
    guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
      appState.errorMessage = L10n.text(
        de: "Nicht unterstütztes Modell. Erlaubt sind .mlmodel, .mlpackage und .mlmodelc.",
        en: "Unsupported model. Supported types are .mlmodel, .mlpackage, and .mlmodelc.",
        fr: "Modèle non pris en charge. Les types acceptés sont .mlmodel, .mlpackage et .mlmodelc."
      )
      return
    }

    let accessed = url.startAccessingSecurityScopedResource()
    isImportingModel = true
    Task {
      await appState.loadCoreMLModel(from: url)
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
      computePlanReport = nil
      isImportingModel = false
    }
  }
}

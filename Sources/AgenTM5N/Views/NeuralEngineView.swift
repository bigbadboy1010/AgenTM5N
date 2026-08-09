import AppKit
import SwiftUI

struct NeuralEngineView: View {
  @EnvironmentObject private var appState: AppState
  @State private var isImportingModel = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        languageCard
        hardwareCard
        appleModelCard
        coreMLCard
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(
      L10n.text(
        de: "Neural Engine",
        en: "Neural Engine",
        fr: "Neural Engine"
      )
    )
  }

  private var languageCard: some View {
    GroupBox(
      L10n.text(
        de: "Sprache",
        en: "Language",
        fr: "Langue"
      )
    ) {
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
    GroupBox(
      L10n.text(
        de: "Hardware",
        en: "Hardware",
        fr: "Matériel"
      )
    ) {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
        GridRow {
          Text("Chip")
            .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.chipName)
        }
        GridRow {
          Text(
            L10n.text(
              de: "Gemeinsamer Speicher",
              en: "Unified Memory",
              fr: "Mémoire unifiée"
            )
          )
          .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.memoryDescription)
        }
        GridRow {
          Text("macOS")
            .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.operatingSystem)
        }
        GridRow {
          Text(
            L10n.text(
              de: "Core-ML-Recheneinheiten",
              en: "Core ML Compute Units",
              fr: "Unités de calcul Core ML"
            )
          )
          .foregroundStyle(.secondary)
          Text(
            L10n.text(
              de: "CPU + GPU + Apple Neural Engine (Core ML entscheidet)",
              en: "CPU + GPU + Apple Neural Engine (Core ML decides)",
              fr: "CPU + GPU + Apple Neural Engine (Core ML décide)"
            )
          )
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
        Button(
          L10n.text(
            de: "Im Chat auswählen",
            en: "Select in Chat",
            fr: "Sélectionner dans le chat"
          )
        ) {
          appState.providerChanged(to: .appleOnDevice)
          appState.selectedSection = .chat
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var coreMLCard: some View {
    GroupBox(
      L10n.text(
        de: "Core ML – adaptive Hardware-Verteilung",
        en: "Core ML – adaptive hardware scheduling",
        fr: "Core ML – répartition matérielle adaptative"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 12) {
          Button(action: selectCoreMLModel) {
            if isImportingModel {
              ProgressView()
                .controlSize(.small)
            } else {
              Label(
                L10n.text(
                  de: "Core-ML-Modell importieren",
                  en: "Import Core ML Model",
                  fr: "Importer un modèle Core ML"
                ),
                systemImage: "square.and.arrow.down"
              )
            }
          }
          .disabled(isImportingModel)

          if let descriptor = appState.coreMLDescriptor {
            Label(
              L10n.text(
                de: "Geladen",
                en: "Loaded",
                fr: "Chargé"
              ),
              systemImage: "checkmark.circle.fill"
            )
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
          predictionEditor
        } else {
          VStack(alignment: .leading, spacing: 8) {
            Text(
              L10n.text(
                de: "Unterstützte Formate",
                en: "Supported formats",
                fr: "Formats pris en charge"
              )
            )
            .font(.headline)

            Text(".mlmodel  ·  .mlpackage  ·  .mlmodelc")
              .font(.system(.body, design: .monospaced))

            Text(
              L10n.text(
                de: "Das ausgewählte Modell wird in den geschützten AgenTM5N-Anwendungsordner kopiert, bei Bedarf kompiliert und mit allen verfügbaren Core-ML-Recheneinheiten geladen. CPU, GPU und Apple Neural Engine bleiben verfügbar; Core ML entscheidet pro Operator, welche Hardware tatsächlich verwendet wird.",
                en: "The selected model is copied into AgenTM5N’s protected application directory, compiled when required, and loaded with all available Core ML compute units. CPU, GPU, and Apple Neural Engine remain available; Core ML decides the actual hardware placement per operator.",
                fr: "Le modèle sélectionné est copié dans le dossier d’application protégé d’AgenTM5N, compilé si nécessaire, puis chargé avec toutes les unités de calcul Core ML disponibles. Le CPU, le GPU et l’Apple Neural Engine restent disponibles ; Core ML décide du matériel utilisé pour chaque opérateur."
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
        L10n.text(
          de: "Rechenrichtlinie",
          en: "Compute Policy",
          fr: "Politique de calcul"
        ),
        value: L10n.text(
          de: "Alle verfügbar (CPU + GPU + Neural Engine)",
          en: "All available (CPU + GPU + Neural Engine)",
          fr: "Toutes disponibles (CPU + GPU + Neural Engine)"
        )
      )

      VStack(alignment: .leading, spacing: 5) {
        Text(
          L10n.text(
            de: "Importierte Quelle",
            en: "Imported Source",
            fr: "Source importée"
          )
        )
        .font(.headline)
        Text(descriptor.sourceURL.path)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }

      VStack(alignment: .leading, spacing: 5) {
        Text(
          L10n.text(
            de: "Kompiliertes Modell",
            en: "Compiled Model",
            fr: "Modèle compilé"
          )
        )
        .font(.headline)
        Text(descriptor.compiledURL.path)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
      }

      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 32) {
          featureList(
            title: L10n.text(de: "Eingaben", en: "Inputs", fr: "Entrées"),
            values: descriptor.inputs
          )
          featureList(
            title: L10n.text(de: "Ausgaben", en: "Outputs", fr: "Sorties"),
            values: descriptor.outputs
          )
        }

        VStack(alignment: .leading, spacing: 14) {
          featureList(
            title: L10n.text(de: "Eingaben", en: "Inputs", fr: "Entrées"),
            values: descriptor.inputs
          )
          featureList(
            title: L10n.text(de: "Ausgaben", en: "Outputs", fr: "Sorties"),
            values: descriptor.outputs
          )
        }
      }
    }
  }

  private func featureList(title: String, values: [String]) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.headline)
      if values.isEmpty {
        Text("–")
          .foregroundStyle(.secondary)
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

  private var predictionEditor: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(
        L10n.text(
          de: "Skalare Eingaben als JSON",
          en: "Scalar Inputs as JSON",
          fr: "Entrées scalaires en JSON"
        )
      )
      .font(.headline)

      Text(
        L10n.text(
          de: "Der generische Runner unterstützt aktuell Zahlen, Ganzzahlen und Text. Bild-, MultiArray-, Sequenz- oder State-Modelle können geladen und analysiert werden, benötigen für Vorhersagen jedoch einen typgerechten Adapter.",
          en: "The generic runner currently supports numbers, integers, and text. Image, MultiArray, sequence, or state models can be loaded and inspected, but prediction requires a type-specific adapter.",
          fr: "L’exécuteur générique prend actuellement en charge les nombres, les entiers et le texte. Les modèles Image, MultiArray, séquence ou état peuvent être chargés et inspectés, mais la prédiction nécessite un adaptateur spécifique."
        )
      )
      .foregroundStyle(.secondary)

      TextEditor(text: $appState.coreMLPredictionInput)
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 120)
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }

      Button {
        Task { await appState.runCoreMLPrediction() }
      } label: {
        if appState.isRunningCoreML {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(
            L10n.text(
              de: "Vorhersage ausführen",
              en: "Run Prediction",
              fr: "Exécuter la prédiction"
            ),
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
              Text(key)
                .font(.system(.caption, design: .monospaced).bold())
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

  private func selectCoreMLModel() {
    let panel = NSOpenPanel()
    panel.title = L10n.text(
      de: "Core-ML-Modell auswählen",
      en: "Select Core ML Model",
      fr: "Sélectionner un modèle Core ML"
    )
    panel.prompt = L10n.text(
      de: "Importieren",
      en: "Import",
      fr: "Importer"
    )
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
      isImportingModel = false
    }
  }
}

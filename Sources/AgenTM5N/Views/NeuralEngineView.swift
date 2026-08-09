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
                de: "Registriert",
                en: "Registered",
                fr: "Enregistré"
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
          Text(
            L10n.text(
              de: "Das Modell ist persistent registriert. Der Core-ML-Execution-Plan wird absichtlich erst bei Aktivierung oder Vorhersage aufgebaut und anschließend für weitere Vorhersagen im Prozess wiederverwendet.",
              en: "The model is persistently registered. Its Core ML execution plan is intentionally built only when activated or predicted with, then reused for later predictions in the same process.",
              fr: "Le modèle est enregistré de façon persistante. Son plan d’exécution Core ML n’est construit qu’à l’activation ou à la prédiction, puis réutilisé pour les prédictions suivantes du même processus."
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)

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
                de: "Das ausgewählte Modell wird transaktional in den geschützten AgenTM5N-Anwendungsordner übernommen, bei Bedarf kompiliert und vor der Registrierung validiert. Identische Modellinhalte werden wiederverwendet statt mehrfach gespeichert. CPU, GPU und Apple Neural Engine bleiben verfügbar; Core ML entscheidet pro Operator, welche Hardware tatsächlich verwendet wird.",
                en: "The selected model is transactionally imported into AgenTM5N’s protected application directory, compiled when required, and validated before registration. Identical model content is reused instead of being stored repeatedly. CPU, GPU, and Apple Neural Engine remain available; Core ML decides the actual hardware placement per operator.",
                fr: "Le modèle sélectionné est importé de façon transactionnelle dans le dossier protégé d’AgenTM5N, compilé si nécessaire et validé avant enregistrement. Un contenu de modèle identique est réutilisé au lieu d’être dupliqué. Le CPU, le GPU et l’Apple Neural Engine restent disponibles ; Core ML décide du matériel utilisé pour chaque opérateur."
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
          de: "Eingaben als JSON",
          en: "Inputs as JSON",
          fr: "Entrées JSON"
        )
      )
      .font(.headline)

      Text(
        L10n.text(
          de: "Der generische Runner unterstützt Zahlen, Ganzzahlen und Text sowie verschachtelte numerische JSON-Arrays für MultiArray-Inputs und lokale Bildpfade für Image-Inputs. Sequence- und State-Modelle können registriert und analysiert werden, benötigen für ihre Vorhersage gegebenenfalls einen typgerechten Adapter.",
          en: "The generic runner supports numbers, integers and text, nested numeric JSON arrays for MultiArray inputs, and local image paths for Image inputs. Sequence and state models can be registered and inspected but may require a type-specific prediction adapter.",
          fr: "L’exécuteur générique prend en charge les nombres, les entiers et le texte, les tableaux JSON numériques imbriqués pour les entrées MultiArray et les chemins d’images locaux pour les entrées Image. Les modèles Sequence et State peuvent être enregistrés et inspectés, mais peuvent nécessiter un adaptateur de prédiction spécifique."
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
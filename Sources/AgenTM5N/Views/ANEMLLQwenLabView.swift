import AppKit
import SwiftUI

struct ANEMLLQwenLabView: View {
  @State private var runtime = ANEMLLRuntimeStore.load()
  @State private var prompt = "Antworte in zwei kurzen Sätzen: Was ist die Apple Neural Engine?"
  @State private var maxTokens = 128
  @State private var temperature = 0.0
  @State private var thinkingEnabled = false
  @State private var descriptor: ANEMLLModelBundleDescriptor?
  @State private var result: ANEMLLRuntimeResult?
  @State private var statusMessage: String?
  @State private var isRunning = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        runtimeCard
        modelCard
        generationCard
        if let result {
          resultCard(result)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Qwen3 · ANEMLL")
    .task {
      validateRuntime()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Qwen3 ANE Runtime Lab · Build 36")
        .font(.title2.bold())
      Text(
        L10n.text(
          de: "Führt Qwen3 über die native Swift-Referenzruntime von ANEMLL aus. Python wird für diesen Lauf nicht verwendet. Die angezeigten Token-Raten sind echte End-to-End-Inferenzwerte der ANEMLL-Runtime; sie sind keine direkte Messung der ANE-Hardwareauslastung.",
          en: "Runs Qwen3 through ANEMLL's native Swift reference runtime. Python is not used for this run. Token rates are real end-to-end ANEMLL inference measurements; they are not direct measurements of ANE hardware utilization.",
          fr: "Exécute Qwen3 via le runtime Swift natif de référence ANEMLL. Python n’est pas utilisé pour cette exécution. Les débits de tokens sont des mesures d’inférence ANEMLL de bout en bout, pas une mesure directe de l’utilisation matérielle de l’ANE."
        )
      )
      .font(.callout)
      .foregroundStyle(.secondary)
    }
  }

  private var runtimeCard: some View {
    GroupBox(L10n.text(de: "Native ANEMLL Runtime", en: "Native ANEMLL Runtime", fr: "Runtime ANEMLL natif")) {
      VStack(alignment: .leading, spacing: 12) {
        LabeledContent(L10n.text(de: "Swift Helper", en: "Swift Helper", fr: "Helper Swift")) {
          TextField("/path/to/anemllcli", text: $runtime.helperPath)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 420)
        }

        LabeledContent("meta.yaml") {
          TextField("/path/to/model/meta.yaml", text: $runtime.metaPath)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 420)
        }

        HStack(spacing: 10) {
          Button(L10n.text(de: "Automatisch erkennen", en: "Auto Detect", fr: "Détection auto")) {
            runtime = ANEMLLRuntimeStore.discoveredConfiguration()
            maxTokens = runtime.defaultMaxTokens
            temperature = runtime.defaultTemperature
            ANEMLLRuntimeStore.save(runtime)
            validateRuntime()
          }

          Button(L10n.text(de: "Konfiguration speichern", en: "Save Configuration", fr: "Enregistrer la configuration")) {
            runtime.defaultMaxTokens = maxTokens
            runtime.defaultTemperature = temperature
            ANEMLLRuntimeStore.save(runtime)
            validateRuntime()
          }

          Button(L10n.text(de: "Modellordner öffnen", en: "Open Model Folder", fr: "Ouvrir le dossier du modèle")) {
            let path = ANEMLLRuntimeStore.expanded(runtime.metaPath)
            let url = URL(fileURLWithPath: path).deletingLastPathComponent()
            NSWorkspace.shared.open(url)
          }
          .disabled(runtime.metaPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        if let statusMessage {
          Text(statusMessage)
            .font(.caption)
            .foregroundStyle(descriptor == nil ? .orange : .secondary)
            .textSelection(.enabled)
        }
      }
      .padding(8)
    }
  }

  private var modelCard: some View {
    GroupBox(L10n.text(de: "ANEMLL Modell-Bundle", en: "ANEMLL Model Bundle", fr: "Bundle de modèle ANEMLL")) {
      if let descriptor {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
          GridRow {
            Text(L10n.text(de: "Modell", en: "Model", fr: "Modèle")).foregroundStyle(.secondary)
            Text(descriptor.modelName)
          }
          GridRow {
            Text(L10n.text(de: "Kontext", en: "Context", fr: "Contexte")).foregroundStyle(.secondary)
            Text(descriptor.contextLength.map(String.init) ?? "–")
          }
          GridRow {
            Text(L10n.text(de: "Prefill Batch", en: "Prefill Batch", fr: "Lot de préremplissage")).foregroundStyle(.secondary)
            Text(descriptor.batchSize.map(String.init) ?? "–")
          }
          GridRow {
            Text(L10n.text(de: "Core-ML-Komponenten", en: "Core ML Components", fr: "Composants Core ML")).foregroundStyle(.secondary)
            Text("\(descriptor.componentCount)")
          }
          GridRow {
            Text("Embeddings").foregroundStyle(.secondary)
            Text(descriptor.embeddingsURL.lastPathComponent)
          }
          GridRow {
            Text("FFN / PREFILL").foregroundStyle(.secondary)
            Text(descriptor.ffnURLs.map(\.lastPathComponent).joined(separator: ", "))
              .lineLimit(2)
          }
          GridRow {
            Text("LM Head").foregroundStyle(.secondary)
            Text(descriptor.lmHeadURL.lastPathComponent)
          }
          GridRow {
            Text("Tokenizer").foregroundStyle(.secondary)
            Text(descriptor.tokenizerURL.lastPathComponent)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        Text(
          L10n.text(
            de: "Noch kein vollständiges ANEMLL-Modell-Bundle validiert.",
            en: "No complete ANEMLL model bundle has been validated yet.",
            fr: "Aucun bundle de modèle ANEMLL complet n’a encore été validé."
          )
        )
        .foregroundStyle(.secondary)
      }
    }
  }

  private var generationCard: some View {
    GroupBox(L10n.text(de: "Native Qwen3 Generation", en: "Native Qwen3 Generation", fr: "Génération Qwen3 native")) {
      VStack(alignment: .leading, spacing: 12) {
        TextEditor(text: $prompt)
          .font(.body)
          .frame(minHeight: 90, idealHeight: 120)
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(.quaternary)
          )

        HStack(spacing: 18) {
          Stepper(
            L10n.text(
              de: "Max Tokens: \(maxTokens)",
              en: "Max Tokens: \(maxTokens)",
              fr: "Tokens max : \(maxTokens)"
            ),
            value: $maxTokens,
            in: 8...2_048,
            step: 8
          )

          LabeledContent("Temperature") {
            TextField(
              "0.0",
              value: $temperature,
              format: .number.precision(.fractionLength(0...3))
            )
            .frame(width: 80)
          }

          Toggle(
            L10n.text(de: "Thinking", en: "Thinking", fr: "Réflexion"),
            isOn: $thinkingEnabled
          )
          .toggleStyle(.switch)
        }

        Button {
          Task { await runGeneration() }
        } label: {
          if isRunning {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text(L10n.text(de: "Qwen3 läuft auf ANEMLL…", en: "Qwen3 is running on ANEMLL…", fr: "Qwen3 s’exécute sur ANEMLL…"))
            }
          } else {
            Label(
              L10n.text(de: "Qwen3 nativ testen", en: "Run Native Qwen3 Test", fr: "Tester Qwen3 en natif"),
              systemImage: "brain.head.profile"
            )
          }
        }
        .disabled(isRunning || descriptor == nil || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(8)
    }
  }

  private func resultCard(_ result: ANEMLLRuntimeResult) -> some View {
    GroupBox(L10n.text(de: "Ergebnis", en: "Result", fr: "Résultat")) {
      VStack(alignment: .leading, spacing: 12) {
        Text(result.response)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)

        Divider()

        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
          GridRow {
            Text("Inference").foregroundStyle(.secondary)
            Text(rate(result.metrics.inferenceTokensPerSecond))
          }
          GridRow {
            Text("Prefill").foregroundStyle(.secondary)
            Text(rate(result.metrics.prefillTokensPerSecond))
          }
          GridRow {
            Text("TTFT").foregroundStyle(.secondary)
            Text(milliseconds(result.metrics.timeToFirstTokenMilliseconds))
          }
          GridRow {
            Text(L10n.text(de: "Generierte Tokens", en: "Generated Tokens", fr: "Tokens générés")).foregroundStyle(.secondary)
            Text(result.metrics.generatedTokens.map(String.init) ?? "–")
          }
          GridRow {
            Text(L10n.text(de: "Modell-Load", en: "Model Load", fr: "Chargement du modèle")).foregroundStyle(.secondary)
            Text(result.metrics.modelLoadSeconds.map { String(format: "%.2f s", $0) } ?? "–")
          }
          GridRow {
            Text(L10n.text(de: "Gesamtlauf", en: "Wall Time", fr: "Durée totale")).foregroundStyle(.secondary)
            Text(String(format: "%.0f ms", result.metrics.wallMilliseconds))
          }
          GridRow {
            Text("Stop").foregroundStyle(.secondary)
            Text(result.metrics.stopReason ?? "–")
          }
        }

        DisclosureGroup(L10n.text(de: "ANEMLL Diagnoseausgabe", en: "ANEMLL Diagnostic Output", fr: "Sortie de diagnostic ANEMLL")) {
          Text(result.diagnosticOutput)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
      }
      .padding(8)
    }
  }

  @MainActor
  private func runGeneration() async {
    guard !isRunning else { return }
    isRunning = true
    result = nil
    defer { isRunning = false }

    runtime.defaultMaxTokens = maxTokens
    runtime.defaultTemperature = temperature
    ANEMLLRuntimeStore.save(runtime)

    do {
      let generated = try await ANEMLLNativeRuntime.complete(
        prompt: prompt,
        systemPrompt: SystemLanguage.current.agentInstruction,
        thinkingEnabled: thinkingEnabled,
        maxTokens: maxTokens,
        temperature: temperature,
        runtimeConfiguration: runtime
      )
      ANEMLLRuntimeTelemetry.shared.record(generated)
      result = generated
      descriptor = generated.descriptor
      statusMessage = L10n.text(
        de: "Native Swift-ANEMLL-Ausführung erfolgreich.",
        en: "Native Swift ANEMLL execution succeeded.",
        fr: "Exécution ANEMLL Swift native réussie."
      )
    } catch {
      statusMessage = error.localizedDescription
    }
  }

  private func validateRuntime() {
    do {
      let helper = ANEMLLRuntimeStore.expanded(runtime.helperPath)
      guard FileManager.default.isExecutableFile(atPath: helper) else {
        descriptor = nil
        statusMessage = L10n.text(
          de: "Native ANEMLL-CLI fehlt. Führe scripts/bootstrap-anemll-runtime.sh aus.",
          en: "Native ANEMLL CLI is missing. Run scripts/bootstrap-anemll-runtime.sh.",
          fr: "Le CLI ANEMLL natif manque. Exécutez scripts/bootstrap-anemll-runtime.sh."
        )
        return
      }
      descriptor = try ANEMLLModelBundleInspector.inspect(metaPath: runtime.metaPath)
      statusMessage = L10n.text(
        de: "Swift Helper und Qwen3-Modell-Bundle sind bereit.",
        en: "Swift helper and Qwen3 model bundle are ready.",
        fr: "Le helper Swift et le bundle Qwen3 sont prêts."
      )
    } catch {
      descriptor = nil
      statusMessage = error.localizedDescription
    }
  }

  private func rate(_ value: Double?) -> String {
    value.map { String(format: "%.1f t/s", $0) } ?? "–"
  }

  private func milliseconds(_ value: Double?) -> String {
    value.map { String(format: "%.1f ms", $0) } ?? "–"
  }
}

import SwiftUI

struct CoreMLModelLabView: View {
  let descriptor: CoreMLModelDescriptor

  @State private var isRunning = false
  @State private var currentMode: CoreMLComputeMode?
  @State private var partialResults: [CoreMLModelLabModeResult] = []
  @State private var labReport: CoreMLModelLabReport?
  @State private var runtimeReport: CoreMLRuntimeBenchmarkReport?

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      GroupBox(
        L10n.text(
          de: "ANE Model Lab · Build 34",
          en: "ANE Model Lab · Build 34",
          fr: "ANE Model Lab · Build 34"
        )
      ) {
        VStack(alignment: .leading, spacing: 14) {
          Text(
            L10n.text(
              de: "Vergleicht dasselbe Core-ML-Modell sequenziell mit Automatisch, CPU+GPU und CPU+Neural Engine. Gemessen wird die Zeit zum Aufbau und Analysieren des MLComputePlan; dies ist keine gemessene Hardware-Auslastung. Die Ergebnisse werden zusammen mit dem Runtime Benchmark hardware- und OS-spezifisch für Adaptive Neural Execution gespeichert.",
              en: "Compares the same Core ML model sequentially with Automatic, CPU+GPU, and CPU+Neural Engine. The measured time is MLComputePlan build and analysis time; it is not measured hardware utilization. The results are stored together with the runtime benchmark per hardware/OS environment for Adaptive Neural Execution.",
              fr: "Compare séquentiellement le même modèle Core ML avec Automatique, CPU+GPU et CPU+Neural Engine. Le temps mesuré correspond à la construction et à l’analyse de MLComputePlan ; il ne s’agit pas d’une utilisation matérielle mesurée. Les résultats sont conservés avec le benchmark d’exécution par environnement matériel/OS pour Adaptive Neural Execution."
            )
          )
          .font(.callout)
          .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            Button {
              Task { await runLab() }
            } label: {
              if isRunning {
                HStack(spacing: 8) {
                  ProgressView().controlSize(.small)
                  Text(
                    currentMode.map {
                      L10n.text(
                        de: "Teste \($0.displayName)…",
                        en: "Testing \($0.displayName)…",
                        fr: "Test de \($0.displayName)…"
                      )
                    }
                      ?? L10n.text(de: "Model Lab läuft…", en: "Model Lab running…", fr: "Model Lab en cours…")
                  )
                }
              } else {
                Label(
                  L10n.text(
                    de: "ANE Model Lab starten",
                    en: "Run ANE Model Lab",
                    fr: "Lancer ANE Model Lab"
                  ),
                  systemImage: "cpu"
                )
              }
            }
            .disabled(isRunning)

            if !partialResults.isEmpty {
              Text(
                L10n.text(
                  de: "\(partialResults.count) / \(CoreMLModelLab.benchmarkModes.count) Modi abgeschlossen",
                  en: "\(partialResults.count) / \(CoreMLModelLab.benchmarkModes.count) modes complete",
                  fr: "\(partialResults.count) / \(CoreMLModelLab.benchmarkModes.count) modes terminés"
                )
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          }

          if let report = labReport {
            modelLabSummary(report)
            modelLabMatrix(report)
          } else if !partialResults.isEmpty {
            modelLabMatrix(
              CoreMLModelLab.evaluate(
                modelName: descriptor.sourceURL.lastPathComponent,
                results: partialResults
              )
            )
          }
        }
        .padding(8)
      }

      CoreMLRuntimeBenchmarkView(
        descriptor: descriptor,
        report: $runtimeReport
      )

      if let runtimeReport {
        CoreMLAdaptiveRouterView(
          descriptor: descriptor,
          modelLabReport: labReport,
          runtimeReport: runtimeReport
        )
      }
    }
    .task(id: descriptor.compiledURL.standardizedFileURL.path) {
      await restoreRoutingEvidence()
    }
  }

  private func modelLabSummary(_ report: CoreMLModelLabReport) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline, spacing: 24) {
        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.text(de: "ANE-Eignung", en: "ANE Suitability", fr: "Compatibilité ANE"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(report.aneSuitability.displayName)
            .font(.title3.bold())
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.text(de: "Heuristischer ANE-Score", en: "Heuristic ANE Score", fr: "Score ANE heuristique"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text("\(report.aneSuitabilityScore) / 100")
            .font(.title3.monospacedDigit().bold())
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(L10n.text(de: "Plan-Empfehlung", en: "Plan recommendation", fr: "Recommandation du plan"))
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(report.recommendedMode.displayName)
            .font(.title3.bold())
        }
      }

      Text(report.recommendationReason)
        .font(.callout)

      Text(
        L10n.text(
          de: "Der Model-Lab-Score bewertet Plan-Kompatibilität und aufgelöste ANE-Coverage. Für die tatsächliche Laufzeitentscheidung verwendet Adaptive Neural Execution zusätzlich Cold Load, erste Vorhersage und warme p50-Latenz.",
          en: "The Model Lab score evaluates plan compatibility and resolved ANE coverage. For the actual runtime decision, Adaptive Neural Execution additionally uses cold load, first prediction, and warm p50 latency.",
          fr: "Le score du Model Lab évalue la compatibilité du plan et la couverture ANE résolue. Pour la décision d’exécution réelle, Adaptive Neural Execution utilise en plus le chargement à froid, la première prédiction et la latence p50 à chaud."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  private func modelLabMatrix(_ report: CoreMLModelLabReport) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L10n.text(de: "Compatibility Matrix", en: "Compatibility Matrix", fr: "Matrice de compatibilité"))
        .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
        GridRow {
          Text(L10n.text(de: "Modus", en: "Mode", fr: "Mode")).bold()
          Text("Plan").bold()
          Text("ms").bold()
          Text(L10n.text(de: "Aufgelöst", en: "Resolved", fr: "Résolues")).bold()
          Text("CPU / GPU / ANE").bold()
          Text("ANE supported").bold()
        }

        Divider().gridCellUnsizedAxes(.horizontal)

        ForEach(report.results) { result in
          GridRow {
            Text(result.mode.displayName)
            Label(
              result.succeeded ? "PASS" : "FAIL",
              systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            .labelStyle(.titleAndIcon)

            Text(result.durationMilliseconds.formatted(.number.precision(.fractionLength(0))))
              .monospacedDigit()

            if let plan = result.report {
              Text("\(result.resolvedOperations) / \(plan.totalOperations)")
                .monospacedDigit()
              Text(
                "\(plan.preferredCPUOperations) / \(plan.preferredGPUOperations) / \(plan.preferredNeuralEngineOperations)"
              )
              .monospacedDigit()
              Text(
                "\(plan.neuralEngineSupportedOperations) · \(percent(plan.neuralEngineSupportedPercentage))"
              )
              .monospacedDigit()
            } else {
              Text("–")
              Text("–")
              Text("–")
            }
          }

          if let error = result.errorDescription, !error.isEmpty {
            GridRow {
              Text("")
              Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .gridCellColumns(5)
            }
          }
        }
      }
      .font(.caption)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  @MainActor
  private func runLab() async {
    guard !isRunning else { return }
    isRunning = true
    currentMode = nil
    partialResults = []
    labReport = nil
    defer {
      currentMode = nil
      isRunning = false
    }

    for mode in CoreMLModelLab.benchmarkModes {
      currentMode = mode
      let result = await CoreMLModelLab.runMode(
        compiledURL: descriptor.compiledURL,
        mode: mode
      )
      partialResults.append(result)
    }

    let evaluated = CoreMLModelLab.evaluate(
      modelName: descriptor.sourceURL.lastPathComponent,
      results: partialResults
    )
    labReport = evaluated
    await CoreMLAdaptiveRouter.shared.recordModelLab(
      evaluated,
      compiledURL: descriptor.compiledURL,
      modelName: descriptor.sourceURL.lastPathComponent
    )
  }

  @MainActor
  private func restoreRoutingEvidence() async {
    guard
      let profile = await CoreMLAdaptiveRouter.shared.profile(
        compiledURL: descriptor.compiledURL
      )
    else {
      return
    }
    labReport = profile.modelLabReport
    partialResults = profile.modelLabReport?.results ?? []
    runtimeReport = profile.runtimeBenchmarkReport
  }

  private func percent(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) %"
  }
}

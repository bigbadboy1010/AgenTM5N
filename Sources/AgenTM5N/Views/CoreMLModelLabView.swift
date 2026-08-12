import SwiftUI

struct CoreMLModelLabView: View {
  let descriptor: CoreMLModelDescriptor

  @State private var isRunning = false
  @State private var currentMode: CoreMLComputeMode?
  @State private var partialResults: [CoreMLModelLabModeResult] = []
  @State private var labReport: CoreMLModelLabReport?

  var body: some View {
    GroupBox(
      L10n.text(
        de: "ANE Model Lab · Build 31",
        en: "ANE Model Lab · Build 31",
        fr: "ANE Model Lab · Build 31"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          L10n.text(
            de: "Vergleicht dasselbe Core-ML-Modell sequenziell mit Automatisch, CPU+GPU und CPU+Neural Engine. Gemessen wird die Zeit zum Aufbau und Analysieren des MLComputePlan; dies ist keine gemessene Hardware-Auslastung und noch kein Token/s-Benchmark.",
            en: "Compares the same Core ML model sequentially with Automatic, CPU+GPU, and CPU+Neural Engine. The measured time is MLComputePlan build and analysis time; it is not measured hardware utilization and not yet a tokens/s benchmark.",
            fr: "Compare séquentiellement le même modèle Core ML avec Automatique, CPU+GPU et CPU+Neural Engine. Le temps mesuré correspond à la construction et à l’analyse de MLComputePlan ; il ne s’agit ni d’une utilisation matérielle mesurée ni encore d’un benchmark en tokens/s."
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
          Text(L10n.text(de: "Empfohlener Modus", en: "Recommended Mode", fr: "Mode recommandé"))
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
          de: "Der Score ist eine transparente AgenTM5N-Heuristik aus Plan-Erfolg und aufgelöster ANE-Coverage. Er ist weder eine Apple-Kennzahl noch eine Messung der realen NPU-Auslastung.",
          en: "The score is a transparent AgenTM5N heuristic derived from plan success and resolved ANE coverage. It is neither an Apple metric nor a measurement of real NPU utilization.",
          fr: "Le score est une heuristique transparente d’AgenTM5N basée sur le succès du plan et la couverture ANE résolue. Ce n’est ni une métrique Apple ni une mesure de l’utilisation réelle du NPU."
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

    labReport = CoreMLModelLab.evaluate(
      modelName: descriptor.sourceURL.lastPathComponent,
      results: partialResults
    )
  }

  private func percent(_ value: Double) -> String {
    "\(value.formatted(.number.precision(.fractionLength(1)))) %"
  }
}

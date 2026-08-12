import SwiftUI

struct CoreMLRuntimeBenchmarkView: View {
  let descriptor: CoreMLModelDescriptor

  @State private var isRunning = false
  @State private var report: CoreMLRuntimeBenchmarkReport?

  var body: some View {
    GroupBox(
      L10n.text(
        de: "ANE Runtime Benchmark · Build 32",
        en: "ANE Runtime Benchmark · Build 32",
        fr: "ANE Runtime Benchmark · Build 32"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          L10n.text(
            de: "Misst echte Core-ML-Vorhersagen mit Automatisch, CPU+GPU und CPU+Neural Engine. Erfasst werden Modell-Ladezeit, erste Vorhersage sowie 10 warme Läufe mit Mittelwert, p50 und p95. Die Messung zeigt Inferenzlatenz, nicht die reale NPU-Auslastung.",
            en: "Measures real Core ML predictions with Automatic, CPU+GPU, and CPU+Neural Engine. It records model load time, first prediction, and 10 warm runs with mean, p50, and p95. The measurement shows inference latency, not actual NPU utilization.",
            fr: "Mesure de vraies prédictions Core ML avec Automatique, CPU+GPU et CPU+Neural Engine. Le benchmark enregistre le chargement du modèle, la première prédiction et 10 exécutions à chaud avec moyenne, p50 et p95. Il mesure la latence d’inférence, pas l’utilisation réelle du NPU."
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        HStack(spacing: 12) {
          Button {
            Task { await runBenchmark() }
          } label: {
            if isRunning {
              HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(
                  L10n.text(
                    de: "Runtime Benchmark läuft…",
                    en: "Runtime Benchmark running…",
                    fr: "Benchmark d’exécution en cours…"
                  )
                )
              }
            } else {
              Label(
                L10n.text(
                  de: "Runtime Benchmark starten",
                  en: "Run Runtime Benchmark",
                  fr: "Lancer le benchmark d’exécution"
                ),
                systemImage: "stopwatch"
              )
            }
          }
          .disabled(isRunning)

          if let report, let fastest = report.fastestMode {
            Text(
              L10n.text(
                de: "Schnellster warmer p50: \(fastest.displayName)",
                en: "Fastest warm p50: \(fastest.displayName)",
                fr: "p50 à chaud le plus rapide : \(fastest.displayName)"
              )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }

        if let report {
          summary(report)
          matrix(report)
        }
      }
      .padding(8)
    }
  }

  private func summary(_ report: CoreMLRuntimeBenchmarkReport) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      if let fastest = report.fastestMode {
        LabeledContent(
          L10n.text(
            de: "Schnellster Modus nach warmem p50",
            en: "Fastest mode by warm p50",
            fr: "Mode le plus rapide selon le p50 à chaud"
          ),
          value: fastest.displayName
        )
      }

      LabeledContent(
        L10n.text(
          de: "Ausgabestruktur über erfolgreiche Modi",
          en: "Output structure across successful modes",
          fr: "Structure de sortie entre les modes réussis"
        ),
        value: report.outputsStructurallyEquivalent
          ? L10n.text(de: "Identisch", en: "Equivalent", fr: "Équivalente")
          : L10n.text(de: "Abweichend / unvollständig", en: "Different / incomplete", fr: "Différente / incomplète")
      )

      Text(
        L10n.text(
          de: "Für Transformer-Eingänge erzeugt AgenTM5N ein festes synthetisches Input-Pattern. Bei input_ids werden [CLS]=101 und [SEP]=102 gesetzt; bei attention_mask werden die ersten zwei Positionen aktiviert. Dadurch lässt sich die Hardware-Latenz reproduzierbar vergleichen, ohne einen externen Tokenizer zu benötigen.",
          en: "For transformer inputs, AgenTM5N generates a fixed synthetic input pattern. input_ids uses [CLS]=101 and [SEP]=102, while attention_mask enables the first two positions. This makes hardware latency reproducible without requiring an external tokenizer.",
          fr: "Pour les entrées Transformer, AgenTM5N génère un motif synthétique fixe. input_ids utilise [CLS]=101 et [SEP]=102, tandis que attention_mask active les deux premières positions. Cela permet de comparer la latence matérielle de façon reproductible sans tokenizer externe."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  private func matrix(_ report: CoreMLRuntimeBenchmarkReport) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        L10n.text(
          de: "Runtime Matrix",
          en: "Runtime Matrix",
          fr: "Matrice d’exécution"
        )
      )
      .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
        GridRow {
          Text(L10n.text(de: "Modus", en: "Mode", fr: "Mode")).bold()
          Text("Status").bold()
          Text("Load ms").bold()
          Text("First ms").bold()
          Text("Mean ms").bold()
          Text("p50 ms").bold()
          Text("p95 ms").bold()
        }

        Divider().gridCellUnsizedAxes(.horizontal)

        ForEach(report.results) { result in
          GridRow {
            Text(result.mode.displayName)
            Label(
              result.succeeded ? "PASS" : "FAIL",
              systemImage: result.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill"
            )
            Text(milliseconds(result.modelLoadMilliseconds))
              .monospacedDigit()
            Text(optionalMilliseconds(result.firstPredictionMilliseconds))
              .monospacedDigit()
            Text(optionalMilliseconds(result.warmMeanMilliseconds))
              .monospacedDigit()
            Text(optionalMilliseconds(result.warmP50Milliseconds))
              .monospacedDigit()
            Text(optionalMilliseconds(result.warmP95Milliseconds))
              .monospacedDigit()
          }

          if let error = result.errorDescription, !error.isEmpty {
            GridRow {
              Text("")
              Text(error)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .gridCellColumns(6)
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
  private func runBenchmark() async {
    guard !isRunning else { return }
    isRunning = true
    report = nil
    defer { isRunning = false }

    report = await CoreMLRuntimeBenchmark.shared.run(
      compiledURL: descriptor.compiledURL,
      warmRuns: 10
    )
  }

  private func milliseconds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
  }

  private func optionalMilliseconds(_ value: Double?) -> String {
    guard let value else { return "–" }
    return milliseconds(value)
  }
}

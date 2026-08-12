import SwiftUI

struct CoreMLAdaptiveRouterView: View {
  let modelLabReport: CoreMLModelLabReport?
  let runtimeReport: CoreMLRuntimeBenchmarkReport

  @State private var workloadPreset: CoreMLAdaptiveWorkloadPreset = .interactive

  var body: some View {
    GroupBox(
      L10n.text(
        de: "Adaptive Neural Router · Build 33",
        en: "Adaptive Neural Router · Build 33",
        fr: "Adaptive Neural Router · Build 33"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          L10n.text(
            de: "Kombiniert MLComputePlan-Evidenz mit real gemessener Vorhersagelatenz. Der Router berücksichtigt neben warmem p50 auch Modell-Ladezeit und erste Vorhersage. Dadurch wird ein schneller ANE-Warm-Pfad nicht automatisch zum besten Modus für kurze Sessions.",
            en: "Combines MLComputePlan evidence with measured prediction latency. The router considers model load time and first prediction in addition to warm p50. A fast warm ANE path therefore does not automatically become the best mode for short sessions.",
            fr: "Combine les informations de MLComputePlan avec la latence de prédiction mesurée. Le routeur tient compte du chargement du modèle et de la première prédiction en plus du p50 à chaud. Un chemin ANE rapide à chaud ne devient donc pas automatiquement le meilleur mode pour les sessions courtes."
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        Picker(
          L10n.text(
            de: "Lastprofil",
            en: "Workload",
            fr: "Profil de charge"
          ),
          selection: $workloadPreset
        ) {
          ForEach(CoreMLAdaptiveWorkloadPreset.allCases) { preset in
            Text("\(preset.displayName) · \(preset.expectedPredictions)")
              .tag(preset)
          }
        }
        .pickerStyle(.segmented)

        let decision = CoreMLAdaptiveRouter.evaluate(
          modelLabReport: modelLabReport,
          runtimeReport: runtimeReport,
          expectedPredictions: workloadPreset.expectedPredictions
        )

        summary(decision)
        estimateMatrix(decision)
      }
      .padding(8)
    }
  }

  private func summary(_ decision: CoreMLAdaptiveRouteDecision) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 7) {
        GridRow {
          Text(
            L10n.text(
              de: "Adaptive Empfehlung",
              en: "Adaptive recommendation",
              fr: "Recommandation adaptative"
            )
          )
          .foregroundStyle(.secondary)
          Text(decision.recommendedMode.displayName).bold()
        }
        GridRow {
          Text(
            L10n.text(
              de: "Konfidenz",
              en: "Confidence",
              fr: "Confiance"
            )
          )
          .foregroundStyle(.secondary)
          Text(decision.confidence.displayName)
        }
        GridRow {
          Text(
            L10n.text(
              de: "Schnellster Cold Start",
              en: "Fastest cold start",
              fr: "Démarrage à froid le plus rapide"
            )
          )
          .foregroundStyle(.secondary)
          Text(decision.coldStartMode?.displayName ?? "–")
        }
        GridRow {
          Text(
            L10n.text(
              de: "Schnellster warmer p50",
              en: "Fastest warm p50",
              fr: "p50 à chaud le plus rapide"
            )
          )
          .foregroundStyle(.secondary)
          Text(decision.warmLatencyMode?.displayName ?? "–")
        }
        GridRow {
          Text(
            L10n.text(
              de: "ANE Break-even vs. Automatisch",
              en: "ANE break-even vs. Automatic",
              fr: "Seuil de rentabilité ANE vs Automatique"
            )
          )
          .foregroundStyle(.secondary)
          if let breakEven = decision.aneBreakEvenPredictionsVersusAutomatic {
            Text(
              L10n.text(
                de: "≈ \(breakEven) Vorhersagen",
                en: "≈ \(breakEven) predictions",
                fr: "≈ \(breakEven) prédictions"
              )
            )
            .monospacedDigit()
          } else {
            Text("–")
          }
        }
      }

      Text(decision.reason)
        .font(.callout)

      Text(
        L10n.text(
          de: "Die Gesamtlatenz ist eine AgenTM5N-Schätzung aus gemessener Ladezeit + erster Vorhersage + warmem p50 × weiteren Vorhersagen. Sie ist workload-spezifisch und keine Apple-Hardwaremetrik. Automatisch kann selbst ANE verwenden, wenn Core ML dies pro Operator auswählt.",
          en: "Total latency is an AgenTM5N estimate from measured load time + first prediction + warm p50 × remaining predictions. It is workload-specific and not an Apple hardware metric. Automatic may itself use ANE when Core ML selects it per operator.",
          fr: "La latence totale est une estimation AgenTM5N basée sur le temps de chargement mesuré + la première prédiction + le p50 à chaud × les prédictions restantes. Elle dépend de la charge et n’est pas une métrique matérielle Apple. Automatique peut lui-même utiliser l’ANE lorsque Core ML le choisit par opérateur."
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  private func estimateMatrix(_ decision: CoreMLAdaptiveRouteDecision) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(
        L10n.text(
          de: "Geschätzte Session-Kosten",
          en: "Estimated session cost",
          fr: "Coût de session estimé"
        )
      )
      .font(.headline)

      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
        GridRow {
          Text(L10n.text(de: "Modus", en: "Mode", fr: "Mode")).bold()
          Text("Cold ms").bold()
          Text("p50 ms").bold()
          Text(
            L10n.text(
              de: "Gesamt ms",
              en: "Total ms",
              fr: "Total ms"
            )
          )
          .bold()
        }

        Divider().gridCellUnsizedAxes(.horizontal)

        ForEach(decision.estimates) { estimate in
          GridRow {
            Text(estimate.mode.displayName)
            Text(milliseconds(estimate.coldStartMilliseconds))
              .monospacedDigit()
            Text(milliseconds(estimate.warmP50Milliseconds))
              .monospacedDigit()
            Text(milliseconds(estimate.estimatedTotalMilliseconds))
              .monospacedDigit()
              .bold(estimate.mode == decision.recommendedMode)
          }
        }
      }
      .font(.caption)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
  }

  private func milliseconds(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
  }
}

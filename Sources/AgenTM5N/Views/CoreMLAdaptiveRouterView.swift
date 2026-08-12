import SwiftUI

struct CoreMLAdaptiveRouterView: View {
  let modelLabReport: CoreMLModelLabReport?
  let runtimeReport: CoreMLRuntimeBenchmarkReport

  @State private var executionStrategy = CoreMLAdaptiveExecutionPolicyStore.strategy
  @State private var workloadPreset = CoreMLAdaptiveExecutionPolicyStore.workloadPreset

  var body: some View {
    GroupBox(
      L10n.text(
        de: "Adaptive Neural Execution · Build 34",
        en: "Adaptive Neural Execution · Build 34",
        fr: "Adaptive Neural Execution · Build 34"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Text(
          L10n.text(
            de: "Build 34 macht aus der Build-33-Empfehlung eine echte Ausführungsrichtlinie. Im adaptiven Modus wählt AgenTM5N den Compute-Pfad aus dem hardware- und OS-spezifischen Model-Lab-/Runtime-Profil und verwendet bei fehlender oder schwacher Evidenz sicherheitshalber Automatisch.",
            en: "Build 34 turns the Build 33 recommendation into a real execution policy. In adaptive mode, AgenTM5N selects the compute path from the hardware/OS-specific Model Lab and runtime profile and safely uses Automatic when evidence is missing or weak.",
            fr: "Le Build 34 transforme la recommandation du Build 33 en véritable politique d’exécution. En mode adaptatif, AgenTM5N choisit le chemin de calcul à partir du profil Model Lab et runtime propre au matériel/OS et utilise Automatique par sécurité lorsque les données sont absentes ou faibles."
          )
        )
        .font(.callout)
        .foregroundStyle(.secondary)

        Picker(
          L10n.text(
            de: "Ausführungsstrategie",
            en: "Execution Strategy",
            fr: "Stratégie d’exécution"
          ),
          selection: $executionStrategy
        ) {
          ForEach(CoreMLExecutionStrategy.allCases) { strategy in
            Text(strategy.displayName).tag(strategy)
          }
        }
        .pickerStyle(.segmented)
        .onChange(of: executionStrategy) { _, newValue in
          CoreMLAdaptiveExecutionPolicyStore.setStrategy(newValue)
          Task { await CoreMLPredictionRunner.shared.clearCache() }
        }

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
        .disabled(executionStrategy != .adaptive)
        .onChange(of: workloadPreset) { _, newValue in
          CoreMLAdaptiveExecutionPolicyStore.setWorkloadPreset(newValue)
          Task { await CoreMLPredictionRunner.shared.clearCache() }
        }

        let decision = CoreMLAdaptiveRouter.evaluate(
          modelLabReport: modelLabReport,
          runtimeReport: runtimeReport,
          expectedPredictions: workloadPreset.expectedPredictions
        )

        executionStatus(decision)
        summary(decision)
        estimateMatrix(decision)
      }
      .padding(8)
    }
  }

  private func executionStatus(_ decision: CoreMLAdaptiveRouteDecision) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 22) {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            L10n.text(
              de: "Ausführung",
              en: "Execution",
              fr: "Exécution"
            )
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text(executionStrategy.displayName)
            .font(.title3.bold())
        }

        VStack(alignment: .leading, spacing: 3) {
          Text(
            executionStrategy == .adaptive
              ? L10n.text(de: "Nächster Prediction-Pfad", en: "Next Prediction Path", fr: "Prochain chemin de prédiction")
              : L10n.text(de: "Manuelle Richtlinie", en: "Manual Policy", fr: "Politique manuelle")
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          Text(
            executionStrategy == .adaptive
              ? decision.recommendedMode.displayName
              : CoreMLRuntimePolicyStore.currentMode.displayName
          )
          .font(.title3.bold())
        }
      }

      if executionStrategy == .adaptive {
        Label(
          L10n.text(
            de: "Adaptive Execution ist aktiv. Schlägt ein spezialisierter adaptiver Pfad bei einer echten Vorhersage fehl, versucht AgenTM5N die Vorhersage einmal automatisch mit Core ML Automatisch erneut.",
            en: "Adaptive Execution is active. If a specialized adaptive path fails during a real prediction, AgenTM5N retries the prediction once with Core ML Automatic.",
            fr: "Adaptive Execution est actif. Si un chemin adaptatif spécialisé échoue pendant une vraie prédiction, AgenTM5N relance une fois la prédiction avec Core ML Automatique."
          ),
          systemImage: "arrow.triangle.branch"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

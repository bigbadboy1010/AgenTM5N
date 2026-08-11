import SwiftUI

struct ActivityView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var telemetry = ToolTelemetryStore.shared
  @ObservedObject private var operatingLayer = AgentOperatingLayerSettings.shared

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        runtimeSummary
        Divider()
        telemetrySummary
        Divider()
        if telemetry.entries.isEmpty {
          ContentUnavailableView(
            L10n.text(de: "Noch keine Werkzeugaktivität", en: "No Tool Activity Yet", fr: "Aucune activité d’outil"),
            systemImage: "waveform.path.ecg",
            description: Text(
              L10n.text(
                de: "Ausgeführte AgenTM5N-Werkzeuge erscheinen hier ohne Secret-Werte oder Tool-Argumente.",
                en: "Executed AgenTM5N tools appear here without secret values or tool arguments.",
                fr: "Les outils AgenTM5N exécutés apparaissent ici sans valeurs secrètes ni arguments d’outil."
              )
            )
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(telemetry.entries) { entry in
            VStack(alignment: .leading, spacing: 7) {
              HStack {
                Label(entry.toolName, systemImage: entry.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                  .font(.system(.body, design: .monospaced))
                Spacer()
                Text(entry.startedAt, style: .time)
                  .foregroundStyle(.secondary)
              }
              HStack(spacing: 12) {
                Text(entry.provider)
                Text(entry.capability)
                Text(entry.risk.displayName)
                Text(entry.durationMilliseconds.formatted(.number.precision(.fractionLength(1))) + " ms")
                Text(ByteCountFormatter.string(fromByteCount: Int64(entry.outputBytes), countStyle: .file))
                if entry.cacheHit {
                  Label("Cache", systemImage: "bolt.fill")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
          }
        }
      }
      .navigationTitle(
        L10n.text(
          de: "Agent Operating Layer",
          en: "Agent Operating Layer",
          fr: "Agent Operating Layer"
        )
      )
      .toolbar {
        ToolbarItemGroup {
          Button(role: .destructive) {
            telemetry.clear()
          } label: {
            Label(
              L10n.text(de: "Protokoll leeren", en: "Clear Log", fr: "Effacer le journal"),
              systemImage: "trash"
            )
          }
          .disabled(telemetry.entries.isEmpty)

          Button {
            dismiss()
          } label: {
            Label(
              L10n.text(de: "Schließen", en: "Close", fr: "Fermer"),
              systemImage: "xmark"
            )
          }
          .keyboardShortcut(.cancelAction)
        }
      }
    }
    .frame(minWidth: 1_000, minHeight: 680)
  }

  private var runtimeSummary: some View {
    let configuration = operatingLayer.configuration
    let totalTools = AgentToolRegistry.allDefinitions.count
    let enabledCapabilities = configuration.enabledCapabilities.count
    let installed = SelfBuiltToolLibrary.shared.records
    let bundledCount = installed.filter {
      BundledToolPackInstaller.isBundledToolName($0.name)
    }.count
    let customCount = installed.count - bundledCount
    let roundValue = configuration.effectiveToolRoundLimit.map(String.init)
      ?? L10n.text(de: "Unbegrenzt", en: "Unlimited", fr: "Illimité")

    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 20) {
        runtimeMetric(
          L10n.text(de: "Provider", en: "Provider", fr: "Provider"),
          value: providerDisplayName
        )
        runtimeMetric(
          L10n.text(de: "Runtime", en: "Runtime", fr: "Runtime"),
          value: localRuntimeDisplayName
        )
        runtimeMetric(
          L10n.text(de: "Modell", en: "Model", fr: "Modèle"),
          value: appState.configuration.model.isEmpty ? "—" : appState.configuration.model
        )
        runtimeMetric(
          L10n.text(de: "Tool-Runden", en: "Tool Rounds", fr: "Cycles d’outils"),
          value: roundValue
        )
        Spacer()
      }

      HStack(spacing: 20) {
        runtimeMetric(
          L10n.text(de: "Registrierte Tools", en: "Registered Tools", fr: "Outils enregistrés"),
          value: "\(totalTools)"
        )
        runtimeMetric(
          L10n.text(de: "Built-ins", en: "Built-ins", fr: "Built-ins"),
          value: "\(bundledCount)/\(BundledToolPackInstaller.bundledToolNames.count)"
        )
        runtimeMetric(
          L10n.text(de: "Eigene Tools", en: "Custom Tools", fr: "Outils personnalisés"),
          value: "\(max(0, customCount))"
        )
        runtimeMetric(
          L10n.text(de: "Capabilities", en: "Capabilities", fr: "Capabilities"),
          value: "\(enabledCapabilities)/\(AgentToolCapability.allCases.count)"
        )
        runtimeMetric(
          "Stagnation Guard",
          value: configuration.stagnationGuardEnabled
            ? "ON · \(configuration.maxIdenticalToolRounds)x"
            : "OFF"
        )
        Spacer()
      }

      Text(appState.configuration.baseURL.isEmpty ? appState.configuration.workspacePath : appState.configuration.baseURL)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding(16)
    .background(.thinMaterial)
  }

  private var telemetrySummary: some View {
    let value = telemetry.summary
    return HStack(spacing: 18) {
      metric(L10n.text(de: "Aufrufe", en: "Calls", fr: "Appels"), value: "\(value.total)")
      metric(L10n.text(de: "Erfolgreich", en: "Succeeded", fr: "Réussis"), value: "\(value.succeeded)")
      metric(L10n.text(de: "Fehler", en: "Failed", fr: "Échecs"), value: "\(value.failed)")
      metric("Cache", value: "\(value.cacheHits)")
      metric(
        "Ø",
        value: value.averageMilliseconds.formatted(.number.precision(.fractionLength(1))) + " ms"
      )
      Spacer()
    }
    .padding(16)
  }

  private var providerDisplayName: String {
    switch appState.configuration.providerKind {
    case .ollamaLocal:
      L10n.text(de: "Lokal", en: "Local", fr: "Local")
    case .ollamaCloud:
      "Ollama Cloud"
    case .appleOnDevice:
      "Apple Foundation Models"
    }
  }

  private var localRuntimeDisplayName: String {
    switch appState.configuration.providerKind {
    case .ollamaLocal:
      operatingLayer.configuration.localInferenceRuntime == .mlxServer
        ? "MLX / Metal"
        : "Ollama"
    case .ollamaCloud:
      "Ollama API"
    case .appleOnDevice:
      "Apple On-Device"
    }
  }

  private func runtimeMetric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
    }
  }

  private func metric(_ title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title3.monospacedDigit())
    }
  }
}

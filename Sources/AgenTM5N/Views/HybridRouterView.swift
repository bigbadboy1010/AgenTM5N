import SwiftUI

struct HybridRouterView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var controller = HybridRoutingController.shared
  @ObservedObject private var operatingLayer = AgentOperatingLayerSettings.shared

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        routingPolicyCard
        environmentCard
        previewCard
        decisionCard
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle("Hybrid Router")
    .task {
      await controller.bootstrap()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 10) {
        Image(systemName: "arrow.triangle.branch")
          .font(.title2)
          .foregroundStyle(.tint)
        Text("AgenTM5N Hybrid Neural + Mesh Router · Build 41")
          .font(.title2.bold())
      }
      Text(
        "Der Router entscheidet fail-safe zwischen dem aktuell aktiven Provider/Runtime-Pfad, Apple On-Device und explizit freigegebenen Agent-Mesh-Peers. Manual bleibt der Default. Persönliche macOS-Daten werden bei aktivem Privacy Lock nicht automatisch an Remote-Ziele geroutet."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .textSelection(.enabled)
    }
  }

  private var routingPolicyCard: some View {
    GroupBox("Routing Policy") {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Modus", selection: $controller.configuration.mode) {
          Text("Manual").tag(HybridRoutingMode.manual)
          Text("Adaptive").tag(HybridRoutingMode.adaptive)
        }
        .pickerStyle(.segmented)

        Toggle(
          "Local-first für explizite/private lokale Routen",
          isOn: $controller.configuration.preferLocal
        )
        Toggle("Apple On-Device als lokalen Zielpfad erlauben", isOn: $controller.configuration.allowAppleOnDevice)
        Toggle("Agent Mesh Routing erlauben", isOn: $controller.configuration.allowMesh)
        Toggle(
          "Mesh nur bei expliziter Delegationsabsicht",
          isOn: $controller.configuration.requireExplicitMeshIntent
        )
        .disabled(!controller.configuration.allowMesh)
        Toggle("Privacy Lock für persönliche macOS-Daten", isOn: $controller.configuration.privacyLockEnabled)

        Stepper(
          "Max. Mesh-Kandidaten: \(controller.configuration.maximumMeshPeersConsidered)",
          value: $controller.configuration.maximumMeshPeersConsidered,
          in: 1...64
        )
        .disabled(!controller.configuration.allowMesh)

        HStack {
          Button("Speichern") {
            controller.save()
          }
          .buttonStyle(.borderedProminent)
          Text(controller.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if controller.configuration.mode == .manual {
          Text(
            "Manual verwendet immer den aktuell ausgewählten Provider/Runtime-Pfad."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        } else {
          Text(
            "Adaptive behält für normalen Chat den ausgewählten Provider bei. Apple On-Device wird nur bei explizitem Apple-Wunsch oder durch Privacy Lock für persönliche Daten gewählt; Mesh folgt den Delegationsregeln."
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      .padding(8)
    }
  }

  private var environmentCard: some View {
    GroupBox("Verfügbare Ziele") {
      VStack(alignment: .leading, spacing: 10) {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
          GridRow {
            Text("Aktiver Provider").foregroundStyle(.secondary)
            Text(activeProviderDescription)
          }
          GridRow {
            Text("Apple Foundation Models").foregroundStyle(.secondary)
            Text(controller.appleAvailability)
          }
          GridRow {
            Text("Trusted Mesh Peers").foregroundStyle(.secondary)
            Text("\(controller.trustedPeers.count)")
          }
        }

        if !controller.trustedPeers.isEmpty {
          Divider()
          ForEach(controller.trustedPeers) { peer in
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(peer.name).font(.headline)
                Text(peer.kind == .agentNexus ? "AgentNexus" : "AgenTM5N")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(peer.endpoint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
              Text("Scope: " + peer.allowedCapabilities.map(\.rawValue).sorted().joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
        }

        Button("Umgebung aktualisieren") {
          Task { await controller.refreshEnvironment() }
        }
      }
      .padding(8)
    }
  }

  private var previewCard: some View {
    GroupBox("Routing Preview") {
      VStack(alignment: .leading, spacing: 10) {
        TextEditor(text: $controller.previewPrompt)
          .font(.body)
          .frame(minHeight: 100)
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.primary.opacity(0.12))
          }

        Button("Route analysieren") {
          _ = controller.preview(
            appConfiguration: appState.configuration,
            operatingConfiguration: operatingLayer.configuration
          )
        }
        .buttonStyle(.borderedProminent)
        .disabled(controller.previewPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        Text(
          "Die Vorschau speichert nur Routing-Metadaten und die Entscheidung, niemals den Prompt-Inhalt."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding(8)
    }
  }

  @ViewBuilder
  private var decisionCard: some View {
    if let decision = controller.decision {
      GroupBox("Letzte Entscheidung") {
        VStack(alignment: .leading, spacing: 9) {
          HStack {
            Text(decision.targetName)
              .font(.headline)
            Spacer()
            Text(decision.kind.rawValue)
              .font(.caption.bold())
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.thinMaterial, in: Capsule())
          }

          Text(decision.reason)
            .textSelection(.enabled)

          Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
            GridRow {
              Text("Confidence").foregroundStyle(.secondary)
              Text(decision.confidence, format: .percent.precision(.fractionLength(0)))
            }
            GridRow {
              Text("Privacy Lock").foregroundStyle(.secondary)
              Text(decision.privacyLocked ? "aktiv für diesen Turn" : "nicht erzwungen")
            }
            GridRow {
              Text("Remote").foregroundStyle(.secondary)
              Text(decision.isRemote ? "ja" : "nein")
            }
          }

          if !decision.requiredCapabilities.isEmpty {
            Text(
              "Erkannte Capabilities: "
                + decision.requiredCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }

          if decision.isBlocked {
            Label("Fail-closed: dieser Turn darf nicht automatisch remote ausgeführt werden.", systemImage: "lock.shield")
              .foregroundStyle(.orange)
          }
        }
        .padding(8)
      }
    }
  }

  private var activeProviderDescription: String {
    switch appState.configuration.providerKind {
    case .appleOnDevice:
      return "Apple On-Device"
    case .ollamaCloud:
      return "Ollama Cloud · \(appState.configuration.model)"
    case .ollamaLocal:
      switch operatingLayer.configuration.localInferenceRuntime {
      case .ollama:
        return "Ollama Local · \(appState.configuration.model)"
      case .mlxServer:
        return "MLX Local · \(appState.configuration.model)"
      case .anemll:
        return "ANEMLL/Qwen3 · \(appState.configuration.model)"
      }
    }
  }
}

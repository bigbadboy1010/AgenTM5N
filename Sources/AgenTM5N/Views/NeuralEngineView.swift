import SwiftUI
import UniformTypeIdentifiers

struct NeuralEngineView: View {
  @EnvironmentObject private var appState: AppState
  @State private var showingModelImporter = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        hardwareCard
        appleModelCard
        coreMLCard
      }
      .padding(20)
    }
    .navigationTitle("Neural Engine")
    .fileImporter(
      isPresented: $showingModelImporter,
      allowedContentTypes: modelContentTypes,
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        Task {
          await appState.loadCoreMLModel(from: url)
          if accessed {
            url.stopAccessingSecurityScopedResource()
          }
        }
      case .failure(let error):
        appState.errorMessage = error.localizedDescription
      }
    }
  }

  private var hardwareCard: some View {
    GroupBox("Hardware") {
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
        GridRow {
          Text("Chip")
            .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.chipName)
        }
        GridRow {
          Text("Unified Memory")
            .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.memoryDescription)
        }
        GridRow {
          Text("macOS")
            .foregroundStyle(.secondary)
          Text(appState.hardwareProfile.operatingSystem)
        }
        GridRow {
          Text("Core ML Compute Units")
            .foregroundStyle(.secondary)
          Text("CPU + Apple Neural Engine")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var appleModelCard: some View {
    GroupBox("Apple On-Device Foundation Model") {
      VStack(alignment: .leading, spacing: 10) {
        LabeledContent("Status", value: appState.hardwareProfile.appleFoundationModelStatus)
        Text(
          "Der Chat-Provider „Apple On-Device“ verwendet Apples lokales System Language Model. Apple entscheidet intern über die Hardware-Verteilung."
        )
        .foregroundStyle(.secondary)
        Button("Im Chat auswählen") {
          appState.providerChanged(to: .appleOnDevice)
          appState.selectedSection = .chat
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var coreMLCard: some View {
    GroupBox("Core ML – expliziter Neural-Engine-Pfad") {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Button {
            showingModelImporter = true
          } label: {
            Label("Core-ML-Modell laden", systemImage: "square.and.arrow.down")
          }

          if let descriptor = appState.coreMLDescriptor {
            Text(descriptor.sourceURL.lastPathComponent)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
          }
        }

        if let descriptor = appState.coreMLDescriptor {
          LabeledContent("Compute Units", value: descriptor.computeUnits)

          HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 5) {
              Text("Inputs")
                .font(.headline)
              ForEach(descriptor.inputs, id: \.self) { input in
                Text(input)
                  .font(.system(.caption, design: .monospaced))
              }
            }

            VStack(alignment: .leading, spacing: 5) {
              Text("Outputs")
                .font(.headline)
              ForEach(descriptor.outputs, id: \.self) { output in
                Text(output)
                  .font(.system(.caption, design: .monospaced))
              }
            }
          }

          Text("Numerische Inputs als JSON")
            .font(.headline)
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
              Label("Prediction ausführen", systemImage: "play.fill")
            }
          }
          .disabled(appState.isRunningCoreML)

          if let result = appState.coreMLPredictionResult {
            VStack(alignment: .leading, spacing: 6) {
              Text(
                "Resultat – \(result.durationMilliseconds, format: .number.precision(.fractionLength(3))) ms"
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
        } else {
          Text(
            "Lade ein `.mlmodel`, `.mlpackage` oder kompiliertes `.mlmodelc`. Das Modell wird mit `MLComputeUnits.cpuAndNeuralEngine` initialisiert."
          )
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var modelContentTypes: [UTType] {
    ["mlmodel", "mlpackage", "mlmodelc"].compactMap { extensionName in
      UTType(filenameExtension: extensionName)
    } + [.data]
  }
}

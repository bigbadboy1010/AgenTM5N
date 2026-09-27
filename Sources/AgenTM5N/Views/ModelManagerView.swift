import SwiftUI

struct ModelManagerView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var controller = ModelManagerController.shared
  @State private var selectedID: UUID?
  @State private var isScanningOllama = false
  @State private var huggingFaceReference = ""
  @State private var isImportingHuggingFace = false
  @State private var huggingFaceError: String?
  @State private var draft = ModelProfile(
    name: "Neues Modellprofil",
    runtime: .ollamaLocal,
    modelIdentifier: "",
    contextWindow: 8_192
  )

  var body: some View {
    HSplitView {
      sidebar
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
      editor
        .frame(minWidth: 540)
    }
    .navigationTitle("Model Manager · Build 42")
    .task {
      await controller.bootstrap()
      if selectedID == nil {
        select(controller.profiles.first)
      }
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Modelle")
          .font(.title2.bold())
        Spacer()
        Button {
          Task {
            if let imported = await controller.importCurrentConfiguration(appState: appState) {
              select(imported)
            }
          }
        } label: {
          Label("Aktuelles importieren", systemImage: "square.and.arrow.down")
        }
      }

      Button {
        Task {
          isScanningOllama = true
          defer { isScanningOllama = false }
          let imported = await controller.discoverLocalOllamaModels()
          if selectedID == nil {
            select(imported.first ?? controller.profiles.first)
          }
        }
      } label: {
        HStack {
          Label("Lokales Ollama scannen", systemImage: "externaldrive.badge.magnifyingglass")
          if isScanningOllama {
            Spacer()
            ProgressView()
              .controlSize(.small)
          }
        }
      }
      .disabled(isScanningOllama)

      Text("Liest /api/tags und /api/show von localhost:11434. Der Scan lädt kein Modell zur Inferenz. :cloud-Aliase werden nicht als lokale Profile importiert.")
        .font(.caption)
        .foregroundStyle(.secondary)

      List(selection: $selectedID) {
        ForEach(controller.profiles) { profile in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(profile.name)
                .fontWeight(profile.id == controller.activeProfileID ? .semibold : .regular)
              Spacer()
              if profile.id == controller.activeProfileID {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundStyle(.green)
              }
            }
            Text("\(profile.runtime.displayName) · \(profile.modelIdentifier)")
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            HStack(spacing: 8) {
              Text(profile.runtime.isLocal ? "LOCAL" : "CLOUD")
              Text("P\(profile.priority)")
              Text("CTX \(profile.contextWindow)")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
          }
          .tag(Optional(profile.id))
          .opacity(profile.enabled ? 1 : 0.5)
        }
      }
      .onChange(of: selectedID) { _, id in
        guard let id,
          let profile = controller.profiles.first(where: { $0.id == id })
        else { return }
        draft = profile
      }

      HStack {
        Button {
          draft = ModelProfile(
            name: "Neues Modellprofil",
            runtime: .ollamaLocal,
            modelIdentifier: "",
            contextWindow: 8_192
          )
          selectedID = draft.id
        } label: {
          Label("Neu", systemImage: "plus")
        }

        Spacer()

        Button {
          Task { await controller.reload() }
        } label: {
          Label("Neu laden", systemImage: "arrow.clockwise")
        }
      }

      Text(controller.statusMessage)
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }
    .padding()
  }

  private var editor: some View {
    Form {
      Section("Profil") {
        TextField("Name", text: $draft.name)

        Picker("Runtime", selection: $draft.runtime) {
          ForEach(ModelProfileRuntime.allCases) { runtime in
            Text(runtime.displayName).tag(runtime)
          }
        }
        .onChange(of: draft.runtime) { _, runtime in
          draft.baseURL = runtime.defaultBaseURL
          if runtime == .appleFoundationModels {
            draft.modelIdentifier = "SystemLanguageModel.default"
          }
        }

        TextField("Model Identifier", text: $draft.modelIdentifier)
          .disabled(draft.runtime == .appleFoundationModels)

        TextField("Base URL", text: $draft.baseURL)
          .disabled(draft.runtime == .appleFoundationModels)

        Toggle("Aktiviert", isOn: $draft.enabled)

        Stepper("Priorität: \(draft.priority)", value: $draft.priority, in: 0...1_000)
        Stepper(
          "Context Window: \(draft.contextWindow)",
          value: $draft.contextWindow,
          in: 128...1_048_576,
          step: 512
        )

        LabeledContent("Geschätzter RAM (MB)") {
          TextField("optional", text: memoryBinding)
            .multilineTextAlignment(.trailing)
            .frame(width: 120)
        }

        LabeledContent("Locality") {
          Text(draft.runtime.isLocal ? "On-Device / Local" : "Remote / Cloud")
        }

        if draft.runtime == .ollamaCloud {
          LabeledContent("Vault Secret Reference") {
            Text(draft.apiKeySecretID?.uuidString ?? "Nicht gesetzt")
              .font(.system(.caption, design: .monospaced))
              .textSelection(.enabled)
          }
          Text("Cloud-Profile speichern nur die UUID des bestehenden Vault-Secrets. Der API-Key selbst wird niemals im Modellprofil gespeichert.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      Section("Hugging Face GGUF via Ollama") {
        TextField(
          "hf.co/owner/repository-GGUF:Q4_K_M",
          text: $huggingFaceReference
        )
          .textFieldStyle(.roundedBorder)
          .disabled(isImportingHuggingFace)

        HStack {
          Button("Laden + Profil anlegen") {
            Task {
              isImportingHuggingFace = true
              huggingFaceError = nil
              defer { isImportingHuggingFace = false }

              do {
                let imported = try await controller.importHuggingFaceGGUF(
                  reference: huggingFaceReference
                )
                huggingFaceReference = ""
                select(imported)
              } catch {
                huggingFaceError = error.localizedDescription
              }
            }
          }
          .disabled(
            isImportingHuggingFace
              || huggingFaceReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )

          if isImportingHuggingFace {
            ProgressView()
              .controlSize(.small)
            Text("Ollama lädt das GGUF-Modell …")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Text(
          "Akzeptiert z. B. hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M oder eine Hugging-Face-Modell-URL. Der Download läuft über dein lokales Ollama; anschließend wird ein normales Ollama-Local-Profil mit den von /api/show erkannten Capabilities angelegt."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Text(
          "Der RAM-Schätzwert bleibt nach dem Import absichtlich leer. Damit bleibt ein späteres automatisches Routing fail-closed, bis der Speicherbedarf bewusst eingetragen wurde. Manuelle Aktivierung bleibt möglich."
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        if let huggingFaceError {
          Text(huggingFaceError)
            .font(.caption)
            .foregroundStyle(.red)
            .textSelection(.enabled)
        }
      }

      Section("Capabilities") {
        ForEach(ModelProfileCapability.allCases) { capability in
          Toggle(
            capability.displayName,
            isOn: Binding(
              get: { draft.capabilities.contains(capability) },
              set: { enabled in
                if enabled {
                  draft.capabilities.insert(capability)
                } else {
                  draft.capabilities.remove(capability)
                }
              }
            )
          )
        }
      }

      Section("Aktionen") {
        HStack {
          Button("Speichern") {
            Task {
              draft.normalize()
              await controller.save(draft)
              selectedID = draft.id
            }
          }
          .keyboardShortcut(.defaultAction)

          Button("Aktivieren") {
            Task {
              draft.normalize()
              await controller.save(draft)
              await controller.activate(profileID: draft.id, appState: appState)
            }
          }
          .disabled(!draft.enabled)

          Spacer()

          Button("Löschen", role: .destructive) {
            let deleting = draft
            Task {
              await controller.remove(deleting)
              selectedID = nil
              select(controller.profiles.first)
            }
          }
          .disabled(draft.id == ModelProfileCatalog.appleBuiltIn.id)
        }
      }

      Section("Routing-Vorschau") {
        let candidates = ModelProfileCatalog.routingCandidates(
          from: controller.profiles,
          preferLocal: HybridRoutingStore.loadConfiguration().preferLocal
        )
        if candidates.isEmpty {
          Text("Keine aktivierten Modellprofile.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(candidates.prefix(8).enumerated()), id: \.element.id) { index, profile in
            LabeledContent("#\(index + 1)") {
              Text("\(profile.name) · P\(profile.priority) · \(profile.runtime.isLocal ? "LOCAL" : "CLOUD")")
                .font(.system(.caption, design: .monospaced))
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }

  private var memoryBinding: Binding<String> {
    Binding(
      get: { draft.estimatedMemoryMB.map(String.init) ?? "" },
      set: { text in
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.estimatedMemoryMB = trimmed.isEmpty ? nil : Int(trimmed)
      }
    )
  }

  private func select(_ profile: ModelProfile?) {
    guard let profile else { return }
    selectedID = profile.id
    draft = profile
  }
}

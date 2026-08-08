import AppKit
import SwiftUI

struct AgentsView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var library = PersistentAgentLibrary.shared

  @State private var selectedID: UUID?
  @State private var taskText = ""
  @State private var errorText: String?

  private var selectedProfile: SavedAgentProfile? {
    guard let selectedID else { return library.profiles.first }
    return library.profile(id: selectedID)
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
    } detail: {
      detail
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 980, minHeight: 680)
    .toolbar {
      ToolbarItemGroup {
        Button {
          prepareAgentCreation()
        } label: {
          Label("Neuer Agent", systemImage: "plus")
        }

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
    .onAppear {
      if selectedID == nil {
        selectedID = library.profiles.first?.id
      }
    }
    .onChange(of: library.profiles) { _, profiles in
      if let selectedID,
        !profiles.contains(where: { $0.id == selectedID })
      {
        self.selectedID = profiles.first?.id
        taskText = ""
      } else if self.selectedID == nil {
        self.selectedID = profiles.first?.id
      }
    }
    .alert(
      "Agentenfehler",
      isPresented: Binding(
        get: { errorText != nil },
        set: { if !$0 { errorText = nil } }
      )
    ) {
      Button("OK", role: .cancel) { errorText = nil }
    } message: {
      Text(errorText ?? "Unbekannter Fehler")
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text("Agenten")
            .font(.title2.bold())
          Spacer()
          Text("\(library.profiles.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        Text("Persistente Spezial-Agenten")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 4)

      Button {
        prepareAgentCreation()
      } label: {
        Label("Mit Haupt-Agent erstellen", systemImage: "sparkles")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.borderedProminent)

      List(selection: $selectedID) {
        ForEach(library.profiles) { profile in
          HStack(spacing: 10) {
            Image(systemName: profile.symbolName)
              .font(.title3)
              .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Text(profile.name)
                  .fontWeight(.semibold)
                  .lineLimit(1)
                Circle()
                  .fill(profile.isEnabled ? Color.green : Color.secondary)
                  .frame(width: 7, height: 7)
              }

              Text(profile.purpose)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer(minLength: 4)
          }
          .padding(.vertical, 4)
          .tag(profile.id)
        }
      }
      .overlay {
        if library.profiles.isEmpty {
          ContentUnavailableView(
            "Noch keine Agenten",
            systemImage: "person.3.sequence",
            description: Text(
              "Erstelle einen persistenten Spezial-Agenten über den Haupt-Agenten."
            )
          )
        }
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private var detail: some View {
    if let profile = selectedProfile {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          agentHeader(profile)
          agentCapabilities(profile)
          agentInstructions(profile)
          agentTask(profile)
          agentSecurity(profile)
        }
        .padding(24)
        .frame(maxWidth: 900, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      ContentUnavailableView(
        "Agent auswählen",
        systemImage: "person.crop.circle.badge.checkmark",
        description: Text("Wähle links einen gespeicherten Spezial-Agenten aus.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func agentHeader(_ profile: SavedAgentProfile) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: profile.symbolName)
        .font(.system(size: 38))
        .frame(width: 58, height: 58)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 5) {
        Text(profile.name)
          .font(.title.bold())
        Text(profile.purpose)
          .foregroundStyle(.secondary)
        HStack(spacing: 8) {
          Label(profile.providerPreference.displayName, systemImage: "cpu")
          Label(
            profile.isEnabled ? "Aktiv" : "Deaktiviert",
            systemImage: profile.isEnabled ? "checkmark.circle.fill" : "pause.circle"
          )
          .foregroundStyle(profile.isEnabled ? Color.green : Color.secondary)
        }
        .font(.caption)
      }

      Spacer()

      Button(profile.isEnabled ? "Deaktivieren" : "Aktivieren") {
        toggle(profile)
      }
    }
  }

  private func agentCapabilities(_ profile: SavedAgentProfile) -> some View {
    GroupBox("Werkzeug-Capabilities") {
      VStack(alignment: .leading, spacing: 10) {
        if let capabilities = profile.allowedCapabilities, !capabilities.isEmpty {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)],
            alignment: .leading,
            spacing: 8
          ) {
            ForEach(capabilities, id: \.rawValue) { capability in
              Label(capabilityTitle(capability), systemImage: capabilityIcon(capability))
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
            }
          }
        } else {
          Label(
            "Alle zentral autorisierten AgenTM5N-Capabilities erben",
            systemImage: "checkmark.shield"
          )
          .foregroundStyle(.secondary)
        }

        Text("Die Capability-Auswahl begrenzt nur verfügbare Werkzeuge. Permission-, Audit-, Vault- und macOS-Regeln bleiben immer aktiv.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(.vertical, 6)
    }
  }

  private func agentInstructions(_ profile: SavedAgentProfile) -> some View {
    GroupBox("Spezial-Anweisungen") {
      Text(profile.instructions)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
  }

  private func agentTask(_ profile: SavedAgentProfile) -> some View {
    GroupBox("Aufgabe an diesen Agenten delegieren") {
      VStack(alignment: .leading, spacing: 10) {
        TextEditor(text: $taskText)
          .font(.body)
          .frame(minHeight: 130, idealHeight: 160)
          .padding(6)
          .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(Color.secondary.opacity(0.25))
          }

        HStack {
          Text("Die Aufgabe wird über agent_delegate an das gespeicherte Profil übergeben.")
            .font(.caption)
            .foregroundStyle(.secondary)

          Spacer()

          Button {
            delegate(profile)
          } label: {
            Label("An Agent delegieren", systemImage: "play.fill")
          }
          .buttonStyle(.borderedProminent)
          .disabled(
            !profile.isEnabled
              || taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          )
        }
      }
      .padding(.vertical, 6)
    }
  }

  private func agentSecurity(_ profile: SavedAgentProfile) -> some View {
    GroupBox("Persistenz und Sicherheit") {
      VStack(alignment: .leading, spacing: 7) {
        Label("Agenten bleiben nach einem Neustart erhalten.", systemImage: "externaldrive.badge.checkmark")
          .foregroundStyle(.secondary)
        Label("Tool-Aufrufe laufen über den zentralen Permission- und Audit-Router.", systemImage: "checkmark.shield")
          .foregroundStyle(.secondary)
        Label("Vault-Secrets werden nicht in Agenten-Anweisungen gespeichert.", systemImage: "key.horizontal")
          .foregroundStyle(.secondary)
        if let lastUsedAt = profile.lastUsedAt {
          Label(
            "Zuletzt verwendet: \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))",
            systemImage: "clock"
          )
          .foregroundStyle(.secondary)
        }

        HStack {
          Spacer()
          Button("Agent löschen", role: .destructive) {
            delete(profile)
          }
        }
      }
      .padding(.vertical, 6)
    }
  }

  private func prepareAgentCreation() {
    appState.inputText = """
      Ich möchte einen neuen persistenten Spezial-Agenten erstellen. Hilf mir, einen präzisen Namen, einen klaren wiederkehrenden Zweck, vollständige operative Anweisungen und passende AgenTM5N-Tool-Capabilities festzulegen. Speichere den fertigen Agenten anschließend mit agent_create, damit er dauerhaft in der Rubrik Agenten verfügbar ist. Speichere keine Passwörter, API-Keys, Tokens oder Private Keys im Agentenprofil.
      """
    appState.selectedSection = .chat
    dismiss()
  }

  private func delegate(_ profile: SavedAgentProfile) {
    let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !task.isEmpty, profile.isEnabled else { return }

    appState.inputText = """
      Delegiere die folgende Aufgabe mit dem AgenTM5N-Werkzeug agent_delegate an den gespeicherten Spezial-Agenten "\(profile.name)". Verwende dessen gespeicherten Provider und dessen Capability-Einschränkungen. Fasse das tatsächliche Delegationsergebnis anschließend für mich zusammen.

      Aufgabe:
      \(task)
      """
    appState.selectedSection = .chat
    dismiss()
    appState.sendMessage()
  }

  private func toggle(_ profile: SavedAgentProfile) {
    do {
      _ = try library.update(
        query: profile.id.uuidString,
        enabled: !profile.isEnabled
      )
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func delete(_ profile: SavedAgentProfile) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Agent löschen?"
    alert.informativeText = "Der gespeicherte Agent \"\(profile.name)\" wird dauerhaft entfernt."
    alert.addButton(withTitle: "Löschen")
    alert.addButton(withTitle: "Abbrechen")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    do {
      _ = try library.delete(query: profile.id.uuidString)
      taskText = ""
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func capabilityTitle(_ capability: AgentToolCapability) -> String {
    switch capability {
    case .workspace: "Workspace"
    case .terminal: "Terminal"
    case .ssh: "SSH"
    case .git: "Git"
    case .macPersonal: "Mac persönlich"
    case .secrets: "Secrets"
    case .http: "HTTP / API"
    case .system: "System"
    case .reminders: "Erinnerungen"
    case .coreML: "Core ML"
    case .memory: "Memory"
    case .knowledge: "Knowledge"
    case .attachments: "Anhänge"
    case .documents: "Dokumente"
    case .agents: "Agenten"
    case .workflows: "Workflows"
    case .updates: "Updates"
    }
  }

  private func capabilityIcon(_ capability: AgentToolCapability) -> String {
    switch capability {
    case .workspace: "folder"
    case .terminal: "terminal"
    case .ssh: "network"
    case .git: "arrow.triangle.branch"
    case .macPersonal: "macbook"
    case .secrets: "key"
    case .http: "globe"
    case .system: "cpu"
    case .reminders: "checklist"
    case .coreML: "brain"
    case .memory: "externaldrive"
    case .knowledge: "books.vertical"
    case .attachments: "paperclip"
    case .documents: "doc"
    case .agents: "person.3.sequence"
    case .workflows: "point.3.connected.trianglepath.dotted"
    case .updates: "arrow.triangle.2.circlepath"
    }
  }
}

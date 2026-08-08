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
    HSplitView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          VStack(alignment: .leading, spacing: 3) {
            Text("Agenten")
              .font(.title2.bold())
            Text("Persistente Spezial-Agenten")
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text("\(library.profiles.count)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }

        Button {
          prepareAgentCreation()
        } label: {
          Label("Mit Haupt-Agent erstellen", systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)

        List(selection: $selectedID) {
          ForEach(library.profiles) { profile in
            HStack(spacing: 10) {
              Image(systemName: profile.symbolName)
                .frame(width: 22)
              VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                  .fontWeight(.semibold)
                Text(profile.purpose)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                  .lineLimit(2)
              }
              Spacer()
              Circle()
                .fill(profile.isEnabled ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            }
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
      .padding(20)
      .frame(minWidth: 330, idealWidth: 380)

      Group {
        if let profile = selectedProfile {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              HStack(alignment: .top) {
                Image(systemName: profile.symbolName)
                  .font(.system(size: 42))
                  .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 4) {
                  Text(profile.name)
                    .font(.title.bold())
                  Text(profile.purpose)
                    .foregroundStyle(.secondary)
                  Text(profile.providerPreference.displayName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Schließen") { dismiss() }
              }

              GroupBox("Spezial-Anweisungen") {
                Text(profile.instructions)
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.vertical, 6)
              }

              GroupBox("Aufgabe mit diesem Agenten ausführen") {
                VStack(alignment: .leading, spacing: 10) {
                  TextEditor(text: $taskText)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay(
                      RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                    )

                  HStack {
                    Button {
                      use(profile)
                    } label: {
                      Label("Im Chat ausführen", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                      !profile.isEnabled
                        || taskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )

                    Button(profile.isEnabled ? "Deaktivieren" : "Aktivieren") {
                      toggle(profile)
                    }

                    Spacer()

                    Button("Löschen", role: .destructive) {
                      delete(profile)
                    }
                  }
                }
                .padding(.vertical, 6)
              }

              GroupBox("Persistenz und Sicherheit") {
                VStack(alignment: .leading, spacing: 6) {
                  Label(
                    "Agenten bleiben nach einem Neustart erhalten.",
                    systemImage: "externaldrive.badge.checkmark"
                  )
                  Label(
                    "Tool-Aufrufe verwenden weiterhin den zentralen Permission- und Audit-Router.",
                    systemImage: "checkmark.shield"
                  )
                  Label(
                    "Secrets gehören in den Tresor und nicht in Agenten-Anweisungen.",
                    systemImage: "key.horizontal"
                  )
                }
                .foregroundStyle(.secondary)
                .padding(.vertical, 6)
              }
            }
            .padding(24)
          }
        } else {
          ContentUnavailableView(
            "Agent auswählen",
            systemImage: "person.crop.circle.badge.checkmark",
            description: Text("Wähle links einen gespeicherten Spezial-Agenten aus.")
          )
        }
      }
      .frame(minWidth: 520)
    }
    .frame(minWidth: 920, minHeight: 650)
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
      } else if self.selectedID == nil {
        self.selectedID = profiles.first?.id
      }
    }
    .alert("Agentenfehler", isPresented: Binding(
      get: { errorText != nil },
      set: { if !$0 { errorText = nil } }
    )) {
      Button("OK", role: .cancel) { errorText = nil }
    } message: {
      Text(errorText ?? "Unbekannter Fehler")
    }
  }

  private func prepareAgentCreation() {
    appState.inputText = """
      Ich möchte einen neuen persistenten Spezial-Agenten erstellen. Hilf mir, einen präzisen Namen, einen klaren wiederkehrenden Zweck und vollständige operative Anweisungen festzulegen. Speichere den fertigen Agenten anschließend mit agent_create, damit er dauerhaft in der Rubrik Agenten verfügbar ist. Speichere keine Passwörter, API-Keys, Tokens oder Private Keys im Agentenprofil.
      """
    appState.selectedSection = .chat
    dismiss()
  }

  private func use(_ profile: SavedAgentProfile) {
    let task = taskText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !task.isEmpty, profile.isEnabled else { return }

    if let provider = profile.providerPreference.providerKind {
      appState.providerChanged(to: provider)
    }
    try? library.markUsed(id: profile.id)
    appState.inputText = """
      Nutze den gespeicherten Spezial-Agenten "\(profile.name)" für die folgende Aufgabe. Rufe zuerst agent_get mit diesem exakten Agentennamen auf und arbeite danach nach dessen gespeicherten Zweck und Anweisungen. Die normalen AgenTM5N Permission-, Audit- und Sicherheitsregeln bleiben unverändert.

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
}

import AppKit
import SwiftUI

struct ToolsView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss

  @State private var records: [SelfBuiltToolRecord] = []
  @State private var selectedID: UUID?
  @State private var errorText: String?

  private var selectedTool: SelfBuiltToolRecord? {
    guard let selectedID else { return records.first }
    return records.first(where: { $0.id == selectedID })
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 390)
    } detail: {
      detail
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 1_050, minHeight: 700)
    .toolbar {
      ToolbarItemGroup {
        Button {
          createWithAgent()
        } label: {
          Label("Neues Tool", systemImage: "plus")
        }

        Button {
          refresh()
        } label: {
          Label("Aktualisieren", systemImage: "arrow.clockwise")
        }

        Button {
          dismiss()
        } label: {
          Label("Schließen", systemImage: "xmark")
        }
        .keyboardShortcut(.cancelAction)
      }
    }
    .onAppear {
      refresh()
    }
    .alert(
      "Tool-Fehler",
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
          Text("Tools")
            .font(.title2.bold())
          Spacer()
          Text("\(records.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        Text("Persistente, vom Agenten erzeugte Runtime-Tools")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 4)

      Button {
        createWithAgent()
      } label: {
        Label("Mit Haupt-Agent erstellen", systemImage: "sparkles")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.borderedProminent)

      List(selection: $selectedID) {
        ForEach(records) { tool in
          HStack(spacing: 10) {
            Image(systemName: tool.language == .python3 ? "chevron.left.forwardslash.chevron.right" : "terminal")
              .font(.title3)
              .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
              HStack(spacing: 6) {
                Text(tool.name)
                  .fontWeight(.semibold)
                  .lineLimit(1)
                Circle()
                  .fill(tool.isEnabled ? Color.green : Color.secondary)
                  .frame(width: 7, height: 7)
              }

              Text(tool.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            }
            Spacer(minLength: 4)
          }
          .padding(.vertical, 4)
          .tag(tool.id)
        }
      }
      .overlay {
        if records.isEmpty {
          ContentUnavailableView(
            "Noch keine Tools",
            systemImage: "wrench.and.screwdriver",
            description: Text("Erstelle ein persistentes Tool über den Haupt-Agenten und Toolsmith.")
          )
        }
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private var detail: some View {
    if let tool = selectedTool {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          toolHeader(tool)
          toolDescription(tool)
          toolParameters(tool)
          toolSource(tool)
          toolRuntime(tool)
          toolActions(tool)
        }
        .padding(24)
        .frame(maxWidth: 920, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    } else {
      ContentUnavailableView(
        "Tool auswählen",
        systemImage: "wrench.and.screwdriver",
        description: Text("Wähle links ein gespeichertes Runtime-Tool aus.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func toolHeader(_ tool: SelfBuiltToolRecord) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: tool.language == .python3 ? "chevron.left.forwardslash.chevron.right" : "terminal")
        .font(.system(size: 34))
        .frame(width: 58, height: 58)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 5) {
        Text(tool.name)
          .font(.title.bold())
          .textSelection(.enabled)

        HStack(spacing: 10) {
          Label(tool.language.rawValue, systemImage: "curlybraces")
          Label(
            tool.isEnabled ? "Aktiv" : "Deaktiviert",
            systemImage: tool.isEnabled ? "checkmark.circle.fill" : "pause.circle"
          )
          .foregroundStyle(tool.isEnabled ? Color.green : Color.secondary)
        }
        .font(.caption)

        Text("ID: \(tool.id.uuidString)")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
      }

      Spacer()
    }
  }

  private func toolDescription(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Beschreibung") {
      Text(tool.description)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(.vertical, 6)
    }
  }

  private func toolParameters(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Parameter") {
      VStack(alignment: .leading, spacing: 8) {
        if tool.parameters.isEmpty {
          Text("Dieses Tool hat keine Parameter.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(tool.parameters.enumerated()), id: \.offset) { _, parameter in
            HStack(alignment: .top, spacing: 10) {
              Text(parameter.name)
                .font(.body.monospaced().bold())
                .textSelection(.enabled)
                .frame(minWidth: 130, alignment: .leading)

              Text(parameter.type.rawValue)
                .font(.caption.monospaced())
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())

              if parameter.required {
                Text("Pflicht")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }

              Text(parameter.description.isEmpty ? "—" : parameter.description)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
      .padding(.vertical, 6)
    }
  }

  private func toolSource(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Quellcode") {
      ScrollView(.horizontal) {
        Text(tool.source)
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
      }
      .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 360, alignment: .topLeading)
      .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
      .padding(.vertical, 6)
    }
  }

  private func toolRuntime(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Runtime und Sicherheit") {
      VStack(alignment: .leading, spacing: 7) {
        Label("Ausführung erfolgt im konfigurierten AgenTM5N-Workspace.", systemImage: "folder.badge.gearshape")
        Label("Toolsmith-Code wird immer als Execute-Risiko behandelt.", systemImage: "checkmark.shield")
        Label("Vault-Secrets und Provider-Tokens werden nicht automatisch an das Tool übergeben.", systemImage: "key.horizontal")
        Label("Laufzeitlimit: 60 Sekunden", systemImage: "timer")

        Divider()

        Text("Erstellt: \(tool.createdAt.formatted(date: .abbreviated, time: .shortened))")
        Text("Geändert: \(tool.updatedAt.formatted(date: .abbreviated, time: .shortened))")
        if let lastRunAt = tool.lastRunAt {
          Text("Zuletzt ausgeführt: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))")
        } else {
          Text("Noch nicht ausgeführt")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.vertical, 6)
    }
  }

  private func toolActions(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Verwalten") {
      HStack(spacing: 10) {
        Button {
          testInChat(tool)
        } label: {
          Label("Im Chat testen", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)

        Button {
          editWithAgent(tool)
        } label: {
          Label("Mit Agent überarbeiten", systemImage: "wand.and.stars")
        }

        Spacer()

        Button("Tool löschen", role: .destructive) {
          delete(tool)
        }
      }
      .padding(.vertical, 6)
    }
  }

  private func refresh() {
    records = SelfBuiltToolLibrary.shared.records
    if let selectedID,
      records.contains(where: { $0.id == selectedID })
    {
      return
    }
    selectedID = records.first?.id
  }

  private func createWithAgent() {
    appState.inputText = """
      Ich möchte ein neues persistentes AgenTM5N Runtime-Tool erstellen. Hilf mir zuerst, Name, Zweck, Parameter und die passende Sprache (python3 oder zsh) festzulegen. Erzeuge es anschließend mit toolsmith_create, teste es mit toolsmith_run und speichere keine Passwörter, Tokens, API-Keys, Private Keys oder andere Secrets im Quellcode.
      """
    appState.selectedSection = .chat
    dismiss()
  }

  private func testInChat(_ tool: SelfBuiltToolRecord) {
    let parameterLines: String
    if tool.parameters.isEmpty {
      parameterLines = "Das Tool hat keine Parameter."
    } else {
      parameterLines = tool.parameters.map { parameter in
        "- \(parameter.name) (\(parameter.type.rawValue)\(parameter.required ? ", Pflicht" : ", optional")): <Wert einsetzen>"
      }.joined(separator: "\n")
    }

    appState.inputText = """
      Teste das bereits gespeicherte AgenTM5N-Tool "\(tool.name)" mit toolsmith_run. Verwende keine erfundenen Werte. Wenn für einen Pflichtparameter unten noch kein konkreter Wert angegeben ist, frage mich zuerst danach. Gib anschließend das tatsächliche Tool-Ergebnis aus.

      Parameter:
      \(parameterLines)
      """
    appState.selectedSection = .chat
    dismiss()
  }

  private func editWithAgent(_ tool: SelfBuiltToolRecord) {
    appState.inputText = """
      Ich möchte das persistente AgenTM5N-Tool "\(tool.name)" überarbeiten. Lies zuerst die aktuelle Definition mit toolsmith_get. Besprich die gewünschte Änderung mit mir und ersetze das Tool anschließend mit toolsmith_create unter demselben Namen. Teste die neue Version danach mit toolsmith_run. Speichere keine Secrets im Quellcode.
      """
    appState.selectedSection = .chat
    dismiss()
  }

  private func delete(_ tool: SelfBuiltToolRecord) {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Tool löschen?"
    alert.informativeText = "Das persistente Runtime-Tool \"\(tool.name)\" wird dauerhaft entfernt."
    alert.addButton(withTitle: "Löschen")
    alert.addButton(withTitle: "Abbrechen")
    guard alert.runModal() == .alertFirstButtonReturn else { return }

    do {
      _ = try SelfBuiltToolLibrary.shared.delete(tool.id.uuidString)
      refresh()
    } catch {
      errorText = error.localizedDescription
    }
  }
}

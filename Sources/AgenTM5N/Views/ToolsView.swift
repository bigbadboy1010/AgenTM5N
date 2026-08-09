import AppKit
import SwiftUI

struct ToolsView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss

  @State private var records: [SelfBuiltToolRecord] = []
  @State private var selectedKey: String?
  @State private var errorText: String?

  private var systemTools: [AgentToolCatalogEntry] {
    AgentToolRegistry.catalog.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private var selectedCustomTool: SelfBuiltToolRecord? {
    guard let selectedKey, selectedKey.hasPrefix("custom:") else { return nil }
    let rawID = String(selectedKey.dropFirst("custom:".count))
    guard let id = UUID(uuidString: rawID) else { return nil }
    return records.first(where: { $0.id == id })
  }

  private var selectedSystemTool: AgentToolCatalogEntry? {
    guard let selectedKey, selectedKey.hasPrefix("system:") else { return nil }
    let name = String(selectedKey.dropFirst("system:".count))
    return systemTools.first(where: { $0.name == name })
  }

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 300, ideal: 350, max: 430)
    } detail: {
      detail
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 1_100, minHeight: 720)
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
          Text("\(records.count + systemTools.count)")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
        }
        Text("System-Tools und vom Agenten erzeugte Runtime-Tools")
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

      List(selection: $selectedKey) {
        Section("Agent-Tools · \(records.count)") {
          if records.isEmpty {
            Text("Noch keine selbst erzeugten Tools")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

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
            .tag("custom:\(tool.id.uuidString)")
          }
        }

        Section("System-Tools · \(systemTools.count)") {
          ForEach(systemTools, id: \.name) { tool in
            HStack(spacing: 10) {
              Image(systemName: icon(for: tool.capability))
                .frame(width: 24)

              VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                  .font(.body.monospaced())
                  .lineLimit(1)
                Text("\(tool.capability.rawValue) · \(tool.risk.displayName)")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer(minLength: 4)
            }
            .padding(.vertical, 3)
            .tag("system:\(tool.name)")
          }
        }
      }
    }
    .padding(16)
  }

  @ViewBuilder
  private var detail: some View {
    if let tool = selectedCustomTool {
      customToolDetail(tool)
    } else if let tool = selectedSystemTool {
      systemToolDetail(tool)
    } else {
      ContentUnavailableView(
        "Tool auswählen",
        systemImage: "wrench.and.screwdriver",
        description: Text("Wähle links ein Agent-Tool oder System-Tool aus.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func customToolDetail(_ tool: SelfBuiltToolRecord) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        customToolHeader(tool)
        customToolDescription(tool)
        customToolParameters(tool)
        customToolSource(tool)
        customToolRuntime(tool)
        customToolActions(tool)
      }
      .padding(24)
      .frame(maxWidth: 920, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func systemToolDetail(_ tool: AgentToolCatalogEntry) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .top, spacing: 14) {
          Image(systemName: icon(for: tool.capability))
            .font(.system(size: 34))
            .frame(width: 58, height: 58)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

          VStack(alignment: .leading, spacing: 5) {
            Text(tool.name)
              .font(.title.bold().monospaced())
              .textSelection(.enabled)
            Text("Fest eingebautes AgenTM5N-System-Tool")
              .foregroundStyle(.secondary)
          }
          Spacer()
        }

        GroupBox("Tool-Eigenschaften") {
          VStack(alignment: .leading, spacing: 9) {
            propertyRow("Capability", value: tool.capability.rawValue)
            propertyRow("Risiko", value: tool.risk.displayName)
            propertyRow("Cachefähig", value: tool.cacheable ? "Ja" : "Nein")
            propertyRow("Secret-aware", value: tool.secretAware ? "Ja" : "Nein")
          }
          .padding(.vertical, 6)
        }

        GroupBox("Verwaltung") {
          VStack(alignment: .leading, spacing: 10) {
            Text("System-Tools sind Bestandteil der signierten AgenTM5N-App. Sie können hier geprüft und verwendet, aber nicht einzeln gelöscht oder überschrieben werden.")
              .foregroundStyle(.secondary)

            Button {
              useSystemToolInChat(tool)
            } label: {
              Label("Im Chat verwenden", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
          }
          .padding(.vertical, 6)
        }
      }
      .padding(24)
      .frame(maxWidth: 920, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func customToolHeader(_ tool: SelfBuiltToolRecord) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: tool.language == .python3 ? "chevron.left.forwardslash.chevron.right" : "terminal")
        .font(.system(size: 34))
        .frame(width: 58, height: 58)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

      VStack(alignment: .leading, spacing: 5) {
        Text(tool.name)
          .font(.title.bold().monospaced())
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

  private func customToolDescription(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Beschreibung") {
      Text(tool.description)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(.vertical, 6)
    }
  }

  private func customToolParameters(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Parameter") {
      VStack(alignment: .leading, spacing: 8) {
        if tool.parameters.isEmpty {
          Text("Dieses Tool hat keine Parameter.")
            .foregroundStyle(.secondary)
        } else {
          ForEach(Array(tool.parameters.enumerated()), id: \.offset) { entry in
            let parameter = entry.element
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

  private func customToolSource(_ tool: SelfBuiltToolRecord) -> some View {
    GroupBox("Quellcode") {
      ScrollView([.horizontal, .vertical]) {
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

  private func customToolRuntime(_ tool: SelfBuiltToolRecord) -> some View {
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

  private func customToolActions(_ tool: SelfBuiltToolRecord) -> some View {
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

  private func propertyRow(_ title: String, value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title)
        .foregroundStyle(.secondary)
        .frame(width: 120, alignment: .leading)
      Text(value)
        .font(.body.monospaced())
        .textSelection(.enabled)
      Spacer()
    }
  }

  private func refresh() {
    records = SelfBuiltToolLibrary.shared.records
    let validKeys = Set(
      records.map { "custom:\($0.id.uuidString)" }
        + systemTools.map { "system:\($0.name)" }
    )
    if let selectedKey, validKeys.contains(selectedKey) {
      return
    }
    if let first = records.first {
      selectedKey = "custom:\(first.id.uuidString)"
    } else if let first = systemTools.first {
      selectedKey = "system:\(first.name)"
    } else {
      selectedKey = nil
    }
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

  private func useSystemToolInChat(_ tool: AgentToolCatalogEntry) {
    appState.inputText = """
      Ich möchte das AgenTM5N-System-Tool "\(tool.name)" verwenden. Ermittle anhand meiner nächsten Angaben die benötigten Parameter, führe das Tool nur mit konkreten, nicht erfundenen Werten aus und berichte anschließend das tatsächliche Tool-Ergebnis.
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

  private func icon(for capability: AgentToolCapability) -> String {
    switch capability {
    case .workspace: "folder"
    case .terminal: "terminal"
    case .ssh: "network"
    case .edge: "server.rack"
    case .browser: "globe"
    case .git: "arrow.triangle.branch"
    case .macPersonal: "macbook"
    case .secrets: "key"
    case .http: "network.badge.shield.half.filled"
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

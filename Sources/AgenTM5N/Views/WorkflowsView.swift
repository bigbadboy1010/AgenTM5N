import SwiftUI

struct WorkflowsView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.dismiss) private var dismiss
  @ObservedObject private var library = AgentWorkflowLibrary.shared
  @State private var selectedID: UUID?

  var body: some View {
    NavigationSplitView {
      List(selection: $selectedID) {
        ForEach(library.workflows) { workflow in
          VStack(alignment: .leading, spacing: 3) {
            Label(workflow.name, systemImage: "point.3.connected.trianglepath.dotted")
            Text("\(workflow.steps.count) Schritte")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .tag(workflow.id)
        }
      }
      .navigationTitle("Workflows")
      .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 340)
    } detail: {
      if let workflow = selectedWorkflow {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
              VStack(alignment: .leading, spacing: 5) {
                Text(workflow.name)
                  .font(.title2.bold())
                Text(workflow.purpose)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Button {
                appState.inputText = "Führe den gespeicherten Workflow \"\(workflow.name)\" aus."
                appState.selectedSection = .chat
                dismiss()
              } label: {
                Label("Im Chat ausführen", systemImage: "play.fill")
              }
              .buttonStyle(.borderedProminent)
            }

            GroupBox("Schritte") {
              VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                  HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                      .font(.caption.monospacedDigit())
                      .frame(width: 24)
                      .foregroundStyle(.secondary)
                    Text(step.toolName)
                      .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text("\(step.arguments.count) Args")
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  if index < workflow.steps.count - 1 { Divider() }
                }
              }
              .padding(6)
            }

            HStack {
              if let lastRunAt = workflow.lastRunAt {
                Label(
                  "Zuletzt: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))",
                  systemImage: "clock"
                )
                .foregroundStyle(.secondary)
              }
              Spacer()
              Button(role: .destructive) {
                _ = try? library.delete(workflow.id.uuidString)
                selectedID = nil
              } label: {
                Label("Workflow löschen", systemImage: "trash")
              }
            }
          }
          .padding(22)
        }
      } else {
        ContentUnavailableView(
          "Workflow auswählen",
          systemImage: "point.3.connected.trianglepath.dotted",
          description: Text(
            "Workflows können vom Haupt-Agenten mit workflow_create angelegt und jederzeit wieder ausgeführt werden."
          )
        )
      }
    }
    .frame(minWidth: 1_000, minHeight: 650)
    .onAppear {
      if selectedID == nil { selectedID = library.workflows.first?.id }
    }
  }

  private var selectedWorkflow: AgentWorkflow? {
    guard let selectedID else { return nil }
    return library.workflows.first { $0.id == selectedID }
  }
}

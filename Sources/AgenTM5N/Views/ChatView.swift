import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      header
      runtimeStatus
      Divider()
      messages
      if let approval = appState.pendingToolApproval {
        Divider()
        ToolApprovalBanner(approval: approval)
      }
      Divider()
      composer
    }
    .navigationTitle("Chat")
  }

  private var header: some View {
    HStack(spacing: 12) {
      Picker(
        "Provider",
        selection: Binding(
          get: { appState.configuration.providerKind },
          set: { appState.providerChanged(to: $0) }
        )
      ) {
        ForEach(ProviderKind.allCases) { provider in
          Text(provider.displayName).tag(provider)
        }
      }
      .frame(width: 190)

      if appState.configuration.providerKind != .appleOnDevice {
        TextField("Modell", text: $appState.configuration.model)
          .textFieldStyle(.roundedBorder)
          .frame(minWidth: 220)

        Button {
          Task { await appState.fetchModels() }
        } label: {
          if appState.isLoadingModels {
            ProgressView()
              .controlSize(.small)
          } else {
            Label("Modelle", systemImage: "arrow.clockwise")
          }
        }
        .disabled(appState.isLoadingModels)

        if !appState.availableModels.isEmpty {
          Picker("Verfügbar", selection: $appState.configuration.model) {
            ForEach(appState.availableModels, id: \.self) { model in
              Text(model).tag(model)
            }
          }
          .labelsHidden()
          .frame(maxWidth: 280)
        }
      }

      agentModeBadge

      Spacer()

      if let metrics = appState.latestMetrics {
        MetricsBadge(metrics: metrics)
      }

      Button(role: .destructive) {
        Task { await appState.resetConversation() }
      } label: {
        Label("Neue Sitzung", systemImage: "plus.bubble")
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 7)
  }

  private var runtimeStatus: some View {
    HStack(spacing: 12) {
      Label(
        appState.configuration.providerKind.displayName,
        systemImage: "cpu"
      )

      if appState.configuration.providerKind != .appleOnDevice {
        Text(appState.configuration.model)
          .font(.system(.caption, design: .monospaced))
      }

      Divider()
        .frame(height: 14)

      Label(
        appState.configuration.workspacePath,
        systemImage: "folder"
      )
      .lineLimit(1)
      .truncationMode(.middle)
      .help(appState.configuration.workspacePath)

      Spacer()

      if appState.configuration.agentEnabled,
        appState.configuration.providerKind != .appleOnDevice
      {
        Text("Lokale Werkzeuge werden dem Modell bereitgestellt.")
          .foregroundStyle(.secondary)
      } else {
        Text("Keine Tool-Ausführung in diesem Modus.")
          .foregroundStyle(.orange)
      }
    }
    .font(.caption)
    .padding(.horizontal, 12)
    .padding(.bottom, 9)
  }

  @ViewBuilder
  private var agentModeBadge: some View {
    if appState.configuration.agentEnabled,
      appState.configuration.providerKind != .appleOnDevice
    {
      Label(
        "Agent · \(appState.configuration.permissionMode.displayName)",
        systemImage: "wrench.and.screwdriver"
      )
      .font(.caption)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(.green.opacity(0.16), in: Capsule())
      .help("Tool Calling ist aktiv.")
    } else {
      Label("Chat-only", systemImage: "bubble.left")
        .font(.caption)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.orange.opacity(0.16), in: Capsule())
        .help("Dieser Provider oder diese Konfiguration führt keine Werkzeuge aus.")
    }
  }

  private var messages: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if appState.messages.isEmpty {
            ContentUnavailableView(
              "Neue Sitzung",
              systemImage: "brain.head.profile",
              description: Text(
                "Für lokale Werkzeuge einen Ollama-Provider wählen, Agent aktivieren und den grünen Agent-Badge prüfen."
              )
            )
            .frame(maxWidth: .infinity, minHeight: 420)
          } else {
            ForEach(appState.messages) { message in
              MessageBubble(message: message)
                .id(message.id)
            }
          }
        }
        .padding(18)
      }
      .onChange(of: appState.messages) { _, messages in
        guard let last = messages.last else { return }
        withAnimation {
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
    }
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 12) {
      TextEditor(text: $appState.inputText)
        .font(.body)
        .frame(minHeight: 70, maxHeight: 180)
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }

      VStack(spacing: 8) {
        if appState.isGenerating {
          Button(role: .destructive) {
            appState.stopGeneration()
          } label: {
            Label("Stop", systemImage: "stop.fill")
          }
          .keyboardShortcut(.cancelAction)
        } else {
          Button {
            appState.sendMessage()
          } label: {
            Label("Senden", systemImage: "paperplane.fill")
          }
          .keyboardShortcut(.return, modifiers: [.command])
          .disabled(appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }

        Button {
          Task { await appState.saveConfiguration() }
        } label: {
          Label("Konfiguration", systemImage: "square.and.arrow.down")
        }
      }
    }
    .padding(14)
  }
}

private struct ToolApprovalBanner: View {
  @EnvironmentObject private var appState: AppState
  let approval: PendingToolApproval

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(
          "Tool-Freigabe erforderlich",
          systemImage: "lock.open.trianglebadge.exclamationmark"
        )
        .font(.headline)
        Spacer()
        Text(approval.risk.displayName)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(.quaternary, in: Capsule())
      }

      Text(approval.summary)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)

      HStack {
        Spacer()
        Button("Ablehnen", role: .destructive) {
          appState.denyPendingTool()
        }
        Button("Einmal erlauben") {
          appState.approvePendingTool()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(12)
    .background(.orange.opacity(0.12))
  }
}

private struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    HStack(alignment: .top) {
      if message.role == .assistant {
        bubble
        Spacer(minLength: 80)
      } else {
        Spacer(minLength: 80)
        bubble
      }
    }
  }

  private var bubble: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(message.role == .assistant ? "Agent" : "Du")
        .font(.caption)
        .foregroundStyle(.secondary)

      if !message.thinking.isEmpty {
        DisclosureGroup("Thinking") {
          Text(message.thinking)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
      }

      if let executions = message.toolExecutions, !executions.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(executions) { execution in
            ToolExecutionCard(execution: execution)
          }
        }
      }

      Text(message.content.isEmpty ? "…" : message.content)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(12)
    .background(
      message.role == .assistant
        ? Color(nsColor: .controlBackgroundColor) : Color.accentColor.opacity(0.16),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .frame(maxWidth: 820, alignment: .leading)
  }
}

private struct ToolExecutionCard: View {
  let execution: ToolExecutionRecord

  var body: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 6) {
        Text(execution.argumentsSummary)
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)

        if !execution.output.isEmpty {
          ScrollView(.horizontal) {
            Text(execution.output)
              .font(.system(.caption2, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 220)
        }
      }
      .padding(.top, 5)
    } label: {
      HStack {
        Image(systemName: statusIcon)
        Text(execution.toolName)
          .font(.system(.caption, design: .monospaced))
        Spacer()
        Text(execution.status.rawValue)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(9)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
  }

  private var statusIcon: String {
    switch execution.status {
    case .running: "hourglass"
    case .succeeded: "checkmark.circle.fill"
    case .failed: "xmark.octagon.fill"
    case .denied: "hand.raised.fill"
    }
  }
}

private struct MetricsBadge: View {
  let metrics: ChatMetrics

  var body: some View {
    HStack(spacing: 8) {
      if let generated = metrics.generatedTokens {
        Label("\(generated)", systemImage: "text.word.spacing")
      }
      if let speed = metrics.tokensPerSecond {
        Text("\(speed, format: .number.precision(.fractionLength(1))) tok/s")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(.quaternary, in: Capsule())
  }
}

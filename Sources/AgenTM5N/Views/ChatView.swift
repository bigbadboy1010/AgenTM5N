import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      messages
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

      Spacer()

      if let metrics = appState.latestMetrics {
        MetricsBadge(metrics: metrics)
      }

      Button(role: .destructive) {
        Task { await appState.resetConversation() }
      } label: {
        Label("Leeren", systemImage: "trash")
      }
    }
    .padding(12)
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
                "Ollama Local, Ollama Cloud oder Apple On-Device auswählen und eine Aufgabe eingeben."
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
    VStack(alignment: .leading, spacing: 8) {
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
    .frame(maxWidth: 760, alignment: .leading)
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

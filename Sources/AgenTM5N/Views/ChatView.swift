import AppKit
import SwiftUI

struct ChatView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @State private var isDropTargeted = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      messages
      if let approval = appState.pendingToolApproval {
        Divider()
        ToolApprovalBanner(approval: approval)
      }
      Divider()
      composer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("Chat")
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) {
          providerPicker
          modelField
          modelsButton
          availableModelMenu
          agentModeBadge
          Spacer(minLength: 12)
          metricsBadge
          newSessionButton
        }

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            providerPicker
              .frame(width: 165)
            modelField
            modelsButton
            Spacer(minLength: 8)
            newSessionButton
          }
          HStack(spacing: 8) {
            agentModeBadge
            availableModelMenu
            Spacer(minLength: 8)
            metricsBadge
          }
        }
      }
      runtimeStatus
    }
    .padding(.horizontal, 12)
    .padding(.top, 12)
    .padding(.bottom, 9)
  }

  private var providerPicker: some View {
    Picker(
      L10n.text(de: "Anbieter", en: "Provider", fr: "Fournisseur"),
      selection: Binding(
        get: { appState.configuration.providerKind },
        set: { appState.providerChanged(to: $0) }
      )
    ) {
      ForEach(ProviderKind.allCases) { provider in
        Text(providerTitle(provider)).tag(provider)
      }
    }
    .labelsHidden()
    .frame(width: 185)
  }

  @ViewBuilder
  private var modelField: some View {
    if appState.configuration.providerKind != .appleOnDevice {
      TextField(
        L10n.text(de: "Modell", en: "Model", fr: "Modèle"),
        text: $appState.configuration.model
      )
      .textFieldStyle(.roundedBorder)
      .frame(minWidth: 150, idealWidth: 220, maxWidth: 280)
    }
  }

  @ViewBuilder
  private var modelsButton: some View {
    if appState.configuration.providerKind != .appleOnDevice {
      Button {
        Task { await appState.fetchModels() }
      } label: {
        if appState.isLoadingModels {
          ProgressView()
            .controlSize(.small)
        } else {
          Label(
            L10n.text(de: "Modelle", en: "Models", fr: "Modèles"),
            systemImage: "arrow.clockwise"
          )
        }
      }
      .disabled(appState.isLoadingModels)
    }
  }

  @ViewBuilder
  private var availableModelMenu: some View {
    if appState.configuration.providerKind != .appleOnDevice,
      !appState.availableModels.isEmpty
    {
      Menu {
        ForEach(appState.availableModels, id: \.self) { model in
          Button(model) {
            appState.configuration.model = model
          }
        }
      } label: {
        Label(
          L10n.text(de: "Modell wählen", en: "Choose Model", fr: "Choisir le modèle"),
          systemImage: "list.bullet"
        )
      }
    }
  }

  @ViewBuilder
  private var metricsBadge: some View {
    if let metrics = appState.latestMetrics {
      MetricsBadge(metrics: metrics)
    }
  }

  private var newSessionButton: some View {
    Button {
      attachmentStore.removeAll()
      Task { await appState.resetConversation() }
    } label: {
      Label(
        L10n.text(de: "Neue Sitzung", en: "New Session", fr: "Nouvelle session"),
        systemImage: "plus.bubble"
      )
    }
  }

  private var runtimeStatus: some View {
    HStack(spacing: 10) {
      Label(
        providerTitle(appState.configuration.providerKind),
        systemImage: "cpu"
      )

      if appState.configuration.providerKind != .appleOnDevice {
        Text(appState.configuration.model)
          .font(.system(.caption, design: .monospaced))
          .lineLimit(1)
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

      Spacer(minLength: 8)

      if appState.configuration.agentEnabled,
        appState.configuration.providerKind != .appleOnDevice
      {
        Text(
          L10n.text(
            de: "Lokale Werkzeuge aktiv",
            en: "Local tools active",
            fr: "Outils locaux actifs"
          )
        )
        .foregroundStyle(.secondary)
      } else {
        Text(
          L10n.text(
            de: "Keine Werkzeugausführung",
            en: "No tool execution",
            fr: "Aucune exécution d’outil"
          )
        )
        .foregroundStyle(.orange)
      }
    }
    .font(.caption)
  }

  @ViewBuilder
  private var agentModeBadge: some View {
    if appState.configuration.agentEnabled,
      appState.configuration.providerKind != .appleOnDevice
    {
      Label(
        "Agent · \(permissionTitle(appState.configuration.permissionMode))",
        systemImage: "wrench.and.screwdriver"
      )
      .font(.caption)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(.green.opacity(0.16), in: Capsule())
    } else {
      Label(
        L10n.text(de: "Nur Chat", en: "Chat Only", fr: "Chat uniquement"),
        systemImage: "bubble.left"
      )
      .font(.caption)
      .lineLimit(1)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(.orange.opacity(0.16), in: Capsule())
    }
  }

  private var messages: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          if appState.messages.isEmpty {
            ContentUnavailableView(
              L10n.text(de: "Neue Sitzung", en: "New Session", fr: "Nouvelle session"),
              systemImage: "brain.head.profile",
              description: Text(
                L10n.text(
                  de: "Nachrichten schreiben, Dateien anhängen oder lokale Werkzeuge verwenden.",
                  en: "Write a message, attach files, or use local tools.",
                  fr: "Écrivez un message, joignez des fichiers ou utilisez les outils locaux."
                )
              )
            )
            .frame(maxWidth: .infinity, minHeight: 320)
          } else {
            ForEach(appState.messages) { message in
              MessageBubble(message: message)
                .id(message.id)
            }
          }
        }
        .padding(18)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: appState.messages) { _, currentMessages in
        guard let last = currentMessages.last else { return }
        withAnimation {
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
    }
  }

  private var composer: some View {
    VStack(alignment: .leading, spacing: 10) {
      if !attachmentStore.attachments.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(attachmentStore.attachments) { attachment in
              AttachmentDraftChip(attachment: attachment) {
                attachmentStore.remove(id: attachment.id)
              }
            }
          }
        }
        .scrollIndicators(.hidden)
      }

      HStack(alignment: .bottom, spacing: 12) {
        TextEditor(text: $appState.inputText)
          .font(.body)
          .frame(minHeight: 56, idealHeight: 76, maxHeight: 160)
          .padding(6)
          .background(
            Color(nsColor: .textBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
          }

        VStack(spacing: 8) {
          if appState.isGenerating {
            Button(role: .destructive) {
              appState.stopGeneration()
            } label: {
              Label(
                L10n.text(de: "Stopp", en: "Stop", fr: "Arrêter"),
                systemImage: "stop.fill"
              )
            }
            .keyboardShortcut(.cancelAction)
          } else {
            Button(action: sendCurrentPrompt) {
              Label(
                L10n.text(de: "Senden", en: "Send", fr: "Envoyer"),
                systemImage: "paperplane.fill"
              )
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!canSend)
          }

          Button {
            Task { await appState.saveConfiguration() }
          } label: {
            Label(
              L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer"),
              systemImage: "square.and.arrow.down"
            )
          }
        }
      }
    }
    .padding(14)
    .background(
      isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear
    )
    .overlay {
      if isDropTargeted {
        RoundedRectangle(cornerRadius: 12)
          .stroke(
            Color.accentColor,
            style: StrokeStyle(lineWidth: 2, dash: [7, 5])
          )
          .padding(6)
          .allowsHitTesting(false)
      }
    }
    .dropDestination(for: URL.self) { urls, _ in
      importDroppedFiles(urls)
      return true
    } isTargeted: { targeted in
      isDropTargeted = targeted
    }
  }

  private var canSend: Bool {
    !appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !attachmentStore.attachments.isEmpty
  }

  private func sendCurrentPrompt() {
    guard canSend else { return }
    do {
      appState.inputText = try PromptAttachmentService.prepareProviderContent(
        prompt: appState.inputText,
        attachments: attachmentStore.attachments
      )
      attachmentStore.removeAll()
      appState.sendMessage()
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  private func importDroppedFiles(_ urls: [URL]) {
    do {
      let imported = try PromptAttachmentService.importPromptFiles(
        urls,
        existingCount: attachmentStore.attachments.count,
        existingCharacterCount: attachmentStore.extractedCharacterCount,
        existingImageCount: attachmentStore.imageCount,
        existingImageBytes: attachmentStore.imageByteCount
      )
      attachmentStore.add(imported)
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  private func providerTitle(_ provider: ProviderKind) -> String {
    switch provider {
    case .ollamaLocal:
      return "Ollama Local"
    case .ollamaCloud:
      return "Ollama Cloud"
    case .appleOnDevice:
      return L10n.text(
        de: "Apple lokal",
        en: "Apple On-Device",
        fr: "Apple local"
      )
    }
  }

  private func permissionTitle(_ mode: AgentPermissionMode) -> String {
    switch mode {
    case .confirm:
      return L10n.text(de: "Bestätigen", en: "Confirm", fr: "Confirmer")
    case .workspaceTrusted:
      return L10n.text(
        de: "Arbeitsbereich vertraut",
        en: "Workspace Trusted",
        fr: "Espace approuvé"
      )
    case .fullAccess:
      return L10n.text(
        de: "Vollzugriff",
        en: "Full Access",
        fr: "Accès complet"
      )
    }
  }
}

private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let removeAction: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      if attachment.kind == .image,
        let data = attachment.imageData,
        let image = NSImage(data: data)
      {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
          .frame(width: 44, height: 44)
          .clipShape(RoundedRectangle(cornerRadius: 7))
      } else {
        Image(
          systemName: attachment.mediaType == "application/pdf"
            ? "doc.richtext"
            : "doc.text"
        )
        .frame(width: 28)
      }

      VStack(alignment: .leading, spacing: 1) {
        Text(attachment.name)
          .font(.caption)
          .lineLimit(1)
        HStack(spacing: 5) {
          Text(attachment.sizeDescription)
          if let dimensions = attachment.dimensionsDescription {
            Text("·")
            Text(dimensions)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Button(action: removeAction) {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.plain)
      .help(
        L10n.text(
          de: "Anhang entfernen",
          en: "Remove Attachment",
          fr: "Retirer la pièce jointe"
        )
      )
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct ToolApprovalBanner: View {
  @EnvironmentObject private var appState: AppState
  let approval: PendingToolApproval

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label(
          L10n.text(
            de: "Werkzeugfreigabe erforderlich",
            en: "Tool Approval Required",
            fr: "Autorisation d’outil requise"
          ),
          systemImage: "lock.open.trianglebadge.exclamationmark"
        )
        .font(.headline)
        Spacer()
        Text(localizedRisk)
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
        Button(
          L10n.text(de: "Ablehnen", en: "Deny", fr: "Refuser"),
          role: .destructive
        ) {
          appState.denyPendingTool()
        }
        Button(
          L10n.text(de: "Einmal erlauben", en: "Allow Once", fr: "Autoriser une fois")
        ) {
          appState.approvePendingTool()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(12)
    .background(.orange.opacity(0.12))
  }

  private var localizedRisk: String {
    switch approval.risk {
    case .read: L10n.text(de: "Lesen", en: "Read", fr: "Lecture")
    case .write: L10n.text(de: "Schreiben", en: "Write", fr: "Écriture")
    case .execute: L10n.text(de: "Ausführen", en: "Execute", fr: "Exécution")
    }
  }
}

private struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    HStack(alignment: .top) {
      if message.role == .assistant {
        bubble
        Spacer(minLength: 40)
      } else {
        Spacer(minLength: 40)
        bubble
      }
    }
  }

  private var bubble: some View {
    let visibleContent = PromptAttachmentService.visiblePrompt(from: message.content)
    let textAttachmentNames = PromptAttachmentService.textAttachmentNames(
      from: message.content
    )
    let imageReferences = PromptAttachmentService.imageReferences(
      from: message.content
    )

    return VStack(alignment: .leading, spacing: 10) {
      Text(
        message.role == .assistant
          ? "Agent"
          : L10n.text(de: "Du", en: "You", fr: "Vous")
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      if !textAttachmentNames.isEmpty {
        FlowLayout(spacing: 6) {
          ForEach(textAttachmentNames, id: \.self) { name in
            Label(name, systemImage: "paperclip")
              .font(.caption2)
              .lineLimit(1)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(.quaternary, in: Capsule())
          }
        }
      }

      if !imageReferences.isEmpty {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
          alignment: .leading,
          spacing: 8
        ) {
          ForEach(imageReferences, id: \.id) { reference in
            ChatImageAttachmentPreview(reference: reference)
          }
        }
      }

      if !message.thinking.isEmpty {
        DisclosureGroup(
          L10n.text(de: "Denkprozess", en: "Thinking", fr: "Raisonnement")
        ) {
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

      if !visibleContent.isEmpty || message.role == .assistant {
        Text(visibleContent.isEmpty ? "…" : visibleContent)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(12)
    .background(
      message.role == .assistant
        ? Color(nsColor: .controlBackgroundColor)
        : Color.accentColor.opacity(0.16),
      in: RoundedRectangle(cornerRadius: 12)
    )
    .frame(maxWidth: 820, alignment: .leading)
  }
}

private struct ChatImageAttachmentPreview: View {
  let reference: PromptImageReference
  @State private var image: NSImage?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Group {
        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
        } else {
          ZStack {
            Rectangle()
              .fill(.quaternary)
            Image(systemName: "photo.badge.exclamationmark")
              .font(.title2)
              .foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: 300, minHeight: 110, maxHeight: 230)
      .clipShape(RoundedRectangle(cornerRadius: 9))

      HStack(spacing: 6) {
        Text(reference.name)
          .font(.caption)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text("\(reference.pixelWidth) × \(reference.pixelHeight)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(8)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    .task(id: reference.id) {
      guard let url = PromptImageAttachmentStorage.imageURL(for: reference) else {
        return
      }
      image = NSImage(contentsOf: url)
    }
  }
}

private struct FlowLayout<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: Content

  init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    HStack(spacing: spacing) {
      content
    }
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
        Text(localizedStatus)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .padding(9)
    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
  }

  private var localizedStatus: String {
    switch execution.status {
    case .running: L10n.text(de: "Läuft", en: "Running", fr: "En cours")
    case .succeeded: L10n.text(de: "Erfolgreich", en: "Succeeded", fr: "Réussi")
    case .failed: L10n.text(de: "Fehlgeschlagen", en: "Failed", fr: "Échec")
    case .denied: L10n.text(de: "Abgelehnt", en: "Denied", fr: "Refusé")
    }
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

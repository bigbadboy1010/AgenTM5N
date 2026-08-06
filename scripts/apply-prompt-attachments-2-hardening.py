#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected one match in {path}, found {count}: {old[:160]!r}"
        )
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


replace_once(
    "Sources/AgenTM5N/Services/PromptAttachmentService.swift",
    """      hasAlpha: false,
      isPlanar: false,""",
    """      hasAlpha: true,
      isPlanar: false,""",
)

replace_once(
    "Sources/AgenTM5N/Views/ChatView.swift",
    '''  private func sendCurrentPrompt() {
    guard canSend else { return }
    do {
      appState.inputText = try PromptAttachmentService.prepareProviderContent(''',
    '''  private func sendCurrentPrompt() {
    guard canSend else { return }
    if appState.configuration.providerKind == .appleOnDevice,
      attachmentStore.attachments.contains(where: { $0.kind == .image })
    {
      appState.errorMessage = PromptAttachmentError.imageProviderUnsupported
        .localizedDescription
      return
    }

    do {
      appState.inputText = try PromptAttachmentService.prepareProviderContent(''',
)

replace_once(
    "Sources/AgenTM5N/Providers/OllamaProvider.swift",
    '''      role = message.role
      content = message.content
      thinking = message.thinking''',
    '''      role = message.role
      content = PromptAttachmentService.providerPrompt(from: message.content)
      thinking = message.thinking''',
)

replace_once(
    "Sources/AgenTM5N/App/AppState.swift",
    '''      present(error)
    }

    resolvePendingApproval(allowed: false)
    isGenerating = false
    generationTask = nil
  }

  private func performOllamaSend''',
    '''      present(error)
      try? await conversationStore.save(messages)
    }

    resolvePendingApproval(allowed: false)
    isGenerating = false
    generationTask = nil
  }

  private func performOllamaSend''',
)

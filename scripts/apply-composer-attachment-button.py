#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected exactly one match in {path}, found {count}: {old[:100]!r}"
        )
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


chat = "Sources/AgenTM5N/Views/ChatView.swift"

replace_once(
    chat,
    """  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @State private var isDropTargeted = false
""",
    """  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @State private var isDropTargeted = false
  @State private var isImportingPromptFiles = false
""",
)

replace_once(
    chat,
    """        VStack(spacing: 8) {
          if appState.isGenerating {
""",
    """        VStack(spacing: 8) {
          Button {
            importPromptFiles()
          } label: {
            if isImportingPromptFiles {
              ProgressView()
                .controlSize(.small)
                .frame(minWidth: 92)
            } else {
              Label(
                L10n.text(
                  de: "Anhängen",
                  en: "Attach",
                  fr: "Joindre"
                ),
                systemImage: "paperclip"
              )
            }
          }
          .disabled(isImportingPromptFiles || appState.isGenerating)
          .help(
            L10n.text(
              de: "Dateien oder Bilder an den aktuellen Prompt anhängen.",
              en: "Attach files or images to the current prompt.",
              fr: "Joindre des fichiers ou des images à l’invite actuelle."
            )
          )

          if appState.isGenerating {
""",
)

replace_once(
    chat,
    """  private func importDroppedFiles(_ urls: [URL]) {
""",
    """  private func importPromptFiles() {
    guard !isImportingPromptFiles else { return }
    isImportingPromptFiles = true
    defer { isImportingPromptFiles = false }

    do {
      guard let imported = try PromptAttachmentService.selectPromptFiles(
        existingCount: attachmentStore.attachments.count,
        existingCharacterCount: attachmentStore.extractedCharacterCount,
        existingImageCount: attachmentStore.imageCount,
        existingImageBytes: attachmentStore.imageByteCount
      ) else {
        return
      }
      attachmentStore.add(imported)
    } catch {
      appState.errorMessage = error.localizedDescription
    }
  }

  private func importDroppedFiles(_ urls: [URL]) {
""",
)

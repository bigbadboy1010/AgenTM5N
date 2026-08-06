#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected one match in {path}, found {count}: {old[:120]!r}"
        )
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


path = "Sources/AgenTM5N/Views/ChatView.swift"
replace_once(
    path,
    '''  @State private var isDropTargeted = false
  @State private var isImportingPromptFiles = false
''',
    '''  @State private var isDropTargeted = false
  @State private var isImportingPromptFiles = false
  @State private var inspectedAttachment: PromptAttachment?
''',
)
replace_once(
    path,
    '''    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("Chat")
  }
''',
    '''    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle("Chat")
    .sheet(item: $inspectedAttachment) { attachment in
      AttachmentInspectorView(attachment: attachment)
    }
  }
''',
)
replace_once(
    path,
    '''            ForEach(attachmentStore.attachments) { attachment in
              AttachmentDraftChip(attachment: attachment) {
                attachmentStore.remove(id: attachment.id)
              }
            }
''',
    '''            ForEach(attachmentStore.attachments) { attachment in
              AttachmentDraftChip(
                attachment: attachment,
                inspectAction: {
                  inspectedAttachment = attachment
                },
                removeAction: {
                  attachmentStore.remove(id: attachment.id)
                }
              )
            }
''',
)
replace_once(
    path,
    '''private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let removeAction: () -> Void
''',
    '''private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let inspectAction: () -> Void
  let removeAction: () -> Void
''',
)
replace_once(
    path,
    '''      } else {
        Image(
          systemName: attachment.mediaType == "application/pdf"
            ? "doc.richtext"
            : "doc.text"
        )
        .frame(width: 28)
      }
''',
    '''      } else {
        Image(systemName: documentIcon)
          .frame(width: 28)
      }
''',
)
replace_once(
    path,
    '''          if let dimensions = attachment.dimensionsDescription {
            Text("·")
            Text(dimensions)
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Button(action: removeAction) {
''',
    '''          if let dimensions = attachment.dimensionsDescription {
            Text("·")
            Text(dimensions)
          }
          if let sourceCount = attachment.sourceCountDescription {
            Text("·")
            Text(sourceCount)
          }
          if attachment.metadata?.cacheHit == true {
            Image(systemName: "bolt.horizontal.circle")
              .help(
                L10n.text(
                  de: "Aus lokalem Extraktionscache geladen",
                  en: "Loaded from local extraction cache",
                  fr: "Chargé depuis le cache local d’extraction"
                )
              )
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Button(action: inspectAction) {
        Image(systemName: "info.circle")
      }
      .buttonStyle(.plain)
      .help(
        L10n.text(
          de: "Extrahierten Inhalt prüfen",
          en: "Inspect extracted content",
          fr: "Inspecter le contenu extrait"
        )
      )

      Button(action: removeAction) {
''',
)
replace_once(
    path,
    '''    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
  }
}

private struct ToolApprovalBanner: View {
''',
    '''    .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
  }

  private var documentIcon: String {
    switch attachment.metadata?.documentKind {
    case .pdf: "doc.richtext"
    case .docx: "doc.text"
    case .xlsx: "tablecells"
    case .pptx: "rectangle.on.rectangle.angled"
    case .plainText, nil: "doc.plaintext"
    }
  }
}

private struct ToolApprovalBanner: View {
''',
)

#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected exactly one match in {path}, found {count}: {old[:140]!r}"
        )
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


chat = "Sources/AgenTM5N/Views/ChatView.swift"
replace_once(
    chat,
    """  @State private var isDropTargeted = false
  @State private var isImportingPromptFiles = false
""",
    """  @State private var isDropTargeted = false
  @State private var isImportingPromptFiles = false
  @State private var inspectedAttachment: PromptAttachment?
""",
)
replace_once(
    chat,
    """    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(\"Chat\")
  }
""",
    """    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(\"Chat\")
    .sheet(item: $inspectedAttachment) { attachment in
      AttachmentInspectorView(attachment: attachment)
    }
  }
""",
)
replace_once(
    chat,
    """            ForEach(attachmentStore.attachments) { attachment in
              AttachmentDraftChip(attachment: attachment) {
                attachmentStore.remove(id: attachment.id)
              }
            }
""",
    """            ForEach(attachmentStore.attachments) { attachment in
              AttachmentDraftChip(
                attachment: attachment,
                inspectAction: { inspectedAttachment = attachment },
                removeAction: { attachmentStore.remove(id: attachment.id) }
              )
            }
""",
)
replace_once(
    chat,
    """private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let removeAction: () -> Void
""",
    """private struct AttachmentDraftChip: View {
  let attachment: PromptAttachment
  let inspectAction: () -> Void
  let removeAction: () -> Void
""",
)
replace_once(
    chat,
    """      Button(action: removeAction) {
        Image(systemName: \"xmark.circle.fill\")
      }
""",
    """      Button(action: inspectAction) {
        Image(systemName: \"info.circle\")
      }
      .buttonStyle(.plain)
      .help(
        L10n.text(
          de: \"Anhang prüfen\",
          en: \"Inspect Attachment\",
          fr: \"Inspecter la pièce jointe\"
        )
      )

      Button(action: removeAction) {
        Image(systemName: \"xmark.circle.fill\")
      }
""",
)

app = "Sources/AgenTM5N/App/AppState.swift"
replace_once(
    app,
    """      ? AgentRuntime.toolDefinitions
        + CoreMLAgentTools.definitions
        + WorkspaceMemoryAgentTools.definitions
      : []
""",
    """      ? AgentRuntime.toolDefinitions
        + CoreMLAgentTools.definitions
        + WorkspaceMemoryAgentTools.definitions
        + ConversationAttachmentAgentTools.definitions
      : []
""",
)
replace_once(
    app,
    """    } else if WorkspaceMemoryAgentTools.handles(call) {
      risk = WorkspaceMemoryAgentTools.risk(for: call)
      summary = WorkspaceMemoryAgentTools.summary(for: call)
    } else {
""",
    """    } else if WorkspaceMemoryAgentTools.handles(call) {
      risk = WorkspaceMemoryAgentTools.risk(for: call)
      summary = WorkspaceMemoryAgentTools.summary(for: call)
    } else if ConversationAttachmentAgentTools.handles(call) {
      risk = ConversationAttachmentAgentTools.risk(for: call)
      summary = ConversationAttachmentAgentTools.summary(for: call)
    } else {
""",
)
replace_once(
    app,
    """    case \"workspace_index_clear\":
      return await clearWorkspaceIndexTool()
    default:
""",
    """    case \"workspace_index_clear\":
      return await clearWorkspaceIndexTool()
    case \"attachment_list\", \"attachment_describe\", \"attachment_search\",
      \"attachment_read_section\":
      return ConversationAttachmentAgentTools.execute(
        call: call,
        messages: messages
      )
    default:
""",
)

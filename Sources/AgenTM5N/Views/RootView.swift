import SwiftUI

struct RootView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @State private var isImportingPromptFiles = false

  var body: some View {
    NavigationSplitView {
      List(AppSection.allCases, selection: $appState.selectedSection) { section in
        Label(sectionTitle(section), systemImage: section.systemImage)
          .tag(section)
      }
      .navigationTitle("AgenTM5N")
      .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 260)
    } detail: {
      Group {
        switch appState.selectedSection {
        case .chat:
          ChatView()
        case .terminal:
          TerminalWorkspaceView()
        case .ssh:
          SSHHostsView()
        case .vault:
          VaultView()
        case .neuralEngine:
          NeuralEngineView()
        case .memory:
          WorkspaceMemoryView()
        case .settings:
          SettingsView()
        }
      }
      .environmentObject(appState)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .toolbar {
        if appState.selectedSection == .chat {
          ToolbarItem {
            Button {
              importPromptFiles()
            } label: {
              if isImportingPromptFiles {
                ProgressView()
                  .controlSize(.small)
              } else {
                Label(
                  L10n.text(
                    de: "Dateien oder Bilder zum Prompt hinzufügen",
                    en: "Add Files or Images to Prompt",
                    fr: "Ajouter des fichiers ou des images à l’invite"
                  ),
                  systemImage: "paperclip"
                )
              }
            }
            .disabled(isImportingPromptFiles || appState.isGenerating)
            .help(
              L10n.text(
                de: "Text-, Code-, Konfigurations-, Log-, PDF- oder Bilddateien an den aktuellen Prompt anhängen.",
                en: "Attach text, code, configuration, log, PDF, or image files to the current prompt.",
                fr: "Joindre des fichiers texte, code, configuration, journal, PDF ou image à l’invite actuelle."
              )
            )
          }
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .alert(
      L10n.text(de: "Fehler", en: "Error", fr: "Erreur"),
      isPresented: Binding(
        get: { appState.errorMessage != nil },
        set: { visible in
          if !visible {
            appState.dismissError()
          }
        }
      )
    ) {
      Button("OK", role: .cancel) {
        appState.dismissError()
      }
    } message: {
      Text(
        appState.errorMessage
          ?? L10n.text(
            de: "Unbekannter Fehler",
            en: "Unknown error",
            fr: "Erreur inconnue"
          )
      )
    }
  }

  private func importPromptFiles() {
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

  private func sectionTitle(_ section: AppSection) -> String {
    switch section {
    case .chat:
      return L10n.text(de: "Chat", en: "Chat", fr: "Chat")
    case .terminal:
      return L10n.text(de: "Terminal", en: "Terminal", fr: "Terminal")
    case .ssh:
      return "SSH"
    case .vault:
      return L10n.text(de: "Tresor", en: "Vault", fr: "Coffre")
    case .neuralEngine:
      return "Neural Engine"
    case .memory:
      return L10n.text(
        de: "Workspace-Gedächtnis",
        en: "Workspace Memory",
        fr: "Mémoire de l’espace de travail"
      )
    case .settings:
      return L10n.text(
        de: "Einstellungen",
        en: "Settings",
        fr: "Réglages"
      )
    }
  }
}

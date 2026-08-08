import SwiftUI

struct RootView: View {
  @EnvironmentObject private var appState: AppState
  @ObservedObject private var attachmentStore = PromptAttachmentDraftStore.shared
  @ObservedObject private var agentLibrary = PersistentAgentLibrary.shared
  @ObservedObject private var workflowLibrary = AgentWorkflowLibrary.shared
  @State private var isImportingPromptFiles = false
  @State private var showingAttachmentCenter = false
  @State private var showingKnowledgeLibrary = false
  @State private var showingDocumentStudio = false
  @State private var showingMacAccessCenter = false
  @State private var showingAgents = false
  @State private var showingWorkflows = false
  @State private var showingActivity = false

  var body: some View {
    NavigationSplitView {
      List(selection: $appState.selectedSection) {
        ForEach(AppSection.allCases) { section in
          Label(sectionTitle(section), systemImage: section.systemImage)
            .tag(section)
        }

        Section {
          Button {
            showingAgents = true
          } label: {
            HStack {
              Label(
                L10n.text(de: "Agenten", en: "Agents", fr: "Agents"),
                systemImage: "person.3.sequence"
              )
              Spacer()
              if !agentLibrary.profiles.isEmpty {
                Text("\(agentLibrary.profiles.count)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)

          Button {
            showingWorkflows = true
          } label: {
            HStack {
              Label("Workflows", systemImage: "point.3.connected.trianglepath.dotted")
              Spacer()
              if !workflowLibrary.workflows.isEmpty {
                Text("\(workflowLibrary.workflows.count)")
                  .font(.caption.monospacedDigit())
                  .foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)

          Button {
            showingActivity = true
          } label: {
            Label(
              L10n.text(de: "Aktivität", en: "Activity", fr: "Activité"),
              systemImage: "waveform.path.ecg"
            )
          }
          .buttonStyle(.plain)
        }
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
          ToolbarItemGroup {
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
                de: "Text-, Office-, PDF- oder Bilddateien an den aktuellen Prompt anhängen.",
                en: "Attach text, Office, PDF, or image files to the current prompt.",
                fr: "Joindre des fichiers texte, Office, PDF ou image à l’invite actuelle."
              )
            )

            Button {
              showingAttachmentCenter = true
            } label: {
              Label(
                L10n.text(
                  de: "Anhangscenter",
                  en: "Attachment Center",
                  fr: "Centre des pièces jointes"
                ),
                systemImage: "doc.text.magnifyingglass"
              )
            }
            .disabled(attachmentStore.attachments.isEmpty)
            .help(
              attachmentStore.attachments.isEmpty
                ? L10n.text(
                  de: "Der aktuelle Prompt enthält noch keine Anhänge.",
                  en: "The current prompt does not contain attachments yet.",
                  fr: "L’invite actuelle ne contient pas encore de pièces jointes."
                )
                : L10n.text(
                  de: "Anhänge und extrahierte Dokumentabschnitte prüfen.",
                  en: "Inspect attachments and extracted document sections.",
                  fr: "Inspecter les pièces jointes et les sections extraites."
                )
            )

            Button {
              showingKnowledgeLibrary = true
            } label: {
              Label(
                L10n.text(
                  de: "Wissensbibliothek",
                  en: "Knowledge Library",
                  fr: "Bibliothèque de connaissances"
                ),
                systemImage: "books.vertical.fill"
              )
            }
            .help(
              L10n.text(
                de: "Dauerhafte Wissenssammlungen verwalten, importieren und durchsuchen.",
                en: "Manage, import, and search persistent knowledge collections.",
                fr: "Gérer, importer et rechercher des collections persistantes."
              )
            )

            Button {
              showingDocumentStudio = true
            } label: {
              Label(
                L10n.text(
                  de: "Document Studio",
                  en: "Document Studio",
                  fr: "Document Studio"
                ),
                systemImage: "doc.badge.plus"
              )
            }
            .help(
              L10n.text(
                de: "DOCX-, PDF-, XLSX- und PPTX-Dokumente lokal erzeugen und exportieren.",
                en: "Generate and export DOCX, PDF, XLSX, and PPTX documents locally.",
                fr: "Générer et exporter localement des documents DOCX, PDF, XLSX et PPTX."
              )
            )

            Button {
              showingMacAccessCenter = true
            } label: {
              Label(
                L10n.text(
                  de: "Mac Access Center",
                  en: "Mac Access Center",
                  fr: "Centre d’accès Mac"
                ),
                systemImage: "lock.shield"
              )
            }
            .help(
              L10n.text(
                de: "macOS-Berechtigungen, gemeinsamen Tool-Router und Audit-Status prüfen.",
                en: "Inspect macOS permissions, the shared tool router, and audit status.",
                fr: "Vérifier les autorisations macOS, le routeur d’outils partagé et l’audit."
              )
            )
          }
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .sheet(isPresented: $showingAttachmentCenter) {
      AttachmentCenterView()
        .environmentObject(appState)
        .frame(minWidth: 840, minHeight: 640)
    }
    .sheet(isPresented: $showingKnowledgeLibrary) {
      KnowledgeLibraryView()
        .frame(minWidth: 1_050, minHeight: 700)
    }
    .sheet(isPresented: $showingDocumentStudio) {
      DocumentStudioView()
        .frame(minWidth: 1_050, minHeight: 700)
    }
    .sheet(isPresented: $showingMacAccessCenter) {
      MacAccessCenterView()
        .environmentObject(appState)
    }
    .sheet(isPresented: $showingAgents) {
      AgentsView()
        .environmentObject(appState)
    }
    .sheet(isPresented: $showingWorkflows) {
      WorkflowsView()
        .environmentObject(appState)
    }
    .sheet(isPresented: $showingActivity) {
      ActivityView()
    }
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

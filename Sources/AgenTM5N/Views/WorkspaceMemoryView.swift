import SwiftUI

struct WorkspaceMemoryView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        overviewCard
        indexCard
        searchCard
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .navigationTitle(
      L10n.text(
        de: "Workspace-Gedächtnis",
        en: "Workspace Memory",
        fr: "Mémoire de l’espace de travail"
      )
    )
    .task {
      await appState.refreshWorkspaceIndexStatus()
    }
  }

  private var overviewCard: some View {
    GroupBox(
      L10n.text(
        de: "Lokaler semantischer Index",
        en: "Local Semantic Index",
        fr: "Index sémantique local"
      )
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Label(
          L10n.text(
            de: "Dateien werden lokal gelesen, in Textabschnitte geteilt und mit einem registrierten Core-ML-Modell eingebettet.",
            en: "Files are read locally, split into text chunks, and embedded with a registered Core ML model.",
            fr: "Les fichiers sont lus localement, divisés en segments de texte et vectorisés avec un modèle Core ML enregistré."
          ),
          systemImage: "lock.macwindow"
        )

        Text(
          L10n.text(
            de: "Das Modell muss genau eine Text-Eingabe und eine MultiArray-Ausgabe besitzen. Modellpfade und Embedding-Vektoren werden dem Sprachmodell nicht offengelegt.",
            en: "The model must expose exactly one text input and one MultiArray output. Model paths and embedding vectors are never exposed to the language model.",
            fr: "Le modèle doit fournir exactement une entrée texte et une sortie MultiArray. Les chemins du modèle et les vecteurs ne sont jamais exposés au modèle linguistique."
          )
        )
        .foregroundStyle(.secondary)

        LabeledContent(
          L10n.text(de: "Workspace", en: "Workspace", fr: "Espace de travail"),
          value: appState.configuration.workspacePath
        )
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var indexCard: some View {
    GroupBox(
      L10n.text(
        de: "Indexverwaltung",
        en: "Index Management",
        fr: "Gestion de l’index"
      )
    ) {
      VStack(alignment: .leading, spacing: 14) {
        Picker(
          L10n.text(
            de: "Embedding-Modell",
            en: "Embedding Model",
            fr: "Modèle d’embedding"
          ),
          selection: $appState.workspaceEmbeddingModelID
        ) {
          Text(
            L10n.text(
              de: "Aktives Core-ML-Modell",
              en: "Active Core ML Model",
              fr: "Modèle Core ML actif"
            )
          )
          .tag(UUID?.none)

          ForEach(appState.coreMLModels) { model in
            Text(model.name).tag(Optional(model.id))
          }
        }

        HStack(spacing: 10) {
          Button {
            Task { await appState.buildWorkspaceIndex() }
          } label: {
            if appState.isBuildingWorkspaceIndex {
              ProgressView()
                .controlSize(.small)
            } else {
              Label(
                appState.workspaceIndexStatus == nil
                  ? L10n.text(
                    de: "Index erstellen",
                    en: "Build Index",
                    fr: "Créer l’index"
                  )
                  : L10n.text(
                    de: "Index neu erstellen",
                    en: "Rebuild Index",
                    fr: "Reconstruire l’index"
                  ),
                systemImage: "square.stack.3d.up"
              )
            }
          }
          .disabled(appState.isBuildingWorkspaceIndex || appState.coreMLModels.isEmpty)

          Button {
            Task { await appState.refreshWorkspaceIndexStatus() }
          } label: {
            Label(
              L10n.text(de: "Aktualisieren", en: "Refresh", fr: "Actualiser"),
              systemImage: "arrow.clockwise"
            )
          }
          .disabled(appState.isBuildingWorkspaceIndex)

          if appState.workspaceIndexStatus != nil {
            Button(role: .destructive) {
              Task { await appState.clearWorkspaceIndex() }
            } label: {
              Label(
                L10n.text(de: "Index löschen", en: "Delete Index", fr: "Supprimer l’index"),
                systemImage: "trash"
              )
            }
            .disabled(appState.isBuildingWorkspaceIndex)
          }
        }

        if appState.coreMLModels.isEmpty {
          Label(
            L10n.text(
              de: "Importiere zuerst ein kompatibles Text-Embedding-Modell unter „Neural Engine“.",
              en: "Import a compatible text embedding model under Neural Engine first.",
              fr: "Importez d’abord un modèle d’embedding de texte compatible dans Neural Engine."
            ),
            systemImage: "exclamationmark.triangle"
          )
          .foregroundStyle(.orange)
        }

        if let status = appState.workspaceIndexStatus {
          Divider()
          Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
              Text(L10n.text(de: "Modell", en: "Model", fr: "Modèle"))
                .foregroundStyle(.secondary)
              Text(status.modelName)
            }
            GridRow {
              Text(L10n.text(de: "Dateien", en: "Files", fr: "Fichiers"))
                .foregroundStyle(.secondary)
              Text("\(status.fileCount)")
            }
            GridRow {
              Text(L10n.text(de: "Abschnitte", en: "Chunks", fr: "Segments"))
                .foregroundStyle(.secondary)
              Text("\(status.chunkCount)")
            }
            GridRow {
              Text(L10n.text(de: "Dimension", en: "Dimension", fr: "Dimension"))
                .foregroundStyle(.secondary)
              Text("\(status.embeddingDimension)")
            }
            GridRow {
              Text(L10n.text(de: "Erstellt", en: "Created", fr: "Créé"))
                .foregroundStyle(.secondary)
              Text(status.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var searchCard: some View {
    GroupBox(
      L10n.text(
        de: "Semantische Suche",
        en: "Semantic Search",
        fr: "Recherche sémantique"
      )
    ) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          TextField(
            L10n.text(
              de: "Zum Beispiel: Wo wird der SSH-Host gespeichert?",
              en: "For example: Where is the SSH host stored?",
              fr: "Par exemple : Où l’hôte SSH est-il enregistré ?"
            ),
            text: $appState.workspaceSemanticQuery
          )
          .textFieldStyle(.roundedBorder)
          .onSubmit {
            Task { await appState.searchWorkspaceMemory() }
          }

          Button {
            Task { await appState.searchWorkspaceMemory() }
          } label: {
            Label(
              L10n.text(de: "Suchen", en: "Search", fr: "Rechercher"),
              systemImage: "magnifyingglass"
            )
          }
          .disabled(
            appState.workspaceIndexStatus == nil
              || appState.workspaceSemanticQuery.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty
          )
        }

        if appState.workspaceSemanticResults.isEmpty {
          Text(
            appState.workspaceIndexStatus == nil
              ? L10n.text(
                de: "Erstelle zuerst einen Index.",
                en: "Build an index first.",
                fr: "Créez d’abord un index."
              )
              : L10n.text(
                de: "Noch keine Suchergebnisse.",
                en: "No search results yet.",
                fr: "Aucun résultat pour le moment."
              )
          )
          .foregroundStyle(.secondary)
        } else {
          ForEach(appState.workspaceSemanticResults) { match in
            VStack(alignment: .leading, spacing: 6) {
              HStack {
                Text("\(match.relativePath):\(match.startLine)-\(match.endLine)")
                  .font(.system(.caption, design: .monospaced).bold())
                  .textSelection(.enabled)
                Spacer()
                Text(match.score.formatted(.number.precision(.fractionLength(4))))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(match.excerpt)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }
}

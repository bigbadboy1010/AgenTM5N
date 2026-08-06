import SwiftUI

struct WorkspaceMemoryView: View {
  @EnvironmentObject private var appState: AppState

  private var compatibleEmbeddingModels: [CoreMLRegisteredModel] {
    appState.coreMLModels.filter { $0.supportsDirectTextEmbedding }
  }

  private var incompatibleModels: [CoreMLRegisteredModel] {
    appState.coreMLModels.filter { !$0.supportsDirectTextEmbedding }
  }

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
      normalizeSelectedEmbeddingModel()
    }
  }

  private var overviewCard: some View {
    GroupBox(
      L10n.text(
        de: "Lokaler Workspace-Index",
        en: "Local Workspace Index",
        fr: "Index local de l’espace de travail"
      )
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Label(
          L10n.text(
            de: "AgenTM5N erstellt zuerst einen persistenten Textindex. Ein kompatibles Core-ML-Modell kann anschließend semantische Vektoren ergänzen.",
            en: "AgenTM5N first creates a persistent text index. A compatible Core ML model can then add semantic vectors.",
            fr: "AgenTM5N crée d’abord un index texte persistant. Un modèle Core ML compatible peut ensuite ajouter des vecteurs sémantiques."
          ),
          systemImage: "lock.macwindow"
        )

        Text(
          L10n.text(
            de: "Der lexikalische Modus funktioniert ohne spezielles Modell. Für direkte Core-ML-Embeddings wird genau eine String-Eingabe und eine MultiArray-Ausgabe benötigt. Tokenisierte Sprachmodelle bleiben im Neural-Engine-Bereich nutzbar, sind aber keine direkten Embedding-Modelle.",
            en: "Lexical mode works without a special model. Direct Core ML embeddings require exactly one String input and one MultiArray output. Tokenized language models remain usable in Neural Engine, but they are not direct embedding models.",
            fr: "Le mode lexical fonctionne sans modèle spécial. Les embeddings Core ML directs nécessitent exactement une entrée String et une sortie MultiArray. Les modèles linguistiques tokenisés restent utilisables dans Neural Engine, mais ne sont pas des modèles d’embedding directs."
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
            de: "Indexmodus",
            en: "Index Mode",
            fr: "Mode d’indexation"
          ),
          selection: $appState.workspaceEmbeddingModelID
        ) {
          Text(
            L10n.text(
              de: "Lexikalischer Index – ohne Core ML",
              en: "Lexical Index – without Core ML",
              fr: "Index lexical – sans Core ML"
            )
          )
          .tag(UUID?.none)

          ForEach(compatibleEmbeddingModels) { model in
            Text("Core ML – \(model.name)").tag(Optional(model.id))
          }
        }

        if compatibleEmbeddingModels.isEmpty {
          Label(
            L10n.text(
              de: "Kein direkt kompatibles Text-Embedding-Modell registriert. Der lexikalische Index steht vollständig zur Verfügung.",
              en: "No directly compatible text embedding model is registered. The lexical index remains fully available.",
              fr: "Aucun modèle d’embedding de texte directement compatible n’est enregistré. L’index lexical reste entièrement disponible."
            ),
            systemImage: "info.circle"
          )
          .foregroundStyle(.secondary)
        }

        if !incompatibleModels.isEmpty {
          DisclosureGroup(
            L10n.text(
              de: "Andere Core-ML-Modelle (\(incompatibleModels.count))",
              en: "Other Core ML Models (\(incompatibleModels.count))",
              fr: "Autres modèles Core ML (\(incompatibleModels.count))"
            )
          ) {
            VStack(alignment: .leading, spacing: 10) {
              ForEach(incompatibleModels) { model in
                VStack(alignment: .leading, spacing: 4) {
                  HStack {
                    Text(model.name)
                      .font(.headline)
                    Spacer()
                    Text(model.capability.displayName)
                      .font(.caption)
                      .foregroundStyle(.secondary)
                  }
                  Text(model.capability.workspaceMemoryExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
              }
            }
            .padding(.top, 8)
          }
        }

        Text(
          appState.workspaceEmbeddingModelID == nil
            ? L10n.text(
              de: "Empfohlener Basistest: Der Index wird sofort lokal gespeichert und kann durchsucht werden.",
              en: "Recommended baseline test: the index is saved locally immediately and can be searched.",
              fr: "Test de base recommandé : l’index est enregistré localement immédiatement et peut être recherché."
            )
            : L10n.text(
              de: "Der Textindex wird zuerst gespeichert. Danach ergänzt das ausgewählte, direkt kompatible Core-ML-Modell semantische Embeddings.",
              en: "The text index is saved first. The selected directly compatible Core ML model then adds semantic embeddings.",
              fr: "L’index texte est d’abord enregistré. Le modèle Core ML directement compatible sélectionné ajoute ensuite des embeddings sémantiques."
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          Button {
            Task { await appState.buildWorkspaceIndex() }
          } label: {
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
          .disabled(appState.isBuildingWorkspaceIndex)

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

        if appState.isBuildingWorkspaceIndex,
          let progress = appState.workspaceIndexProgress
        {
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              ProgressView()
                .controlSize(.small)
              Text(progress.phase.displayName)
                .font(.headline)
              Spacer()
              if progress.total > 0 {
                Text("\(progress.completed) / \(progress.total)")
                  .font(.system(.caption, design: .monospaced))
                  .foregroundStyle(.secondary)
              }
            }

            if let fraction = progress.fractionCompleted {
              ProgressView(value: fraction)
            }

            if !progress.detail.isEmpty {
              Text(progress.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
          .padding(12)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }

        if let status = appState.workspaceIndexStatus {
          Divider()
          Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
              Text(L10n.text(de: "Status", en: "Status", fr: "État"))
                .foregroundStyle(.secondary)
              Label(
                L10n.text(de: "Index vorhanden", en: "Index available", fr: "Index disponible"),
                systemImage: "checkmark.circle.fill"
              )
              .foregroundStyle(.green)
            }
            GridRow {
              Text(L10n.text(de: "Modus", en: "Mode", fr: "Mode"))
                .foregroundStyle(.secondary)
              Text(status.mode.displayName)
            }
            GridRow {
              Text(L10n.text(de: "Modell", en: "Model", fr: "Modèle"))
                .foregroundStyle(.secondary)
              Text(status.modelName ?? "–")
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
              Text(L10n.text(de: "Zeichen", en: "Characters", fr: "Caractères"))
                .foregroundStyle(.secondary)
              Text(status.indexedCharacterCount.formatted())
            }
            GridRow {
              Text(L10n.text(de: "Dimension", en: "Dimension", fr: "Dimension"))
                .foregroundStyle(.secondary)
              Text(status.embeddingDimension.map(String.init) ?? "–")
            }
            GridRow {
              Text(L10n.text(de: "Erstellt", en: "Created", fr: "Créé"))
                .foregroundStyle(.secondary)
              Text(status.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
          }

          if let warning = status.warning, !warning.isEmpty {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.orange)
              .textSelection(.enabled)
              .padding(10)
              .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
          }
        } else if !appState.isBuildingWorkspaceIndex {
          Label(
            L10n.text(
              de: "Noch kein Index für diesen Workspace vorhanden.",
              en: "No index exists for this workspace yet.",
              fr: "Aucun index n’existe encore pour cet espace de travail."
            ),
            systemImage: "square.stack.3d.up.slash"
          )
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(8)
    }
  }

  private var searchCard: some View {
    GroupBox(
      appState.workspaceIndexStatus?.mode == .coreMLEmbedding
        ? L10n.text(
          de: "Semantische Suche",
          en: "Semantic Search",
          fr: "Recherche sémantique"
        )
        : L10n.text(
          de: "Indexsuche",
          en: "Index Search",
          fr: "Recherche dans l’index"
        )
    ) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          TextField(
            L10n.text(
              de: "Zum Beispiel: Wo werden SSH-Profile gespeichert?",
              en: "For example: Where are SSH profiles stored?",
              fr: "Par exemple : Où les profils SSH sont-ils enregistrés ?"
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

  private func normalizeSelectedEmbeddingModel() {
    guard let selectedID = appState.workspaceEmbeddingModelID else { return }
    guard compatibleEmbeddingModels.contains(where: { $0.id == selectedID }) else {
      appState.workspaceEmbeddingModelID = nil
      return
    }
  }
}

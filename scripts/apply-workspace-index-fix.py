#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"Expected one match in {path}, found {count}: {old[:160]!r}")
    file.write_text(text.replace(old, new, 1), encoding="utf-8")


app = "Sources/AgenTM5N/App/AppState.swift"
replace_once(
    app,
    '''private struct WorkspaceIndexToolStatusDescriptor: Encodable {
  let indexed: Bool
  let modelID: String?
  let modelName: String?
  let createdAt: Date?
  let fileCount: Int?
  let chunkCount: Int?
  let embeddingDimension: Int?
  let indexedCharacterCount: Int?
}''',
    '''private struct WorkspaceIndexToolStatusDescriptor: Encodable {
  let indexed: Bool
  let mode: String?
  let modelID: String?
  let modelName: String?
  let warning: String?
  let createdAt: Date?
  let fileCount: Int?
  let chunkCount: Int?
  let embeddingDimension: Int?
  let indexedCharacterCount: Int?
}''',
)
replace_once(
    app,
    '''  @Published public var workspaceSemanticResults: [WorkspaceSemanticMatch] = []
  @Published public var isBuildingWorkspaceIndex = false''',
    '''  @Published public var workspaceSemanticResults: [WorkspaceSemanticMatch] = []
  @Published public var isBuildingWorkspaceIndex = false
  @Published public var workspaceIndexProgress: WorkspaceIndexBuildProgress?''',
)
replace_once(
    app,
    '''      workspaceEmbeddingModelID = workspaceIndexStatus?.modelID
        ?? snapshot.activeModelID''',
    '''      workspaceEmbeddingModelID = workspaceIndexStatus?.modelID''',
)
replace_once(
    app,
    '''      coreMLPredictionResult = nil
      if workspaceEmbeddingModelID == nil {
        workspaceEmbeddingModelID = record.id
      }''',
    '''      coreMLPredictionResult = nil''',
)
replace_once(
    app,
    '''  public func buildWorkspaceIndex() async {
    guard !isBuildingWorkspaceIndex else { return }
    isBuildingWorkspaceIndex = true
    defer { isBuildingWorkspaceIndex = false }

    do {
      let model = try await selectedWorkspaceEmbeddingModel()
      workspaceIndexStatus = try await workspaceIndexService.build(
        workspacePath: configuration.workspacePath,
        model: model
      )
      workspaceEmbeddingModelID = model.id
      workspaceSemanticResults = []
    } catch {
      present(error)
    }
  }''',
    '''  public func buildWorkspaceIndex() async {
    guard !isBuildingWorkspaceIndex else { return }
    isBuildingWorkspaceIndex = true
    workspaceIndexProgress = WorkspaceIndexBuildProgress(
      phase: .preparing
    )
    defer { isBuildingWorkspaceIndex = false }

    do {
      let model = try await selectedWorkspaceEmbeddingModel()
      workspaceIndexStatus = try await workspaceIndexService.build(
        workspacePath: configuration.workspacePath,
        model: model,
        progress: { [weak self] progress in
          self?.workspaceIndexProgress = progress
        }
      )
      workspaceEmbeddingModelID = workspaceIndexStatus?.modelID
      workspaceSemanticResults = []
    } catch {
      workspaceIndexProgress = nil
      present(error)
    }
  }''',
)
replace_once(
    app,
    '''  public func searchWorkspaceMemory() async {
    do {
      guard let status = workspaceIndexStatus else {
        throw WorkspaceIndexError.indexNotFound(configuration.workspacePath)
      }
      let model = try await coreMLService.registeredModel(
        query: status.modelID.uuidString
      )
      workspaceSemanticResults = try await workspaceIndexService.search(
        query: workspaceSemanticQuery,
        workspacePath: configuration.workspacePath,
        model: model
      )
    } catch {
      present(error)
    }
  }''',
    '''  public func searchWorkspaceMemory() async {
    do {
      guard let status = workspaceIndexStatus else {
        throw WorkspaceIndexError.indexNotFound(configuration.workspacePath)
      }
      let model: CoreMLRegisteredModel?
      if let modelID = status.modelID {
        model = try await coreMLService.registeredModel(
          query: modelID.uuidString
        )
      } else {
        model = nil
      }
      workspaceSemanticResults = try await workspaceIndexService.search(
        query: workspaceSemanticQuery,
        workspacePath: configuration.workspacePath,
        model: model
      )
    } catch {
      present(error)
    }
  }''',
)
replace_once(
    app,
    '''      workspaceIndexStatus = nil
      workspaceSemanticResults = []''',
    '''      workspaceIndexStatus = nil
      workspaceIndexProgress = nil
      workspaceSemanticResults = []''',
)
replace_once(
    app,
    '''  private func buildWorkspaceIndexTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let modelQuery = optionalToolString("model", in: call)
      let model = try await coreMLService.registeredModel(query: modelQuery)
      let status = try await workspaceIndexService.build(
        workspacePath: configuration.workspacePath,
        model: model
      )
      workspaceIndexStatus = status
      workspaceEmbeddingModelID = model.id
      workspaceSemanticResults = []
      return encodedToolResult(workspaceStatusDescriptor(status))
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }''',
    '''  private func buildWorkspaceIndexTool(
    _ call: ProviderToolCall
  ) async -> ToolExecutionResult {
    do {
      let modelQuery = optionalToolString("model", in: call)
      let model: CoreMLRegisteredModel?
      if let modelQuery {
        model = try await coreMLService.registeredModel(query: modelQuery)
      } else {
        model = nil
      }
      let status = try await workspaceIndexService.build(
        workspacePath: configuration.workspacePath,
        model: model,
        progress: { [weak self] progress in
          self?.workspaceIndexProgress = progress
        }
      )
      workspaceIndexStatus = status
      workspaceEmbeddingModelID = status.modelID
      workspaceSemanticResults = []
      return encodedToolResult(workspaceStatusDescriptor(status))
    } catch {
      return ToolExecutionResult(success: false, output: error.localizedDescription)
    }
  }''',
)
replace_once(
    app,
    '''      let model = try await coreMLService.registeredModel(
        query: status.modelID.uuidString
      )
      let matches = try await workspaceIndexService.search(''',
    '''      let model: CoreMLRegisteredModel?
      if let modelID = status.modelID {
        model = try await coreMLService.registeredModel(
          query: modelID.uuidString
        )
      } else {
        model = nil
      }
      let matches = try await workspaceIndexService.search(''',
)
replace_once(
    app,
    '''    WorkspaceIndexToolStatusDescriptor(
      indexed: status != nil,
      modelID: status?.modelID.uuidString,
      modelName: status?.modelName,
      createdAt: status?.createdAt,''',
    '''    WorkspaceIndexToolStatusDescriptor(
      indexed: status != nil,
      mode: status?.mode.rawValue,
      modelID: status?.modelID?.uuidString,
      modelName: status?.modelName,
      warning: status?.warning,
      createdAt: status?.createdAt,''',
)
replace_once(
    app,
    '''  private func selectedWorkspaceEmbeddingModel() async throws -> CoreMLRegisteredModel {
    if let modelID = workspaceEmbeddingModelID {
      return try await coreMLService.registeredModel(
        query: modelID.uuidString
      )
    }
    return try await coreMLService.registeredModel(query: nil)
  }''',
    '''  private func selectedWorkspaceEmbeddingModel() async throws -> CoreMLRegisteredModel? {
    guard let modelID = workspaceEmbeddingModelID else {
      return nil
    }
    return try await coreMLService.registeredModel(
      query: modelID.uuidString
    )
  }''',
)

service = "Sources/AgenTM5N/Services/WorkspaceIndexService.swift"
replace_once(
    service,
    '  public typealias ProgressHandler = @Sendable (WorkspaceIndexBuildProgress) async -> Void',
    '  public typealias ProgressHandler = @MainActor @Sendable (WorkspaceIndexBuildProgress) async -> Void',
)

build = "scripts/build-app.sh"
replace_once(build, 'VERSION="0.4.0"', 'VERSION="0.4.1"')
replace_once(build, 'BUILD_NUMBER="12"', 'BUILD_NUMBER="13"')

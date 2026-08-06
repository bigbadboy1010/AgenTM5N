import Foundation

public struct CoreMLRegisteredModel: Codable, Identifiable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public let sourceURL: URL
  public let compiledURL: URL
  public let inputs: [String]
  public let outputs: [String]
  public let computeUnits: String
  public let importedAt: Date

  public init(
    id: UUID = UUID(),
    name: String,
    sourceURL: URL,
    compiledURL: URL,
    inputs: [String],
    outputs: [String],
    computeUnits: String,
    importedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.sourceURL = sourceURL
    self.compiledURL = compiledURL
    self.inputs = inputs
    self.outputs = outputs
    self.computeUnits = computeUnits
    self.importedAt = importedAt
  }

  public var descriptor: CoreMLModelDescriptor {
    CoreMLModelDescriptor(
      sourceURL: sourceURL,
      compiledURL: compiledURL,
      inputs: inputs,
      outputs: outputs,
      computeUnits: computeUnits
    )
  }
}

public struct CoreMLRegistryDocument: Codable, Equatable, Sendable {
  public var version: Int
  public var activeModelID: UUID?
  public var models: [CoreMLRegisteredModel]

  public init(
    version: Int = 1,
    activeModelID: UUID? = nil,
    models: [CoreMLRegisteredModel] = []
  ) {
    self.version = version
    self.activeModelID = activeModelID
    self.models = models
  }
}

public struct CoreMLRegistrySnapshot: Equatable, Sendable {
  public let models: [CoreMLRegisteredModel]
  public let activeModelID: UUID?
  public let activeDescriptor: CoreMLModelDescriptor?

  public init(
    models: [CoreMLRegisteredModel],
    activeModelID: UUID?,
    activeDescriptor: CoreMLModelDescriptor?
  ) {
    self.models = models
    self.activeModelID = activeModelID
    self.activeDescriptor = activeDescriptor
  }
}

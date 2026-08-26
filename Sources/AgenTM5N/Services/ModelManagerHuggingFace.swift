import Foundation

@MainActor
extension ModelManagerController {
  @discardableResult
  public func importHuggingFaceGGUF(
    reference: String,
    contextWindow: Int = 8_192,
    priority: Int = 100,
    importer: HuggingFaceOllamaImportService = HuggingFaceOllamaImportService()
  ) async throws -> ModelProfile {
    let imported = try await importer.importGGUF(reference: reference)
    let identifier = imported.reference.modelIdentifier
    let capabilities = OllamaModelCapabilityPolicy.profileCapabilities(
      model: identifier,
      ollamaCapabilities: imported.capabilities
    )

    let profile = ModelProfile(
      name: "Hugging Face · \(imported.reference.displayName)",
      runtime: .ollamaLocal,
      modelIdentifier: identifier,
      baseURL: LocalInferenceRuntime.ollama.defaultBaseURL,
      contextWindow: contextWindow,
      estimatedMemoryMB: nil,
      priority: priority,
      enabled: true,
      capabilities: capabilities
    )

    await save(profile)
    await reload()

    guard profiles.contains(where: { $0.id == profile.id }) else {
      throw ModelProfileError.profileNotFound
    }
    return profile
  }
}

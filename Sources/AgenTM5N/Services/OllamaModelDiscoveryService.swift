import Foundation

public struct DiscoveredOllamaModel: Equatable, Sendable {
  public let name: String
  public let sizeBytes: Int64?
  public let capabilities: Set<ModelProfileCapability>

  public init(
    name: String,
    sizeBytes: Int64?,
    capabilities: Set<ModelProfileCapability>
  ) {
    self.name = name
    self.sizeBytes = sizeBytes
    self.capabilities = capabilities
  }
}

public enum OllamaModelDiscoveryError: LocalizedError {
  case invalidBaseURL(String)
  case invalidHTTPResponse
  case httpError(statusCode: Int, body: String)

  public var errorDescription: String? {
    switch self {
    case .invalidBaseURL(let value):
      return "Die lokale Ollama-Basis-URL ist ungültig: \(value)"
    case .invalidHTTPResponse:
      return "Ollama hat bei der Modell-Erkennung keine gültige HTTP-Antwort geliefert."
    case .httpError(let statusCode, let body):
      return "Ollama HTTP \(statusCode) bei der Modell-Erkennung: \(body)"
    }
  }
}

public final class OllamaModelDiscoveryService: @unchecked Sendable {
  private struct TagsResponse: Decodable {
    let models: [Model]

    struct Model: Decodable {
      let name: String
      let size: Int64?
    }
  }

  private struct ShowRequest: Encodable {
    let model: String
    let verbose = false
  }

  private struct ShowResponse: Decodable {
    let capabilities: [String]?
  }

  private let session: URLSession

  public init(session: URLSession = .shared) {
    self.session = session
  }

  public func discover(
    baseURL: String = LocalInferenceRuntime.ollama.defaultBaseURL
  ) async throws -> [DiscoveredOllamaModel] {
    let tagsURL = try endpointURL(baseURL: baseURL, path: "/api/tags")
    var tagsRequest = URLRequest(url: tagsURL)
    tagsRequest.httpMethod = "GET"
    tagsRequest.timeoutInterval = 30

    let (tagsData, tagsResponse) = try await session.data(for: tagsRequest)
    try validate(response: tagsResponse, body: tagsData)

    let tags = try JSONDecoder().decode(TagsResponse.self, from: tagsData)
    let candidates = tags.models
      .filter { !Self.isCloudAlias($0.name) }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }

    var discovered: [DiscoveredOllamaModel] = []
    discovered.reserveCapacity(candidates.count)

    for candidate in candidates {
      try Task.checkCancellation()
      let rawCapabilities = (try? await fetchCapabilities(
        model: candidate.name,
        baseURL: baseURL
      )) ?? []
      discovered.append(
        DiscoveredOllamaModel(
          name: candidate.name,
          sizeBytes: candidate.size,
          capabilities: Self.profileCapabilities(from: rawCapabilities)
        )
      )
    }

    return discovered
  }

  public static func makeProfile(
    from model: DiscoveredOllamaModel,
    baseURL: String = LocalInferenceRuntime.ollama.defaultBaseURL
  ) -> ModelProfile {
    ModelProfile(
      name: "Ollama · \(model.name)",
      runtime: .ollamaLocal,
      modelIdentifier: model.name,
      baseURL: baseURL,
      contextWindow: 8_192,
      estimatedMemoryMB: nil,
      priority: 100,
      enabled: true,
      capabilities: model.capabilities
    )
  }

  static func isCloudAlias(_ modelName: String) -> Bool {
    modelName
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .hasSuffix(":cloud")
  }

  static func profileCapabilities(
    from rawCapabilities: Set<String>
  ) -> Set<ModelProfileCapability> {
    let normalized = Set(rawCapabilities.map { $0.lowercased() })
    var capabilities: Set<ModelProfileCapability> = [
      .textGeneration,
      .streaming,
      .onDevice,
    ]

    if normalized.contains("tools") || normalized.contains("tool") {
      capabilities.insert(.toolCalling)
    }
    if normalized.contains("thinking") || normalized.contains("reasoning") {
      capabilities.insert(.thinking)
    }
    if normalized.contains("vision") || normalized.contains("image") {
      capabilities.insert(.imageInput)
    }

    return capabilities
  }

  private func fetchCapabilities(
    model: String,
    baseURL: String
  ) async throws -> Set<String> {
    let showURL = try endpointURL(baseURL: baseURL, path: "/api/show")
    var request = URLRequest(url: showURL)
    request.httpMethod = "POST"
    request.timeoutInterval = 20
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(ShowRequest(model: model))

    let (data, response) = try await session.data(for: request)
    try validate(response: response, body: data)
    let decoded = try JSONDecoder().decode(ShowResponse.self, from: data)
    return Set((decoded.capabilities ?? []).map { $0.lowercased() })
  }

  private func endpointURL(baseURL: String, path: String) throws -> URL {
    let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard var components = URLComponents(string: trimmed),
      let scheme = components.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      components.host != nil
    else {
      throw OllamaModelDiscoveryError.invalidBaseURL(baseURL)
    }

    components.path = path
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      throw OllamaModelDiscoveryError.invalidBaseURL(baseURL)
    }
    return url
  }

  private func validate(response: URLResponse, body: Data) throws {
    guard let http = response as? HTTPURLResponse else {
      throw OllamaModelDiscoveryError.invalidHTTPResponse
    }
    guard (200...299).contains(http.statusCode) else {
      let bounded = body.prefix(64 * 1024)
      let text = String(decoding: bounded, as: UTF8.self)
      throw OllamaModelDiscoveryError.httpError(
        statusCode: http.statusCode,
        body: text.isEmpty ? "Keine Fehlerdetails" : text
      )
    }
  }
}

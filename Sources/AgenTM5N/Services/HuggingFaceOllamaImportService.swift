import Foundation

public enum HuggingFaceOllamaImportError: LocalizedError, Equatable {
  case invalidReference(String)
  case invalidLocalOllamaURL
  case invalidResponse
  case httpError(statusCode: Int, body: String)

  public var errorDescription: String? {
    switch self {
    case .invalidReference(let value):
      return "Ungültige Hugging-Face-GGUF-Referenz: \(value)"
    case .invalidLocalOllamaURL:
      return "Die lokale Ollama-URL ist ungültig."
    case .invalidResponse:
      return "Ollama hat beim Hugging-Face-Import keine gültige HTTP-Antwort geliefert."
    case .httpError(let statusCode, let body):
      return "Ollama Hugging-Face-Import HTTP \(statusCode): \(body)"
    }
  }
}

public struct HuggingFaceOllamaReference: Equatable, Sendable {
  public let modelIdentifier: String

  public init(_ rawValue: String) throws {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw HuggingFaceOllamaImportError.invalidReference(rawValue)
    }

    let candidate: String
    if let url = URL(string: trimmed),
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http"
    {
      guard let host = url.host?.lowercased(),
        ["huggingface.co", "www.huggingface.co", "hf.co", "www.hf.co"].contains(host),
        url.query == nil,
        url.fragment == nil
      else {
        throw HuggingFaceOllamaImportError.invalidReference(rawValue)
      }

      let components = url.path
        .split(separator: "/")
        .map(String.init)
      guard components.count == 2 else {
        throw HuggingFaceOllamaImportError.invalidReference(rawValue)
      }
      candidate = "hf.co/\(components[0])/\(components[1])"
    } else {
      var value = trimmed
      for prefix in ["www.huggingface.co/", "huggingface.co/", "www.hf.co/"] {
        if value.lowercased().hasPrefix(prefix) {
          value = "hf.co/" + value.dropFirst(prefix.count)
          break
        }
      }
      if !value.lowercased().hasPrefix("hf.co/") {
        value = "hf.co/" + value
      }
      candidate = value
    }

    let normalized = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard !normalized.contains(where: { $0.isWhitespace }),
      !normalized.contains("?"),
      !normalized.contains("#")
    else {
      throw HuggingFaceOllamaImportError.invalidReference(rawValue)
    }

    let components = normalized.split(separator: "/", omittingEmptySubsequences: true)
    guard components.count == 3,
      components[0].lowercased() == "hf.co",
      !components[1].isEmpty,
      !components[2].isEmpty
    else {
      throw HuggingFaceOllamaImportError.invalidReference(rawValue)
    }

    modelIdentifier = "hf.co/\(components[1])/\(components[2])"
  }

  public var displayName: String {
    String(modelIdentifier.dropFirst("hf.co/".count))
  }
}

public struct HuggingFaceOllamaImportResult: Equatable, Sendable {
  public let reference: HuggingFaceOllamaReference
  public let capabilities: Set<String>

  public init(reference: HuggingFaceOllamaReference, capabilities: Set<String>) {
    self.reference = reference
    self.capabilities = capabilities
  }
}

public final class HuggingFaceOllamaImportService: @unchecked Sendable {
  private struct PullRequest: Encodable {
    let model: String
    let stream = false
  }

  private struct ShowRequest: Encodable {
    let model: String
    let verbose = false
  }

  private struct ShowResponse: Decodable {
    let capabilities: [String]?
  }

  private let session: URLSession
  private let baseURL: String

  public init(
    session: URLSession = .shared,
    baseURL: String = LocalInferenceRuntime.ollama.defaultBaseURL
  ) {
    self.session = session
    self.baseURL = baseURL
  }

  public func importGGUF(reference rawReference: String) async throws -> HuggingFaceOllamaImportResult {
    let reference = try HuggingFaceOllamaReference(rawReference)

    let pullURL = try endpointURL(path: "/api/pull")
    var pullRequest = URLRequest(url: pullURL)
    pullRequest.httpMethod = "POST"
    pullRequest.timeoutInterval = 3_600
    pullRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    pullRequest.httpBody = try JSONEncoder().encode(
      PullRequest(model: reference.modelIdentifier)
    )

    let (pullData, pullResponse) = try await session.data(for: pullRequest)
    try validate(response: pullResponse, body: pullData)

    let showURL = try endpointURL(path: "/api/show")
    var showRequest = URLRequest(url: showURL)
    showRequest.httpMethod = "POST"
    showRequest.timeoutInterval = 60
    showRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    showRequest.httpBody = try JSONEncoder().encode(
      ShowRequest(model: reference.modelIdentifier)
    )

    let (showData, showResponse) = try await session.data(for: showRequest)
    try validate(response: showResponse, body: showData)
    let metadata = try JSONDecoder().decode(ShowResponse.self, from: showData)
    let capabilities = Set((metadata.capabilities ?? []).map { $0.lowercased() })

    return HuggingFaceOllamaImportResult(
      reference: reference,
      capabilities: capabilities
    )
  }

  private func endpointURL(path: String) throws -> URL {
    guard var components = URLComponents(string: baseURL) else {
      throw HuggingFaceOllamaImportError.invalidLocalOllamaURL
    }
    let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    components.path = "/" + [basePath, endpointPath]
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    guard let url = components.url else {
      throw HuggingFaceOllamaImportError.invalidLocalOllamaURL
    }
    return url
  }

  private func validate(response: URLResponse, body: Data) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
      throw HuggingFaceOllamaImportError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      let bodyText = String(data: body, encoding: .utf8) ?? "Keine Fehlerdetails"
      throw HuggingFaceOllamaImportError.httpError(
        statusCode: httpResponse.statusCode,
        body: bodyText
      )
    }
  }
}

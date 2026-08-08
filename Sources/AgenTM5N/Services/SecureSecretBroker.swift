import Foundation

public enum SecureSecretBrokerError: LocalizedError {
  case vaultLocked
  case secretNotFound(String)
  case ambiguousSecret(String)
  case invalidURL(String)
  case unsupportedScheme(String)
  case insecureSecretTransport(String)
  case invalidHeaderName(String)
  case sensitiveHeaderBlocked(String)
  case responseTooLarge(Int)

  public var errorDescription: String? {
    switch self {
    case .vaultLocked:
      return "Der AgenTM5N-Tresor ist gesperrt. Entsperre ihn, bevor ein Secret verwendet wird."
    case .secretNotFound(let query):
      return "Kein Secret passt eindeutig zu: \(query)"
    case .ambiguousSecret(let query):
      return "Mehrere Secrets passen zu: \(query). Verwende ein eindeutiges Label."
    case .invalidURL(let value):
      return "Ungültige URL: \(value)"
    case .unsupportedScheme(let value):
      return "Nicht unterstütztes URL-Schema: \(value). Erlaubt sind http und https."
    case .insecureSecretTransport(let host):
      return "Ein Secret wird nicht über unverschlüsseltes HTTP an \(host) gesendet. Verwende HTTPS oder einen lokalen Host."
    case .invalidHeaderName(let name):
      return "Ungültiger HTTP-Headername: \(name)"
    case .sensitiveHeaderBlocked(let name):
      return "Der direkte HTTP-Header \(name) ist für Modellaufrufe blockiert. Hinterlege Zugangsdaten im Tresor und verwende secret_ref."
    case .responseTooLarge(let limit):
      return "Die HTTP-Antwort überschreitet das Limit von \(limit) Bytes."
    }
  }
}

public struct SecretMetadataDescriptor: Codable, Equatable, Sendable {
  public let label: String
  public let kind: String
  public let username: String?
  public let host: String?
  public let notesPresent: Bool

  public init(secret: VaultSecret) {
    label = secret.label
    kind = secret.kind.rawValue
    username = secret.username.isEmpty ? nil : secret.username
    host = secret.host.isEmpty ? nil : secret.host
    notesPresent = !secret.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

public enum SecretHTTPUsage: String, Codable, CaseIterable, Sendable {
  case bearer
  case basic
  case header
}

public enum SecureSecretBroker {
  public static func metadata(_ secrets: [VaultSecret]) -> [SecretMetadataDescriptor] {
    secrets
      .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
      .map(SecretMetadataDescriptor.init(secret:))
  }

  public static func resolve(
    _ query: String,
    from secrets: [VaultSecret]
  ) throws -> VaultSecret {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      throw SecureSecretBrokerError.secretNotFound(query)
    }

    let matches = secrets.filter { secret in
      secret.label.caseInsensitiveCompare(normalized) == .orderedSame
        || secret.id.uuidString.caseInsensitiveCompare(normalized) == .orderedSame
    }
    guard !matches.isEmpty else {
      throw SecureSecretBrokerError.secretNotFound(query)
    }
    guard matches.count == 1, let secret = matches.first else {
      throw SecureSecretBrokerError.ambiguousSecret(query)
    }
    return secret
  }

  /// Removes known secret representations from model-visible output. Raw,
  /// percent-encoded, base64 and Basic-auth payload forms are covered so a
  /// diagnostic endpoint cannot trivially reflect a Vault value back to a model.
  public static func redact(
    _ text: String,
    secrets: [VaultSecret]
  ) -> String {
    var candidates: Set<String> = []
    for secret in secrets where secret.value.count >= 4 {
      candidates.insert(secret.value)
      candidates.insert(Data(secret.value.utf8).base64EncodedString())
      if let escaped = secret.value.addingPercentEncoding(
        withAllowedCharacters: .alphanumerics
      ), !escaped.isEmpty
      {
        candidates.insert(escaped)
      }
      if !secret.username.isEmpty {
        let basic = Data("\(secret.username):\(secret.value)".utf8)
          .base64EncodedString()
        candidates.insert(basic)
        candidates.insert("Basic \(basic)")
      }
      candidates.insert("Bearer \(secret.value)")
    }

    var result = text
    for candidate in candidates.sorted(by: { $0.count > $1.count })
      where candidate.count >= 4
    {
      result = result.replacingOccurrences(
        of: candidate,
        with: "<redacted-secret>"
      )
    }
    return result
  }
}

public struct SecureHTTPResponseDescriptor: Codable, Equatable, Sendable {
  public let statusCode: Int
  public let url: String
  public let headers: [String: String]
  public let body: String
  public let truncated: Bool
}

public struct SecureHTTPClient: Sendable {
  public static let maximumResponseBytes = 256 * 1024
  public static let maximumRequestBytes = 1 * 1024 * 1024

  private static let forbiddenRequestHeaders: Set<String> = [
    "authorization",
    "proxy-authorization",
    "cookie",
    "set-cookie",
    "set-cookie2",
  ]

  public init() {}

  public func request(
    method: String,
    urlText: String,
    headers: [String: String],
    body: String?,
    secret: VaultSecret?,
    secretUsage: SecretHTTPUsage?,
    secretHeaderName: String?
  ) async throws -> SecureHTTPResponseDescriptor {
    guard let url = URL(string: urlText),
      let scheme = url.scheme?.lowercased(),
      let host = url.host,
      url.user == nil,
      url.password == nil
    else {
      throw SecureSecretBrokerError.invalidURL(urlText)
    }
    guard scheme == "https" || scheme == "http" else {
      throw SecureSecretBrokerError.unsupportedScheme(scheme)
    }
    if secret != nil, scheme != "https", !Self.isLocalHost(host) {
      throw SecureSecretBrokerError.insecureSecretTransport(host)
    }

    let normalizedMethod = method
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    let allowedMethods = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    guard allowedMethods.contains(normalizedMethod) else {
      throw SecureSecretBrokerError.invalidURL(
        "Unsupported HTTP method: \(normalizedMethod)"
      )
    }

    var request = URLRequest(url: url)
    request.httpMethod = normalizedMethod
    request.timeoutInterval = 60
    request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

    for (name, value) in headers {
      try Self.validateHeaderName(name)
      if Self.forbiddenRequestHeaders.contains(name.lowercased()) {
        throw SecureSecretBrokerError.sensitiveHeaderBlocked(name)
      }
      guard !value.contains("\r"), !value.contains("\n") else {
        throw SecureSecretBrokerError.invalidHeaderName(name)
      }
      request.setValue(value, forHTTPHeaderField: name)
    }

    if let body {
      guard body.utf8.count <= Self.maximumRequestBytes else {
        throw AgentRuntimeError.inputTooLarge(limit: Self.maximumRequestBytes)
      }
      request.httpBody = Data(body.utf8)
      if request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue(
          "application/json; charset=utf-8",
          forHTTPHeaderField: "Content-Type"
        )
      }
    }

    if let secret {
      switch secretUsage ?? .bearer {
      case .bearer:
        request.setValue(
          "Bearer \(secret.value)",
          forHTTPHeaderField: "Authorization"
        )
      case .basic:
        let raw = "\(secret.username):\(secret.value)"
        request.setValue(
          "Basic \(Data(raw.utf8).base64EncodedString())",
          forHTTPHeaderField: "Authorization"
        )
      case .header:
        let header = secretHeaderName?
          .trimmingCharacters(in: .whitespacesAndNewlines)
          ?? "X-API-Key"
        try Self.validateHeaderName(header)
        guard !Self.forbiddenRequestHeaders.contains(header.lowercased()) else {
          throw SecureSecretBrokerError.sensitiveHeaderBlocked(header)
        }
        request.setValue(secret.value, forHTTPHeaderField: header)
      }
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false

    let redirectDelegate = SecureHTTPRedirectDelegate(
      originalHost: host,
      hasSecret: secret != nil
    )
    let session = URLSession(
      configuration: configuration,
      delegate: redirectDelegate,
      delegateQueue: nil
    )
    defer { session.invalidateAndCancel() }

    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw SecureSecretBrokerError.invalidURL("No HTTP response")
    }

    let limited = data.prefix(Self.maximumResponseBytes)
    let bodyText = String(decoding: limited, as: UTF8.self)
    let redactionSecrets = secret.map { [$0] } ?? []
    let safeBody = SecureSecretBroker.redact(
      bodyText,
      secrets: redactionSecrets
    )

    var safeHeaders: [String: String] = [:]
    let blockedResponseHeaders = Set([
      "authorization", "proxy-authorization", "set-cookie", "set-cookie2",
      "www-authenticate", "proxy-authenticate"
    ])
    for (key, value) in http.allHeaderFields {
      let name = String(describing: key)
      guard !blockedResponseHeaders.contains(name.lowercased()) else { continue }
      safeHeaders[name] = SecureSecretBroker.redact(
        String(describing: value),
        secrets: redactionSecrets
      )
    }

    return SecureHTTPResponseDescriptor(
      statusCode: http.statusCode,
      url: http.url?.absoluteString ?? url.absoluteString,
      headers: safeHeaders,
      body: safeBody,
      truncated: data.count > Self.maximumResponseBytes
    )
  }

  fileprivate static func isLocalHost(_ host: String) -> Bool {
    let normalized = host.lowercased()
    if normalized == "localhost" || normalized == "::1" || normalized.hasSuffix(".local") {
      return true
    }
    if normalized.hasPrefix("127.")
      || normalized.hasPrefix("10.")
      || normalized.hasPrefix("192.168.")
    {
      return true
    }
    if normalized.hasPrefix("172."),
      let second = normalized.split(separator: ".").dropFirst().first,
      let value = Int(second),
      (16...31).contains(value)
    {
      return true
    }
    return false
  }

  private static func validateHeaderName(_ name: String) throws {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
    )
    guard !name.isEmpty,
      name.unicodeScalars.allSatisfy({ allowed.contains($0) })
    else {
      throw SecureSecretBrokerError.invalidHeaderName(name)
    }
  }
}

private final class SecureHTTPRedirectDelegate: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private let originalHost: String
  private let hasSecret: Bool

  init(originalHost: String, hasSecret: Bool) {
    self.originalHost = originalHost.lowercased()
    self.hasSecret = hasSecret
    super.init()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard hasSecret else {
      completionHandler(request)
      return
    }
    guard let url = request.url,
      let host = url.host?.lowercased(),
      let scheme = url.scheme?.lowercased()
    else {
      completionHandler(nil)
      return
    }

    let encryptedOrLocal = scheme == "https"
      || (scheme == "http" && SecureHTTPClient.isLocalHost(host))
    guard encryptedOrLocal, host == originalHost else {
      completionHandler(nil)
      return
    }
    completionHandler(request)
  }
}

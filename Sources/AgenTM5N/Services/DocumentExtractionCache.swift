import CryptoKit
import Foundation

public struct DocumentExtractionResult: Codable, Equatable, Sendable {
  public let text: String
  public let sections: [PromptAttachmentSection]
  public let metadata: PromptAttachmentMetadata

  public init(
    text: String,
    sections: [PromptAttachmentSection],
    metadata: PromptAttachmentMetadata
  ) {
    self.text = text
    self.sections = sections
    self.metadata = metadata
  }

  public func withCacheHit(_ cacheHit: Bool) -> DocumentExtractionResult {
    DocumentExtractionResult(
      text: text,
      sections: sections,
      metadata: metadata.withCacheHit(cacheHit)
    )
  }
}

public enum DocumentExtractionCache {
  public static func sha256(for url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hasher = SHA256()
    while true {
      let data = try handle.read(upToCount: 1 * 1024 * 1024) ?? Data()
      if data.isEmpty { break }
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  public static func load(sha256: String) throws -> DocumentExtractionResult? {
    try AppPaths.ensureDirectories()
    let url = AppPaths.documentExtractionCacheFile(sha256: sha256)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return nil
    }

    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    let decoder = JSONDecoder()
    let result = try decoder.decode(DocumentExtractionResult.self, from: data)
    guard result.metadata.sourceSHA256 == sha256 else {
      try? FileManager.default.removeItem(at: url)
      return nil
    }
    return result.withCacheHit(true)
  }

  public static func save(
    _ result: DocumentExtractionResult,
    sha256: String
  ) throws {
    try AppPaths.ensureDirectories()
    let url = AppPaths.documentExtractionCacheFile(sha256: sha256)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(result.withCacheHit(false))
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )
  }

  public static func removeAll() throws {
    try AppPaths.ensureDirectories()
    let manager = FileManager.default
    let files = try manager.contentsOfDirectory(
      at: AppPaths.documentExtractionCacheDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    for file in files where file.pathExtension.lowercased() == "json" {
      try manager.removeItem(at: file)
    }
  }
}

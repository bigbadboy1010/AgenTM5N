import CryptoKit
import Foundation

public enum CoreMLManagedStorage {
  public struct CopyResult: Sendable {
    public let url: URL
    public let created: Bool

    public init(url: URL, created: Bool) {
      self.url = url
      self.created = created
    }
  }

  private static let chunkSize = 4 * 1024 * 1024

  public static func contentDigest(at url: URL) throws -> String {
    let manager = FileManager.default
    let standardized = url.standardizedFileURL
    var isDirectory: ObjCBool = false
    guard manager.fileExists(atPath: standardized.path, isDirectory: &isDirectory) else {
      throw CoreMLServiceError.sourceUnavailable(standardized.path)
    }

    var hasher = SHA256()
    if isDirectory.boolValue {
      update(&hasher, text: "directory\0")
      let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
      ]
      guard let enumerator = manager.enumerator(
        at: standardized,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles],
        errorHandler: { _, _ in true }
      ) else {
        return hex(hasher.finalize())
      }

      var entries: [URL] = []
      for case let entry as URL in enumerator {
        entries.append(entry)
      }
      entries.sort {
        relativePath($0, root: standardized) < relativePath($1, root: standardized)
      }

      for entry in entries {
        let values = try entry.resourceValues(forKeys: Set(keys))
        let relative = relativePath(entry, root: standardized)
        if values.isDirectory == true, values.isSymbolicLink != true {
          update(&hasher, text: "dir\0\(relative)\0")
          continue
        }
        if values.isSymbolicLink == true {
          let destination = (try? manager.destinationOfSymbolicLink(atPath: entry.path)) ?? ""
          update(&hasher, text: "link\0\(relative)\0\(destination)\0")
          continue
        }
        guard values.isRegularFile == true else { continue }
        update(&hasher, text: "file\0\(relative)\0")
        try update(&hasher, file: entry)
        update(&hasher, text: "\0")
      }
    } else {
      update(&hasher, text: "file\0")
      try update(&hasher, file: standardized)
    }

    return hex(hasher.finalize())
  }

  public static func sameContent(_ lhs: URL, _ rhs: URL) throws -> Bool {
    try contentDigest(at: lhs) == contentDigest(at: rhs)
  }

  public static func persistentCopy(
    of sourceURL: URL,
    in directory: URL,
    preferredExtension: String,
    digest: String? = nil
  ) throws -> CopyResult {
    let manager = FileManager.default
    try manager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try? manager.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )

    let contentHash: String
    if let digest {
      contentHash = digest
    } else {
      contentHash = try contentDigest(at: sourceURL)
    }

    let baseName = sanitizedBaseName(
      sourceURL.deletingPathExtension().lastPathComponent
    )
    let destination = directory.appendingPathComponent(
      "\(baseName)-\(contentHash).\(preferredExtension)",
      isDirectory: preferredExtension == "mlpackage" || preferredExtension == "mlmodelc"
    )

    if manager.fileExists(atPath: destination.path) {
      guard try sameContent(sourceURL, destination) else {
        throw CocoaError(.fileWriteFileExists)
      }
      return CopyResult(url: destination, created: false)
    }

    do {
      try manager.copyItem(at: sourceURL, to: destination)
      if preferredExtension == "mlpackage" || preferredExtension == "mlmodelc" {
        try? manager.setAttributes(
          [.posixPermissions: 0o700],
          ofItemAtPath: destination.path
        )
      } else {
        try? manager.setAttributes(
          [.posixPermissions: 0o600],
          ofItemAtPath: destination.path
        )
      }
      return CopyResult(url: destination, created: true)
    } catch {
      try? manager.removeItem(at: destination)
      throw error
    }
  }

  public static func removeOrphans(
    in directory: URL,
    referencedURLs: [URL]
  ) throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath: directory.path) else { return }
    let referenced = Set(
      referencedURLs.map { $0.standardizedFileURL.path }
    )
    let entries = try manager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    for entry in entries where !referenced.contains(entry.standardizedFileURL.path) {
      try manager.removeItem(at: entry)
    }
  }

  public static func isManaged(_ url: URL, inside directory: URL) -> Bool {
    let path = url.standardizedFileURL.path
    let root = directory.standardizedFileURL.path
    return path == root || path.hasPrefix(root + "/")
  }

  private static func update(_ hasher: inout SHA256, text: String) {
    hasher.update(data: Data(text.utf8))
  }

  private static func update(_ hasher: inout SHA256, file: URL) throws {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    while true {
      let data = handle.readData(ofLength: chunkSize)
      if data.isEmpty { break }
      hasher.update(data: data)
    }
  }

  private static func relativePath(_ url: URL, root: URL) -> String {
    let rootPath = root.standardizedFileURL.path
    let path = url.standardizedFileURL.path
    guard path.hasPrefix(rootPath + "/") else { return path }
    return String(path.dropFirst(rootPath.count + 1))
  }

  private static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }

  private static func sanitizedBaseName(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(
      CharacterSet(charactersIn: "-_")
    )
    let scalars = value.unicodeScalars.map {
      allowed.contains($0) ? Character(String($0)) : "-"
    }
    let result = String(scalars).trimmingCharacters(
      in: CharacterSet(charactersIn: "-")
    )
    return result.isEmpty ? "CoreMLModel" : result
  }
}
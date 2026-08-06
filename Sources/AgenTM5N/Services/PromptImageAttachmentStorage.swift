import Foundation

public enum PromptImageAttachmentStorageError: LocalizedError {
  case missingImageData(String)
  case invalidRelativePath(String)
  case missingStoredImage(String)

  public var errorDescription: String? {
    switch self {
    case .missingImageData(let name):
      return L10n.text(
        de: "Der Bildanhang \(name) enthält keine lesbaren Bilddaten.",
        en: "Image attachment \(name) does not contain readable image data.",
        fr: "La pièce jointe image \(name) ne contient pas de données d’image lisibles."
      )
    case .invalidRelativePath(let path):
      return L10n.text(
        de: "Ungültiger interner Bildpfad: \(path)",
        en: "Invalid internal image path: \(path)",
        fr: "Chemin d’image interne non valide : \(path)"
      )
    case .missingStoredImage(let path):
      return L10n.text(
        de: "Der gespeicherte Bildanhang ist nicht mehr vorhanden: \(path)",
        en: "The stored image attachment is no longer available: \(path)",
        fr: "La pièce jointe image enregistrée n’est plus disponible : \(path)"
      )
    }
  }
}

public enum PromptImageAttachmentStorage {
  private static let imageDirectoryName = "Images"

  public static func persist(
    _ attachment: PromptAttachment
  ) throws -> PromptImageReference {
    guard attachment.kind == .image,
      let imageData = attachment.imageData,
      !imageData.isEmpty,
      let pixelWidth = attachment.pixelWidth,
      let pixelHeight = attachment.pixelHeight
    else {
      throw PromptImageAttachmentStorageError.missingImageData(attachment.name)
    }

    try AppPaths.ensureDirectories()
    let directory = imageDirectory
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directory.path
    )

    let fileName = "\(attachment.id.uuidString.lowercased()).jpg"
    let destination = directory.appendingPathComponent(fileName)
    try imageData.write(to: destination, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: destination.path
    )

    return PromptImageReference(
      id: attachment.id,
      name: attachment.name,
      mediaType: "image/jpeg",
      byteCount: imageData.count,
      relativePath: "\(imageDirectoryName)/\(fileName)",
      pixelWidth: pixelWidth,
      pixelHeight: pixelHeight
    )
  }

  public static func data(
    for reference: PromptImageReference
  ) throws -> Data {
    let url = try resolvedURL(for: reference.relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PromptImageAttachmentStorageError.missingStoredImage(
        reference.relativePath
      )
    }
    return try Data(contentsOf: url, options: [.mappedIfSafe])
  }

  public static func imageURL(
    for reference: PromptImageReference
  ) -> URL? {
    try? resolvedURL(for: reference.relativePath)
  }

  public static func remove(
    _ reference: PromptImageReference
  ) {
    guard let url = try? resolvedURL(for: reference.relativePath) else {
      return
    }
    try? FileManager.default.removeItem(at: url)
  }

  public static func removeAll() throws {
    let manager = FileManager.default
    guard manager.fileExists(atPath: AppPaths.promptAttachmentsDirectory.path) else {
      return
    }
    let entries = try manager.contentsOfDirectory(
      at: AppPaths.promptAttachmentsDirectory,
      includingPropertiesForKeys: nil,
      options: []
    )
    for entry in entries {
      try manager.removeItem(at: entry)
    }
  }

  private static var imageDirectory: URL {
    AppPaths.promptAttachmentsDirectory.appendingPathComponent(
      imageDirectoryName,
      isDirectory: true
    )
  }

  private static func resolvedURL(for relativePath: String) throws -> URL {
    let root = AppPaths.promptAttachmentsDirectory.standardizedFileURL
    let candidate = root
      .appendingPathComponent(relativePath)
      .standardizedFileURL
    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard candidate.path.hasPrefix(rootPrefix) else {
      throw PromptImageAttachmentStorageError.invalidRelativePath(relativePath)
    }
    return candidate
  }
}

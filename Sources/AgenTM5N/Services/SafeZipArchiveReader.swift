import Foundation

public enum SafeZipArchiveError: LocalizedError {
  case archiveToolUnavailable
  case invalidArchive(String)
  case tooManyEntries(Int)
  case listingTooLarge(Int)
  case unsafeEntry(String)
  case missingEntry(String)
  case expandedEntryTooLarge(String, Int)
  case commandFailed(String)

  public var errorDescription: String? {
    switch self {
    case .archiveToolUnavailable:
      return L10n.text(
        de: "Das macOS-Werkzeug /usr/bin/unzip ist nicht verfügbar.",
        en: "The macOS /usr/bin/unzip tool is unavailable.",
        fr: "L’outil macOS /usr/bin/unzip n’est pas disponible."
      )
    case .invalidArchive(let name):
      return L10n.text(
        de: "Das Office-Dokument „\(name)“ ist kein lesbares OOXML-Archiv oder ist kennwortgeschützt.",
        en: "Office document “\(name)” is not a readable OOXML archive or is password protected.",
        fr: "Le document Office « \(name) » n’est pas une archive OOXML lisible ou est protégé par mot de passe."
      )
    case .tooManyEntries(let limit):
      return L10n.text(
        de: "Das Office-Dokument enthält mehr als \(limit) Archiveinträge.",
        en: "The Office document contains more than \(limit) archive entries.",
        fr: "Le document Office contient plus de \(limit) entrées d’archive."
      )
    case .listingTooLarge(let limit):
      return L10n.text(
        de: "Die Archivstruktur überschreitet das Limit von \(limit) Bytes.",
        en: "The archive directory exceeds the \(limit)-byte limit.",
        fr: "La structure de l’archive dépasse la limite de \(limit) octets."
      )
    case .unsafeEntry(let entry):
      return L10n.text(
        de: "Das Office-Dokument enthält einen unsicheren Archiveintrag: \(entry)",
        en: "The Office document contains an unsafe archive entry: \(entry)",
        fr: "Le document Office contient une entrée d’archive non sûre : \(entry)"
      )
    case .missingEntry(let entry):
      return L10n.text(
        de: "Der erwartete Dokumentbestandteil fehlt: \(entry)",
        en: "An expected document component is missing: \(entry)",
        fr: "Un composant attendu du document est absent : \(entry)"
      )
    case .expandedEntryTooLarge(let entry, let limit):
      return L10n.text(
        de: "Der entpackte Dokumentbestandteil \(entry) überschreitet das Limit von \(limit) Bytes.",
        en: "Expanded document component \(entry) exceeds the \(limit)-byte limit.",
        fr: "Le composant décompressé \(entry) dépasse la limite de \(limit) octets."
      )
    case .commandFailed(let detail):
      return L10n.text(
        de: "Das Office-Archiv konnte nicht verarbeitet werden: \(detail)",
        en: "The Office archive could not be processed: \(detail)",
        fr: "L’archive Office n’a pas pu être traitée : \(detail)"
      )
    }
  }
}

public final class SafeZipArchiveReader: @unchecked Sendable {
  public static let maximumEntries = 5_000
  public static let maximumListingBytes = 2 * 1024 * 1024

  private let archiveURL: URL
  private let archiveName: String
  private var cachedEntries: Set<String>?
  private let lock = NSLock()

  public init(url: URL) throws {
    guard FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip") else {
      throw SafeZipArchiveError.archiveToolUnavailable
    }
    archiveURL = url
    archiveName = url.lastPathComponent
  }

  public func entries() throws -> Set<String> {
    lock.lock()
    if let cachedEntries {
      lock.unlock()
      return cachedEntries
    }
    lock.unlock()

    let data: Data
    do {
      data = try runUnzip(
        arguments: ["-Z1", archiveURL.path],
        maximumOutputBytes: Self.maximumListingBytes,
        oversizedError: .listingTooLarge(Self.maximumListingBytes)
      )
    } catch SafeZipArchiveError.commandFailed {
      throw SafeZipArchiveError.invalidArchive(archiveName)
    }

    guard let text = String(data: data, encoding: .utf8) else {
      throw SafeZipArchiveError.invalidArchive(archiveName)
    }

    let listed = text
      .split(whereSeparator: \ .isNewline)
      .map(String.init)
      .filter { !$0.isEmpty }

    guard listed.count <= Self.maximumEntries else {
      throw SafeZipArchiveError.tooManyEntries(Self.maximumEntries)
    }

    var validated = Set<String>()
    for entry in listed {
      try Self.validate(entry: entry)
      validated.insert(entry)
    }

    lock.lock()
    cachedEntries = validated
    lock.unlock()
    return validated
  }

  public func contains(_ entry: String) throws -> Bool {
    try Self.validate(entry: entry)
    return try entries().contains(entry)
  }

  public func data(
    for entry: String,
    maximumBytes: Int
  ) throws -> Data {
    try Self.validate(entry: entry)
    guard try entries().contains(entry) else {
      throw SafeZipArchiveError.missingEntry(entry)
    }

    do {
      return try runUnzip(
        arguments: ["-p", archiveURL.path, entry],
        maximumOutputBytes: maximumBytes,
        oversizedError: .expandedEntryTooLarge(entry, maximumBytes)
      )
    } catch SafeZipArchiveError.commandFailed {
      throw SafeZipArchiveError.invalidArchive(archiveName)
    }
  }

  public func optionalData(
    for entry: String,
    maximumBytes: Int
  ) throws -> Data? {
    guard try contains(entry) else { return nil }
    return try data(for: entry, maximumBytes: maximumBytes)
  }

  private static func validate(entry: String) throws {
    let normalized = entry.replacingOccurrences(of: "\\", with: "/")
    let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
    guard !normalized.hasPrefix("/"),
      !normalized.contains("\0"),
      !components.contains(where: { $0 == ".." }),
      !components.contains(where: { $0.isEmpty && components.count > 1 })
    else {
      throw SafeZipArchiveError.unsafeEntry(entry)
    }
  }

  private func runUnzip(
    arguments: [String],
    maximumOutputBytes: Int,
    oversizedError: SafeZipArchiveError
  ) throws -> Data {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()

    var output = Data()
    while true {
      let chunk = try outputPipe.fileHandleForReading.read(upToCount: 64 * 1024) ?? Data()
      if chunk.isEmpty { break }
      output.append(chunk)
      if output.count > maximumOutputBytes {
        process.terminate()
        process.waitUntilExit()
        throw oversizedError
      }
    }

    process.waitUntilExit()
    let errorData = try errorPipe.fileHandleForReading.readToEnd() ?? Data()
    guard process.terminationStatus == 0 else {
      let detail = String(data: errorData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      throw SafeZipArchiveError.commandFailed(
        detail?.isEmpty == false ? detail! : "Exit \(process.terminationStatus)"
      )
    }
    return output
  }
}

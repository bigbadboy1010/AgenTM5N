import Foundation

public enum AppPaths {
  public static let bundleIdentifier = "team.cloudforge.AgenTM5N"
  private static let applicationDirectoryName = "AgenTM5N"
  private static let legacyApplicationDirectoryName = "MacAgentForge"

  public static var applicationSupportDirectory: URL {
    applicationSupportBaseDirectory.appendingPathComponent(
      applicationDirectoryName,
      isDirectory: true
    )
  }

  public static var runtimeDirectory: URL {
    applicationSupportDirectory.appendingPathComponent("Runtime", isDirectory: true)
  }

  public static var coreMLModelsDirectory: URL {
    applicationSupportDirectory.appendingPathComponent("CoreML", isDirectory: true)
  }

  public static var coreMLSourcesDirectory: URL {
    coreMLModelsDirectory.appendingPathComponent("Sources", isDirectory: true)
  }

  public static var coreMLCompiledDirectory: URL {
    coreMLModelsDirectory.appendingPathComponent("Compiled", isDirectory: true)
  }

  public static var configurationFile: URL {
    applicationSupportDirectory.appendingPathComponent("configuration.json")
  }

  public static var sshHostsFile: URL {
    applicationSupportDirectory.appendingPathComponent("ssh-hosts.json")
  }

  public static var conversationFile: URL {
    applicationSupportDirectory.appendingPathComponent("conversation.json")
  }

  public static var vaultFile: URL {
    applicationSupportDirectory.appendingPathComponent("vault.json")
  }

  public static func ensureDirectories() throws {
    try migrateLegacyApplicationDirectoryIfNeeded()

    let manager = FileManager.default
    for directory in [
      applicationSupportDirectory,
      runtimeDirectory,
      coreMLModelsDirectory,
      coreMLSourcesDirectory,
      coreMLCompiledDirectory,
    ] {
      try manager.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try manager.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: directory.path
      )
    }
  }

  public static func purgeRuntimeDirectory() throws {
    try ensureDirectories()
    let manager = FileManager.default
    let entries = try manager.contentsOfDirectory(
      at: runtimeDirectory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )
    for entry in entries {
      try manager.removeItem(at: entry)
    }
  }

  private static var applicationSupportBaseDirectory: URL {
    FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support",
        isDirectory: true
      )
  }

  private static func migrateLegacyApplicationDirectoryIfNeeded() throws {
    let manager = FileManager.default
    let current = applicationSupportDirectory
    guard !manager.fileExists(atPath: current.path) else { return }

    let legacy = applicationSupportBaseDirectory.appendingPathComponent(
      legacyApplicationDirectoryName,
      isDirectory: true
    )
    guard manager.fileExists(atPath: legacy.path) else { return }

    try manager.moveItem(at: legacy, to: current)
  }
}

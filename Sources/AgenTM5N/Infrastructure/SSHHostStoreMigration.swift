import Foundation

public enum SSHHostStoreMigration {
  @discardableResult
  public static func repairDuplicateIdentifiersIfNeeded(at url: URL) throws -> Bool {
    let manager = FileManager.default
    guard manager.fileExists(atPath: url.path) else { return false }

    let originalData = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    var hosts = try decoder.decode([SSHHost].self, from: originalData)

    var seenIdentifiers = Set<UUID>()
    var repaired = false

    for index in hosts.indices {
      let host = hosts[index]
      if seenIdentifiers.insert(host.id).inserted {
        continue
      }

      hosts[index] = replacingIdentifier(of: host, with: UUID())
      repaired = true
    }

    guard repaired else { return false }

    let backupURL = uniqueBackupURL(for: url, manager: manager)
    try originalData.write(to: backupURL, options: [.atomic])
    try manager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: backupURL.path
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let repairedData = try encoder.encode(hosts)
    try repairedData.write(to: url, options: [.atomic])
    try manager.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: url.path
    )

    return true
  }

  private static func replacingIdentifier(
    of host: SSHHost,
    with identifier: UUID
  ) -> SSHHost {
    SSHHost(
      id: identifier,
      name: host.name,
      hostname: host.hostname,
      port: host.port,
      username: host.username,
      authenticationKind: host.authenticationKind,
      authenticationSecretID: host.authenticationSecretID,
      passphraseSecretID: host.passphraseSecretID,
      remoteCommand: host.remoteCommand,
      createdAt: host.createdAt,
      updatedAt: host.updatedAt
    )
  }

  private static func uniqueBackupURL(
    for url: URL,
    manager: FileManager
  ) -> URL {
    let baseName = url.lastPathComponent + ".before-id-repair"
    var candidate = url.deletingLastPathComponent().appendingPathComponent(baseName)
    var suffix = 2

    while manager.fileExists(atPath: candidate.path) {
      candidate = url.deletingLastPathComponent().appendingPathComponent(
        "\(baseName)-\(suffix)"
      )
      suffix += 1
    }

    return candidate
  }
}

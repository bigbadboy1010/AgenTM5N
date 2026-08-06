import Foundation

public enum SSHLaunchServiceError: LocalizedError {
  case missingAuthenticationSecret
  case invalidAuthenticationSecret(SecretKind)

  public var errorDescription: String? {
    switch self {
    case .missingAuthenticationSecret:
      "Für diesen SSH-Host ist kein passendes Secret hinterlegt."
    case .invalidAuthenticationSecret(let kind):
      "Der ausgewählte Secret-Typ \(kind.displayName) passt nicht zur SSH-Authentifizierung."
    }
  }
}

public struct SSHLaunchService: Sendable {
  public init() {}

  public func makeLaunch(
    host: SSHHost,
    authenticationSecret: VaultSecret?,
    passphraseSecret: VaultSecret?
  ) throws -> TerminalLaunch {
    let target = "\(host.username)@\(host.hostname)"
    var arguments = [
      "-p", String(host.port),
      "-o", "ServerAliveInterval=30",
      "-o", "ServerAliveCountMax=3",
      "-o", "StrictHostKeyChecking=accept-new",
    ]

    switch host.authenticationKind {
    case .systemDefault:
      return TerminalLaunch(
        title: host.name,
        initialCommand: sshCommand(
          environment: [:],
          arguments: arguments,
          target: target,
          remoteCommand: host.remoteCommand
        )
      )

    case .password:
      guard let authenticationSecret else {
        throw SSHLaunchServiceError.missingAuthenticationSecret
      }
      guard authenticationSecret.kind == .password else {
        throw SSHLaunchServiceError.invalidAuthenticationSecret(authenticationSecret.kind)
      }

      arguments.append(contentsOf: [
        "-o", "PreferredAuthentications=password,keyboard-interactive",
        "-o", "PubkeyAuthentication=no",
        "-o", "NumberOfPasswordPrompts=1",
      ])
      return try makeAskPassLaunch(
        host: host,
        target: target,
        arguments: arguments,
        secretValue: authenticationSecret.value,
        privateKey: nil
      )

    case .privateKey:
      guard let authenticationSecret else {
        throw SSHLaunchServiceError.missingAuthenticationSecret
      }
      guard authenticationSecret.kind == .sshPrivateKey else {
        throw SSHLaunchServiceError.invalidAuthenticationSecret(authenticationSecret.kind)
      }

      let directory = try makeSecureRuntimeDirectory()
      let keyFile = directory.appendingPathComponent("identity")
      try writeSecure(authenticationSecret.value, to: keyFile, permissions: 0o600)
      arguments.append(contentsOf: [
        "-i", keyFile.path,
        "-o", "IdentitiesOnly=yes",
      ])

      guard let passphrase = passphraseSecret?.value, !passphrase.isEmpty else {
        return TerminalLaunch(
          title: host.name,
          initialCommand: sshCommand(
            environment: [:],
            arguments: arguments,
            target: target,
            remoteCommand: host.remoteCommand
          ),
          cleanupPaths: [directory]
        )
      }

      return try makeAskPassLaunch(
        host: host,
        target: target,
        arguments: arguments,
        secretValue: passphrase,
        privateKey: keyFile,
        existingDirectory: directory
      )
    }
  }

  private func makeAskPassLaunch(
    host: SSHHost,
    target: String,
    arguments: [String],
    secretValue: String,
    privateKey: URL?,
    existingDirectory: URL? = nil
  ) throws -> TerminalLaunch {
    let directory = try existingDirectory ?? makeSecureRuntimeDirectory()
    let secretFile = directory.appendingPathComponent("askpass-secret.txt")
    let helperFile = directory.appendingPathComponent("askpass.zsh")

    try writeSecure(secretValue, to: secretFile, permissions: 0o600)
    try writeSecure(Self.askPassHelper, to: helperFile, permissions: 0o700)

    var environment = [
      "AGENTM5N_ASKPASS_SECRET": secretFile.path,
      "SSH_ASKPASS": helperFile.path,
      "SSH_ASKPASS_REQUIRE": "force",
      "DISPLAY": ":0",
    ]
    if let privateKey {
      environment["AGENTM5N_PRIVATE_KEY"] = privateKey.path
    }

    return TerminalLaunch(
      title: host.name,
      initialCommand: sshCommand(
        environment: environment,
        arguments: arguments,
        target: target,
        remoteCommand: host.remoteCommand
      ),
      cleanupPaths: [directory]
    )
  }

  private func sshCommand(
    environment: [String: String],
    arguments: [String],
    target: String,
    remoteCommand: String
  ) -> String {
    var parts: [String] = environment.keys.sorted().map { key in
      "\(key)=\(ShellEscaping.singleQuoted(environment[key] ?? ""))"
    }
    parts.append("/usr/bin/ssh")
    parts.append(contentsOf: arguments.map(ShellEscaping.singleQuoted))
    parts.append(ShellEscaping.singleQuoted(target))

    let trimmedRemoteCommand = remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmedRemoteCommand.isEmpty {
      parts.append(ShellEscaping.singleQuoted(trimmedRemoteCommand))
    }
    return parts.joined(separator: " ")
  }

  private func makeSecureRuntimeDirectory() throws -> URL {
    try AppPaths.ensureDirectories()
    let directory = AppPaths.runtimeDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    return directory
  }

  private func writeSecure(
    _ value: String,
    to url: URL,
    permissions: Int
  ) throws {
    guard let data = value.data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: permissions],
      ofItemAtPath: url.path
    )
  }

  private static let askPassHelper = #"""
    #!/bin/zsh
    set -euo pipefail
    if [[ -z "${AGENTM5N_ASKPASS_SECRET:-}" ]]; then
        exit 1
    fi
    /bin/cat -- "$AGENTM5N_ASKPASS_SECRET"
    """#
}

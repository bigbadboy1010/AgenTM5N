import SwiftUI

struct SSHHostsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var editingHost: SSHHost?
  @State private var showingEditor = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Remote-Macs und SSH-Systeme")
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          editingHost = nil
          showingEditor = true
        } label: {
          Label("Host hinzufügen", systemImage: "plus")
        }
      }
      .padding(12)

      Divider()

      if appState.sshHosts.isEmpty {
        ContentUnavailableView(
          "Keine SSH-Hosts",
          systemImage: "network",
          description: Text(
            "Füge einen Mac oder Server hinzu. Auf dem Ziel-Mac muss Remote Login aktiviert sein.")
        )
      } else {
        List {
          ForEach(appState.sshHosts) { host in
            SSHHostRow(host: host) {
              Task { await appState.connect(to: host) }
            } editAction: {
              editingHost = host
              showingEditor = true
            } deleteAction: {
              Task { await appState.deleteSSHHost(id: host.id) }
            }
          }
        }
      }
    }
    .navigationTitle("SSH")
    .sheet(isPresented: $showingEditor) {
      SSHHostEditorView(
        host: editingHost,
        secrets: appState.secrets,
        vaultUnlocked: appState.vaultUnlocked
      ) { host in
        let saved = await appState.saveSSHHost(host)
        if saved {
          showingEditor = false
        }
      }
      .frame(minWidth: 700, minHeight: 620)
    }
  }
}

private struct SSHHostRow: View {
  let host: SSHHost
  let connectAction: () -> Void
  let editAction: () -> Void
  let deleteAction: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "desktopcomputer")
        .font(.title2)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 4) {
        Text(host.name)
          .font(.headline)
        Text("\(host.username)@\(host.hostname):\(host.port)")
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
        Text(host.authenticationKind.displayName)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Spacer()

      Button("Verbinden", action: connectAction)
        .buttonStyle(.borderedProminent)

      Button(action: editAction) {
        Image(systemName: "pencil")
      }
      .help("Bearbeiten")

      Button(role: .destructive, action: deleteAction) {
        Image(systemName: "trash")
      }
      .help("Löschen")
    }
    .padding(.vertical, 7)
  }
}

private struct SSHHostEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: SSHHost
  @State private var isSaving = false
  let secrets: [VaultSecret]
  let vaultUnlocked: Bool
  let saveAction: (SSHHost) async -> Void

  init(
    host: SSHHost?,
    secrets: [VaultSecret],
    vaultUnlocked: Bool,
    saveAction: @escaping (SSHHost) async -> Void
  ) {
    _draft = State(
      initialValue: host
        ?? SSHHost(
          name: "",
          hostname: "",
          username: NSUserName()
        ))
    self.secrets = secrets
    self.vaultUnlocked = vaultUnlocked
    self.saveAction = saveAction
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(draft.name.isEmpty ? "SSH-Host hinzufügen" : "SSH-Host bearbeiten")
        .font(.title2.bold())

      Form {
        TextField("Name", text: $draft.name)
        TextField("Hostname / IP", text: $draft.hostname)
        TextField("Benutzername", text: $draft.username)
        TextField("Port", value: $draft.port, format: .number)

        Picker("Authentifizierung", selection: $draft.authenticationKind) {
          ForEach(SSHAuthenticationKind.allCases) { kind in
            Text(kind.displayName).tag(kind)
          }
        }
        .onChange(of: draft.authenticationKind) { _, kind in
          switch kind {
          case .systemDefault:
            draft.authenticationSecretID = nil
            draft.passphraseSecretID = nil
          case .password:
            draft.passphraseSecretID = nil
          case .privateKey:
            break
          }
        }

        if draft.authenticationKind == .password {
          if vaultUnlocked {
            Picker("Passwort-Secret", selection: $draft.authenticationSecretID) {
              Text("Nicht ausgewählt").tag(UUID?.none)
              ForEach(passwordSecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }
          } else {
            Text("Vault entsperren, um ein Passwort-Secret auszuwählen.")
              .foregroundStyle(.secondary)
          }
        }

        if draft.authenticationKind == .privateKey {
          if vaultUnlocked {
            Picker("Private-Key-Secret", selection: $draft.authenticationSecretID) {
              Text("Nicht ausgewählt").tag(UUID?.none)
              ForEach(privateKeySecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }

            Picker("Passphrase-Secret", selection: $draft.passphraseSecretID) {
              Text("Keine Passphrase").tag(UUID?.none)
              ForEach(passphraseSecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }
          } else {
            Text("Vault entsperren, um Private Key und Passphrase auszuwählen.")
              .foregroundStyle(.secondary)
          }
        }

        TextField("Remote Command beim Login", text: $draft.remoteCommand, axis: .vertical)
          .lineLimit(2...6)

        Text("Für macOS-Ziele: Systemeinstellungen → Allgemein → Teilen → Remote Login aktivieren.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("Abbrechen") {
          dismiss()
        }
        Button {
          isSaving = true
          Task {
            await saveAction(draft)
            isSaving = false
          }
        } label: {
          if isSaving {
            ProgressView()
              .controlSize(.small)
          } else {
            Text("Speichern")
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving || !isValid)
      }
    }
    .padding(24)
  }

  private var passwordSecrets: [VaultSecret] {
    secrets.filter { $0.kind == .password }
  }

  private var privateKeySecrets: [VaultSecret] {
    secrets.filter { $0.kind == .sshPrivateKey }
  }

  private var passphraseSecrets: [VaultSecret] {
    secrets.filter { $0.kind == .sshPassphrase || $0.kind == .password }
  }

  private var isValid: Bool {
    guard
      !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      (1...65_535).contains(draft.port)
    else {
      return false
    }

    switch draft.authenticationKind {
    case .systemDefault:
      return true
    case .password, .privateKey:
      return draft.authenticationSecretID != nil
    }
  }
}

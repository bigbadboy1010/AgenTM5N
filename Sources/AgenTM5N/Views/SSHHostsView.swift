import SwiftUI

private struct SSHHostEditorSession: Identifiable {
  let id = UUID()
  let host: SSHHost
  let isNew: Bool

  static func create() -> SSHHostEditorSession {
    SSHHostEditorSession(
      host: SSHHost(
        name: "",
        hostname: "",
        username: NSUserName()
      ),
      isNew: true
    )
  }

  static func edit(_ host: SSHHost) -> SSHHostEditorSession {
    SSHHostEditorSession(host: host, isNew: false)
  }
}

struct SSHHostsView: View {
  @EnvironmentObject private var appState: AppState
  @State private var editorSession: SSHHostEditorSession?

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(
            L10n.text(
              de: "Remote-Macs und SSH-Systeme",
              en: "Remote Macs and SSH Systems",
              fr: "Mac distants et systèmes SSH"
            )
          )
          .foregroundStyle(.secondary)

          if !appState.sshHosts.isEmpty {
            Text(
              L10n.text(
                de: "\(appState.sshHosts.count) gespeicherte Profile",
                en: "\(appState.sshHosts.count) saved profiles",
                fr: "\(appState.sshHosts.count) profils enregistrés"
              )
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
          }
        }

        Spacer()

        Button {
          editorSession = .create()
        } label: {
          Label(
            L10n.text(
              de: "Host hinzufügen",
              en: "Add Host",
              fr: "Ajouter un hôte"
            ),
            systemImage: "plus"
          )
        }
      }
      .padding(12)

      Divider()

      if appState.sshHosts.isEmpty {
        ContentUnavailableView(
          L10n.text(
            de: "Keine SSH-Hosts",
            en: "No SSH Hosts",
            fr: "Aucun hôte SSH"
          ),
          systemImage: "network",
          description: Text(
            L10n.text(
              de: "Füge einen Mac oder Server hinzu. Auf macOS-Zielen muss Remote Login aktiviert sein.",
              en: "Add a Mac or server. Remote Login must be enabled on macOS targets.",
              fr: "Ajoutez un Mac ou un serveur. La connexion à distance doit être activée sur les cibles macOS."
            )
          )
        )
      } else {
        List {
          ForEach(appState.sshHosts) { host in
            SSHHostRow(host: host) {
              Task { await appState.connect(to: host) }
            } editAction: {
              editorSession = .edit(host)
            } deleteAction: {
              Task { await appState.deleteSSHHost(id: host.id) }
            }
          }
        }
      }
    }
    .navigationTitle("SSH")
    .sheet(item: $editorSession, onDismiss: {
      editorSession = nil
    }) { session in
      SSHHostEditorView(
        host: session.host,
        isNew: session.isNew,
        existingHosts: appState.sshHosts,
        secrets: appState.secrets,
        vaultUnlocked: appState.vaultUnlocked
      ) { host in
        let saved = await appState.saveSSHHost(host)
        if saved {
          editorSession = nil
        }
      }
      .id(session.id)
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
        Text(authenticationTitle(host.authenticationKind))
          .font(.caption)
          .foregroundStyle(.tertiary)
      }

      Spacer()

      Button(
        L10n.text(de: "Verbinden", en: "Connect", fr: "Connecter"),
        action: connectAction
      )
      .buttonStyle(.borderedProminent)

      Button(action: editAction) {
        Image(systemName: "pencil")
      }
      .help(L10n.text(de: "Bearbeiten", en: "Edit", fr: "Modifier"))

      Button(role: .destructive, action: deleteAction) {
        Image(systemName: "trash")
      }
      .help(L10n.text(de: "Löschen", en: "Delete", fr: "Supprimer"))
    }
    .padding(.vertical, 7)
  }

  private func authenticationTitle(_ kind: SSHAuthenticationKind) -> String {
    switch kind {
    case .systemDefault:
      return L10n.text(
        de: "System / SSH-Agent",
        en: "System / SSH Agent",
        fr: "Système / Agent SSH"
      )
    case .password:
      return L10n.text(de: "Passwort", en: "Password", fr: "Mot de passe")
    case .privateKey:
      return L10n.text(
        de: "Privater Schlüssel",
        en: "Private Key",
        fr: "Clé privée"
      )
    }
  }
}

private struct SSHHostEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: SSHHost
  @State private var isSaving = false

  let isNew: Bool
  let existingHosts: [SSHHost]
  let secrets: [VaultSecret]
  let vaultUnlocked: Bool
  let saveAction: (SSHHost) async -> Void

  init(
    host: SSHHost,
    isNew: Bool,
    existingHosts: [SSHHost],
    secrets: [VaultSecret],
    vaultUnlocked: Bool,
    saveAction: @escaping (SSHHost) async -> Void
  ) {
    _draft = State(initialValue: host)
    self.isNew = isNew
    self.existingHosts = existingHosts
    self.secrets = secrets
    self.vaultUnlocked = vaultUnlocked
    self.saveAction = saveAction
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        isNew
          ? L10n.text(
            de: "SSH-Host hinzufügen",
            en: "Add SSH Host",
            fr: "Ajouter un hôte SSH"
          )
          : L10n.text(
            de: "SSH-Host bearbeiten",
            en: "Edit SSH Host",
            fr: "Modifier l’hôte SSH"
          )
      )
      .font(.title2.bold())

      Form {
        TextField(
          L10n.text(de: "Name", en: "Name", fr: "Nom"),
          text: $draft.name
        )

        if nameConflict {
          Label(
            L10n.text(
              de: "Dieser Profilname wird bereits verwendet. SSH-Profilnamen müssen eindeutig sein.",
              en: "This profile name is already in use. SSH profile names must be unique.",
              fr: "Ce nom de profil est déjà utilisé. Les noms de profils SSH doivent être uniques."
            ),
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.caption)
          .foregroundStyle(.red)
        }

        TextField(
          L10n.text(de: "Hostname / IP", en: "Hostname / IP", fr: "Nom d’hôte / IP"),
          text: $draft.hostname
        )
        TextField(
          L10n.text(de: "Benutzername", en: "Username", fr: "Nom d’utilisateur"),
          text: $draft.username
        )
        TextField(
          L10n.text(de: "Port", en: "Port", fr: "Port"),
          value: $draft.port,
          format: .number
        )

        Picker(
          L10n.text(
            de: "Authentifizierung",
            en: "Authentication",
            fr: "Authentification"
          ),
          selection: $draft.authenticationKind
        ) {
          ForEach(SSHAuthenticationKind.allCases) { kind in
            Text(authenticationTitle(kind)).tag(kind)
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
            Picker(
              L10n.text(
                de: "Passwort-Eintrag",
                en: "Password Entry",
                fr: "Entrée de mot de passe"
              ),
              selection: $draft.authenticationSecretID
            ) {
              Text(
                L10n.text(
                  de: "Nicht ausgewählt",
                  en: "Not Selected",
                  fr: "Non sélectionné"
                )
              )
              .tag(UUID?.none)
              ForEach(passwordSecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }
          } else {
            Text(
              L10n.text(
                de: "Tresor entsperren, um einen Passwort-Eintrag auszuwählen.",
                en: "Unlock the vault to select a password entry.",
                fr: "Déverrouillez le coffre pour sélectionner une entrée de mot de passe."
              )
            )
            .foregroundStyle(.secondary)
          }
        }

        if draft.authenticationKind == .privateKey {
          if vaultUnlocked {
            Picker(
              L10n.text(
                de: "Private-Key-Eintrag",
                en: "Private Key Entry",
                fr: "Entrée de clé privée"
              ),
              selection: $draft.authenticationSecretID
            ) {
              Text(
                L10n.text(
                  de: "Nicht ausgewählt",
                  en: "Not Selected",
                  fr: "Non sélectionné"
                )
              )
              .tag(UUID?.none)
              ForEach(privateKeySecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }

            Picker(
              L10n.text(
                de: "Passphrase-Eintrag",
                en: "Passphrase Entry",
                fr: "Entrée de phrase secrète"
              ),
              selection: $draft.passphraseSecretID
            ) {
              Text(
                L10n.text(
                  de: "Keine Passphrase",
                  en: "No Passphrase",
                  fr: "Aucune phrase secrète"
                )
              )
              .tag(UUID?.none)
              ForEach(passphraseSecrets) { secret in
                Text(secret.label).tag(Optional(secret.id))
              }
            }
          } else {
            Text(
              L10n.text(
                de: "Tresor entsperren, um Private Key und Passphrase auszuwählen.",
                en: "Unlock the vault to select a private key and passphrase.",
                fr: "Déverrouillez le coffre pour sélectionner une clé privée et une phrase secrète."
              )
            )
            .foregroundStyle(.secondary)
          }
        }

        TextField(
          L10n.text(
            de: "Remote-Kommando beim Login",
            en: "Remote Command at Login",
            fr: "Commande distante à la connexion"
          ),
          text: $draft.remoteCommand,
          axis: .vertical
        )
        .lineLimit(2...6)

        Text(
          L10n.text(
            de: "Für macOS-Ziele: Systemeinstellungen → Allgemein → Teilen → Remote Login aktivieren.",
            en: "For macOS targets: System Settings → General → Sharing → enable Remote Login.",
            fr: "Pour les cibles macOS : Réglages Système → Général → Partage → activer Session à distance."
          )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .formStyle(.grouped)

      HStack {
        if isNew {
          Label(
            L10n.text(
              de: "Dieses Profil erhält eine neue eindeutige ID.",
              en: "This profile receives a new unique ID.",
              fr: "Ce profil reçoit un nouvel identifiant unique."
            ),
            systemImage: "checkmark.shield"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }

        Spacer()

        Button(
          L10n.text(de: "Abbrechen", en: "Cancel", fr: "Annuler")
        ) {
          dismiss()
        }

        Button {
          isSaving = true
          Task {
            await saveAction(normalizedDraft)
            isSaving = false
          }
        } label: {
          if isSaving {
            ProgressView()
              .controlSize(.small)
          } else {
            Text(L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer"))
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving || !isValid)
      }
    }
    .padding(24)
  }

  private var normalizedDraft: SSHHost {
    var value = draft
    value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
    value.hostname = value.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
    value.username = value.username.trimmingCharacters(in: .whitespacesAndNewlines)
    value.remoteCommand = value.remoteCommand.trimmingCharacters(in: .whitespacesAndNewlines)
    return value
  }

  private var normalizedName: String {
    draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var nameConflict: Bool {
    guard !normalizedName.isEmpty else { return false }
    return existingHosts.contains { host in
      host.id != draft.id
        && host.name.trimmingCharacters(in: .whitespacesAndNewlines)
          .caseInsensitiveCompare(normalizedName) == .orderedSame
    }
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
    let value = normalizedDraft
    guard
      !value.name.isEmpty,
      !value.hostname.isEmpty,
      !value.username.isEmpty,
      !nameConflict,
      (1...65_535).contains(value.port)
    else {
      return false
    }

    switch value.authenticationKind {
    case .systemDefault:
      return true
    case .password, .privateKey:
      return value.authenticationSecretID != nil
    }
  }

  private func authenticationTitle(_ kind: SSHAuthenticationKind) -> String {
    switch kind {
    case .systemDefault:
      return L10n.text(
        de: "System / SSH-Agent",
        en: "System / SSH Agent",
        fr: "Système / Agent SSH"
      )
    case .password:
      return L10n.text(de: "Passwort", en: "Password", fr: "Mot de passe")
    case .privateKey:
      return L10n.text(
        de: "Privater Schlüssel",
        en: "Private Key",
        fr: "Clé privée"
      )
    }
  }
}

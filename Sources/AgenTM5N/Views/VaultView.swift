import SwiftUI

struct VaultView: View {
  @EnvironmentObject private var appState: AppState
  @State private var masterPassword = ""
  @State private var editingSecret: VaultSecret?
  @State private var showingSecretEditor = false

  var body: some View {
    Group {
      if appState.vaultUnlocked {
        unlockedView
      } else {
        lockedView
      }
    }
    .navigationTitle(
      L10n.text(
        de: "Sicherer Tresor",
        en: "Secure Vault",
        fr: "Coffre sécurisé"
      )
    )
    .sheet(isPresented: $showingSecretEditor) {
      SecretEditorView(secret: editingSecret) { secret in
        let saved = await appState.upsertSecret(secret)
        if saved {
          showingSecretEditor = false
        }
      }
      .frame(minWidth: 620, minHeight: 560)
    }
  }

  private var lockedView: some View {
    VStack(spacing: 18) {
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 64))
        .foregroundStyle(.secondary)

      Text(
        FileManager.default.fileExists(atPath: AppPaths.vaultFile.path)
          ? L10n.text(de: "Tresor entsperren", en: "Unlock Vault", fr: "Déverrouiller le coffre")
          : L10n.text(de: "Neuen Tresor erstellen", en: "Create New Vault", fr: "Créer un nouveau coffre")
      )
      .font(.title2.bold())

      Text(
        L10n.text(
          de: "Das Master-Passwort wird nicht gespeichert. API Keys, Tokens, Passwörter und SSH-Schlüssel werden als AES-256-GCM-Payload verschlüsselt.",
          en: "The master password is not stored. API keys, tokens, passwords, and SSH keys are encrypted as an AES-256-GCM payload.",
          fr: "Le mot de passe maître n’est pas stocké. Les clés API, jetons, mots de passe et clés SSH sont chiffrés dans une charge utile AES-256-GCM."
        )
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 520)

      SecureField(
        L10n.text(de: "Master-Passwort", en: "Master Password", fr: "Mot de passe maître"),
        text: $masterPassword
      )
      .textFieldStyle(.roundedBorder)
      .frame(width: 360)
      .onSubmit {
        unlock()
      }

      Button(L10n.text(de: "Entsperren", en: "Unlock", fr: "Déverrouiller")) {
        unlock()
      }
      .keyboardShortcut(.defaultAction)
      .disabled(masterPassword.isEmpty)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
  }

  private var unlockedView: some View {
    VStack(spacing: 0) {
      HStack {
        Text(
          L10n.text(
            de: "\(appState.secrets.count) Einträge",
            en: "\(appState.secrets.count) Entries",
            fr: "\(appState.secrets.count) entrées"
          )
        )
        .foregroundStyle(.secondary)
        Spacer()
        Button {
          editingSecret = nil
          showingSecretEditor = true
        } label: {
          Label(
            L10n.text(de: "Eintrag hinzufügen", en: "Add Entry", fr: "Ajouter une entrée"),
            systemImage: "plus"
          )
        }
        Button {
          Task { await appState.lockVault() }
        } label: {
          Label(
            L10n.text(de: "Sperren", en: "Lock", fr: "Verrouiller"),
            systemImage: "lock"
          )
        }
      }
      .padding(12)

      Divider()

      if appState.secrets.isEmpty {
        ContentUnavailableView(
          L10n.text(de: "Keine Einträge", en: "No Entries", fr: "Aucune entrée"),
          systemImage: "key",
          description: Text(
            L10n.text(
              de: "Lege API Keys, Tokens, Passwörter oder private SSH-Schlüssel an.",
              en: "Add API keys, tokens, passwords, or private SSH keys.",
              fr: "Ajoutez des clés API, jetons, mots de passe ou clés SSH privées."
            )
          )
        )
      } else {
        List {
          ForEach(appState.secrets) { secret in
            VaultSecretRow(secret: secret) {
              editingSecret = secret
              showingSecretEditor = true
            } copyAction: {
              Task { await appState.copySecretToClipboard(id: secret.id) }
            } deleteAction: {
              Task { await appState.deleteSecret(id: secret.id) }
            }
          }
        }
      }
    }
  }

  private func unlock() {
    let password = masterPassword
    masterPassword = ""
    Task {
      _ = await appState.unlockVault(password: password)
    }
  }
}

private struct VaultSecretRow: View {
  let secret: VaultSecret
  let editAction: () -> Void
  let copyAction: () -> Void
  let deleteAction: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: iconName)
        .frame(width: 24)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 3) {
        Text(secret.label)
          .font(.headline)
        HStack(spacing: 8) {
          Text(kindTitle(secret.kind))
          if !secret.username.isEmpty {
            Text(secret.username)
          }
          if !secret.host.isEmpty {
            Text(secret.host)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      Spacer()

      Text(secret.redactedValue)
        .font(.system(.body, design: .monospaced))
        .foregroundStyle(.secondary)

      Button(action: copyAction) {
        Image(systemName: "doc.on.doc")
      }
      .help(L10n.text(de: "Wert kopieren", en: "Copy Value", fr: "Copier la valeur"))

      Button(action: editAction) {
        Image(systemName: "pencil")
      }
      .help(L10n.text(de: "Bearbeiten", en: "Edit", fr: "Modifier"))

      Button(role: .destructive, action: deleteAction) {
        Image(systemName: "trash")
      }
      .help(L10n.text(de: "Löschen", en: "Delete", fr: "Supprimer"))
    }
    .padding(.vertical, 5)
  }

  private func kindTitle(_ kind: SecretKind) -> String {
    switch kind {
    case .apiKey:
      return "API Key"
    case .token:
      return "Token"
    case .password:
      return L10n.text(de: "Passwort", en: "Password", fr: "Mot de passe")
    case .sshPrivateKey:
      return L10n.text(de: "Privater SSH-Schlüssel", en: "SSH Private Key", fr: "Clé SSH privée")
    case .sshPassphrase:
      return L10n.text(de: "SSH-Passphrase", en: "SSH Passphrase", fr: "Phrase secrète SSH")
    case .databaseConnectionString:
      return L10n.text(de: "Datenbank-Verbindungszeichenfolge", en: "Database Connection String", fr: "Chaîne de connexion à la base")
    case .generic:
      return L10n.text(de: "Allgemeiner Eintrag", en: "Generic Entry", fr: "Entrée générique")
    }
  }

  private var iconName: String {
    switch secret.kind {
    case .apiKey, .token: "key.horizontal"
    case .password, .sshPassphrase: "lock"
    case .sshPrivateKey: "terminal"
    case .databaseConnectionString: "cylinder"
    case .generic: "doc.text"
    }
  }
}

private struct SecretEditorView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draft: VaultSecret
  @State private var isSaving = false
  let saveAction: (VaultSecret) async -> Void

  init(
    secret: VaultSecret?,
    saveAction: @escaping (VaultSecret) async -> Void
  ) {
    _draft = State(
      initialValue: secret
        ?? VaultSecret(
          kind: .apiKey,
          label: "",
          value: ""
        ))
    self.saveAction = saveAction
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(
        draft.label.isEmpty
          ? L10n.text(de: "Eintrag hinzufügen", en: "Add Entry", fr: "Ajouter une entrée")
          : L10n.text(de: "Eintrag bearbeiten", en: "Edit Entry", fr: "Modifier l’entrée")
      )
      .font(.title2.bold())

      Form {
        Picker(L10n.text(de: "Typ", en: "Type", fr: "Type"), selection: $draft.kind) {
          ForEach(SecretKind.allCases) { kind in
            Text(kind.rawValue).tag(kind)
          }
        }

        TextField(L10n.text(de: "Bezeichnung", en: "Label", fr: "Libellé"), text: $draft.label)
        TextField(L10n.text(de: "Benutzername", en: "Username", fr: "Nom d’utilisateur"), text: $draft.username)
        TextField(L10n.text(de: "Host oder Dienst", en: "Host or Service", fr: "Hôte ou service"), text: $draft.host)

        if draft.kind == .sshPrivateKey || draft.kind == .databaseConnectionString {
          TextEditor(text: $draft.value)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 180)
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        } else {
          SecureField(L10n.text(de: "Geheimwert", en: "Secret Value", fr: "Valeur secrète"), text: $draft.value)
        }

        TextField(L10n.text(de: "Notizen", en: "Notes", fr: "Notes"), text: $draft.notes, axis: .vertical)
          .lineLimit(2...5)
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button(L10n.text(de: "Abbrechen", en: "Cancel", fr: "Annuler")) {
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
            Text(L10n.text(de: "Speichern", en: "Save", fr: "Enregistrer"))
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(
          isSaving || draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.value.isEmpty
        )
      }
    }
    .padding(24)
  }
}

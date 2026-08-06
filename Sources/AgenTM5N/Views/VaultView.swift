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
    .navigationTitle("Secret Vault")
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
          ? "Vault entsperren"
          : "Neuen Vault erstellen"
      )
      .font(.title2.bold())

      Text(
        "Das Master-Passwort wird nicht gespeichert. API Keys, Tokens, Passwörter und SSH Keys werden als AES-256-GCM-Payload verschlüsselt."
      )
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 520)

      SecureField("Master-Passwort", text: $masterPassword)
        .textFieldStyle(.roundedBorder)
        .frame(width: 360)
        .onSubmit {
          unlock()
        }

      Button("Entsperren") {
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
        Text("\(appState.secrets.count) Secrets")
          .foregroundStyle(.secondary)
        Spacer()
        Button {
          editingSecret = nil
          showingSecretEditor = true
        } label: {
          Label("Secret hinzufügen", systemImage: "plus")
        }
        Button {
          Task { await appState.lockVault() }
        } label: {
          Label("Sperren", systemImage: "lock")
        }
      }
      .padding(12)

      Divider()

      if appState.secrets.isEmpty {
        ContentUnavailableView(
          "Keine Secrets",
          systemImage: "key",
          description: Text("Lege API Keys, Tokens, Passwörter oder SSH Private Keys an.")
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
          Text(secret.kind.displayName)
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
      .help("Secret kopieren")

      Button(action: editAction) {
        Image(systemName: "pencil")
      }
      .help("Bearbeiten")

      Button(role: .destructive, action: deleteAction) {
        Image(systemName: "trash")
      }
      .help("Löschen")
    }
    .padding(.vertical, 5)
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
      Text(draft.label.isEmpty ? "Secret hinzufügen" : "Secret bearbeiten")
        .font(.title2.bold())

      Form {
        Picker("Typ", selection: $draft.kind) {
          ForEach(SecretKind.allCases) { kind in
            Text(kind.displayName).tag(kind)
          }
        }

        TextField("Bezeichnung", text: $draft.label)
        TextField("Benutzername", text: $draft.username)
        TextField("Host / Dienst", text: $draft.host)

        if draft.kind == .sshPrivateKey || draft.kind == .databaseConnectionString {
          TextEditor(text: $draft.value)
            .font(.system(.body, design: .monospaced))
            .frame(minHeight: 180)
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
        } else {
          SecureField("Secret-Wert", text: $draft.value)
        }

        TextField("Notizen", text: $draft.notes, axis: .vertical)
          .lineLimit(2...5)
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
        .disabled(
          isSaving || draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draft.value.isEmpty
        )
      }
    }
    .padding(24)
  }
}

# AgenTM5N 1.0.1 — Build 23

Release date: 2026-08-08

## Scope

AgenTM5N 1.0.1 closes the operational-tool gap between Apple On-Device Foundation Models and the Ollama providers.

### Apple On-Device operational tools

When the current task is operational, Apple Foundation Models can now receive routed adapters for the existing AgenTM5N runtime tools:

- `list_directory`
- `glob_files`
- `search_text`
- `read_file`
- `apply_patch`
- `write_file`
- `run_command`
- `terminal_open`
- `ssh_list_hosts`
- `ssh_run`
- `ssh_open_terminal`
- `git_status`
- `git_diff`
- `git_branches`
- `git_checkout`
- `git_commit`

All adapters create ordinary `ProviderToolCall` values and route them through `AgentToolExecutionBridge`. The existing AppState permission, audit and execution path remains authoritative.

## Task-scoped tool loading

The Apple on-device model has a relatively small context budget, and Foundation Models tool schemas contribute to that context. AgenTM5N therefore selects tool packs from the recent user request instead of registering every application tool for every turn.

Operational terms such as SSH, server, Docker, Linux, terminal, Git, repository, workspace, file, log, VM, Kubernetes and OpenShift activate the operational pack.

Calendar/Contacts/Mail terms activate the native Mac pack. Agent-related terms activate the persistent-agent pack. Multiple packs can be active in the same turn when the request spans multiple domains.

## SSH and Vault secrets

Apple On-Device never receives SSH password, private-key, passphrase or Vault secret values.

The flow is:

1. Apple calls `ssh_list_hosts` and sees only non-secret host metadata plus whether credentials are configured.
2. Apple calls `ssh_run` or `ssh_open_terminal` using the saved host profile name/hostname/UUID.
3. AgenTM5N resolves `authenticationSecretID` and `passphraseSecretID` internally through the already-unlocked encrypted Vault.
4. The existing SSH launch service creates the local execution/terminal launch.
5. Temporary runtime files are cleaned up by the existing SSH tool implementation.
6. Only bounded command output is returned to the model.

The model must never request or echo a secret value.

Generic arbitrary Vault-secret injection into shell/API calls is intentionally not included in 1.0.1. That capability needs a separate redaction-aware audit path so a command cannot accidentally echo a secret into model output or the persistent tool audit.

## Version

- App version: `1.0.1`
- Build: `23`
- Bundle ID: `team.cloudforge.AgenTM5N`
- Architecture: arm64

## Build gate

```bash
cd ~/Downloads/AgenTM5N
git fetch origin
git switch agent/v1.0.1-unified-tools
git pull --ff-only origin agent/v1.0.1-unified-tools

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm Package.resolved
bash scripts/verify.sh
bash scripts/build-app.sh
bash scripts/check-release.sh
open dist/AgenTM5N.app
```

Expected development version:

```text
Version: 1.0.1 Build 23
```

## Apple On-Device smoke tests

Select Apple On-Device and keep Agent mode enabled.

### 1. Discover SSH hosts

```text
Zeige mir meine gespeicherten SSH-Verbindungen. Zeige keine Passwörter, Keys oder Secret-Werte.
```

Expected tool: `ssh_list_hosts`.

### 2. Remote read command

```text
Verbinde dich per SSH mit <GESPEICHERTES_PROFIL> und führe uname -a aus.
```

Expected tool: `ssh_run`, central execution approval, audit record, remote output.

### 3. Secret-backed SSH authentication

Use a saved SSH profile whose password/private key/passphrase is already linked to the AgenTM5N Vault. Do not provide credentials in the prompt.

```text
Verbinde dich per SSH mit <GESPEICHERTES_PROFIL> und führe whoami aus.
```

Expected: successful authentication using the internally referenced Vault secret. The model output and audit must not contain the secret value.

### 4. Docker remote command

```text
Verbinde dich per SSH mit <GESPEICHERTES_PROFIL> und zeige docker ps --format 'table {{.Names}}\t{{.Status}}'.
```

Expected: `ssh_run`, central approval, bounded output.

### 5. Local workspace tool

```text
Zeige mir den Git-Status meines aktuellen Workspace und liste die Swift-Dateien unter Sources auf.
```

Expected: `git_status` plus `glob_files` or equivalent operational tools.

### 6. Regression

After operational tests, verify Apple On-Device still handles:

- Calendar read/create/delete
- Contacts search
- Apple Mail draft creation
- persistent agent list/use

## Release gate

Only after all smoke tests pass:

```bash
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

Expected artifact:

```text
dist/AgenTM5N-1.0.1-build23.dmg
```

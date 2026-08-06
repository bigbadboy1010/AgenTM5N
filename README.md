# AgenTM5N

AgenTM5N is a native personal AI agent for Apple Silicon. It combines Ollama
Cloud, local Ollama models, Apple Foundation Models, Core ML acceleration, an
encrypted credential vault, an embedded terminal, structured SSH access and a
controlled tool-calling runtime.

> Status: 0.2.2 development candidate for macOS 26 and Apple Silicon.

## Current capabilities

- Native SwiftUI application for Apple Silicon and macOS 26+
- Ollama Local through `http://localhost:11434/api`
- Ollama Cloud through `https://ollama.com/api`
- NDJSON streaming for `/api/chat`
- Multi-turn Ollama tool calling with streamed `tool_calls`
- Permission modes: Confirm, Workspace Trusted and Full Access
- Directory listing, recursive globs and native UTF-8 repository search
- File reading, complete-file writing and exact single-occurrence patch editing
- Local shell commands with timeout, bounded output and exit status
- Git status, diff, branch inventory, safe checkout/create and path-scoped local
  commits without push
- Visible local terminal opening
- Saved SSH host inventory, structured remote execution and interactive SSH
  terminal opening without exposing Vault secrets to the model
- Equivalent local tool-call repetition guard
- Per-tool approval and persisted execution audit cards
- Apple on-device Foundation Models provider
- AES-256-GCM encrypted vault for API keys, tokens, passwords, SSH private
  keys, passphrases and connection strings
- PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 256-bit salt
- Embedded Zsh PTY using SwiftTerm 1.11.0 with CoreText rendering
- Core ML model loading with `MLComputeUnits.cpuAndNeuralEngine`

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- full Xcode 26 or newer
- Apple Intelligence enabled for Apple Foundation Models
- Ollama Local or an Ollama Cloud API key

The standalone Command Line Tools package is not sufficient because AgenTM5N
links AppKit, Core ML and Foundation Models from the full macOS SDK.

## Build the stable main branch

```bash
git clone https://github.com/bigbadboy1010/AgenTM5N.git
cd AgenTM5N

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/bootstrap-xcode.sh
rm -rf .build .swiftpm Package.resolved dist
bash scripts/verify.sh
bash scripts/build-app.sh
open dist/AgenTM5N.app
```

## Test 0.2.2 workspace engineering tools

```bash
cd ~/Downloads/AgenTM5N
git fetch --prune origin
git checkout agent/workspace-engineering-tools
git pull --ff-only origin agent/workspace-engineering-tools

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export DEVELOPER_DIR="$AGENTM5N_XCODE_PATH"

bash scripts/bootstrap-xcode.sh
bash scripts/verify.sh
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/AgenTM5N.app
open dist/AgenTM5N.app
```

Expected bundle version: `0.2.2` build `7`.

The build scripts automatically search these locations:

```text
/Applications/Xcode.app
/Applications/Xcode-beta.app
~/Applications/Xcode.app
~/Applications/Xcode-beta.app
~/Downloads/Xcode.app
~/Downloads/Xcode-beta.app
```

## Agent runtime setup

1. Open `Settings`.
2. Select Ollama Local or Ollama Cloud.
3. Enable `Tool Calling`.
4. Choose a workspace directory.
5. Start with permission mode `Confirm`.
6. Save the configuration and create a new chat session.

Recommended read-only prompt:

```text
Use glob_files to find Swift sources, search_text to locate AgentRuntime, read
the relevant files and summarize the implementation. Do not modify files.
```

Recommended targeted-edit prompt:

```text
Read README.md, change one exact sentence with apply_patch, show git_diff and do
not commit until I approve the result.
```

`apply_patch` fails when the old text is absent or appears more than once. This
prevents broad or ambiguous replacements.

## Permission modes

- **Confirm:** reads run within the workspace; writes, patches, Git mutations,
  local commands and terminal opens require approval.
- **Workspace Trusted:** local workspace tools run automatically; remote SSH
  execution and SSH terminal opening still require approval.
- **Full Access:** filesystem paths outside the workspace and local or remote
  execution are allowed; tool calls remain audited.

See [Agent Runtime](docs/AGENT_RUNTIME.md), [Workspace Engineering Tools](docs/WORKSPACE_ENGINEERING_TOOLS.md)
and [SSH Agent Tools](docs/SSH_AGENT_TOOLS.md) for the complete execution and
security model.

## Ollama Cloud configuration

1. Open `Vault` and create or unlock the encrypted vault.
2. Store an API key secret.
3. Open `Settings`.
4. Select `Ollama Cloud`.
5. Use `https://ollama.com` as the base URL.
6. Select the stored API key.
7. Enter a model name or load the available models.

## SSH access to another Mac

On the target Mac enable `System Settings > General > Sharing > Remote Login`.
Then create a host profile under `SSH`. Passwords, private keys and passphrases
are resolved internally from the encrypted AgenTM5N vault.

Runtime credential material is created with restrictive POSIX permissions and
removed when structured execution ends, the terminal session closes or
AgenTM5N starts again.

## Apple Neural Engine

The Neural Engine view accepts `.mlmodel`, `.mlpackage` and `.mlmodelc` files.
Models are loaded using:

```swift
let configuration = MLModelConfiguration()
configuration.computeUnits = .cpuAndNeuralEngine
```

Core ML decides the final placement of supported operators. AgenTM5N reports
the requested compute policy rather than claiming every operator executed on
the Neural Engine.

## Data directories

```text
~/Library/Application Support/AgenTM5N/configuration.json
~/Library/Application Support/AgenTM5N/conversation.json
~/Library/Application Support/AgenTM5N/ssh-hosts.json
~/Library/Application Support/AgenTM5N/vault.json
~/Library/Application Support/AgenTM5N/Runtime/
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Agent Runtime](docs/AGENT_RUNTIME.md)
- [Workspace Engineering Tools](docs/WORKSPACE_ENGINEERING_TOOLS.md)
- [SSH Agent Tools](docs/SSH_AGENT_TOOLS.md)
- [Security model](docs/SECURITY.md)
- [Build troubleshooting](docs/TROUBLESHOOTING.md)
- [Roadmap](docs/ROADMAP.md)
- [Validation status](VALIDATION.md)

## License

GNU General Public License v3.0. Third-party components retain their respective
licenses.

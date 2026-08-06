# AgenTM5N

AgenTM5N is a native personal AI agent for Apple Silicon. It combines Ollama
Cloud, local Ollama models, Apple Foundation Models, Core ML acceleration, an
encrypted credential vault, an embedded terminal, SSH access and a controlled
tool-calling runtime.

> Status: 0.2.0 development candidate for macOS 26 and Apple Silicon.

## Current capabilities

- Native SwiftUI application for Apple Silicon and macOS 26+
- Ollama Local through `http://localhost:11434/api`
- Ollama Cloud through `https://ollama.com/api`
- NDJSON streaming for `/api/chat`
- Multi-turn Ollama tool calling with streamed `tool_calls`
- Permission modes: Confirm, Workspace Trusted and Full Access
- Directory listing, file reading/writing, shell commands, Git status and diff
- Per-tool approval and persisted execution audit cards
- Command timeout, workspace boundaries and bounded tool output
- Apple on-device Foundation Models provider
- AES-256-GCM encrypted vault for API keys, tokens, passwords, SSH private
  keys, passphrases and connection strings
- PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 256-bit salt
- Embedded Zsh PTY using SwiftTerm 1.11.0 with CoreText rendering
- SSH profiles for remote Macs and servers
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

## Test Milestone 2

```bash
cd ~/Downloads/AgenTM5N
git fetch --prune origin
git checkout agent/milestone-2-runtime
git pull --ff-only origin agent/milestone-2-runtime

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm Package.resolved dist
bash scripts/bootstrap-xcode.sh
bash scripts/verify.sh
bash scripts/build-app.sh
open dist/AgenTM5N.app
```

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
6. Save the configuration.

Recommended first prompt:

```text
Inspect the current workspace. Show the Git status, list the top-level files,
read the README and summarize what this project does. Do not modify files.
```

Then test explicit write approval:

```text
Create a file named agentm5n-tool-test.txt containing a one-line timestamped
message, then read it back and report the result.
```

In Confirm mode, the write operation must display a one-time approval banner.

## Permission modes

- **Confirm:** reads run within the workspace; writes and commands require
  approval.
- **Workspace Trusted:** tools run automatically but filesystem access remains
  inside the workspace.
- **Full Access:** filesystem paths outside the workspace and unrestricted shell
  commands are allowed; tool calls remain audited.

See [Agent Runtime](docs/AGENT_RUNTIME.md) for the complete execution and
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
can be read from the encrypted AgenTM5N vault.

Runtime credential material is created with restrictive POSIX permissions and
removed when the terminal session closes or AgenTM5N starts again.

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
- [Security model](docs/SECURITY.md)
- [Build troubleshooting](docs/TROUBLESHOOTING.md)
- [Roadmap](docs/ROADMAP.md)
- [Validation status](VALIDATION.md)

## License

GNU General Public License v3.0. Third-party components retain their respective
licenses.

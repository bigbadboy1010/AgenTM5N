# AgenTM5N

AgenTM5N is a native personal AI agent for Apple Silicon. It combines Ollama
Cloud, local Ollama models, Apple Foundation Models, Core ML acceleration,
an encrypted credential vault, an embedded terminal and SSH access.

> Status: early macOS MVP. The current release is intended for development and
> controlled personal use.

## Current capabilities

- Native SwiftUI application for Apple Silicon and macOS 26+
- Ollama Local through `http://localhost:11434/api`
- Ollama Cloud through `https://ollama.com/api`
- NDJSON streaming for `/api/chat`
- Model discovery through `/api/tags`
- Apple on-device Foundation Models provider
- AES-256-GCM encrypted vault for API keys, tokens, passwords, SSH private
  keys, passphrases and connection strings
- PBKDF2-HMAC-SHA256 with 600,000 iterations and a random 256-bit salt
- Embedded Zsh PTY using SwiftTerm
- SSH profiles for remote Macs and servers
- Core ML model loading with `MLComputeUnits.cpuAndNeuralEngine`
- Local provider configuration, conversation history and SSH profiles

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- full Xcode 26 or newer
- optional Metal Toolchain component for Xcode
- Apple Intelligence enabled for Apple Foundation Models
- Ollama Local or an Ollama Cloud API key

The standalone Command Line Tools package is not sufficient. SwiftTerm contains
Metal shaders. Xcode 26 additionally distributes the Metal Toolchain as an
optional component.

## Build

```bash
git clone --branch agent/initial-macos-mvp \
  https://github.com/bigbadboy1010/AgenTM5N.git
cd AgenTM5N

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/bootstrap-xcode.sh
bash scripts/verify.sh
bash scripts/build-app.sh
open dist/AgenTM5N.app
```

The scripts automatically search these locations:

```text
/Applications/Xcode.app
/Applications/Xcode-beta.app
~/Applications/Xcode.app
~/Applications/Xcode-beta.app
~/Downloads/Xcode.app
~/Downloads/Xcode-beta.app
```

A custom location can be supplied without changing the global developer path:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
```

## Fix for `unable to spawn process 'metal'`

Your original log shows that SwiftPM used this developer directory:

```text
/Library/Developer/CommandLineTools
```

That package does not provide the complete Xcode/Metal build environment. Run:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/bootstrap-xcode.sh
rm -rf .build .swiftpm
bash scripts/verify.sh
bash scripts/build-app.sh
```

The bootstrap initializes Xcode and installs the optional component using:

```bash
xcodebuild -downloadComponent metalToolchain
```

To switch the entire Mac permanently instead:

```bash
sudo xcode-select --switch "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
sudo xcodebuild -license accept
```

The permanent switch is optional; `AGENTM5N_XCODE_PATH` is safer when several
Xcode versions are installed.

## Development run

```bash
bash scripts/run-dev.sh
```

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

Core ML decides the final placement of supported operators. The application
therefore reports the requested compute policy rather than claiming that every
operator executed on the Neural Engine.

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
- [Security model](docs/SECURITY.md)
- [Build troubleshooting](docs/TROUBLESHOOTING.md)
- [Roadmap](docs/ROADMAP.md)
- [Validation status](VALIDATION.md)

## License

GNU General Public License v3.0. Third-party components retain their respective licenses.

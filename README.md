# AgenTM5N

AgenTM5N is a native personal AI agent for Apple Silicon. It combines Apple Foundation Models, Ollama Local, Ollama Cloud, Core ML, native macOS actions, controlled local and remote execution, Microsoft Edge automation, reusable specialist agents, workflows, persistent runtime tools and local document/context services.

> Status: **1.1.2 Build 28 release candidate** for macOS 26+ / Apple Silicon.
> Source hardening is implemented on `agent/v1.1.0-platform-expansion`. The candidate still requires a fresh target-Mac build/test run and the final runtime matrix before notarization.

## Current capabilities

- Native SwiftUI application for Apple Silicon and macOS 26+
- Apple On-Device Foundation Models
- Ollama Local and Ollama Cloud with multi-turn tool calling
- provider-neutral central tool registry, capability classification and risk policy
- permission modes: Confirm, Workspace Trusted and Full Access
- persisted per-tool audit records, telemetry and bounded result caching
- workspace file read/search/write/patch tools and Git operations
- controlled local terminal and command execution
- saved SSH profiles, remote commands, batch execution, upload/download and log tailing
- Edge infrastructure control over the existing SSH/Vault stack
- Microsoft Edge automation through a managed local Chromium DevTools profile
- Calendar, Contacts, Apple Mail, Reminders, Clipboard, Notifications, Shortcuts and Finder actions
- encrypted Vault and native Secret Broker with model-invisible `secret_ref` usage
- HTTP(S) tool with optional Vault-secret host binding, redirect protection and result redaction
- persistent specialist agents with technical capability sandboxes and monotonic nested delegation
- reusable workflows with bounded steps and composite approval summaries
- Toolsmith persistent zsh/python3 runtime tools with typed parameters and enable/disable controls
- document generation for DOCX, PDF, XLSX and PPTX
- conversation attachments, document extraction and local Knowledge Library
- unified context search and Workspace Memory
- Core ML registry/prediction and semantic embedding support
- Developer-ID/notarized macOS release pipeline

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- full Xcode 26 or newer; current development is validated against the configured Xcode 27 beta toolchain
- Apple Intelligence enabled when Apple Foundation Models are used
- Ollama only when Ollama Local/Cloud providers are used

The standalone Command Line Tools package is not sufficient because AgenTM5N links AppKit, Core ML, Foundation Models and other macOS frameworks from the full SDK.

## Build the 1.1.2 Build 28 candidate

```bash
cd ~/Downloads/AgenTM5N

git fetch origin
git switch agent/v1.1.0-platform-expansion
git pull --ff-only origin agent/v1.1.0-platform-expansion

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"

rm -rf .build .swiftpm .build-artifacts Package.resolved
bash scripts/verify.sh
bash scripts/build-app.sh
open dist/AgenTM5N.app
```

`verify.sh` performs dependency resolution, the debug build and the automated regression tests. `build-app.sh` produces **1.1.2 Build 28** by default.

## Permission modes

### Confirm

Read-only tool calls may run automatically. Writes, mutations and execute-risk operations require explicit approval.

### Workspace Trusted

Ordinary bounded workspace file reads/writes may run automatically. Sensitive operations still require approval, including local shell/terminal execution, SSH/Edge, browser mutations, HTTP/API calls, Shortcuts, Toolsmith, personal macOS mutations, visible system mutations, persistent agent/workflow mutations, delegation and workflow execution.

### Full Access

Full Access is an explicit trusted-user mode. It removes the normal approval boundary and permits filesystem access outside the configured workspace. Capability routing, audit records and output redaction remain active. Use it only on a trusted personal workstation.

## Specialist capability sandboxes

`nil` capability configuration means a specialist inherits the centrally authorized main-agent catalog. A concrete capability list is an explicit sandbox; an empty list means no tools.

Nested delegation is capability-monotonic: a child receives the intersection of its own profile and an already restricted parent scope. A child therefore cannot regain SSH, browser, terminal, Toolsmith or another capability removed by its parent. Apple Foundation Models also enforce the scope again in the native execution bridge.

Foundation Models tool execution is serialized before entering the shared AppState approval path so framework-created concurrent tool calls cannot overwrite a pending user approval.

## Secret model

The Vault stores sensitive values encrypted locally. Models can discover only secret metadata/labels through `secret_list`; secret-aware native tools resolve `secret_ref` internally.

For HTTP/API use:

- direct model-supplied Authorization, Proxy-Authorization and Cookie headers are blocked
- secret-bearing HTTP requires HTTPS except on loopback
- redirects carrying a secret remain on the original host and secure/loopback transport
- if a Vault secret has a non-empty `host`, that secret may only be sent to the exact normalized host
- cookies are disabled in the ephemeral URLSession
- known secret representations are removed from model-visible responses

A blank Vault `host` intentionally remains an unbound generic secret for backward compatibility. Set a host when the secret belongs to one service.

## Toolsmith

Toolsmith creates persistent `custom_*` tools implemented in zsh or Python 3. Self-built code is always execute-risk. Runtime processes receive the configured workspace as working directory, a temporary private `HOME`/`TMPDIR`, a minimal `PATH`, typed non-secret arguments, no inherited Vault/provider/SSH-agent environment, a 60-second runtime limit and bounded output.

Toolsmith is not a kernel-level sandbox. Outside Full Access execution remains behind AgenTM5N's approval boundary. A disabled Toolsmith tool cannot be silently replaced and re-enabled through the agent router; it must be explicitly enabled first.

## Core ML

Core ML uses `.all`, leaving CPU, GPU and Apple Neural Engine available while Core ML decides operator placement. This avoids the execution-plan failure seen with large stateful transformer graphs when GPU was excluded.

The managed Core ML store is content-addressed with SHA-256. Imports are transactional: compiled artifacts are validated before registry commit, newly created artifacts are removed on failure, identical model content is reused instead of copied repeatedly, and unreferenced managed artifacts are cleaned during bootstrap.

Large models are not execution-plan-loaded during application startup. Prediction models are loaded lazily and cached in-process after first use. The Neural Engine view therefore distinguishes a **registered** persistent model from runtime execution.

## macOS privacy access

Calendar, Reminders and Contacts remain controlled by macOS TCC. Apple Mail and applicable automation remain controlled by Apple Events permission. The Mac Access Center displays authorization state and links to the relevant System Settings panes.

## Data directories

Primary persistent data is stored below:

```text
~/Library/Application Support/AgenTM5N/
```

This includes configuration, conversation state, SSH profiles, encrypted Vault, Core ML registry/models, Workspace Memory, Knowledge Library, generated documents, workflows and self-built tools. Sensitive/configuration stores created by AgenTM5N use restrictive user-only POSIX permissions where applicable.

## Validation and release

The source/build gate is only one part of release validation. Before notarization, complete the runtime matrix in [VALIDATION.md](VALIDATION.md), especially permission prompts, specialist sandbox denial, Core ML prediction with the active large model, HTTP secret transport, macOS TCC actions, SSH/Edge, browser, documents and Toolsmith.

After the runtime matrix is green:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

Expected artifact:

```text
dist/AgenTM5N-1.1.2-build28.dmg
```

The release pipeline requires Developer ID signing, Apple notarization acceptance, stapling, mounted-DMG validation and Gatekeeper verification before printing `RELEASE READY`.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Agent Runtime](docs/AGENT_RUNTIME.md)
- [Security model](docs/SECURITY.md)
- [Toolsmith](docs/TOOLSMITH.md)
- [Validation status](VALIDATION.md)
- [Changelog](CHANGELOG.md)

## License

GNU General Public License v3.0. Third-party components retain their respective licenses.

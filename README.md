# AgenTM5N

AgenTM5N is a native personal AI agent for Apple Silicon. It combines Apple
Foundation Models, Ollama Local, Ollama Cloud, Core ML/Apple Neural Engine,
native macOS actions, controlled local and remote execution, Microsoft Edge
automation, reusable specialist agents, workflows and persistent runtime tools.

> Status: **1.1.1 Build 25 release candidate** for macOS 26+ / Apple Silicon.
> The candidate must pass the target-Mac build, security regression suite and
> runtime matrix before the notarized DMG is released.

## Current capabilities

- Native SwiftUI application for Apple Silicon and macOS 26+
- Apple On-Device Foundation Models
- Ollama Local and Ollama Cloud with multi-turn tool calling
- Provider-neutral central tool registry, risk classification and execution router
- Permission modes: Confirm, Workspace Trusted and Full Access
- Persisted per-tool audit records, telemetry and bounded result caching
- Workspace file read/search/write/patch tools and Git operations
- Controlled local terminal and command execution
- Saved SSH profiles, remote commands, batch execution, upload/download and log tailing
- Edge infrastructure control over the existing SSH/Vault stack
- Microsoft Edge browser automation through a managed persistent Chromium DevTools profile
- Calendar, Contacts, Apple Mail, Reminders, Clipboard, Notifications, Shortcuts and Finder actions
- Encrypted Vault and native Secret Broker with model-invisible `secret_ref` usage
- HTTP(S) tool with secret-aware transport, redirect protection and result redaction
- Persistent specialist agents with optional technical capability sandboxes
- Reusable workflows with bounded steps and composite approval summaries
- Toolsmith: persistent self-built zsh/python3 runtime tools with typed parameters
- Tools Center for system tools and self-built tools, including enable/disable controls
- Document generation for DOCX, PDF, XLSX and PPTX
- Conversation attachments, document extraction and local Knowledge Library
- Unified context search and Workspace Memory
- Core ML model registry/prediction and semantic embedding support
- Version/update inspection and Developer-ID/notarized release pipeline

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- full Xcode 26 or newer; current development is validated against the configured Xcode 27 beta toolchain
- Apple Intelligence enabled for Apple Foundation Models
- Ollama only when Ollama Local/Cloud providers are used

The standalone Command Line Tools package is not sufficient because AgenTM5N
links AppKit, Core ML, Foundation Models and other macOS frameworks from the full SDK.

## Build the 1.1.1 candidate

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

`verify.sh` performs the debug build and the automated security regression tests.
`build-app.sh` produces the release application as **1.1.1 Build 25** by default.

## Permission modes

### Confirm

Read-only tool calls may run automatically. Writes, mutations and execution
require explicit approval.

### Workspace Trusted

Normal bounded workspace reads/writes may run automatically. Sensitive execution
still requires approval, including local shell commands, visible terminal commands,
SSH/Edge operations, browser mutations, HTTP/API calls, Shortcuts execution,
Toolsmith runtime code, macOS personal-data mutations, delegation and workflow runs.

### Full Access

The user explicitly opts into unrestricted local/remote execution and filesystem
access. Tool calls remain audited and model-visible outputs still pass through
secret redaction. Full Access intentionally removes the normal approval boundary
and should only be used on a trusted personal workstation.

## Capability sandboxes

Persistent specialist agents inherit all centrally authorized capabilities by
default. When a profile is explicitly restricted, its capability set is enforced
technically when provider tool definitions are selected and again before delegated
native execution. A restricted specialist cannot regain SSH, browser, Toolsmith or
other capabilities through a workflow.

## Toolsmith

Toolsmith creates persistent `custom_*` tools implemented in zsh or Python 3.
Self-built source is always classified as execute-risk. Runtime processes receive:

- the configured AgenTM5N workspace as working directory
- a temporary isolated `HOME` and `TMPDIR`
- a minimal `PATH`
- structured non-secret arguments
- no inherited Vault values, provider tokens or SSH-agent environment
- a 60-second runtime limit and bounded stdout/stderr

Toolsmith is intentionally powerful runtime code, not a kernel-level sandbox.
Outside Full Access it therefore remains behind AgenTM5N's execution approval
boundary. Do not store credentials in generated source.

## Secret model

The Vault stores sensitive values encrypted locally. Models discover only secret
metadata/labels via `secret_list`; tools that support credentials accept a
`secret_ref` and resolve the value natively. Direct Authorization/Cookie injection
from model arguments is blocked. Secret-bearing HTTP is restricted to HTTPS, with
plain HTTP allowed only on loopback, and known secret representations are removed
from model-visible results.

## macOS privacy access

AgenTM5N uses the macOS privacy system for Calendar, Reminders, Contacts and Apple
Events/Automation. The Mac Access Center displays the current Calendar, Reminders
and Contacts authorization state and links to the relevant System Settings panes.
Apple Mail automation remains subject to macOS Automation permission.

## Data directories

Primary persistent data is below:

```text
~/Library/Application Support/AgenTM5N/
```

including configuration, conversation state, SSH profiles, encrypted Vault,
Core ML registry/models, Workspace Memory, Knowledge Library, generated documents,
workflows and `self-built-tools.json`. Sensitive/configuration JSON stores created
by AgenTM5N use restrictive user-only POSIX permissions where applicable.

## Release

After the full runtime matrix is green, create the signed/notarized release with:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

The expected artifact is:

```text
dist/AgenTM5N-1.1.1-build25.dmg
```

The release script runs the build/test gate, Developer ID signing checks,
notarization, stapling and final mounted-DMG/Gatekeeper verification.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Agent Runtime](docs/AGENT_RUNTIME.md)
- [Security model](docs/SECURITY.md)
- [Toolsmith](docs/TOOLSMITH.md)
- [Build troubleshooting](docs/TROUBLESHOOTING.md)
- [Validation status](VALIDATION.md)

## License

GNU General Public License v3.0. Third-party components retain their respective
licenses.

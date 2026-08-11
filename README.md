# AgenTM5N

AgenTM5N is a native personal AI Agent Operating Layer for Apple Silicon. It combines Apple Foundation Models, Ollama Local, MLX local inference, Ollama Cloud, Core ML, native macOS actions, controlled local and remote execution, browser automation, persistent specialist agents, workflows, maintained and self-built tools, MCP bridging and local document/context services.

> Status: **1.2.0 Build 29 candidate** for macOS 26+ / Apple Silicon.
> Development branch: `agent/v1.2.0-agent-operating-layer`.
> GitHub source validation is required to be green before target-Mac validation. The final Swift typecheck/build, Apple framework linking and runtime matrix must be completed on the target Apple Silicon Mac before merge/release.

## What 1.2 changes

AgenTM5N 1.2 is no longer designed as “one model plus a few tools”. The application owns a provider-neutral execution layer:

```text
Model / Planner
      |
      v
AgenTM5N Agent Operating Layer
      |
      +--> capability routing
      +--> adaptive tool selection
      +--> permission engine
      +--> stagnation guard
      +--> Vault / secret broker
      +--> tool execution
      +--> telemetry / cache
      |
      v
Mac + Workspace + DevOps + Remote + MCP + Core ML
```

The model can request an action. AgenTM5N decides whether that action is available, authorized and executable.

## Current capabilities

### Model runtimes

- Apple On-Device Foundation Models
- Ollama Local
- MLX local inference through `mlx_lm.server`
- Ollama Cloud
- Core ML as a separate native inference/embedding plane with Apple Neural Engine eligibility where supported by the model graph

### Agent runtime

- fixed tool-round limits from 1 to 1,000,000
- Unlimited tool-round mode
- configurable global stagnation guard for identical repeated calls
- adaptive, capability-filtered or complete tool advertisement
- configurable maximum advertised tools per model request
- central provider-neutral tool registry
- capability-monotonic specialist-agent sandboxes
- Confirm, Workspace Trusted and Full Access permission modes
- persisted tool telemetry and bounded read-result caching

### Local engineering

- workspace file listing, globbing, search, reading, writing and patching
- local terminal and controlled command execution
- Git status, diff, branches, checkout and commit
- maintained Git log/show/fetch/fast-forward pull/push tools
- filesystem metadata, SHA-256, mkdir, copy, move and ZIP tools

### Containers and platforms

- Docker inventory, inspect, logs, stats, lifecycle and exec
- Podman inventory, inspect, logs and lifecycle
- Kubernetes contexts, pods, logs, describe, rollout status and workspace-bounded apply
- OpenShift projects, pods, routes and logs
- Edge-node actions over the existing SSH/Vault stack

### Network and APIs

- DNS lookup
- bounded ping
- bounded traceroute
- single TCP port probe
- HTTP(S) requests with optional Vault secret injection
- host binding, redirect protection and result redaction for secret-bearing HTTP calls

### MCP

- maintained stdio MCP bridge
- `tools/list`
- `tools/call`
- argv-based server launch without arbitrary shell construction
- bounded response timeout and minimal process environment

### macOS native access

- Calendar read/create/update/delete
- Contacts search/create/update
- Apple Mail recent messages/read/draft/send/reply
- Reminders list/create/complete
- Clipboard read/write
- Notifications
- Shortcuts list/run
- Finder reveal
- Mac Access Center for TCC/Apple Events status

### AI context and documents

- conversation attachments
- DOCX/XLSX/PPTX/PDF extraction
- local OCR path
- persistent Knowledge Library
- unified context search across Workspace Memory, attachments and Knowledge Library
- document generation for DOCX, PDF, XLSX and PPTX
- Core ML registry/prediction and semantic workspace embedding support

### Agent platform

- persistent specialist agents
- nested delegation with capability intersection
- reusable workflows
- Toolsmith persistent zsh/python3 tools with typed parameters
- maintained built-in tools use the same Toolsmith isolation, approval and telemetry path
- Microsoft Edge automation through the managed local Chromium DevTools profile

## Requirements

- Apple Silicon Mac
- macOS 26 or newer
- full Xcode 26 or newer
- Apple Intelligence enabled for Apple Foundation Models
- Ollama when using Ollama Local/Cloud
- optional Python environment with `mlx-lm` when using MLX
- platform CLIs only for the corresponding optional built-in packs, for example Docker, Podman, `kubectl` or `oc`

The standalone Command Line Tools package is not sufficient because AgenTM5N links AppKit, Core ML, Foundation Models and other macOS frameworks from the full SDK.

## Build the 1.2.0 Build 29 candidate

```bash
cd ~/Downloads/AgenTM5N

git fetch origin
git switch agent/v1.2.0-agent-operating-layer
git pull --ff-only origin agent/v1.2.0-agent-operating-layer

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"

rm -rf .build .swiftpm .build-artifacts Package.resolved
bash scripts/verify.sh
bash scripts/build-app.sh
open dist/AgenTM5N.app
```

Adjust `AGENTM5N_XCODE_PATH` if Xcode is installed elsewhere.

`verify.sh` performs dependency resolution, the debug build and automated tests. `build-app.sh` produces **1.2.0 Build 29** by default.

## Local inference: Ollama or MLX

For the local provider, Settings now exposes a runtime choice:

```text
Local Runtime
  -> Ollama
  -> MLX / mlx_lm.server
```

Ollama remains the default.

For MLX, use an isolated Python environment and start the selected model with `mlx_lm.server`, then point AgenTM5N at the default local endpoint:

```text
http://127.0.0.1:8080
```

See [MLX Runtime](docs/MLX_RUNTIME.md) for the exact setup and validation sequence.

## Runtime settings

1.2 adds a dedicated operating-layer configuration stored below the AgenTM5N Application Support directory. It controls:

- fixed or unlimited tool rounds
- adaptive tool selection
- maximum advertised tools
- enabled capabilities
- maintained built-in packs
- stagnation protection
- local inference runtime
- thinking mode
- context/output limits
- temperature, top-k, top-p and min-p
- repeat penalty and repeat context
- seed
- keep-alive
- request timeout

The former hard 24-round limit is not the authoritative 1.2 runtime limit.

## Permission modes

### Confirm

Read-only tool calls may run automatically. Writes, mutations and execute-risk operations require explicit approval.

### Workspace Trusted

Ordinary bounded workspace operations and approved read-only inspection may run automatically. Sensitive operations still require approval, including shell-style execution, SSH/Edge, browser mutations, HTTP/API calls, active network probes, MCP, Toolsmith management/runtime code, container/Kubernetes mutations, personal macOS mutations, persistent agent/workflow mutations and delegation.

### Full Access

Full Access is an explicit trusted-user mode. It removes the normal approval boundary and permits supported filesystem access outside the configured workspace. Capability routing, specialist sandboxes, audit records, stagnation protection and secret redaction remain active.

## Capability sandboxes

A specialist with no explicit capability configuration inherits the centrally authorized tool catalog. A concrete capability list is an explicit sandbox; an empty list means no tools.

Nested delegation is capability-monotonic: a child receives the intersection of its own scope and an already restricted parent scope. A child cannot recover SSH, browser, terminal, macOS personal access or another capability removed upstream.

## Secret model

The encrypted Vault stores sensitive values locally. Models can discover only safe secret metadata through `secret_list`; secret-aware native tools resolve a `secret_ref` internally.

For HTTP/API use:

- direct model-supplied Authorization, Proxy-Authorization and Cookie headers are blocked
- secret-bearing HTTP requires HTTPS except on loopback
- redirects carrying a secret remain on the original host and secure/loopback transport
- a Vault secret with a configured host may only be sent to that normalized host
- cookies are disabled in the ephemeral URLSession
- known secret representations are removed from model-visible results

Maintained Toolsmith built-ins receive no inherited Vault/provider/SSH-agent environment.

## Built-in tool packs

The maintained `custom_builtin_*` tools provide a stronger baseline without preventing the agent or user from creating additional Toolsmith tools.

They cover:

- Filesystem
- Git
- Docker
- Podman
- Kubernetes
- OpenShift
- Network diagnostics
- MCP stdio

See [Built-in Tool Packs](docs/BUILTIN_TOOLS.md).

## Toolsmith

Toolsmith creates persistent `custom_*` tools implemented in zsh or Python 3. Runtime processes receive the configured workspace as working directory, a private temporary `HOME`/`TMPDIR`, a minimal `PATH`, typed non-secret arguments, no inherited Vault/provider/SSH-agent environment, a bounded runtime and bounded output.

Toolsmith is not a kernel-level sandbox. Execute-risk operations still use the central permission policy unless Full Access was explicitly selected.

## Core ML / Neural Engine

Core ML uses `.all`, leaving CPU, GPU and Apple Neural Engine available while Core ML decides supported operator placement. Models are registered persistently but prediction models are loaded lazily.

Core ML is intentionally not conflated with MLX: MLX is the local Metal-oriented LLM runtime; Core ML remains the native model/ANE execution plane.

## Operating Layer dashboard

Open **Activity** to see the Agent Operating Layer status together with execution telemetry:

- provider/runtime/model
- tool-round mode
- registered tool count
- installed maintained built-ins
- custom Toolsmith tool count
- enabled capabilities
- stagnation guard state
- executed tools, duration, output size and cache hits

## macOS privacy access

Calendar, Reminders and Contacts remain controlled by macOS TCC. Apple Mail and applicable automation remain controlled by Apple Events permission. The Mac Access Center displays authorization state and links to the relevant System Settings panes.

## Data directory

Primary persistent data is stored below:

```text
~/Library/Application Support/AgenTM5N/
```

This includes configuration, operating-layer settings, conversation state, SSH profiles, encrypted Vault, Core ML registry/models, Workspace Memory, Knowledge Library, generated documents, workflows, self-built tools and telemetry. Sensitive/configuration stores use restrictive user-only POSIX permissions where applicable.

## Validation and release

GitHub CI is a source gate, not a substitute for the target-Mac runtime gate. Before merge/release, complete the 1.2 matrix in [VALIDATION.md](VALIDATION.md), especially:

- full Swift build/tests on Apple Silicon
- Ollama chat + tool loop
- MLX chat + tool loop
- fixed and Unlimited tool rounds
- stagnation guard
- capability disable/deny behavior
- Confirm/Workspace Trusted/Full Access
- built-in Docker/Podman/Kubernetes/OpenShift tools when the CLIs are installed
- MCP stdio
- macOS TCC actions
- SSH/Edge
- browser
- documents/context
- Core ML model execution

After the runtime matrix is green, the release pipeline can create and notarize the DMG:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

Expected artifact:

```text
dist/AgenTM5N-1.2.0-build29.dmg
```

## Documentation

- [Agent Operating Layer](docs/OPERATING_LAYER.md)
- [Built-in Tool Packs](docs/BUILTIN_TOOLS.md)
- [MLX Runtime](docs/MLX_RUNTIME.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Agent Runtime](docs/AGENT_RUNTIME.md)
- [Security model](docs/SECURITY.md)
- [Toolsmith](docs/TOOLSMITH.md)
- [Validation](VALIDATION.md)
- [1.2.0 Changelog](CHANGELOG-1.2.0.md)
- [Full changelog](CHANGELOG.md)

## License

GNU General Public License v3.0. Third-party components retain their respective licenses.

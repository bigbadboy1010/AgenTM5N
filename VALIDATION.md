# Validation status

Date: 2026-08-11
Version: **1.2.0 Build 29 candidate**
Branch: `agent/v1.2.0-agent-operating-layer`

This document separates GitHub source validation, automated target-Mac validation and manual runtime validation. A feature is not release-green merely because its source parses successfully.

## Current gate state

The previous 1.1.x target-Mac baseline completed a successful debug/test/production build on the Apple Silicon development Mac. Version 1.2.0 introduces a new operating-layer configuration, MLX transport, maintained built-in tool packs, adaptive routing and a universal stagnation guard, so **Build 29 requires a fresh full target-Mac build and runtime matrix before merge/release**.

GitHub CI validates:

- shell syntax for development, build, release, verification, notarization and publishing scripts
- Swift source parsing
- rejection of incomplete source markers such as `TODO`, `FIXME`, `fatalError`, `try!` and forced casts in `Sources`

GitHub's Ubuntu source gate does not link Apple frameworks and is not a substitute for the Apple Silicon build.

## Target-Mac build gate

Run on the target Mac:

```bash
cd ~/Downloads/AgenTM5N

git fetch origin
git switch agent/v1.2.0-agent-operating-layer
git pull --ff-only origin agent/v1.2.0-agent-operating-layer

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm .build-artifacts Package.resolved

bash scripts/verify.sh
bash scripts/build-app.sh
```

Adjust `AGENTM5N_XCODE_PATH` to the installed full Xcode if necessary.

Expected application metadata:

```text
Version: 1.2.0
Build:   29
```

The target-Mac gate is green only if dependency resolution, debug compilation, XCTest, release compilation, bundle assembly and code-sign verification all succeed.

## 1.2 runtime invariants

### Operating-layer configuration

Verify persistence across quit/relaunch for:

- local runtime selection
- tool-round mode
- fixed maximum rounds
- adaptive routing mode
- maximum advertised tools
- enabled capabilities
- maintained built-in tool enable flag
- stagnation guard state and threshold
- model sampling/runtime settings

The 1.2 settings file must remain separate from the legacy `configuration.json` and both documents must remain readable after migration from 1.1.x.

### Tool rounds

Verify:

1. Fixed mode with a value greater than 24 is retained and used.
2. Fixed mode stops at the configured limit when the model keeps requesting tools.
3. Unlimited mode no longer stops because of the former 24-round ceiling.
4. The user Stop action still cancels generation in Unlimited mode.
5. Approval prompts continue to work after more than 24 rounds.

### Stagnation guard

In a disposable test workspace:

1. Enable the guard with threshold 3.
2. Cause the model or a test harness to request the exact same uncached tool with identical arguments repeatedly.
3. Verify the first three executions are allowed subject to normal permission policy.
4. Verify the next identical execution returns `STAGNATION_GUARD_TRIGGERED` and does not perform the operation.
5. Change one argument and verify execution can continue.
6. Verify cache hits do not consume the stagnation threshold.
7. Disable the guard and verify the guard no longer blocks repeated calls.

## Provider matrix

### Apple Foundation Models

- normal chat
- authoritative current date/time
- native routed macOS tools
- specialist capability denial
- approval serialization

### Ollama Local

- model refresh
- plain chat
- streaming response
- tool calling
- multi-round tool loop
- runtime parameter persistence
- adaptive tool selection
- fixed and Unlimited rounds

### Ollama Cloud

- Vault-backed API key
- model refresh
- plain chat
- tool calling
- secret redaction
- adaptive tool selection

### MLX / `mlx_lm.server`

Start an isolated local server before the test. Validate:

- `/v1/models` refresh through AgenTM5N
- plain chat
- one model that supports tool calling through its chat template
- read-only AgenTM5N tool call and result continuation
- write/execute approval in Confirm mode
- multiple tool rounds
- server shutdown surfaces a transport error instead of a fabricated answer
- image attachment is rejected safely rather than sent through an unsupported MLX image payload
- model-visible tool output remains secret-redacted

## Capability routing matrix

For each relevant provider verify:

- disabling `git` removes/denies Git tools
- disabling `terminal` removes/denies Toolsmith and MCP
- disabling `system` removes/denies container, Kubernetes/OpenShift and network built-ins
- disabling `macPersonal` removes/denies Calendar/Contacts/Mail
- disabling `ssh` removes/denies SSH tools
- disabling `coreML` removes/denies Core ML agent tools
- disabling `documents` removes/denies document-generation tools
- an explicit specialist scope can only reduce the global capability set
- a nested specialist cannot regain a capability removed by its parent

## Permission matrix

### Confirm

- read-only calls can run directly
- write-risk calls require approval
- execute-risk calls require approval
- maintained built-in risk matches `BundledToolCatalog`

### Workspace Trusted

Verify bounded ordinary workspace operations can run automatically while the following remain approval-sensitive where classified as mutating/execute:

- local shell/terminal
- Git fetch/pull/push
- active network probes
- Docker/Podman lifecycle and exec
- Kubernetes apply
- MCP calls
- SSH/Edge
- browser mutation
- HTTP
- Shortcuts execution
- Toolsmith management/runtime execution
- personal macOS mutations
- persistent agent/workflow mutations and delegation

### Full Access

- explicitly selecting Full Access removes the normal approval/workspace boundary
- capability scopes still deny disabled tool families
- specialist sandboxes remain enforced
- telemetry remains active
- secret redaction remains active
- stagnation protection remains active when enabled

## Maintained built-in tool matrix

Only test packs whose CLI/runtime is installed. Missing CLIs must fail clearly rather than silently falling back.

### Filesystem

- stat
- SHA-256
- mkdir
- copy
- move
- archive create/extract
- absolute and traversal path rejection

### Git

- log
- show
- fetch
- fast-forward-only pull
- normal push
- verify no force-push path exists

### Docker

- ps
- inspect
- logs
- stats
- start/stop/restart on a disposable container
- exec inside a disposable container

### Podman

- ps
- inspect
- logs
- lifecycle on a disposable container

### Kubernetes

Use a non-production test context:

- contexts
- pods
- logs
- describe
- rollout status
- apply a harmless workspace manifest
- reject manifest path outside workspace

### OpenShift

Use a non-production test project:

- current/list projects
- pods
- routes
- logs

### Network

Use known test destinations only:

- DNS lookup
- bounded ping
- bounded traceroute
- one TCP port probe

### MCP

Use a known local test MCP server:

- `tools/list`
- `tools/call`
- argument JSON validation
- executable-root rejection
- timeout behavior
- process termination after request
- Confirm-mode approval before MCP execution

## Existing platform regression matrix

The 1.2 build must also preserve the previous platform functionality:

1. Toolsmith list/get/create/run/disable/reactivate and disabled-tool replacement policy.
2. Browser open/read/tabs/actions/batch.
3. Calendar, Reminders, Contacts and Apple Mail permission/status plus mutations.
4. SSH with saved Vault-backed profiles.
5. Edge-node regression on an authorized test host.
6. HTTP secret transport:
   - correctly host-bound HTTPS secret succeeds
   - wrong host is rejected before transmission
   - intended loopback HTTP secret request succeeds
   - private-LAN/external plain HTTP secret request is rejected
7. Documents: DOCX, PDF, XLSX and PPTX.
8. Core ML:
   - application startup does not eagerly load a multi-gigabyte registered model
   - model description reports adaptive compute policy
   - in-app prediction completes with a known compatible model
   - repeated prediction reuses the in-process loaded model where designed
   - duplicate import does not duplicate managed model content
9. Workspace Memory lexical and compatible semantic search.
10. Conversation attachments, Knowledge Library and unified context search.
11. Persistent agents, nested delegation and workflows.
12. Quit/relaunch persistence for configuration, operating-layer settings, agents, workflows, Toolsmith, Vault metadata links and Core ML registry.

## Dashboard and telemetry

Open **Activity / Agent Operating Layer** and verify:

- provider/runtime/model are correct
- fixed or Unlimited round display is correct
- registered tool count is non-zero
- installed maintained built-in count is visible
- custom-tool count excludes maintained built-ins
- enabled capability count matches Settings
- stagnation guard status matches Settings
- tool calls record provider, capability, risk, duration, output size and cache-hit state
- no raw Vault secret is visible in telemetry

## Release gate

Only after the Build 29 target-Mac automated gate and required runtime matrix are green:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

Expected artifact:

```text
dist/AgenTM5N-1.2.0-build29.dmg
```

The release script requires Developer ID signing, Apple notarization acceptance, stapling, mounted-DMG validation and Gatekeeper verification before printing `RELEASE READY`.

## Trust boundary

Toolsmith and maintained command-based built-ins execute native child processes and are not a kernel-level sandbox. AgenTM5N reduces risk with capability routing, explicit risk metadata, permission policy, workspace-bounded path handling where applicable, minimal child-process environments, output bounds, telemetry, secret redaction and the stagnation guard.

A dedicated sandboxed helper/XPC service remains a possible future defense-in-depth layer; Build 29 does not claim kernel isolation for Toolsmith code.

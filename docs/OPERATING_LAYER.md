# AgenTM5N Agent Operating Layer 1.2

AgenTM5N 1.2 turns the application from a model client with tools into a native macOS agent operating layer. The operating layer owns model routing, capability routing, tool authorization, execution, audit, local context and native Mac access. Models propose actions; AgenTM5N remains the authority that decides what can actually run.

## Architecture

```text
User / UI
   |
   v
AppState / Agent Loop
   |
   +--> Apple Foundation Models
   |
   +--> Local Runtime Router
   |      +--> Ollama Local
   |      `--> MLX / mlx_lm.server
   |
   `--> Ollama Cloud
          |
          v
   AgentToolRegistry
          |
          +--> Capability filter
          +--> Adaptive tool router
          +--> Permission policy
          +--> Stagnation guard
          +--> Result cache
          +--> Tool telemetry
          |
          v
   Native + maintained + user tools
          |
          +--> Workspace / Git / Terminal
          +--> macOS Calendar / Contacts / Mail / Reminders
          +--> Core ML / Neural Engine
          +--> SSH / Edge
          +--> Browser
          +--> HTTP + Vault Secret Broker
          +--> Docker / Podman
          +--> Kubernetes / OpenShift
          +--> Network diagnostics
          +--> MCP stdio bridge
          +--> Documents / Knowledge / Context
          +--> Persistent Agents / Workflows
          `--> Toolsmith custom tools
```

## Runtime configuration

The 1.2-specific runtime configuration is stored separately in:

```text
~/Library/Application Support/AgenTM5N/agent-operating-layer.json
```

This avoids breaking the existing `AppConfiguration` document and keeps migration from 1.1.x deterministic.

The operating-layer configuration controls:

- fixed or unlimited tool rounds
- maximum fixed tool rounds up to 1,000,000
- adaptive, capability-filtered or complete tool advertisement
- maximum tools advertised per model request
- enabled capability families
- maintained built-in tool packs
- stagnation guard and repeat threshold
- local inference runtime: Ollama or MLX server
- Ollama thinking mode
- context/output/sampling/repetition parameters
- seed, keep-alive and request timeout

`AppConfiguration.maxToolIterations` remains only as the compatibility field consumed by the existing agent loop. The 1.2 operating-layer settings are authoritative.

## Tool round modes

### Fixed

A fixed limit from 1 to 1,000,000 can be selected. The former 24-round ceiling is removed from the 1.2 runtime path.

### Unlimited

Unlimited mode maps to a deliberately very high compatibility ceiling in the existing loop. It does not remove cancellation or authorization. The user can stop generation at any time and every tool call remains subject to capability and permission policy.

Unlimited mode is paired with the global stagnation guard.

## Stagnation guard

`ToolStagnationGuard` fingerprints the tool name and normalized arguments of uncached tool executions. Repeating the exact same call more than the configured threshold inside the guard window returns a structured failure instead of executing the action again.

The guard:

- applies to native, maintained, Toolsmith, container, Kubernetes, MCP and macOS tools through the shared execution path
- does not count cache hits as repeated execution
- resets when the call signature changes or the observation window expires
- is configurable and can be disabled explicitly

This protects unlimited sessions from accidental identical-action loops without imposing a small global round count.

## Capability routing

Every centrally known tool has an `AgentToolCapability`. Examples:

- `workspace`
- `terminal`
- `ssh`
- `edge`
- `browser`
- `git`
- `macPersonal`
- `secrets`
- `http`
- `system`
- `reminders`
- `coreML`
- `memory`
- `knowledge`
- `attachments`
- `documents`
- `agents`
- `workflows`
- `updates`

The user can disable capability families globally. Specialist-agent capability scopes are monotonic restrictions: a child agent can further restrict the centrally authorized set but cannot recover a capability removed by its parent or by the operating-layer settings.

## Adaptive tool routing

Advertising every available schema to every model call becomes counterproductive as the tool catalog grows. In adaptive mode AgenTM5N first reduces the registry using the current user intent and capability scope, then advertises only a bounded relevant set.

The router intentionally keeps context/workspace primitives available for broad engineering requests and promotes specialized families for signals such as Docker, Podman, Kubernetes, OpenShift, SSH, Git, HTTP, macOS personal data, documents, Core ML, workflows or MCP.

The actual execution authority remains independent of tool advertisement. Advertising a tool never bypasses authorization.

## Permission model

### Confirm

Read-risk calls may run automatically. Write and execute-risk calls require explicit approval.

### Workspace Trusted

Bounded workspace operations and approved read-only system inspection can run automatically. External, shell-like, network-active and mutating operations remain approval-gated according to the central registry policy.

### Full Access

The normal approval/workspace boundary is removed for a trusted personal workstation. Capability scopes, tool telemetry, output redaction, Secret Broker protections and explicit specialist sandboxes remain active.

## Maintained built-in tools

The 1.2 built-ins are installed into the existing Toolsmith runtime rather than creating a parallel executor. This is intentional. They inherit:

- the Toolsmith minimal process environment
- isolated temporary `HOME` and `TMPDIR`
- no inherited Vault/provider/SSH-agent environment
- bounded runtime and output
- central capability metadata
- central risk metadata
- approval policy
- telemetry
- secret redaction
- stagnation protection

AgenTM5N never overwrites an existing local record with the same built-in name. User state remains authoritative.

See [BUILTIN_TOOLS.md](BUILTIN_TOOLS.md).

## Local model runtimes

### Ollama

Ollama remains the default local runtime and supports the full AgenTM5N streaming path. 1.2 exposes the major runtime parameters rather than hard-coding only model, messages and thinking.

### MLX

MLX is integrated through the local OpenAI-compatible `mlx_lm.server` surface. The model inference therefore runs through MLX/Metal while AgenTM5N continues to own tool schemas, tool history, approval, Vault isolation and execution.

This sidecar architecture avoids introducing MLX Swift/Metal build requirements into the current SwiftPM release path. A direct in-process MLX Swift backend can be added later as an Xcode-specific provider without changing the operating-layer contracts.

See [MLX_RUNTIME.md](MLX_RUNTIME.md).

## Core ML and Apple Neural Engine

Core ML remains a separate native execution plane. It is not treated as an LLM transport. AgenTM5N uses Core ML for registered model inference and semantic embedding workflows where Core ML can schedule supported operators across CPU, GPU and Apple Neural Engine.

## MCP

1.2 includes maintained stdio MCP bridge tools for:

- listing server tools
- invoking one server tool with JSON arguments

The MCP executable is launched directly from approved CLI roots rather than through an arbitrary shell command. Server arguments are passed as an argv array. The bridge uses a minimal environment and bounded response timeout.

MCP calls are execute-risk because the remote/local MCP server defines the downstream behavior.

## Runtime dashboard

The existing Activity window is extended into the Operating Layer dashboard. It shows:

- provider and local runtime
- active model
- tool-round mode
- registered tool count
- installed maintained built-ins
- custom Toolsmith tool count
- enabled capability count
- stagnation-guard state
- tool telemetry, duration, output size and cache hits

## Security invariant

The key 1.2 invariant is:

> The model is a planner and caller. AgenTM5N is the execution authority.

Provider changes must not weaken:

- capability checks
- approval checks
- Vault isolation
- secret redaction
- workspace boundaries
- telemetry
- stagnation protection
- specialist-agent sandboxing

That invariant is the basis for adding future providers, MCP transports and tool packs without turning each integration into a separate security model.

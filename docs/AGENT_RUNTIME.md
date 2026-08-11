# Agent Runtime

AgenTM5N 1.2.0 Build 29 provides a provider-neutral multi-turn agent runtime for Apple Foundation Models, Ollama Local, MLX local inference and Ollama Cloud. Models generate responses and tool requests; AgenTM5N owns capability selection, risk, approval, execution, secret handling, telemetry and loop protection.

## Main agent loop

1. AgenTM5N builds provider messages and the centrally authorized tool catalog.
2. Global capability settings reduce the catalog.
3. A specialist capability scope can only reduce the catalog further.
4. Adaptive routing can reduce the provider-visible schemas to a bounded relevant set.
5. The provider may return normal content and one or more tool calls.
6. AgenTM5N resolves risk and a sanitized approval summary from `AgentToolRegistry`.
7. The current permission mode decides whether explicit user approval is required.
8. The global stagnation guard checks uncached repeated calls.
9. Approved calls execute through the shared tool router.
10. Results are bounded, secret-redacted, audited and returned to the model.
11. The provider loop continues until the model stops requesting tools, the user cancels, an error terminates the turn or a configured fixed round limit is reached.

Apple Foundation Models uses the same AppState execution authority through `AgentToolExecutionBridge`. Foundation Models uses focused compile-time Swift `Tool` adapters. Ollama and MLX use provider-style JSON tool schemas.

## Tool round budget

The authoritative 1.2 budget lives in `AgentOperatingLayerConfiguration`.

### Fixed mode

Fixed mode supports a configured maximum from 1 to 1,000,000 rounds. The previous 24-round ceiling is not the 1.2 runtime ceiling.

### Unlimited mode

Unlimited mode exposes a very large compatibility ceiling to the existing loop instead of imposing a small hard stop. Cancellation, authorization, capability checks and stagnation protection remain active.

This design allows long autonomous jobs while still retaining user control.

## Stagnation protection

`ToolStagnationGuard` runs in the shared uncached execution path. It fingerprints:

```text
tool name + normalized sorted arguments
```

If the exact same call is repeated beyond the configured threshold within the guard window, AgenTM5N returns `STAGNATION_GUARD_TRIGGERED` without executing the duplicate action again.

A different call signature resets the consecutive sequence. Cache hits are intentionally not counted because they do not repeat the underlying side effect or expensive read.

The guard complements the older low-level `AgentRuntime` repetition ledger and extends protection across native tools, Toolsmith, maintained built-ins, container/Kubernetes tools, MCP and macOS actions.

## Provider paths

### Apple Foundation Models

Apple uses native Foundation Models sessions and compile-time Tool adapters. Tool execution is serialized before entering the shared visible approval path so concurrent framework callbacks cannot overwrite pending approval state.

### Ollama Local

Ollama Local uses `/api/chat` streaming and receives the adaptive provider tool catalog. 1.2 forwards configurable runtime options including output/context, sampling, repetition, seed, keep-alive and supported thinking mode.

### MLX local

When `LocalInferenceRuntime` is `mlxServer`, the local provider delegates inference to `MLXProvider`, which uses `mlx_lm.server` through `/v1/models` and `/v1/chat/completions`.

The MLX transport is non-streaming in the initial 1.2 implementation but emits the same `ProviderStreamEvent` contract to the AppState loop. Tool calls are converted into `ProviderToolCall`, executed by AgenTM5N and returned in later turns.

MLX does not bypass the AgenTM5N permission or execution layer.

### Ollama Cloud

Ollama Cloud retains the existing Vault-backed bearer-token path and the same tool/capability/approval logic as Ollama Local.

## Adaptive tool advertisement

The 1.2 tool catalog is large enough that sending every schema to every model turn is undesirable. `AgentToolSelectionMode` supports:

- `all`: send every centrally allowed definition
- `capabilityFiltered`: send all definitions allowed by capability scope
- `adaptive`: select a bounded subset relevant to the current user request

Adaptive routing promotes capability families based on intent signals such as:

- source/repository/build/test → workspace, Git, terminal, memory
- Docker/Podman → system/container tools
- Kubernetes/OpenShift → system/platform tools
- SSH/server/remote → SSH/Edge
- HTTP/API → HTTP and secret metadata
- Calendar/Contacts/Mail → macOS personal tools
- documents → document/context/attachment tools
- Core ML/Neural Engine → Core ML and memory
- MCP/Toolsmith → terminal capability

Advertisement is not authorization. Every call is checked again before execution.

## Tool families

The provider-neutral registry covers:

- workspace listing/glob/search/read/write/patch
- local command and visible terminal
- Git status/diff/branches/checkout/commit plus maintained log/show/fetch/pull/push
- filesystem metadata/checksum/copy/move/archive tools
- SSH list/run/terminal/upload/download/tail/batch
- Edge infrastructure list/read/write/control
- Microsoft Edge browser session/tabs/open/read/action/batch
- Calendar, Contacts and Apple Mail reads/mutations
- Reminders
- Clipboard, Notifications, Shortcuts, Finder and system diagnostics
- Secret metadata and HTTP(S)
- Docker and Podman
- Kubernetes and OpenShift
- DNS/ping/traceroute/TCP probe
- MCP stdio bridge
- Core ML and Workspace Memory
- Unified Context, Knowledge Library and attachments
- persistent specialist agents and delegation
- reusable workflows
- Toolsmith and dynamic `custom_*` runtime tools
- generated documents
- version/update checks

## Maintained built-ins

Maintained `custom_builtin_*` tools are persisted through the Toolsmith library but are not treated as unclassified arbitrary custom code. `BundledToolCatalog` assigns their central capability and risk.

Examples:

- read-only Docker inventory → `system/read`
- Docker lifecycle/exec → `system/execute`
- Git log/show → `git/read`
- Git fetch/pull/push → `git/execute`
- workspace copy/move/archive → `workspace/write`
- Kubernetes apply → `system/execute`
- MCP → `terminal/execute`

This keeps approval semantics tied to the maintained tool contract rather than to the implementation language.

## Permission modes

### Confirm

- read-risk calls may execute automatically
- write and execute-risk calls require explicit approval
- normal workspace file boundaries remain active
- calls are audited and telemetry is persisted

### Workspace Trusted

Ordinary bounded workspace operations and approved read-only inspection can run without repeated prompts. Broader local, personal, persistent or external actions remain approval-sensitive according to their central risk/capability classification.

Typical approval-required actions include:

- arbitrary local shell and visible terminal
- Git network mutation
- active network probes
- container lifecycle/exec
- Kubernetes apply
- MCP execution
- SSH/Edge execution and transfer
- browser mutation
- HTTP/API execution
- Shortcuts execution
- Toolsmith management/runtime execution
- macOS personal mutations
- persistent agent/workflow mutation and delegation

### Full Access

Full Access is an explicit trusted-user mode. Supported operations may run automatically and supported file operations may leave the configured workspace. Capability scopes, specialist sandboxes, telemetry, secret redaction and stagnation protection remain active.

## Capability sandboxes

A persistent specialist has either:

- `nil` capabilities: inherit the centrally authorized catalog
- an explicit capability set: receive only the intersection
- an explicit empty set: receive no tools

Nested delegation is capability-monotonic. A child cannot regain authority removed by an outer specialist or by global operating-layer settings.

## Workflows

A workflow stores ordered provider-neutral calls. Workflow execution is a composite operation with a sanitized stored-step summary. Steps run sequentially, stop on failure and are checked against any active specialist capability scope.

## Toolsmith

Toolsmith creates persistent zsh/Python tools with typed parameters. Child processes receive:

- the active workspace as working directory
- temporary private HOME/TMP/XDG paths
- a minimal PATH
- structured arguments
- no inherited Vault/provider/SSH-agent environment
- bounded runtime and output

Toolsmith is not a kernel-level sandbox. Arbitrary custom runtime code remains execute-risk and approval-controlled outside explicit Full Access.

Maintained built-ins reuse this runtime but receive their own central risk/capability metadata.

## Workspace boundary

Relative file paths resolve against the configured workspace. Existing paths are standardized and symlinks are resolved before boundary checks. Destination parents are validated before creating a new path.

Full Access explicitly permits supported file operations outside the normal boundary. Maintained filesystem built-ins independently reject absolute/traversal paths and stay workspace-relative.

## Browser execution

`browser_batch` contains bounded declared ordered interactions. After central approval, the native browser service executes only those steps and can optionally perform a final read. The managed DevTools endpoint remains loopback-only.

## Secret-aware HTTP execution

The model supplies secret metadata references rather than secret values. Native code resolves secrets and applies transport controls before transmission. Plain HTTP with secrets is loopback-only. Host-bound secrets cannot be redirected or sent to a different normalized host. Model-visible output is redacted.

## Core ML runtime

Core ML remains independent from Ollama/MLX LLM transport. AgenTM5N keeps registered Core ML models and can use Core ML's adaptive compute placement for compatible inference and embedding workflows across CPU, GPU and Apple Neural Engine.

Managed imports are content-addressed and prediction models are loaded lazily.

## Audit and telemetry

Main tool execution records include:

- tool name
- sanitized argument summary
- risk
- running/succeeded/failed/denied state
- bounded/redacted output
- timestamps

Telemetry records:

- provider
- capability
- duration
- output byte count
- cache-hit state

The Activity view exposes this together with operating-layer runtime status.

## Current deliberate limitations

- provider-returned multi-tool calls are executed sequentially in the main AppState loop
- the initial MLX transport uses a local server sidecar rather than in-process MLX Swift
- the initial MLX transport is treated as text-only
- MCP 1.2 stdio calls are stateless per bridge invocation rather than persistent sessions
- Toolsmith is native child-process execution rather than a dedicated kernel-sandboxed XPC helper
- Apple Foundation Models still requires static Swift Tool adapter types; dynamic custom functions use the existing Toolsmith meta-adapter path
- release readiness still requires the target-Mac automated gate and manual runtime matrix in `VALIDATION.md`

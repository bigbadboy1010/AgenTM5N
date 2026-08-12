# AgenTM5N 1.2.0 — Agent Operating Layer

Build 29 candidate.

## Runtime

- Replaces the historical 24-tool-round ceiling with an operating-layer budget.
- Fixed tool-round mode supports values from 1 to 1,000,000.
- Unlimited mode is available for long autonomous sessions.
- Adds a configurable global stagnation guard for identical uncached tool calls.
- Adds adaptive, capability-filtered and all-tools advertisement modes.
- Adds a configurable maximum number of advertised tools per model request.
- Adds global capability enable/disable controls.

## Local inference

- Keeps Ollama Local as the default local runtime.
- Adds MLX local inference through `mlx_lm.server`.
- MLX uses the same AgenTM5N conversation, tool, approval, Vault and audit layer.
- Adds configurable Ollama thinking modes: off, standard, low, medium, high and max.
- Exposes model runtime controls for context/output, sampling, repetition, seed, keep-alive and timeout where supported by the selected runtime.

## Tool platform

- Adds maintained Built-in Tool Packs installed through the existing Toolsmith execution sandbox.
- Adds central capability/risk metadata for maintained built-ins.
- Adds Filesystem tools for metadata, SHA-256, mkdir, copy, move and ZIP handling.
- Adds Git tools for log, show, fetch, fast-forward-only pull and non-force push.
- Adds Docker tools for inventory, inspect, logs, stats, lifecycle and exec.
- Adds Podman tools for inventory, inspect, logs and lifecycle.
- Adds Kubernetes tools for contexts, pods, logs, describe, rollout status and workspace-bounded apply.
- Adds OpenShift tools for projects, pods, routes and logs.
- Adds network tools for DNS, ping, traceroute and single-port probing.
- Adds an MCP stdio bridge for `tools/list` and `tools/call`.

## Security and governance

- Maintained built-ins do not bypass Toolsmith isolation or the central permission engine.
- Built-ins receive explicit read/write/execute risk metadata independent of their script implementation.
- Active network probes, Git network mutation, container mutation, Kubernetes apply and MCP calls remain execute-risk.
- Capability routing applies to dynamic maintained tools before advertisement and execution.
- Specialist-agent capability scopes remain monotonic restrictions.
- Tool telemetry continues to redact known Vault secret values.

## UI

- Expands Settings into a runtime control surface.
- Adds local runtime selection between Ollama and MLX.
- Adds configurable tool-round, routing, capability and stagnation settings.
- Extends Activity into an Agent Operating Layer dashboard showing provider/runtime/model, tool counts, built-ins, custom tools, capability scope and telemetry.

## Build and release

- Default application version is 1.2.0 Build 29.
- Build, release, release-check, DMG verification and GitHub publishing defaults are synchronized to 1.2.0 Build 29.
- Source CI now shell-parses all release scripts in addition to parsing Swift sources and rejecting incomplete source markers.

## Validation status

GitHub source validation covers syntax-level Swift parsing, shell syntax and source-policy markers. The final Apple Silicon typecheck/build, framework linking, runtime permission matrix, Ollama/MLX tool loops and native macOS behavior must be validated on the target Mac before merge/release.

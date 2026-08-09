# AgenTM5N architecture

## Runtime layers

```text
SwiftUI interface
  ├─ Chat / provider selection
  ├─ Tools Center
  ├─ Persistent specialist agents
  ├─ Workflows
  ├─ Activity / audit
  ├─ Mac Access Center
  ├─ Encrypted Vault
  ├─ Embedded terminal / SSH profiles
  └─ Core ML / Workspace Memory / Knowledge

Provider layer
  ├─ AppleFoundationModelsProvider
  │    └─ focused static FoundationModels.Tool adapters
  ├─ OllamaProvider Local
  └─ OllamaProvider Cloud
            │
            ▼
Provider-neutral tool model
  ├─ AgentToolRegistry
  │    ├─ capability
  │    ├─ risk
  │    ├─ cache policy
  │    └─ secret-awareness metadata
  ├─ AgentToolExecutionBridge (Apple)
  └─ ProviderToolCall / ProviderToolDefinition (shared)
            │
            ▼
Central execution policy
  ├─ capability sandbox check
  ├─ Confirm / Workspace Trusted / Full Access
  ├─ user approval when required
  ├─ ToolExecutionRecord audit
  ├─ telemetry / bounded cache
  └─ SecureSecretBroker output redaction
            │
            ▼
Native execution services
  ├─ AgentRuntime (workspace / command / Git)
  ├─ macOS EventKit / Contacts / Apple Events
  ├─ SSHLaunchService / Edge infrastructure
  ├─ MicrosoftEdgeBrowserService (local CDP)
  ├─ SecureHTTPClient
  ├─ CoreMLService / WorkspaceIndexService
  ├─ Knowledge / Attachments / Documents
  ├─ Workflow engine / agent delegation
  └─ Toolsmith runtime library
```

## Provider boundary

The chat/runtime layer uses provider-neutral messages, tool definitions and tool
calls. Ollama receives those schemas directly. Apple Foundation Models requires
compile-time Swift `Tool` types, so AgenTM5N exposes small focused adapters that
translate Apple-generated arguments back into the same provider-neutral calls.
Native execution, capability enforcement, permission policy and audit therefore
remain outside the model provider.

Apple focused packs also reduce Foundation Models context pressure: browser,
SSH, Edge, Toolsmith, knowledge, documents and other modes load only the relevant
static adapters for the current request.

## Capability boundary

Every registered system tool has an `AgentToolCapability`. Persistent specialists
inherit all centrally authorized tools unless the user explicitly saves a
restricted capability set. Restricted scopes are enforced in two places:

1. provider tool schemas are filtered before a delegated model sees them;
2. the native execution path rejects calls outside the TaskLocal delegated scope.

Workflows executed by a restricted specialist use the same scope, preventing a
workflow from becoming a capability-escalation path.

## Permission boundary

`ToolRisk` classifies calls as read, write or execute. The policy is then applied
by AppState:

- **Confirm** — writes/execute require approval;
- **Workspace Trusted** — bounded normal workspace operations are trusted, while
  local shell/terminal execution, Shortcuts, Toolsmith, browser mutations,
  SSH/Edge, HTTP, personal-data mutations, delegation and workflow runs remain
  approval-gated;
- **Full Access** — explicit trusted-user mode that allows automatic execution
  and supported filesystem access outside the workspace.

Tool results are still audited and passed through secret redaction in all modes.

## Terminal and command boundary

The visible SwiftTerm PTY is separate from structured command execution. `run_command`
returns bounded stdout/stderr/exit status and has a timeout/repetition guard.
Workspace Trusted no longer treats arbitrary shell source as a bounded workspace
operation: local command/terminal execution is approval-gated because a normal
shell can intentionally access paths beyond its current working directory.

## Secret boundary

The Vault uses PBKDF2-HMAC-SHA256 and AES-GCM. Models receive labels/metadata, not
general secret-read access. Secret-aware tools resolve `secret_ref` natively.
HTTP credential injection, redirect rules and response redaction are implemented
inside the native Secret Broker/HTTP client rather than in model prompts.

## Browser boundary

Microsoft Edge automation uses a dedicated persistent AgenTM5N browser profile
and local Chromium DevTools Protocol transport. The browser layer never provides
cookie/localStorage/sessionStorage/saved-password export tools. `browser_batch`
is provider-neutral and converts an approved ordered batch into native browser
actions.

## Toolsmith boundary

Toolsmith definitions are persistent data, not newly compiled Swift code. Enabled
`custom_*` definitions are dynamically exposed to Ollama; Apple uses the static
focused Toolsmith adapter. Runtime scripts execute as explicit execute-risk child
processes with temporary HOME/TMP/XDG locations, minimal environment, bounded
runtime/output and no inherited Vault/provider/SSH-agent variables.

Toolsmith is not a kernel-level sandbox. Confirm/Workspace Trusted therefore keep
it behind the execution approval boundary; Full Access is the explicit opt-in for
unattended native runtime code.

## Local ML execution

- Apple Foundation Models: native on-device language model provider
- Core ML: local registered models with CPU/Apple Neural Engine compute policy
- Workspace Memory: lexical indexing plus optional local Core ML embeddings
- Ollama Local: local LLM provider
- Ollama Cloud: remote inference with local tool execution and secret handling

## Persistence

Managed state lives below `~/Library/Application Support/AgenTM5N/`: configuration,
conversation/audit, SSH profiles, encrypted Vault, Core ML registry, Knowledge
Library, Workspace Memory, generated documents, workflows and self-built tools.
Managed sensitive/configuration files use restrictive user-only POSIX permissions
where implemented.

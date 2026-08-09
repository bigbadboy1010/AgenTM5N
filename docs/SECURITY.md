# Security model

AgenTM5N is designed for a trusted personal macOS workstation and intentionally supports powerful local and remote operations. The security model separates model planning from native execution: providers can request tools, while the AgenTM5N runtime remains responsible for capability checks, permission policy, credential resolution, audit records and output redaction.

## Central execution boundary

The main Apple Foundation Models and Ollama paths converge on the same native AppState execution router. `AgentToolRegistry` is the provider-neutral authority for each tool's capability and risk classification (`read`, `write`, or `execute`). Module-specific helpers may provide sanitized human-readable summaries, but the central router does not let those helpers override registry risk.

Persistent specialist agents may define a capability sandbox. A restricted capability set is enforced when provider tool schemas are selected and again before delegated native execution. Nested delegation is monotonic: a child receives only the intersection of the parent scope and child profile, so a child cannot regain a capability removed by an outer specialist. Workflows executed by a restricted specialist cannot escape that scope.

Apple Foundation Models may create tool-call tasks concurrently. `AgentToolExecutionBridge` serializes native executions before they reach AppState's single visible approval path, preventing concurrent approval requests from overwriting one another.

## Permission modes

### Confirm

Read operations may run automatically. Writes and execute-risk operations require explicit approval.

### Workspace Trusted

Ordinary bounded workspace file reads/writes may run automatically. Sensitive operations continue to require approval, including:

- local shell execution and visible terminal commands
- SSH and Edge infrastructure actions
- Microsoft Edge browser mutations
- HTTP/API calls
- macOS Shortcuts execution
- Clipboard writes, notifications and Finder reveal actions
- Calendar/Contacts/Mail/Reminders mutations
- persistent agent create/update/delete and delegated-agent execution
- workflow create/delete and workflow runs
- Toolsmith management/execution and dynamic `custom_*` runtime tools

### Full Access

Full Access is an explicit trusted-user mode. It allows filesystem access outside the workspace and automatic execution of otherwise approval-gated tools. Audit, capability routing and secret redaction remain active, but the normal user approval boundary is intentionally removed.

## Workflows

A workflow is a stored composite action. `workflow_run` receives one explicit execution approval outside Full Access. The approval summary expands stored steps and shows sanitized concrete operation details before execution. Nested workflow management steps are prohibited. Secret values may not be embedded in workflow arguments; secret-aware tools use `secret_ref` labels.

Within a restricted specialist, every workflow step is checked against the active capability scope before execution. Replacing the contents of an existing disabled workflow preserves its disabled state.

## Secret vault

- the complete Vault payload is encrypted with AES-256-GCM
- the encryption key is derived with PBKDF2-HMAC-SHA256
- the KDF uses 600,000 iterations and a random 256-bit salt
- the master password is retained only in process memory
- Vault and managed credential files use restrictive user-only POSIX permissions

## Secret Broker

Models do not receive a general secret-read tool. `secret_list` returns metadata and labels only. Secret-aware native tools resolve `secret_ref` internally.

For HTTP/API execution:

- direct model-supplied Authorization, Proxy-Authorization and Cookie headers are blocked
- secret-bearing requests require HTTPS except for loopback HTTP
- loopback means localhost, `127.0.0.0/8`, or `::1`
- if a Vault secret has a non-empty `host`, that secret may only be injected into a request for the exact normalized host
- an empty Vault `host` intentionally remains an unbound generic secret for backward compatibility
- redirects carrying a secret must remain on the exact original request host and retain secure/loopback transport
- cookies are disabled in the ephemeral URLSession
- sensitive response headers are removed
- known raw/base64/percent-encoded/Bearer/Basic representations are redacted from model-visible output

The host binding is enforced natively before the secret is inserted into the request, including in Full Access.

## SSH materialization

SSH credentials remain linked to saved host profiles and the encrypted Vault. Temporary key/ASKPASS material is created with restrictive permissions and cleaned after structured execution. The runtime directory is purged during AgenTM5N startup.

## Toolsmith

Toolsmith permits the agent to create persistent zsh/Python runtime tools. This is deliberately treated as code execution, never as a harmless read operation.

Controls include:

- all dynamic `custom_*` execution is execute risk
- Workspace Trusted and Confirm keep Toolsmith management/execution behind approval
- generated source is limited in size and checked for blocked credential patterns
- Vault/provider/SSH-agent environment variables are not inherited
- each run receives temporary isolated `HOME`, `TMPDIR`, XDG config/cache paths
- Python user-site packages are disabled
- the configured workspace is the required working directory
- execution is limited to 60 seconds
- stdout/stderr are bounded and pass through central secret redaction
- custom tools can be explicitly enabled or disabled
- a disabled tool cannot be replaced through the central router until it has been explicitly re-enabled

Toolsmith is **not a kernel-level sandbox**. An approved script is native code running as the logged-in user and can intentionally reference absolute filesystem paths or initiate network connections. This is why Toolsmith remains execute-risk. Full Access should only be enabled when that level of trust is intended. A future strict-containment design can move Toolsmith into a dedicated sandboxed helper/XPC service with an explicit workspace grant.

## Browser automation

Microsoft Edge automation uses a dedicated AgenTM5N-managed browser profile and a loopback-only Chromium DevTools Protocol connection. Browser tools do not expose cookies, localStorage, sessionStorage or saved browser passwords. Text filling rejects password and file inputs. Multi-step interaction is represented by provider-neutral `browser_batch`, which receives one central execute approval and then runs only its declared ordered actions.

## Core ML managed storage

Core ML model persistence is treated as managed local data:

- source/compiled artifacts use content-addressed SHA-256 filenames
- identical content is reused rather than copied repeatedly
- imports compile and validate the persistent compiled artifact before registry commit
- newly created managed artifacts are removed when import fails
- unreferenced top-level artifacts inside the managed Core ML Sources/Compiled directories are cleaned during bootstrap
- registry persistence uses user-only permissions
- large models are restored lazily so application startup does not build their execution plans
- prediction models are cached in-process after first use
- `.all` compute units keep CPU, GPU and Apple Neural Engine available while Core ML decides operator placement

## macOS privacy

Calendar, Reminders and Contacts continue to be controlled by macOS privacy/TCC. Apple Mail and applicable macOS automation are controlled by Apple Events permission. AgenTM5N includes the required privacy usage descriptions and a Mac Access Center for authorization status.

## Local persistence

AgenTM5N creates its managed Application Support directories with user-only permissions where applicable. Configuration and chat history are local JSON and are not encrypted; the Vault is separately encrypted. Generated documents, telemetry and knowledge/memory stores should therefore be treated as normal local user data.

## Release controls

Release candidates must pass:

- target-Mac Swift debug build
- automated security regression tests
- arm64 release build
- Info.plist privacy-key validation
- Hardened Runtime/signature validation
- Developer ID validation for distribution builds
- full manual runtime matrix in `VALIDATION.md`
- notarization and stapling
- mounted-DMG and Gatekeeper validation

The release pipeline fails closed when a required gate is not satisfied. Static GitHub source-policy CI supplements but does not replace the target-Mac Xcode/FoundationModels/CoreML gate.

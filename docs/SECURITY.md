# Security model

AgenTM5N is designed for a trusted personal macOS workstation and intentionally
supports powerful local and remote operations. The security model separates
model planning from native execution: providers can request tools, while the
AgenTM5N runtime remains responsible for capability checks, permission policy,
credential resolution, audit records and output redaction.

## Central execution boundary

The main Apple Foundation Models and Ollama paths converge on the same native
AppState execution router. Each tool has a provider-neutral capability and risk
classification (`read`, `write`, or `execute`). Tool outputs are sanitized before
they are returned to a model.

Persistent specialist agents may optionally define a capability sandbox. A
restricted capability set is enforced when provider tool schemas are selected
and again before delegated native execution. Workflows created/executed by a
restricted specialist cannot be used to escape that capability set.

## Permission modes

### Confirm

Read operations may run automatically. Writes and execute-risk operations require
explicit approval.

### Workspace Trusted

Bounded normal workspace operations may run automatically. Sensitive operations
continue to require approval, including:

- local shell execution and terminal commands
- SSH and Edge infrastructure actions
- Microsoft Edge browser mutations
- HTTP/API calls
- macOS Shortcuts execution
- Calendar/Contacts/Mail/Reminders mutations
- delegated-agent execution
- workflow runs
- Toolsmith management/execution and dynamic `custom_*` runtime tools

### Full Access

Full Access is an explicit trusted-user mode. It allows filesystem access outside
the workspace and automatic execution of otherwise approval-gated tools. Audit,
capability routing and secret redaction still apply, but the normal user approval
boundary is intentionally removed.

## Workflows

A workflow is a stored composite action. `workflow_run` receives one explicit
execution approval outside Full Access. The approval summary expands the stored
steps and shows sanitized concrete operation details before execution. Nested
workflow management steps are prohibited. Secret values may not be embedded in
workflow arguments; secret-aware tools use `secret_ref` labels.

Within a restricted specialist, every workflow step is checked against that
specialist's capability sandbox before execution.

## Secret vault

- The complete Vault payload is encrypted with AES-256-GCM.
- The encryption key is derived with PBKDF2-HMAC-SHA256.
- The KDF uses 600,000 iterations and a random 256-bit salt.
- The master password is retained only in process memory.
- Vault and managed credential files use restrictive user-only POSIX permissions.

## Secret Broker

Models do not receive a general secret-read tool. `secret_list` returns metadata
and labels only. Secret-aware native tools resolve `secret_ref` internally.

For HTTP/API execution:

- direct model-supplied Authorization, Proxy-Authorization and Cookie headers are blocked
- secret-bearing requests require HTTPS except for loopback HTTP
- loopback means localhost, `127.0.0.0/8`, or `::1`
- redirects carrying a secret must remain on the exact original host and retain a secure/loopback transport
- cookies are disabled in the ephemeral URLSession
- sensitive response headers are removed
- known raw/base64/percent-encoded/Bearer/Basic representations are redacted from model-visible output

## SSH materialization

SSH credentials remain linked to saved host profiles and the encrypted Vault.
Temporary key/ASKPASS material is created with restrictive permissions and cleaned
up after structured execution. The runtime directory is purged during AgenTM5N
startup.

## Toolsmith

Toolsmith permits the agent to create persistent zsh/Python runtime tools. This
is deliberately treated as code execution, never as a harmless read operation.

Controls include:

- all dynamic `custom_*` execution is `execute` risk
- Workspace Trusted and Confirm keep it behind the normal approval boundary
- generated source is limited in size and checked for blocked credential patterns
- Vault/provider/SSH-agent environment variables are not inherited
- each run receives temporary isolated `HOME`, `TMPDIR`, XDG config/cache paths
- Python user-site packages are disabled
- the configured workspace is the required working directory
- execution is limited to 60 seconds
- stdout/stderr are bounded and then passed through central secret redaction
- custom tools can be disabled without deletion

Toolsmith is **not a kernel-level sandbox**. A script approved for execution is
still native code running as the logged-in user and can intentionally reference
absolute filesystem paths or initiate network connections. This is why Toolsmith
remains execute-risk. Full Access should only be enabled when that level of trust
is intended. A future strict-containment design can move Toolsmith into a dedicated
sandboxed helper/XPC service with an explicit workspace grant.

## Browser automation

Microsoft Edge automation uses a dedicated AgenTM5N-managed browser profile and
local Chromium DevTools Protocol connection. Browser tools do not expose cookies,
localStorage, sessionStorage or saved browser passwords. Multi-step browser
interaction is represented by provider-neutral `browser_batch`, which receives
one central execute approval and then executes only its declared ordered steps.

## macOS privacy

Calendar, Reminders and Contacts continue to be controlled by macOS privacy/TCC.
Apple Mail and applicable macOS automation are controlled by Apple Events
permission. AgenTM5N includes the required privacy usage descriptions in its app
bundle and a Mac Access Center for inspecting the current authorization state.

## Local persistence

AgenTM5N creates its managed Application Support directories with user-only
permissions where applicable. Configuration and chat history are local JSON and
are not encrypted; the Vault is separately encrypted. Generated documents and
knowledge/memory stores should therefore be treated as normal local user data.

## Release controls

Release candidates must pass:

- Swift debug build
- automated security regression tests
- release build
- Info.plist privacy-key validation
- Hardened Runtime/signature validation
- Developer ID validation for release builds
- notarization and stapling
- mounted-DMG and Gatekeeper validation

The release pipeline fails closed when a required gate is not satisfied.

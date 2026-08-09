# Agent Runtime

AgenTM5N 1.1.1 provides multi-turn tool calling for Ollama Local, Ollama Cloud
and Apple Foundation Models. Apple uses focused compile-time Swift `Tool`
adapters; all providers route into the same provider-neutral native tool model.

## Main agent loop

1. AgenTM5N builds provider messages and the allowed tool catalog.
2. The provider plans a response and may request one or more tools.
3. AgenTM5N resolves the provider-neutral tool capability, risk and sanitized
   approval summary.
4. A delegated specialist capability sandbox is checked when active.
5. The current permission mode decides whether explicit user approval is needed.
6. Approved calls execute in native Swift services.
7. Tool results are bounded, secret-redacted, audited and returned to the model.
8. The provider loop continues until no tool call remains or the configured
   iteration limit is reached.

Apple Foundation Models uses the same AppState executor through
`AgentToolExecutionBridge`. Focused packs keep the Apple tool context small and
avoid exposing irrelevant schemas to the on-device model.

## Tool families

The provider-neutral `AgentToolRegistry` currently covers:

- workspace listing/glob/search/read/write/patch
- local command and visible terminal
- Git status/diff/branches/checkout/commit
- SSH list/run/terminal/upload/download/tail/batch
- Edge infrastructure list/read/write/control
- Microsoft Edge browser session/tabs/open/read/action/batch
- Calendar, Contacts and Apple Mail read/mutations
- Reminders
- Clipboard, Notifications, Shortcuts, Finder and system diagnostics
- Secret metadata and HTTP(S)
- Core ML and Workspace Memory
- Unified Context, Knowledge Library and attachments
- persistent specialist agents and delegation
- reusable workflows
- Toolsmith and dynamic `custom_*` runtime tools
- generated documents
- version/update checks

The Tools Center displays the fixed system catalog and persistent self-built tools.

## Permission modes

### Confirm

- read-risk calls may execute automatically;
- write and execute-risk calls require explicit approval;
- normal workspace file boundaries remain active;
- tool calls are audited.

### Workspace Trusted

Bounded normal workspace file/Git mutations can run without repeated prompts, but
operations capable of escaping a simple working-directory boundary remain
approval-gated. This includes:

- `run_command` and `terminal_open`
- SSH/Edge execution and transfers
- browser navigation/mutations and `browser_batch`
- HTTP/API execution
- `shortcuts_run`
- Toolsmith management/execution and dynamic `custom_*` code
- Calendar/Contacts/Mail/Reminders mutations
- delegated-agent execution
- `workflow_run`

The working directory alone is not treated as a security sandbox for a shell.

### Full Access

- explicit trusted-user mode;
- tool calls run automatically;
- supported file tools may accept paths outside the workspace;
- local command-pattern blocking is relaxed according to the existing runtime;
- remote/browser/Toolsmith actions may run automatically;
- capability scopes for explicitly sandboxed delegated specialists and secret
  redaction remain enforced.

## Capability sandboxes

A persistent specialist has either:

- unrestricted inherited AgenTM5N capabilities; or
- an explicit set such as `workspace,memory`.

For an explicit sandbox, provider definitions are filtered before inference and
native delegated execution checks the same TaskLocal scope again. A workspace-only
specialist therefore cannot call SSH, browser or Toolsmith and cannot regain those
capabilities through a stored workflow.

## Workflows

A workflow stores 1–20 ordered provider-neutral tool calls. Nested workflow
management is prohibited and obvious secret-bearing argument keys are rejected.
Known unlocked Vault values are also rejected from workflow definitions.

`workflow_run` is a composite execute-risk action. Outside Full Access, the user
receives one approval for the complete stored workflow. The approval summary
expands each stored step into a sanitized concrete operation/risk summary before
execution. Steps run sequentially, stop on failure and remain inside a delegated
specialist capability scope when one is active.

## Toolsmith

Toolsmith creates persistent zsh/Python tools with typed parameters. Enabled tools
appear directly in Ollama provider definitions; Apple Foundation Models uses the
focused static Toolsmith adapter.

Every custom source execution is execute-risk. Child processes receive a temporary
HOME/TMP/XDG environment, a minimal PATH, structured argument files and no
inherited Vault/provider/SSH-agent environment. Runtime is capped at 60 seconds
and output is bounded/redacted. Toolsmith is not a kernel-level sandbox, so it
remains approval-gated outside Full Access.

## Workspace boundary

Relative file paths resolve against the configured workspace. Existing paths are
standardized and symlinks are resolved before boundary checks. For destinations,
the resolved parent is checked before the new filename is appended.

Full Access explicitly allows supported file operations outside this boundary.
Git operations remain tied to the configured workspace repository.

## Local command execution

Structured `run_command` uses non-interactive zsh with bounded stdout/stderr and
a timeout. A small blocklist rejects obvious destructive host-level commands
outside Full Access, and a repetition ledger rejects a third equivalent local
AgentRuntime call inside a short time window.

These checks are defense in depth, not a shell sandbox; the permission policy is
the primary boundary for arbitrary shell source.

## Browser execution

`browser_batch` is one provider-neutral execute-risk tool containing 1–12 declared
ordered interactions. After the single central approval, the native browser service
executes only those declared steps and can optionally perform a final page read.
Page refs are temporary and should be refreshed after navigation or major DOM
changes.

## Audit and telemetry

Each main tool execution records:

- tool name
- sanitized argument summary
- risk
- running/succeeded/failed/denied status
- bounded/redacted output
- timestamps

Telemetry additionally records provider, capability, duration, output byte count
and cache-hit state without persisting raw tool arguments or secret values.

## Current deliberate limitations

- provider-requested tool calls are executed sequentially;
- Git tools create local state but do not push;
- Toolsmith is approval-controlled native runtime code rather than a dedicated
  kernel-sandboxed XPC helper;
- Apple Foundation Models requires static adapter types, so dynamic `custom_*`
  functions are executed through the Toolsmith meta-adapter on Apple;
- release readiness still requires the target-Mac automated gate plus the manual
  runtime matrix in `VALIDATION.md`.

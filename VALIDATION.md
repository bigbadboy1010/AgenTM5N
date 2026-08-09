# Validation status

Date: 2026-08-09
Version: **1.1.1 Build 25 release candidate**
Branch: `agent/v1.1.0-platform-expansion`

This document distinguishes source-review status from target-Mac runtime status.
A feature is not considered release-green solely because it exists in source.

## Automated source/build gate

Run on the target Apple Silicon Mac with the configured full Xcode toolchain:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm .build-artifacts Package.resolved
bash scripts/verify.sh
bash scripts/build-app.sh
```

`verify.sh` now performs:

- SwiftPM dependency resolution and manifest validation
- arm64 debug compilation
- XCTest security regression suite

The initial security tests cover:

- Workspace Trusted classification for local execution, Shortcuts and Toolsmith
- provider-neutral `browser_batch` registration and execute risk
- technical capability filtering between workspace/terminal/SSH/browser tools
- Toolsmith naming and credential-pattern rejection
- persistent Toolsmith enable/disable state
- terminal capability exposure of Toolsmith management tools

`build-app.sh` then performs the arm64 release compilation, app assembly,
Info.plist generation, Hardened Runtime signing and signature verification.

## Permission/privacy gate

The generated application must contain non-empty usage descriptions for:

- Calendar full access
- Reminders full access
- Contacts
- Apple Events/Automation

The release check validates the expected Calendar, Contacts and Apple Events
entitlements and rejects `com.apple.security.get-task-allow` in the release app.
The Mac Access Center must show Calendar, Reminders and Contacts authorization
states and a link to Automation settings.

## Security hardening in this candidate

- `run_command`, `terminal_open` and `shortcuts_run` require approval in Workspace Trusted.
- Toolsmith management and dynamic runtime execution require approval in Workspace Trusted.
- Delegated specialist capability sandboxes filter provider tool definitions and are checked again before native execution.
- Workflow creation/execution respects delegated capability scopes.
- Workflow-run approval expands sanitized stored step details before the composite action is allowed.
- `browser_batch` is provider-neutral and receives one central execute approval.
- Secret-bearing HTTP uses HTTPS except for loopback HTTP and secret redirects stay on the original host.
- Toolsmith processes use temporary HOME/TMP/XDG locations and do not inherit Vault/provider/SSH-agent environment.
- Self-built tools can be enabled or disabled without deletion.

## Previously runtime-validated functional areas

The following areas had successful manual runtime checks during development and
must still receive a final regression pass after this hardening build:

- Calendar read/create/update/delete
- Contacts search/create/update
- Apple Mail list/read/draft/send/reply
- Reminders list/create/complete
- Clipboard read/write
- Notifications and Shortcuts
- local system/process/disk/network information
- SSH baseline execution and SSH2 batch/tail/upload/download
- Secret Broker and HTTP redaction behavior
- Edge infrastructure read/write/control
- Microsoft Edge open/read and form interaction
- Apple document generation/save path
- Toolsmith creation and execution of `custom_hello_tool`

## Required final runtime matrix

Before notarization, verify at minimum:

1. Apple On-Device normal chat and current-date tool.
2. Ollama Local and Ollama Cloud basic chat/tool routing.
3. Permission modes:
   - Confirm read vs write/execute behavior
   - Workspace Trusted bounded workspace mutation without prompt
   - Workspace Trusted local command/terminal/Shortcut/Toolsmith with prompt
   - Full Access behavior only after explicit selection
4. Specialist capability sandbox:
   - workspace-only agent can read workspace
   - same agent cannot invoke SSH, browser or Toolsmith
   - same agent cannot escape through a workflow
5. Workflow run approval visibly lists stored step operations.
6. Toolsmith:
   - list/get/create/run
   - deactivate/reactivate
   - disabled tool cannot execute
   - no Vault/provider secret appears in output/audit
7. Browser:
   - open/read
   - `browser_batch` fill/check/select/click
   - tabs, activate/close, keyboard, scroll, wait, back/forward/reload
8. macOS privacy status and mutation regression for Calendar, Reminders, Contacts and Mail Automation.
9. SSH/Edge regression with saved Vault-backed profiles.
10. HTTP secret transport:
    - HTTPS secret request succeeds
    - loopback HTTP secret request succeeds when intended
    - private-LAN/external plain HTTP secret request is rejected
11. Documents: DOCX, PDF, XLSX and PPTX on Apple and at least one Ollama provider.
12. Workspace semantic memory/Core ML prediction regression.
13. Activity/audit/telemetry/cache sanity check.

## Release gate

Only after the build and runtime matrix are green:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

Expected artifact:

```text
dist/AgenTM5N-1.1.1-build25.dmg
```

The release script requires Developer ID signing, Apple notarization acceptance,
stapling and final Gatekeeper verification before printing `RELEASE READY`.

## Known trust boundary

Toolsmith is execute-risk native runtime code, not a kernel-level sandbox. Outside
Full Access it is protected by the explicit AgenTM5N permission boundary and a
restricted child-process environment. Full Access intentionally means the user
has opted into unrestricted execution. A dedicated sandboxed helper/XPC runtime
remains a possible future defense-in-depth enhancement rather than a prerequisite
for this personal-workstation release model.

# Validation status

Date: 2026-08-09
Version: **1.1.2 Build 28 release candidate**
Branch: `agent/v1.1.0-platform-expansion`

This document separates source-review status, automated target-Mac status and manual runtime status. A feature is not release-green merely because the source change exists.

## Current gate state

The previous **1.1.2 Build 27** target-Mac run completed successfully with Xcode 27.0 Build 27A5228h: debug build, 8 XCTest security regressions and production build all passed. Build 28 contains additional review hardening and therefore requires a fresh target-Mac verification before release.

Run:

```bash
cd ~/Downloads/AgenTM5N

git fetch origin
git switch agent/v1.1.0-platform-expansion
git pull --ff-only origin agent/v1.1.0-platform-expansion

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm .build-artifacts Package.resolved

bash scripts/verify.sh
bash scripts/build-app.sh
```

Expected application metadata after the Build 28 source is verified:

```text
Version: 1.1.2
Build:   28
```

## Automated regression coverage

`SecurityPolicyTests` now covers at least the following policy invariants:

- Workspace Trusted approval classification for shell, terminal, Shortcuts, browser mutation, Toolsmith, visible system mutation and persistent agent/workflow mutation
- provider-neutral `browser_batch` registration and execute risk
- capability filtering between workspace/terminal/SSH/browser/Toolsmith
- delegated scope intersection and native bridge scope persistence
- Toolsmith naming and credential-pattern rejection
- persistent Toolsmith enable/disable behavior
- fail-closed replacement of a disabled Toolsmith tool through the agent router
- terminal capability exposure of Toolsmith management tools
- registry definition coverage for fixed catalog tools
- central registry risk classification checks
- Vault secret host binding normalization/mismatch rejection
- Core ML content-addressed managed-storage reuse
- Core ML orphan cleanup behavior

The Build 28 suite must be run on the target Mac before its exact passing test count is recorded here.

## Security hardening in Build 28

### Permission and capability boundary

- AgentToolRegistry is the central risk authority used by the AppState router.
- Workspace Trusted allows ordinary bounded workspace file operations without approval but requires approval for shell/runtime/external operations, macOS personal mutations, system mutations and persistent agent/workflow mutations.
- nested specialist delegation is capability-monotonic; a child cannot add capabilities removed by an outer specialist
- Foundation Models tool execution is serialized before the single visible AppState approval path
- workflows remain checked against an active delegated capability scope before each stored step executes
- workflow-run approval expands sanitized stored step details

### Secret transport

- models receive secret metadata/labels rather than a general secret-read tool
- direct model-supplied Authorization/Proxy-Authorization/Cookie headers are blocked
- secret-bearing requests require HTTPS except on loopback
- a non-empty Vault secret `host` is an exact normalized destination binding
- secret-bearing redirects remain on the original host and secure/loopback transport
- cookies are disabled and sensitive response headers are removed
- known raw/base64/percent-encoded/Bearer/Basic secret representations are redacted

### Core ML persistence/runtime

- compute units use `.all`, leaving CPU, GPU and Apple Neural Engine available while Core ML decides placement
- managed models are content-addressed with SHA-256
- imports validate the compiled persistent artifact before registry commit
- failed imports roll back newly created managed artifacts
- identical source content resolves to the existing registered model instead of being duplicated
- unreferenced managed Core ML top-level artifacts are removed during bootstrap
- large registered models are not execution-plan-loaded during startup
- prediction models are lazily loaded and cached in-process after first use

The previously reproduced standalone test for the recompiled StatefulMistral model succeeded with `.all` after approximately 52.81 seconds. The same model still needs an in-app Build 28 `coreml_predict` regression before release.

### Toolsmith/workflows

- Toolsmith remains native execute-risk code rather than a kernel sandbox
- runtime receives private temporary HOME/TMP/XDG paths and a minimal environment
- Vault/provider/SSH-agent environment is not inherited
- a disabled Toolsmith tool cannot be silently replaced/re-enabled through the central router; explicit re-enable is required first
- replacing a disabled workflow preserves its disabled state

## Required final runtime matrix

Before notarization verify all of the following on **Build 28**:

1. Apple On-Device normal chat and authoritative current-date/time behavior.
2. Ollama Local and Ollama Cloud basic chat plus provider-neutral tool routing.
3. Permission modes:
   - Confirm: read auto, write/execute approval
   - Workspace Trusted: bounded workspace file write auto
   - Workspace Trusted: `run_command`, terminal, Shortcut, browser mutation, HTTP, Toolsmith, system mutation, agent/workflow mutation require approval
   - Full Access only after explicit selection
4. Specialist sandbox:
   - workspace-only agent can use `list_directory`
   - same agent cannot invoke terminal, SSH, browser or Toolsmith
   - restricted parent delegating to a broader child cannot regain removed capabilities
   - workflow cannot escape specialist scope
5. Workflow approval visibly lists stored steps; disabled workflow stays disabled after replacement.
6. Toolsmith:
   - list/get/create/run
   - disable/reactivate
   - disabled tool cannot run
   - disabled tool cannot be replaced until explicitly re-enabled
   - no Vault/provider secret appears in result/audit
7. Browser:
   - open/read
   - `browser_batch` fill/check/select/click
   - tabs, activate/close, keyboard, scroll, wait, back/forward/reload
8. macOS privacy/status and mutations for Calendar, Reminders, Contacts and Mail Automation.
9. SSH/Edge regression with saved Vault-backed profiles.
10. HTTP secret transport:
    - HTTPS request with correctly host-bound secret succeeds
    - same secret to a different HTTPS host is rejected before transmission
    - loopback HTTP secret request succeeds when intended
    - private-LAN/external plain HTTP secret request is rejected
11. Documents: DOCX, PDF, XLSX and PPTX on Apple and at least one Ollama provider.
12. Core ML:
    - application starts without eagerly loading the multi-gigabyte registered model
    - `coreml_describe_model` reports CPU/GPU/Neural Engine adaptive policy
    - in-app prediction no longer produces execution-plan error `-14`
    - second prediction in the same process avoids rebuilding the model execution plan
    - re-importing identical source does not create another multi-gigabyte Sources/Compiled pair
13. Workspace Memory lexical regression plus semantic regression with a genuinely compatible embedding model.
14. Activity/audit/telemetry/cache sanity check.
15. Quit/relaunch persistence check for configuration, agents, workflows, Toolsmith, Vault metadata links and Core ML registry.

## Release gate

Only after the Build 28 automated gate and runtime matrix are green:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

Expected artifact:

```text
dist/AgenTM5N-1.1.2-build28.dmg
```

The release script requires Developer ID signing, Apple notarization acceptance, stapling, mounted-DMG validation and Gatekeeper verification before printing `RELEASE READY`.

## Known trust boundary

Toolsmith is intentionally powerful native runtime code and is not a kernel-level sandbox. Outside Full Access it remains protected by the explicit execution approval boundary and a restricted child-process environment. A dedicated sandboxed helper/XPC service remains a possible future defense-in-depth enhancement, not a claim made by Build 28.

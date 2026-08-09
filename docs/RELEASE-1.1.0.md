# AgenTM5N 1.1.0 — Platform Expansion

Version: **1.1.0**  
Build: **24**

## Goal

AgenTM5N 1.1 turns the 1.0 provider-specific feature set into a provider-neutral agent platform. Apple On-Device, Ollama Local, Ollama Cloud, persistent specialist agents, workflows, macOS tools, SSH, Core ML, semantic memory, and Vault-backed HTTP access share the same native permission, audit, redaction, cache, and telemetry path.

## Implemented milestones

### 1. Universal Tool Registry

`AgentToolRegistry` owns the provider-neutral catalog, capability, risk, caching and secret-awareness metadata. Ollama receives registry definitions directly. Apple Foundation Models receives small focused wrappers selected per request to respect the on-device context budget.

### 2. Secure Secret Broker

- `secret_list` exposes labels/kinds/optional host+username only.
- There is intentionally no `secret_get` tool.
- Secret values are resolved only inside the native executor.
- Known raw/base64/Basic/Bearer/percent-encoded secret representations are redacted from model-visible output.
- Direct model-supplied Authorization/Cookie headers are blocked.
- Vault-backed HTTP secrets require HTTPS except for local/private hosts.
- Cross-host redirects are blocked while a secret is attached.

### 3. Agent-to-Agent Delegation

`agent_delegate` runs a bounded task through one enabled persistent specialist. Existing agent files remain compatible. New agents can optionally define tool capability scopes. Ollama requests are hard-filtered to the allowed capability packs; Apple nested delegates are tool-less to avoid recursive Foundation Models sessions and context exhaustion.

### 4. Apple Neural Engine Semantic Memory

The existing Workspace Memory semantic index is exposed as a first-class agent capability:

- `workspace_index_status`
- `workspace_index_build`
- `workspace_semantic_search`
- `workspace_index_clear`

When a registered embedding model is selected, embeddings run locally with Core ML `cpuAndNeuralEngine` compute policy and cosine similarity. Lexical mode remains the fallback.

### 5. More Native Mac Tools

- Reminders: list/create/complete using EventKit full access
- Clipboard: read/write
- Notifications
- Shortcuts: list/run
- Finder reveal
- System information
- Process list
- Disk information
- Network information

Calendar, Contacts and Apple Mail remain unchanged from 1.0.x.

### 6. SSH 2.0

- `ssh_upload`
- `ssh_download`
- `ssh_tail_log`
- `ssh_run_batch`

SCP uses the same Vault-backed password/private-key/passphrase path as `ssh_run`. Batch execution intentionally uses one SSH connection for multiple diagnostic commands instead of persisting long-lived ControlMaster credential state.

### 7. Native HTTP/API Tool

`http_request` supports GET/HEAD/POST/PUT/PATCH/DELETE/OPTIONS with bounded request/response sizes, ephemeral URLSession state, optional Vault-backed authentication, redirect controls and output redaction.

### 8. Tool Observability

The new Activity view records bounded operational metadata only:

- tool name
- capability
- provider
- risk
- success/failure
- latency
- output byte count
- cache hit

Tool arguments and secret values are not stored in telemetry.

### 9. Read Cache

A bounded in-memory TTL cache accelerates safe read tools. Any write/execute operation invalidates the cache. Vault/config/workspace/SSH/Core ML/index changes also invalidate cached results.

### 10. Core ML Expansion

`coreml_predict` now accepts:

- Double/Int64/String scalars
- nested numeric JSON arrays for `MLMultiArray`
- local image paths for Core ML image inputs

Core ML remains local and requests CPU + Apple Neural Engine compute units.

### 11. Persistent Workflows

Reusable workflows are stored locally in `workflows.json` and exposed through:

- `workflow_list`
- `workflow_create`
- `workflow_delete`
- `workflow_run`

Workflow definitions reject embedded secret-like arguments and use `secret_ref` labels instead. The Workflows UI can send a saved workflow to the main chat for execution.

### 12. Update / Release Hardening

- 1.1.0 / Build 24 release defaults
- Reminders privacy usage declaration
- release gate validates Calendar + Reminders + Contacts + Apple Events privacy metadata
- release scripts prefer the newer `diskutil image` workflow and retain `hdiutil` compatibility fallback
- `app_version_info`
- `app_check_update` for explicit HTTPS JSON update manifests; checking never installs automatically

## Security invariants

1. Models never receive raw Vault secret values through a supported tool.
2. `secret_list` returns no secret ID/value.
3. Remote/external actions remain approval-required in Workspace Trusted mode.
4. Personal macOS mutations remain approval-required in Workspace Trusted mode.
5. Workflows and delegation are explicit execute actions.
6. Workspace filesystem boundaries are enforced unless Full Access is selected.
7. SCP local paths resolve symlinks before workspace-boundary validation.
8. Telemetry contains no tool arguments.
9. Cache is memory-only and invalidated by mutations.
10. Apple On-Device uses focused tool packs instead of the full registry.

## Integration test matrix

### Gate A — Build

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm Package.resolved
bash scripts/verify.sh
bash scripts/build-app.sh
```

Expected: `Version: 1.1.0 Build 24`.

### Gate B — 1.0 regression

With Apple On-Device:

1. list three calendar events
2. create and delete a test calendar event
3. search a contact
4. create an Apple Mail draft without sending
5. list saved SSH profiles
6. run `whoami; hostname; uname -a` against an existing SSH profile

Repeat representative read/tool calls with Ollama Local and Ollama Cloud.

### Gate C — Secret Broker

1. Unlock Vault.
2. Ask: `Zeige mir die verfügbaren Secret-Labels und Typen, aber keine Secret-Werte.`
3. Verify output contains labels/types but no raw values or secret UUIDs.
4. Use a controlled API with `http_request` + exact `secret_ref` label.
5. Verify Audit/Activity/model output contain no secret value.

### Gate D — Native Mac 1.1

Apple On-Device:

- `Zeige meine offenen Erinnerungen.`
- create a disposable reminder and mark it complete
- `Zeige Systeminfo und freien Plattenplatz.`
- clipboard read/write with non-sensitive test text
- list Shortcuts
- send a harmless local notification

### Gate E — SSH 2.0

On a test SSH profile:

- `ssh_run_batch`: whoami, hostname, uptime, df -h
- upload a disposable workspace text file to `/tmp/agentm5n-1.1-test.txt`
- download it back into the workspace
- tail a known non-sensitive log/test file
- delete disposable remote test data manually or via approved `ssh_run`

### Gate F — Semantic Memory / ANE

1. Register/select a suitable Core ML embedding model.
2. Build Workspace Memory index with that model.
3. Verify status reports semantic mode/model/dimension.
4. Search using wording not literally present in the target file.
5. Confirm the intended chunk is returned.

### Gate G — Core ML

- existing scalar model regression
- one MLMultiArray model with nested numeric JSON arrays
- one image-input model using a local image path

### Gate H — Specialist Delegation

Create a disposable specialist with capabilities:

`ssh,system,memory`

Delegate a system/SSH task and verify it succeeds. Ask it to modify Git or send mail and verify those tools are not present in the delegated Ollama tool set.

### Gate I — Workflows

Create `Lenovo Health Check` with an `ssh_run_batch` step, run it from Workflows, verify central approval and bounded step output.

### Gate J — Cache / Activity

1. Run `system_info` twice within 60 seconds.
2. Open Activity.
3. Verify the second call records `Cache`.
4. Verify Activity contains tool/provider/risk/latency/output-size but no arguments or secrets.

### Gate K — Release

Only after A–J pass:

```bash
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
unset AGENTM5N_SIGNING_IDENTITY
bash scripts/release-macos.sh
```

Expected final artifact:

`dist/AgenTM5N-1.1.0-build24.dmg`

Expected final state:

- Developer ID valid
- Hardened Runtime active
- Notarization Accepted
- ticket stapled
- Gatekeeper accepted
- DMG verification OK

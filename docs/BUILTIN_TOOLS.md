# AgenTM5N 1.2 Built-in Tool Packs

AgenTM5N 1.2 ships a maintained baseline of operational tools in addition to the native tool catalog and user-created Toolsmith tools.

The maintained tools use the `custom_builtin_*` namespace and are installed into the existing Toolsmith store. They therefore use the same bounded runtime, audit, approval and capability path as other AgenTM5N tools.

## Filesystem pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_fs_stat` | read | file/directory metadata and disk usage |
| `custom_builtin_fs_sha256` | read | SHA-256 of a workspace file |
| `custom_builtin_fs_mkdir` | write | create workspace directory tree |
| `custom_builtin_fs_copy` | write | copy inside workspace |
| `custom_builtin_fs_move` | write | move/rename inside workspace |
| `custom_builtin_archive_create` | write | create ZIP archive |
| `custom_builtin_archive_extract` | write | extract ZIP archive |

Filesystem built-ins reject absolute paths and `..` traversal. Their paths remain relative to `AGENTM5N_WORKSPACE`.

## Git pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_git_log` | read | bounded decorated history |
| `custom_builtin_git_show` | read | revision metadata and patch |
| `custom_builtin_git_fetch` | execute | fetch/prune remote refs |
| `custom_builtin_git_pull_ff` | execute | fast-forward-only pull |
| `custom_builtin_git_push` | execute | normal current-branch push; never force-push |

Remote names and revisions are validated before invocation.

## Docker pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_docker_ps` | read | list containers |
| `custom_builtin_docker_inspect` | read | inspect Docker object |
| `custom_builtin_docker_logs` | read | bounded container logs |
| `custom_builtin_docker_stats` | read | one-shot resource stats |
| `custom_builtin_docker_action` | execute | start/stop/restart/pause/unpause |
| `custom_builtin_docker_exec` | execute | non-interactive command inside a container |

The Docker CLI is resolved only from known executable roots such as Homebrew and system binary directories.

## Podman pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_podman_ps` | read | list containers |
| `custom_builtin_podman_inspect` | read | inspect object |
| `custom_builtin_podman_logs` | read | bounded logs |
| `custom_builtin_podman_action` | execute | container lifecycle action |

## Kubernetes pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_kube_contexts` | read | current/all kube contexts |
| `custom_builtin_kube_pods` | read | pods in current, selected or all namespaces |
| `custom_builtin_kube_logs` | read | bounded pod logs |
| `custom_builtin_kube_describe` | read | describe a resource |
| `custom_builtin_kube_rollout_status` | read | rollout status with bounded timeout |
| `custom_builtin_kube_apply` | execute | apply a manifest from the AgenTM5N workspace |

`kube_apply` only accepts a workspace-relative manifest path.

## OpenShift pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_oc_project` | read | current and available projects |
| `custom_builtin_oc_pods` | read | project pods |
| `custom_builtin_oc_routes` | read | project routes |
| `custom_builtin_oc_logs` | read | bounded pod logs |

OpenShift mutation remains available through approved terminal/SSH workflows until a broader typed mutation pack is added.

## Network pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_dns_lookup` | read | DNS resolution |
| `custom_builtin_ping` | execute | bounded ICMP probe |
| `custom_builtin_traceroute` | execute | bounded traceroute |
| `custom_builtin_port_probe` | execute | one TCP connect probe |

Active probes are execute-risk even though they do not mutate the local Mac.

## MCP stdio pack

| Tool | Risk | Purpose |
|---|---|---|
| `custom_builtin_mcp_stdio_list` | execute | start an MCP stdio server and request `tools/list` |
| `custom_builtin_mcp_stdio_call` | execute | start an MCP stdio server and invoke `tools/call` |

Security properties:

- no arbitrary shell string is used to start the MCP executable
- executable must resolve from approved CLI roots or an approved absolute executable path
- server arguments are JSON-decoded into an argv array
- a minimal environment is supplied
- stderr is not merged into model-visible protocol output
- response timeout is bounded
- MCP calls remain approval-gated outside explicit Full Access

The initial 1.2 bridge is intentionally stateless per AgenTM5N call: the MCP process is launched, initialized if required, used for one request and terminated. Persistent MCP sessions and OAuth/HTTP transports can be built on top of the same capability policy later.

## Built-ins and local customization

AgenTM5N does not overwrite an existing Toolsmith record with the same built-in name. This protects user-local changes and avoids silently re-enabling a disabled customized tool.

If a maintained tool requires a CLI that is not installed, execution fails explicitly with `Required CLI not found` rather than silently substituting another tool.

## Capability mapping

The central `BundledToolCatalog` assigns capability and risk metadata independently from the executable implementation. This means a model cannot change the declared risk by editing arguments.

Broad mapping:

- filesystem → `workspace`
- Git → `git`
- Docker/Podman/Kubernetes/OpenShift/Network → `system`
- MCP → `terminal`

Global capability settings and specialist-agent scopes apply before execution.

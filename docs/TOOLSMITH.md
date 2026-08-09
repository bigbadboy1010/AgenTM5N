# AgenTM5N Toolsmith

Toolsmith lets AgenTM5N create persistent runtime tools without rebuilding or resigning the macOS application.

## Model

A self-built tool contains:

- a normalized `custom_*` function name
- a precise description used by model tool selection
- `zsh` or `python3` source
- up to 16 typed parameters (`string`, `integer`, `number`, `boolean`)
- enabled/disabled state
- persistent metadata and last-run timestamp

The library is stored under AgenTM5N Application Support as `self-built-tools.json` with directory mode `0700` and file mode `0600`.

## Toolsmith management tools

- `toolsmith_list`
- `toolsmith_get`
- `toolsmith_create`
- `toolsmith_set_enabled`
- `toolsmith_delete`
- `toolsmith_run`

Ollama Local/Cloud additionally receive enabled self-built tools as first-class generated function definitions, so a tool such as `custom_workspace_summary` can be called directly on a subsequent model request.

Apple Foundation Models cannot synthesize new Swift `Tool` conformances at runtime. AgenTM5N therefore exposes a focused static `toolsmith` adapter with `list/get/create/enable/disable/delete/run` operations. It resolves and executes the same persistent runtime tools through the provider-neutral bridge.

## Runtime contract

Self-built source receives a deliberately minimal environment:

- `AGENTM5N_TOOL_NAME`
- `AGENTM5N_WORKSPACE`
- `AGENTM5N_ARGS_FILE` — path to a mode-0600 JSON object containing all arguments
- `AGENTM5N_ARG_<NAME>` — primitive parameter convenience values
- a temporary per-run `HOME`
- a temporary per-run `TMPDIR`
- temporary XDG config/cache directories
- `PYTHONNOUSERSITE=1`
- a minimal system `PATH`

The process does **not** inherit the AgenTM5N process environment, so Vault values, provider tokens and SSH-agent variables are not automatically available. The process runs with the configured workspace as its current directory. It should print its result to stdout and use stderr for diagnostics. Exit status zero means success.

Example Python source:

```python
import json
import os
from pathlib import Path

args = json.loads(Path(os.environ["AGENTM5N_ARGS_FILE"]).read_text())
name = args.get("name", "world")
print(f"hello {name}")
```

Example parameter manifest:

```json
[
  {
    "name": "name",
    "type": "string",
    "description": "Name to greet",
    "required": true
  }
]
```

## Security invariants

1. Every self-built tool is classified as `execute` risk regardless of source or description. A generated manifest cannot downgrade its own risk.
2. Tool creation/deletion/state changes are mutations and execution remains subject to AgenTM5N permission policy and audit.
3. Toolsmith belongs to the existing `terminal` capability. In Workspace Trusted mode, Toolsmith management and every direct `custom_*` execution require approval. Full Access is the explicit opt-in for unattended native execution.
4. Restricted specialist agents need `terminal` capability to create, manage or execute self-built tools. The capability is enforced in provider tool selection and delegated native execution.
5. The child process receives temporary HOME/TMP/XDG paths and no inherited Vault/provider/SSH-agent environment.
6. The global result sanitizer redacts known unlocked Vault values from model-visible output.
7. Source is capped at 64 KiB; arguments are schema-validated; execution is capped at 60 seconds; output is bounded.
8. Private-key blocks and direct macOS Keychain password-dump patterns are rejected from generated source.
9. Temporary source, argument and output files use restrictive permissions and are removed after execution.
10. Disabling a custom tool removes it from enabled provider definitions without deleting its source or metadata.
11. The central execution router fails closed if `toolsmith_create` targets an existing disabled tool. The user must explicitly re-enable the record with `toolsmith_set_enabled` before replacing its implementation, so replacement cannot silently reactivate disabled runtime code.

## Trust boundary

Toolsmith is **not a kernel-level sandbox**. An approved zsh/Python program runs as the logged-in user and can intentionally reference absolute paths or initiate network connections. The primary boundary is therefore the AgenTM5N capability and permission system: Toolsmith remains execute-risk outside Full Access.

For a future stricter multi-user or enterprise deployment, move dynamic runtime code into a dedicated sandboxed helper/XPC service with an explicit workspace grant and separately declared network/filesystem capabilities.

## Suggested acceptance test

Ask a Toolsmith-capable agent to create a disposable tool:

> Create a reusable Python tool named `hello_tool` with one required string parameter `name`. It must print `Hello <name>` and contain no secrets.

The stored name should become `custom_hello_tool`.

Then run it with `name=AgenTM5N` and expect:

```text
Hello AgenTM5N
```

Then disable it with `toolsmith_set_enabled` and verify execution is rejected. Attempting `toolsmith_create` with the same disabled name must also be rejected. Explicitly re-enable the tool, replace it if desired, verify execution succeeds again, and finally delete the disposable tool with `toolsmith_delete`.

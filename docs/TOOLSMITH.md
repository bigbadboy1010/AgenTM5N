# AgenTM5N Toolsmith

Toolsmith lets AgenTM5N create persistent runtime tools without rebuilding or resigning the macOS application.

## Model

A self-built tool contains:

- a normalized `custom_*` function name
- a precise description used by model tool selection
- `zsh` or `python3` source
- up to 16 typed parameters (`string`, `integer`, `number`, `boolean`)
- persistent metadata and last-run timestamp

The library is stored under AgenTM5N Application Support as `self-built-tools.json` with directory mode `0700` and file mode `0600`.

## Toolsmith management tools

- `toolsmith_list`
- `toolsmith_get`
- `toolsmith_create`
- `toolsmith_delete`
- `toolsmith_run`

Ollama Local/Cloud additionally receive enabled self-built tools as first-class generated function definitions, so a tool such as `custom_workspace_summary` can be called directly.

Apple Foundation Models cannot synthesize new Swift `Tool` conformances at runtime. The Apple persistent-agent pack therefore exposes one static `toolsmith` adapter with `list/get/create/delete/run` operations. It resolves and executes the same persistent runtime tools through the provider-neutral bridge.

## Runtime contract

Self-built source receives a deliberately minimal environment:

- `AGENTM5N_TOOL_NAME`
- `AGENTM5N_WORKSPACE`
- `AGENTM5N_ARGS_FILE` — path to a mode-0600 JSON object containing all arguments
- `AGENTM5N_ARG_<NAME>` — primitive parameter convenience values

The process runs with the configured workspace as its current directory. It should print its result to stdout and use stderr for diagnostics. Exit status zero means success.

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

1. Every self-built tool is classified as `execute` risk regardless of its source or description. A generated manifest cannot downgrade its own risk.
2. Tool creation/deletion is a mutation and execution remains subject to AgenTM5N permission policy and audit.
3. Workspace Trusted treats the `customTools` capability as externally sensitive, so self-built tool operations require approval there. Full Access is the explicit opt-in for unattended execution.
4. The child process does not inherit the application's environment. API keys, provider tokens and Vault values are not passed automatically.
5. The global AgenTM5N result sanitizer still redacts known unlocked Vault values from tool output.
6. Source is capped at 64 KiB; arguments are schema-validated; execution is capped at 60 seconds; combined model-visible output is capped at 256 KiB.
7. Private-key blocks and direct macOS Keychain password lookup commands are rejected from generated source.
8. Temporary source, argument and output files are created in a private runtime directory and removed after execution.
9. Restricted specialist agents must explicitly include the `customTools` capability. Full-parity agents inherit it automatically through `capabilities=all`.

## Suggested acceptance test

Ask a Toolsmith-capable agent to create a disposable tool:

> Create a reusable Python tool named `hello_tool` with one required string parameter `name`. It must print `Hello <name>` and contain no secrets.

The stored name should become `custom_hello_tool`.

Then run it with `name=AgenTM5N` and expect:

```text
Hello AgenTM5N
```

Finally delete the disposable tool with `toolsmith_delete`.

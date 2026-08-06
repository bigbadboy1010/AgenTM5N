# Agent Runtime

AgenTM5N 0.2.0 adds a multi-turn tool-calling runtime for Ollama Local and
Ollama Cloud. Apple Foundation Models remains a chat-only provider in this
milestone.

## Agent loop

1. AgenTM5N sends the current conversation and tool schemas to `/api/chat`.
2. Streamed `content`, `thinking` and `tool_calls` fields are accumulated.
3. The assistant turn, including its tool calls, is appended to the provider
   conversation.
4. Each requested tool is evaluated by the permission policy.
5. Approved tools are executed and recorded in the local chat audit.
6. Tool results are appended as `role: tool` messages with `tool_name`.
7. The loop continues until the model returns no tool calls or the configured
   iteration limit is reached.

## Built-in tools

| Tool | Risk | Purpose |
|---|---|---|
| `list_directory` | read | List up to 500 visible entries |
| `read_file` | read | Read UTF-8 text up to 512 KiB |
| `write_file` | write | Atomically create or replace UTF-8 text up to 1 MiB |
| `run_command` | execute | Run a Zsh command in the workspace |
| `git_status` | read | Run `git status --short --branch` |
| `git_diff` | read | Return working-tree or staged Git diff |

Command output is limited to 256 KiB per stream and command execution is
terminated after 120 seconds.

## Permission modes

### Confirm

- Read tools within the workspace execute automatically.
- Write and execute tools require a visible one-time approval.
- File tools remain restricted to the configured workspace.
- A small set of destructive system command patterns remains blocked.

### Workspace Trusted

- Read, write and execute tools run automatically.
- File tools remain restricted to the configured workspace.
- Destructive system command patterns remain blocked.

### Full Access

- Tool calls run automatically.
- Absolute file paths outside the workspace are accepted.
- The workspace remains the current directory for shell commands.
- Workspace command-pattern blocking is disabled.
- Every tool call remains visible in the conversation audit.

## Workspace boundary

Relative paths resolve against the configured workspace. Existing paths are
standardized and symlinks are resolved before the boundary check. For new files,
the parent directory is resolved before the destination filename is appended.

Full Access explicitly disables this boundary check.

## Audit records

Each tool execution stores:

- tool name
- redacted argument summary for file content
- risk category
- status: running, succeeded, failed or denied
- bounded output
- start and end timestamps

These records are persisted with the chat history. Vault secret values are not
made available as agent tools in 0.2.0.

## Current limitations

- File edits replace complete files; patch-based editing is planned.
- Tool calls are executed sequentially even when the model requests them in
  parallel.
- Repetition detection is not yet implemented.
- Apple Foundation Models does not receive tool schemas yet.
- Shell commands are local only; structured remote SSH execution is planned for
  the DevOps milestone.

# Agent Runtime

AgenTM5N 0.2.x provides a multi-turn tool-calling runtime for Ollama Local and
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

### Workspace inspection and editing

| Tool | Risk | Purpose |
|---|---|---|
| `list_directory` | read | List up to 500 visible directory entries |
| `glob_files` | read | Recursively find up to 500 matching files |
| `search_text` | read | Search UTF-8 files and return up to 200 locations |
| `read_file` | read | Read UTF-8 text up to 512 KiB |
| `apply_patch` | write | Replace exactly one known text block |
| `write_file` | write | Atomically create or replace UTF-8 text up to 1 MiB |
| `run_command` | execute | Run a Zsh command in the workspace |
| `terminal_open` | execute | Open the visible local terminal |

### Git

| Tool | Risk | Purpose |
|---|---|---|
| `git_status` | read | Run `git status --short --branch` |
| `git_diff` | read | Return working-tree or staged Git diff |
| `git_branches` | read | Return current and local branches |
| `git_checkout` | write | Create or switch a branch on a clean worktree |
| `git_commit` | write | Commit only explicit paths without push |

### SSH

| Tool | Risk | Purpose |
|---|---|---|
| `ssh_list_hosts` | read | Return non-secret saved host metadata |
| `ssh_run` | execute | Run a bounded remote command through a saved profile |
| `ssh_open_terminal` | execute | Open a saved profile in the visible terminal |

Command output is limited to 256 KiB per stream and structured command
execution is terminated after 120 seconds.

## Permission modes

### Confirm

- Read tools within the workspace execute automatically.
- Write, Git mutation, terminal and execute tools require visible one-time
  approval.
- File tools remain restricted to the configured workspace.
- A small set of destructive local system-command patterns remains blocked.
- Remote SSH execution requires approval.

### Workspace Trusted

- Local read, write, Git and execute tools run automatically.
- File tools remain restricted to the configured workspace.
- Destructive local system-command patterns remain blocked.
- `ssh_run` and `ssh_open_terminal` still require approval.

### Full Access

- Tool calls run automatically.
- Absolute file paths outside the workspace are accepted where the tool supports
  them.
- The workspace remains the current directory for local shell commands.
- Local command-pattern blocking is disabled.
- Remote SSH tools may run automatically.
- Every tool call remains visible in the conversation audit.

## Workspace boundary

Relative paths resolve against the configured workspace. Existing paths are
standardized and symlinks are resolved before the boundary check. For new files,
the parent directory is resolved before the destination filename is appended.

Full Access explicitly disables this boundary check for file operations. Git
operations always remain scoped to the configured repository workspace.

## Targeted editing

`apply_patch` is the preferred tool for existing files. It requires an exact
`old_text` block and applies the change only when that block appears exactly
once. A missing or ambiguous block fails without writing the file.

The recommended editing sequence is:

1. find files with `glob_files`
2. locate code with `search_text`
3. inspect context with `read_file`
4. modify with `apply_patch`
5. verify with `git_diff`
6. build or test with `run_command`
7. commit explicit paths with `git_commit`

## Repetition protection

Local AgentRuntime calls are canonicalized by tool name and sorted arguments.
A third equivalent call within 90 seconds is rejected. This permits an initial
execution and one verification execution while stopping simple tool loops.

## Audit records

Each tool execution stores:

- tool name
- redacted argument summary for file and patch content
- risk category
- status: running, succeeded, failed or denied
- bounded output
- start and end timestamps

These records are persisted with the chat history. Passwords, private keys,
passphrases and other Vault values are never returned to the model.

## Current limitations

- Tool calls are executed sequentially even when the model requests them in
  parallel.
- The repetition guard currently applies to local AgentRuntime tools; remote SSH
  actions rely on their explicit approval policy.
- Git tools create local state only and do not push.
- Dedicated audit export and workspace-specific tool presets are not yet
  implemented.
- Apple Foundation Models does not receive tool schemas yet.

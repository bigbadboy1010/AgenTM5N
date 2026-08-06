# Workspace engineering tools

AgenTM5N 0.2.2 adds targeted repository inspection, patch editing and local Git
operations to the controlled agent runtime.

## Tool inventory

### `glob_files`

Finds regular workspace files with a glob pattern.

Supported pattern elements:

- `**` matches recursively across directories
- `*` matches inside one path segment
- `?` matches one character inside one path segment

Examples:

```text
**/*.swift
*.yml
Sources/**
```

The result contains relative paths only and is capped at 500 entries.

### `search_text`

Searches UTF-8 files for one literal text fragment and reports:

```text
relative/path:line:column: preview
```

Options can restrict the root path, glob, case sensitivity and hidden files.
Search is capped at 200 results. Individual files larger than 1 MiB, binary
files, symlinks and common generated directories are skipped.

### `apply_patch`

Replaces one exact text block in an existing UTF-8 file.

The patch is rejected when:

- `old_text` is missing
- `old_text` occurs more than once
- the file is not UTF-8
- the file or resulting content exceeds 1 MiB
- the resolved path violates the workspace boundary

This is the preferred editing tool for existing files. `write_file` remains
available for file creation and intentional complete replacement.

### `git_branches`

Returns the current branch and local branch list.

### `git_checkout`

Switches to an existing branch or creates a local branch from the current HEAD.
The operation is rejected when the worktree is dirty. It never uses force and
never discards local changes.

### `git_commit`

Creates a local commit from explicit paths.

Guardrails:

- at least one concrete path is required
- the broad `.` path is rejected
- paths outside the workspace are rejected
- existing staged changes cause the operation to fail
- only the supplied paths are staged
- a failed commit attempts to unstage only those supplied paths
- no remote push is performed

## Repetition guard

Equivalent local tool calls are tracked by tool name and canonicalized
arguments. A third equivalent execution within 90 seconds is rejected. This
limits accidental agent loops while allowing an initial call and one deliberate
verification call.

The guard currently applies to tools executed through the local
`AgentRuntime`. Remote SSH actions retain their explicit approval policy.

## Permission behavior

| Tool | Confirm | Workspace Trusted | Full Access |
|---|---|---|---|
| `glob_files` | automatic | automatic | automatic |
| `search_text` | automatic | automatic | automatic |
| `apply_patch` | approval | automatic | automatic |
| `git_branches` | automatic | automatic | automatic |
| `git_checkout` | approval | automatic | automatic |
| `git_commit` | approval | automatic | automatic |

All executions remain visible in the chat audit.

## Recommended workflow

A safe code-change sequence is:

1. `git_status`
2. `glob_files`
3. `search_text`
4. `read_file`
5. `apply_patch`
6. `git_diff`
7. build or test with `run_command`
8. `git_commit` only after the diff and validation are acceptable

## Smoke tests

### Search

```text
Use glob_files with **/*.swift. Then use search_text to find
"public actor AgentRuntime" in Swift files. Do not modify anything.
```

### Patch

```text
Read a temporary text file, replace one exact sentence with apply_patch and
show git_diff. Do not commit.
```

### Safe branch creation

```text
Confirm that git_status is clean, list branches and create the branch
agent/test-workspace-tools with git_checkout. Do not commit or push.
```

### Scoped commit

```text
Commit only docs/WORKSPACE_ENGINEERING_TOOLS.md with the message
"document workspace engineering tools". Do not push.
```

Use a disposable test branch for branch and commit validation.

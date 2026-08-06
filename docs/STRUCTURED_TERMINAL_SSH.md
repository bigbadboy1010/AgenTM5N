# Structured Terminal and SSH Tools

AgenTM5N 0.2.1 separates non-interactive command execution from visible,
interactive terminal sessions.

## Local tools

### `run_command`

Runs `/bin/zsh -lc` in the configured workspace and returns bounded stdout,
stderr and the exit status. Use it when the agent must inspect command output.

### `terminal_open`

Opens the visible embedded terminal with an optional initial command and title.
It is intended for interactive user sessions. The agent does not scrape the
terminal screen or inject follow-up keystrokes into an existing session.

## SSH tools

### `ssh_list_hosts`

Returns only non-secret profile metadata:

- profile UUID
- display name
- hostname
- port
- username
- authentication type
- whether a credential or passphrase is configured

Secret identifiers and values are excluded.

### `ssh_run`

Runs a remote command non-interactively through a configured profile. AgenTM5N:

1. resolves the profile by name, hostname or UUID;
2. retrieves required credentials internally from the unlocked vault;
3. creates temporary private-key or askpass material with restrictive POSIX
   permissions when required;
4. executes `/usr/bin/ssh` without allocating a remote TTY;
5. returns bounded stdout, stderr and exit status;
6. removes all temporary credential material.

The model never receives password, key or passphrase values.

### `ssh_open_terminal`

Opens a configured profile in the visible embedded terminal. An optional remote
command can be started immediately after login. This is an interactive user
session, not a structured output channel.

## Permission behavior

| Mode | `terminal_open` | `ssh_list_hosts` | `ssh_run` | `ssh_open_terminal` |
|---|---|---|---|---|
| Confirm | approval | automatic | approval | approval |
| Workspace Trusted | automatic | automatic | approval | approval |
| Full Access | automatic | automatic | automatic | automatic |

Remote execution remains approval-gated in Workspace Trusted because the
workspace boundary does not constrain changes made on a remote system.

## Operational limits

- SSH connect timeout: 20 seconds
- connection attempts: 1
- command execution timeout: 120 seconds
- stdout and stderr are bounded by the Agent Runtime output limit
- host-key behavior: `StrictHostKeyChecking=accept-new`

## Current boundary

AgenTM5N can open interactive terminal sessions but does not yet maintain a
bidirectional agent-controlled PTY channel. The agent cannot read an arbitrary
existing terminal screen, answer interactive prompts, or control full-screen
programs such as `vim`, `top` or `less`. Structured local and remote work should
use `run_command` and `ssh_run`.

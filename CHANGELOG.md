# Changelog

All notable changes to AgenTM5N are documented in this file.

## [0.2.0] - 2026-08-06

### Added

- Multi-turn Ollama tool-calling agent loop with streamed `tool_calls`.
- Permission profiles: Confirm, Workspace Trusted and Full Access.
- Workspace selector and configurable maximum tool iterations.
- Built-in tools for directory listing, UTF-8 file reading and writing,
  shell command execution, Git status and Git diff.
- Per-tool approval UI for write and execute operations in Confirm mode.
- Persisted tool execution audit cards in the chat history.
- Command timeout, output limits, file-size limits and workspace path checks.
- Compatibility migration for existing 0.1.x configuration files.
- Explicit agent-readiness badge, active model and workspace in the chat UI.

### Fixed

- Agent requests now receive a binding runtime context that identifies the
  actual macOS workspace and real local tools.
- Models are instructed not to claim missing filesystem, terminal or repository
  access while AgenTM5N tools are available.
- Capability-denial responses without tool calls now receive a visible
  AgenTM5N diagnostic instead of remaining indistinguishable from a valid
  agent answer.
- The conversation reset action is labeled as a new session to avoid carrying
  unrelated persisted context into agent tests.

### Changed

- App version increased to 0.2.0 build 4.
- Default system prompt identifies the agent as AgenTM5N and instructs it to
  verify tool results before continuing.
- Apple Foundation Models remains a chat-only provider in this milestone.

## [0.1.1] - 2026-08-06

### Fixed

- Build scripts select a complete Xcode installation instead of standalone
  Command Line Tools.
- Full Xcode installations are discovered automatically, including
  `~/Downloads/Xcode-beta.app`.
- SwiftTerm repository URL corrected to `migueldeicaza/SwiftTerm`.
- SwiftTerm pinned to 1.11.0 with CoreText rendering, removing the optional
  command-line Metal Toolchain requirement.
- SwiftPM packaging made compatible with macOS Bash 3.2.
- SwiftPM resource bundles are copied into the generated macOS application.

### Changed

- Product, executable, application bundle and persistence directory renamed
  from `MacAgentForge` to `AgenTM5N`.
- Project licensing changed to GNU General Public License v3.0.

## [0.1.0] - 2026-08-06

### Added

- SwiftUI desktop shell.
- Ollama Local and Ollama Cloud streaming providers.
- Apple Foundation Models provider.
- AES-256-GCM encrypted secret vault.
- Embedded SwiftTerm PTY and SSH host profiles.
- Core ML model loading with CPU and Apple Neural Engine compute units.

# Changelog

All notable changes to AgenTM5N are documented in this file.

## [1.0.0] - 2026-08-08

### Added

- Native macOS Calendar tools for reading, creating, updating, and deleting events.
- Native Contacts search, create, and update tools.
- Apple Mail tools for recent-message listing, message reading, draft creation,
  sending, and replying through macOS Automation.
- Shared Apple On-Device / Ollama tool execution bridge so native Mac actions
  use the same permission and audit pipeline.
- Authoritative current Mac date, time, and time-zone grounding for model turns.
- Mac Access Center for Calendar, Contacts, Automation, router, permission, and
  audit visibility.
- Persistent reusable specialist-agent library with `agent_list`, `agent_get`,
  `agent_create`, `agent_update`, and `agent_delete`.
- Agenten UI for inspecting, enabling, disabling, deleting, and reusing saved
  specialist agents after application restarts.
- Dedicated AgenTM5N macOS application icon generated into a complete `.icns`.
- Hardened Runtime entitlements for Apple Events, Contacts, and Calendar.
- Developer-ID-aware application build with secure timestamp support.
- Release validation gate for version, build, bundle ID, icon, Hardened Runtime,
  entitlements, Developer ID, and Gatekeeper assessment.
- Notarized DMG release workflow using `notarytool` and `stapler`.
- Detailed V1.0 release and smoke-test documentation.

### Security

- Personal macOS mutations remain subject to the central AgenTM5N permission
  policy and audit trail.
- Workspace Trusted does not silently authorize personal Calendar, Contacts, or
  Mail mutations.
- Saved specialist agents cannot bypass AgenTM5N permissions, audit, or macOS
  TCC/Automation controls.
- Release notarization refuses ad-hoc signing and requires a valid Developer ID
  Application identity.
- Production release checks reject `get-task-allow` and require Hardened Runtime.

### Changed

- App version is 1.0.0 build 22.
- Calendar creation on Apple On-Device preserves local wall-clock components and
  performs authoritative conversion in Swift using the Mac time zone.
- Standard development builds may remain ad-hoc signed; distribution releases
  use Developer ID Application signing with a secure timestamp.

## [0.3.0] - 2026-08-06

### Added

- Persistent Core ML model registry with stable model UUIDs, unique display names
  and automatic restoration of the active compiled model after app restart.
- `coreml_list_models` returns registered models without internal filesystem
  paths.
- `coreml_describe_model` reports the selected or active model inputs, outputs
  and requested compute policy.
- `coreml_predict` runs a scalar JSON prediction through the controlled agent
  permission and audit workflow.
- Chat toolbar paperclip imports text, source, configuration, log, CSV, JSON,
  YAML, XML, Markdown and PDF content into the current prompt.
- PDF text extraction runs locally through PDFKit.
- Dedicated Neural Agent Tools documentation.

### Security

- Core ML tool results omit imported source and compiled model paths.
- Prediction JSON is capped at 1 MiB.
- Prompt import is capped at eight files, 2 MiB per file and 180,000 extracted
  characters per file.
- Unsupported binary and image content is rejected rather than silently
  ignored or misrepresented as analyzed.
- `coreml_predict` requires approval in Confirm mode and remains fully audited.

### Changed

- App version is 0.3.0 build 9.
- Imported Core ML models remain persistent and no longer need to be selected
  again after each application restart.

## [0.2.3] - 2026-08-06

### Added

- Native macOS Core ML importer for `.mlmodel`, `.mlpackage` and `.mlmodelc`.
- Persistent source and compiled model copies under AgenTM5N Application Support.
- Central macOS language detection through `Locale.preferredLanguages`.
- Binding language instructions for Ollama Local, Ollama Cloud and Apple
  Foundation Models.
- Localized Chat, Settings, Vault and Neural Engine core interfaces.

### Fixed

- `.mlpackage` and `.mlmodelc` package directories can be selected reliably.
- Core ML source models are compiled before asynchronous loading.
- Agent responses follow the current preferred macOS language while technical
  tool names, paths and command output retain their original form.

### Changed

- App version is 0.2.3 build 8.
- Core ML compute policy is described accurately as CPU + Apple Neural Engine
  requested; actual operator placement remains controlled by Core ML.

## [0.2.2] - 2026-08-06

### Added

- `glob_files` recursively finds workspace files with bounded glob patterns.
- `search_text` searches UTF-8 files and returns relative path, line, column and
  a bounded preview without requiring external tools such as ripgrep.
- `apply_patch` replaces exactly one known text block and fails safely when the
  old block is missing or ambiguous.
- `git_branches` reports the current branch and local branch inventory.
- `git_checkout` switches or creates local branches only when the working tree
  is clean and never forces or discards changes.
- `git_commit` stages only explicitly named workspace paths, rejects existing
  staged changes, creates a local commit and never pushes.
- Equivalent local tool calls are limited to two executions within a 90-second
  window to stop accidental agent loops.

### Security

- Search and glob operations skip symlinks and common generated or sensitive
  directories such as `.git`, `.build`, `.swiftpm`, `dist` and `node_modules`.
- Search output is capped at 200 matches and glob output at 500 paths.
- Patch and write operations retain the existing workspace and file-size
  boundaries.
- Git paths are normalized against the active workspace and `git_commit`
  rejects the broad `.` path.
- Git checkout is blocked on dirty worktrees; Git commit is blocked when staged
  changes already exist.

### Changed

- App version is 0.2.2 build 7.
- Agents are instructed through tool descriptions to inspect with search/read,
  apply targeted patches and verify changes with Git diff before committing.

## [0.2.1] - 2026-08-06

### Added

- `terminal_open` opens the visible local terminal with an optional initial
  command and title.
- `ssh_list_hosts` exposes non-secret metadata for configured SSH profiles.
- `ssh_run` executes a bounded, non-interactive remote command through a saved
  SSH profile and returns stdout, stderr and exit status.
- `ssh_open_terminal` opens a saved SSH profile in the visible interactive
  terminal, optionally starting a remote command.
- SSH host names, hostnames and UUIDs can be used to resolve a saved profile.

### Security

- Passwords, private keys, passphrases and secret identifiers are never returned
  to the model.
- SSH authentication is resolved internally from the encrypted vault.
- Temporary askpass files and private-key material are removed after structured
  SSH execution.
- `ssh_run` and `ssh_open_terminal` require explicit approval in Confirm and
  Workspace Trusted modes; only Full Access allows automatic remote execution.
- Structured SSH connections use bounded connection attempts and a connect
  timeout.

### Changed

- App version is 0.2.1 build 6.
- Local non-interactive work remains isolated in `run_command`; visible terminal
  sessions and remote SSH actions use dedicated tools and audit records.

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
- Main and Settings windows now use flexible minimum and default sizes instead
  of fixed content sizing.
- The chat toolbar switches between wide and compact layouts when the window is
  narrowed.
- The embedded SwiftTerm view now expands and contracts with the available
  terminal workspace.

### Changed

- App version is 0.2.0 build 5.
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

# Roadmap

## Milestone 2: agent runtime

### Delivered in 0.2.0

- multi-turn Ollama tool-calling loop
- streamed tool call collection and tool-result continuation
- structured shell command executor
- filesystem list, read and write tools
- Git status and diff tools
- cancellation, command timeout and output limits
- permission profiles: Confirm, Workspace Trusted and Full Access
- per-action approval UI and persisted audit cards
- workspace boundary enforcement with Full Access override

### Delivered in 0.2.1

- visible local terminal opening through a structured tool
- non-secret SSH host inventory
- bounded non-interactive SSH command execution
- visible interactive SSH terminal opening
- internal Vault credential resolution without exposing secrets to the model
- explicit remote-action approvals in Confirm and Workspace Trusted modes
- adaptive macOS window and terminal resizing

### Delivered in 0.2.2

- recursive workspace glob tool
- native UTF-8 repository text search with path, line and column output
- exact single-occurrence patch editing
- local Git branch inventory
- safe branch create and checkout with clean-worktree enforcement
- path-scoped local Git commits without push
- equivalent local tool-call repetition guard

### Remaining for 0.2.x

- reusable tool presets per workspace
- dedicated audit-log export
- structured file-delete and move tools with confirmation
- agent-session diagnostics and tool compatibility report

## Milestone 3: local intelligence

### In development for 0.4.0

- isolated Core ML text embedding batches
- persistent semantic workspace index
- safe UTF-8 workspace scanning and bounded chunking
- semantic search with relative paths and line ranges
- agent tools for index status, build, search and clear
- dedicated Workspace Memory user interface

### Planned next

- automatic context ranking and deduplication
- prompt compression
- semantic response cache
- local secret and command-risk classification

## Milestone 4: DevOps workspace

### Partially delivered

- structured SSH command execution
- saved remote host profiles
- interactive remote terminal opening

### Planned

- Docker and Compose inventory and lifecycle tools
- remote macOS and Linux node information
- reusable skills and workflows
- deployment checkpoints and audit history
- service health checks and rollback plans

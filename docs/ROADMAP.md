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

### Remaining for 0.2.x

- patch-based file editing instead of complete-file replacement
- repository text search and glob tools
- Git branch, commit and checkout tools
- repetition detection across equivalent tool calls
- reusable tool presets per workspace
- dedicated audit-log export

## Milestone 3: local intelligence

- Core ML embeddings
- semantic workspace index
- context ranking and deduplication
- prompt compression
- semantic response cache
- local secret and command-risk classification

## Milestone 4: DevOps workspace

- Docker and Compose tools
- SSH command execution with structured output
- remote macOS node information
- reusable skills and workflows
- deployment checkpoints and audit history

# AgenTM5N architecture

## Runtime layers

```text
SwiftUI interface
  ├─ Chat and provider settings
  ├─ Secret vault
  ├─ Embedded terminal
  ├─ SSH profiles
  └─ Neural Engine workspace

Application services
  ├─ OllamaProvider
  ├─ AppleFoundationModelsProvider
  ├─ CoreMLService
  ├─ SSHLaunchService
  └─ HardwareService

Persistence and security
  ├─ JSONDocumentStore
  ├─ VaultStore actor
  ├─ AES-256-GCM
  └─ PBKDF2-HMAC-SHA256
```

## Provider boundary

The chat UI depends on provider-neutral messages and events. Provider-specific
HTTP payloads remain inside the provider implementation. This keeps the next
milestone open for an agent runtime, tool calling and additional providers.

## Terminal boundary

Interactive terminal sessions use SwiftTerm and a real local PTY. Agent command
execution will be implemented separately and will return structured exit code,
stdout, stderr, duration and timeout metadata. Mixing both paths would make
commands difficult to audit and reproduce.

## Local ML execution

- Apple Foundation Models: native on-device language model provider
- Core ML: local models with CPU and Neural Engine compute policy
- Ollama Local: local LLM provider, normally accelerated through Metal/MLX
- Ollama Cloud: remote inference with local context and secret handling

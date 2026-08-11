# AgenTM5N 1.2 MLX Runtime

AgenTM5N can use MLX as the local language-model inference runtime while keeping the AgenTM5N agent/tool/security layer unchanged.

## Design

The 1.2 implementation uses the OpenAI-compatible HTTP API exposed by `mlx_lm.server`.

```text
AgenTM5N
   |
   | HTTP /v1/chat/completions
   v
mlx_lm.server
   |
   v
MLX / Metal / Apple Silicon GPU
```

AgenTM5N still owns:

- conversation state
- tool definitions
- capability filtering
- adaptive tool selection
- approval prompts
- execution
- Vault and secret isolation
- telemetry
- stagnation protection

Only local model inference is delegated to the MLX server.

## Why a sidecar in 1.2

The existing AgenTM5N release is built as a Swift Package executable and assembled into a macOS application by the release scripts. Direct MLX Swift embedding introduces Metal build/resource requirements that belong in an Xcode-native integration path.

Using the server transport keeps 1.2 compatible with the current build architecture while establishing a provider contract that can later be backed by an in-process MLX Swift implementation.

## Installation

Install `mlx-lm` in the Python environment you want to use for local inference. A dedicated virtual environment is recommended so AgenTM5N does not depend on global Python packages.

Example:

```bash
python3 -m venv "$HOME/.venvs/agentm5n-mlx"
source "$HOME/.venvs/agentm5n-mlx/bin/activate"
python -m pip install --upgrade pip
python -m pip install mlx-lm
```

## Start a local model server

```bash
source "$HOME/.venvs/agentm5n-mlx/bin/activate"
mlx_lm.server --model <MODEL_ID_OR_LOCAL_PATH>
```

The default AgenTM5N MLX URL is:

```text
http://127.0.0.1:8080
```

The actual model selection must fit the available unified memory of the Mac. AgenTM5N does not silently download or substitute a model.

## AgenTM5N configuration

Open Settings and select:

```text
Model Provider: Local Runtime
Local Inference Runtime: MLX / mlx_lm.server
Base URL: http://127.0.0.1:8080
Model: <same model served by mlx_lm.server>
```

Then use model refresh if required to query `/v1/models`.

## Tool calling

AgenTM5N forwards its provider tool definitions to the MLX chat endpoint. Tool support depends on the loaded model and its chat template.

When the server returns tool calls, AgenTM5N converts their JSON argument strings into the same `ProviderToolCall` structure used by Ollama. The normal central authorization and execution path then runs the tool and sends its result back into the next model turn.

A model that does not support tool calling remains usable for plain chat, but it cannot act as a full AgenTM5N tool agent.

## Sampling parameters

The MLX transport currently forwards:

- max output tokens
- temperature
- top-p
- top-k
- min-p
- repetition penalty
- repetition context size
- seed

The Ollama-specific `keep_alive`, `num_ctx` request option and thinking-mode field are not forwarded to MLX.

The MLX server's own KV/context limits are configured when that server is launched.

## Images

The initial MLX 1.2 transport is treated as text-only by AgenTM5N's capability validation. Conversation image attachments therefore do not get silently sent through an unsupported payload shape.

Vision can be added later through a validated MLX-VLM transport rather than guessing compatibility.

## Security

The MLX server should remain bound to loopback for normal personal use. AgenTM5N does not need the model server exposed to the LAN or Internet.

The server is an inference endpoint, not the execution authority. Even if the model requests a destructive operation, AgenTM5N still evaluates capability, risk and permission before the corresponding local tool runs.

## First validation

After building AgenTM5N 1.2 on the target Mac:

1. Start `mlx_lm.server` with a known compatible model.
2. Select MLX in AgenTM5N Settings.
3. Refresh the model list.
4. Send a plain prompt and verify a response.
5. Ask for a read-only tool action such as Git status in a test repository.
6. Verify the tool appears in Activity / Agent Operating Layer telemetry.
7. Trigger a write/execute action in Confirm mode and verify the approval dialog appears before execution.
8. Stop the MLX server and verify AgenTM5N reports a transport failure rather than fabricating a response.

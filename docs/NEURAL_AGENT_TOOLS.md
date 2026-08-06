# Neural agent tools and prompt files

AgenTM5N 0.3.0 connects the persistent Core ML runtime to the controlled Ollama agent loop and adds local file import for prompts.

## Persistent Core ML registry

Imported models are registered in:

```text
~/Library/Application Support/AgenTM5N/CoreML/registry.json
```

The registry stores model IDs, display names, persistent source and compiled locations, input/output descriptions, requested compute policy and import time. The active compiled model is restored when AgenTM5N starts.

Internal model paths are not returned to the language model.

## Agent tools

### `coreml_list_models`

Returns the registered model IDs, names, active state, inputs, outputs, requested compute policy and import time.

### `coreml_describe_model`

Describes one model by exact name or UUID. Without a model argument, the active model is used.

### `coreml_predict`

Runs one local prediction. Input keys must exactly match the model description. AgenTM5N 0.3.0 supports scalar `Double`, `Int64` and `String` inputs through the generic JSON adapter.

The tool output contains the model ID and name, requested compute policy, prediction duration and bounded textual output values. Internal model paths are omitted.

## Permission behavior

| Tool | Confirm | Workspace Trusted | Full Access |
|---|---|---|---|
| `coreml_list_models` | automatic | automatic | automatic |
| `coreml_describe_model` | automatic | automatic | automatic |
| `coreml_predict` | approval | automatic | automatic |

All calls remain visible in the chat audit. `coreml_predict` is classified as execution because it can consume CPU, memory and Neural Engine resources.

## Prompt file import

The paperclip button in the Chat toolbar imports up to eight files into the current prompt.

Supported content in 0.3.0:

- UTF-8 text and Markdown
- source code and shell scripts
- JSON, YAML, XML, plist, TOML and configuration files
- CSV and TSV
- log files
- PDF text extracted locally with PDFKit

Limits:

- 8 files per import
- 2 MiB per file
- 180,000 extracted characters per file

The extracted content is inserted into the prompt inside an `agentm5n_attachment` block. No file is uploaded to an external AgenTM5N service. The selected model provider still receives the resulting prompt according to the configured provider.

Direct image payloads for vision-capable Ollama models are planned for the next attachment iteration. This build deliberately rejects unsupported binary and image files instead of pretending that their content was analyzed.

## Recommended smoke test

```text
Liste mit coreml_list_models alle registrierten Core-ML-Modelle auf. Beschreibe danach das aktive Modell mit coreml_describe_model. Führe keine Vorhersage aus.
```

Then test a prediction with input names copied exactly from the model description.

# AgenTM5N 0.3.0 Build 9

## Added

- Persistent Core ML model registry with automatic active-model restore.
- `coreml_list_models`, `coreml_describe_model` and `coreml_predict` agent tools.
- Neural predictions participate in the existing permission and audit workflow.
- Prompt file import from the Chat toolbar for text, source, configuration, log, CSV, JSON, YAML, XML, Markdown and PDF content.
- Local PDF text extraction through PDFKit.

## Security and limits

- Core ML tool output does not expose internal model filesystem paths.
- Prediction JSON is limited to 1 MiB.
- Prompt import is limited to eight files, 2 MiB per file and 180,000 extracted characters per file.
- Unsupported binary and image content is rejected rather than silently ignored.
- Core ML continues to request `cpuAndNeuralEngine`; actual operator placement remains controlled by Core ML.

# Prompt Attachments

AgenTM5N supports structured text attachments and real image payloads without placing binary data in the visible prompt editor.

## Supported attachments

### Text extraction

- UTF-8 text and Markdown
- source code and shell scripts
- JSON, YAML, XML, plist, TOML and configuration files
- CSV and TSV
- log files
- PDF text extracted locally with PDFKit

Text content is placed inside an `agentm5n_attachment` block and treated as untrusted user data.

### Images

- JPEG
- PNG
- HEIC and HEIF
- TIFF
- BMP
- GIF
- WebP when supported by the installed macOS image stack

Images can be selected with the paperclip control or dropped into the Chat composer.

## Image pipeline

1. macOS decodes the source image locally.
2. AgenTM5N preserves aspect ratio and limits the largest edge to 2048 pixels.
3. Transparent areas are rendered over white.
4. The normalized payload is encoded as JPEG with quality 0.86.
5. The payload is persisted in AgenTM5N's protected application-support directory.
6. The conversation stores a validated relative reference, not Base64 data.
7. Before an Ollama request, AgenTM5N loads the referenced payload and places its Base64 representation in the message `images` array.
8. Internal IDs and storage paths are removed from the content visible to the model.

## Provider behavior

### Ollama

Before sending a conversation that contains images, AgenTM5N calls `/api/show` for the configured model. The request proceeds only when the response contains the `vision` capability.

A non-vision rejection does not delete the image reference or conversation message. The user can select a vision-capable model and continue the conversation.

### Apple on-device

The current Apple Foundation Models integration accepts text only. AgenTM5N rejects image attachments before persisting the draft and leaves the attachment visible in the composer.

## Storage

```text
~/Library/Application Support/AgenTM5N/PromptAttachments/
└── Images/
    └── <attachment-uuid>.jpg
```

Permissions:

- directories: `0700`
- image files: `0600`

A new Chat session removes the persisted image attachments from the previous session.

## Limits

- 8 total attachments per prompt
- 4 images per prompt
- 12 MiB source size per image
- 2048 pixels maximum edge
- 6 MiB normalized payload per image
- 20 MiB normalized image payloads per prompt
- 2 MiB per text or PDF attachment
- 48,000 extracted characters per text attachment
- 120,000 extracted characters across one prompt

## Security properties

- no arbitrary absolute image paths are persisted in messages
- relative-path resolution is confined to the protected attachment root
- image Base64 content is not written into the visible editor or conversation JSON
- attachment instructions do not gain system or developer authority
- image support does not bypass tool permission or approval rules

## Smoke tests

1. Attach a text file and PDF; verify the existing extraction behavior.
2. Attach a PNG through the paperclip; verify draft thumbnail, dimensions and normalized size.
3. Drop a JPEG into the composer; verify the drop-target outline and thumbnail.
4. Send an image with a vision-capable Ollama model; verify the response describes the image.
5. Send with a non-vision model; verify a localized rejection and retained history.
6. Select Apple on-device with a pending image; verify rejection while the draft remains.
7. Restart AgenTM5N; verify the image preview remains in the conversation.
8. Start a new session; verify stored image files are removed.

# AgenTM5N Release Archive

This directory is the repository-side index for distributable AgenTM5N macOS releases.

## Binary storage policy

Do **not** commit `.dmg` files directly into Git history. macOS installer images are published as **GitHub Release assets** so normal clones remain small and repository history is not permanently inflated by binaries.

Each published AgenTM5N release should contain:

- `AgenTM5N-<version>-build<build>.dmg`
- `AgenTM5N-<version>-build<build>.dmg.sha256`
- release notes for the matching source tag

Recommended tag format:

```text
v<version>-build<build>
```

Example:

```text
v1.1.2-build28
AgenTM5N-1.1.2-build28.dmg
AgenTM5N-1.1.2-build28.dmg.sha256
```

## Source of truth

A release asset must only be published after the corresponding source revision has passed the documented target-Mac validation, Developer ID signing, Apple notarization, stapling and final DMG verification.

The release tag must point to the source revision used to build the uploaded DMG.

## Publishing

Use:

```bash
bash scripts/publish-github-release.sh
```

The script uploads the already validated DMG from `dist/` and a SHA-256 sidecar to the matching GitHub Release. It does not build, sign or notarize the application itself.

For historical binaries, publish only when the exact source commit/tag corresponding to that DMG is known. Do not attach an old binary to an unrelated current source tag merely for archival convenience.

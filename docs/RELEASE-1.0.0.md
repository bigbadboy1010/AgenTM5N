# AgenTM5N 1.0.0 — Build 22

Release date: 2026-08-08

## Release scope

AgenTM5N 1.0.0 turns the existing local/cloud model shell into a reusable macOS agent runtime with native Mac access, central permissions/audit, persistent specialist agents, local knowledge/document tooling, and a notarizable macOS distribution pipeline.

## V1 highlights

### Provider-neutral agent runtime

- Apple On-Device Foundation Models
- Ollama Local
- Ollama Cloud
- shared native macOS tool execution path
- shared risk classification, permission policy, and tool audit records
- authoritative current Mac date/time/time-zone context for provider grounding

### Native macOS access

Validated native capabilities include:

- Calendar: list, create, update, delete
- Contacts: search, create, update
- Apple Mail: list recent, read message, create draft, send, reply
- macOS TCC/Automation remains authoritative
- personal Mac mutations remain confirmable through the central AgenTM5N router

### Persistent specialist agents

- persistent reusable agent profiles under Application Support
- create specialist agents through the main AgenTM5N agent
- list, inspect, update, enable/disable, delete, and reuse agents
- provider preference per saved agent
- specialist prompts never bypass AgenTM5N permissions, audit, or macOS privacy controls
- agent management tools: `agent_list`, `agent_get`, `agent_create`, `agent_update`, `agent_delete`

### Knowledge and documents

- persistent Knowledge Library
- unified context retrieval over workspace, attachments, and knowledge sources
- local Document Studio for DOCX, PDF, XLSX, and PPTX
- generated-document management tools
- local document extraction and OCR paths

### macOS application integration

- Mac Access Center for native permission and audit visibility
- dedicated AgenTM5N application icon
- Hardened Runtime
- explicit Apple Events, Contacts, and Calendar entitlements
- direct-distribution release pipeline using Developer ID Application signing
- notarized DMG workflow using `notarytool` and `stapler`
- final mounted-DMG verification including Gatekeeper assessment of the delivered app

## Version

- `CFBundleShortVersionString`: `1.0.0`
- `CFBundleVersion`: `22`
- Bundle ID: `team.cloudforge.AgenTM5N`
- Minimum macOS version: `26.0`
- Architecture: Apple Silicon / arm64

## Development build

The standard build remains usable without a distribution certificate. It produces a Hardened Runtime app with an ad-hoc signature:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/verify.sh
bash scripts/build-app.sh
bash scripts/check-release.sh
open dist/AgenTM5N.app
```

## Developer ID release

A real release requires a valid `Developer ID Application` identity in the login keychain and valid saved `notarytool` credentials.

Inspect identities:

```bash
security find-identity -v -p codesigning
```

Create a dedicated notary credential profile once, if required. Do not put the app-specific password on the command line; `notarytool` asks for it interactively and stores the validated credentials in the Keychain:

```bash
xcrun notarytool store-credentials "AgenTM5NNotary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID"
```

Then create the final release:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
bash scripts/release-macos.sh
```

If more than one Developer ID Application identity exists, select one explicitly:

```bash
export AGENTM5N_SIGNING_IDENTITY="SHA1_OR_DEVELOPER_ID_APPLICATION_NAME"
bash scripts/release-macos.sh
```

Expected final artifact:

```text
dist/AgenTM5N-1.0.0-build22.dmg
```

The release script also stores the notary result and notary log in `dist/`.

## Automated release gates

The release workflow runs:

1. `scripts/verify.sh`
2. Developer-ID build through `scripts/build-app.sh`
3. `scripts/check-release.sh` against the built app
4. DMG creation and Developer ID signing
5. Apple `notarytool submit --wait`
6. immediate download of the notary log when a submission ID is available
7. `stapler staple` and `stapler validate`
8. `scripts/verify-release-dmg.sh`, which verifies and mounts the final DMG and checks the delivered app again, including Gatekeeper

## Final smoke-test checklist

After `scripts/release-macos.sh` reports `RELEASE READY`:

1. Mount `AgenTM5N-1.0.0-build22.dmg` and drag AgenTM5N to Applications.
2. Launch the installed app through Finder.
3. Confirm the AgenTM5N icon appears in Finder/Dock.
4. Open Mac Access Center and verify Calendar/Contacts/Automation state.
5. Apple On-Device: read three upcoming Calendar events.
6. Apple On-Device: create and delete a temporary Calendar event; verify central approval and audit entries.
7. Search an existing Contact and perform one approved update when appropriate.
8. Create an Apple Mail draft without sending; verify central approval/audit.
9. Ollama Local or Cloud: query the current Mac date/time/time zone and read Calendar entries.
10. Create or open a persistent specialist agent, run a task, close/relaunch AgenTM5N, and verify the agent remains available.
11. Verify Document Studio and Knowledge Library open normally.
12. Run `xcrun stapler validate dist/AgenTM5N-1.0.0-build22.dmg` and confirm success.

## Release acceptance

V1.0 is release-ready when:

- `scripts/verify.sh` passes
- the app reports version `1.0.0` build `22`
- Developer ID Application signing and Hardened Runtime checks pass
- Apple notarization returns `Accepted`
- the notary ticket is successfully stapled and validated
- the mounted final DMG passes `verify-release-dmg.sh` including Gatekeeper assessment
- the manual smoke-test checklist above is green

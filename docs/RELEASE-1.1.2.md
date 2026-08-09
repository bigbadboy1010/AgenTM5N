# AgenTM5N 1.1.2 — Build 28 release candidate

Version: **1.1.2**  
Build: **28**  
Branch: `agent/v1.1.0-platform-expansion`

Build 28 is the post-review hardening candidate. It is intentionally not considered release-ready until a fresh target-Mac build/test pass and the manual runtime matrix in `VALIDATION.md` are complete.

## Main changes

- central provider-neutral tool registry is the runtime risk authority
- Workspace Trusted approval policy expanded for visible system and persistent agent/workflow mutations
- nested specialist capability scopes are monotonic and cannot expand through child delegation
- Apple Foundation Models native tool execution is serialized before AppState approval handling
- Vault HTTP secrets support exact normalized host binding
- disabled Toolsmith replacement fails closed until explicit re-enable
- disabled workflow replacement preserves state
- specialist UI distinguishes `nil` full parity from an explicit empty no-tools sandbox
- Core ML uses all available CPU/GPU/Neural Engine compute units with Core ML operator placement
- Core ML managed storage is SHA-256 content-addressed and transactional
- failed imports roll back newly created managed artifacts
- registered large Core ML models load lazily and prediction models are cached in-process
- Neural Engine UI distinguishes registered state from execution-plan loading
- regression tests and static source-policy CI expanded
- release metadata standardized on 1.1.2 Build 28

## Target-Mac validation

```bash
cd ~/Downloads/AgenTM5N

git fetch origin
git switch agent/v1.1.0-platform-expansion
git pull --ff-only origin agent/v1.1.0-platform-expansion

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
rm -rf .build .swiftpm .build-artifacts Package.resolved

bash scripts/verify.sh
bash scripts/build-app.sh
```

Then run the Build 28 runtime matrix in `VALIDATION.md`. The Core ML regression must include an in-app prediction with the large registered StatefulMistral model and a second prediction in the same process to verify the lazy-load cache behavior.

## Distribution gate

Only after validation is green:

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
export AGENTM5N_NOTARY_PROFILE="AgenTM5NNotary"
unset AGENTM5N_SIGNING_IDENTITY
bash scripts/release-macos.sh
```

Expected final artifact:

```text
dist/AgenTM5N-1.1.2-build28.dmg
```

`release-macos.sh` must complete Developer ID signing, source/test gate, app validation, notarization, stapling, mounted-DMG validation and Gatekeeper assessment before reporting `RELEASE READY`.

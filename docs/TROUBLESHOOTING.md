# Build troubleshooting

## `Failed to clone repository ... migueldeic/SwiftTerm.git`

### Cause

An early AgenTM5N revision used an invalid GitHub owner in `Package.swift`.
The correct upstream repository is:

```text
https://github.com/migueldeicaza/SwiftTerm.git
```

### Fix

```bash
cd ~/Downloads/AgenTM5N
git pull --ff-only origin agent/initial-macos-mvp
rm -rf .build .swiftpm Package.resolved
rm -rf "$HOME/Library/Caches/org.swift.swiftpm/repositories/SwiftTerm-"*
bash scripts/verify.sh
```

## `unable to spawn process 'metal'`

### Cause

An early revision pinned SwiftTerm 1.15.0. That release declares
`Apple/Metal/Shaders.metal` as a Swift Package resource, so SwiftPM invokes the
optional command-line Metal Toolchain.

### Current solution

AgenTM5N now pins SwiftTerm 1.11.0 and uses its CoreText renderer. The optional
Metal Toolchain is no longer required for compiling the embedded terminal.
This change does not disable Core ML or Apple Neural Engine functionality.

Update and clear all old dependency state:

```bash
cd ~/Downloads/AgenTM5N
git pull --ff-only origin agent/initial-macos-mvp
rm -rf .build .swiftpm Package.resolved dist
rm -rf "$HOME/Library/Caches/org.swift.swiftpm/repositories/SwiftTerm-"*

export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/bootstrap-xcode.sh
bash scripts/verify.sh
bash scripts/build-app.sh
```

## Full Xcode is not selected

### Diagnose

```bash
xcode-select -p
```

AgenTM5N must use a full Xcode installation because the project links AppKit,
Core ML and Foundation Models. The standalone path below is insufficient:

```text
/Library/Developer/CommandLineTools
```

### Project-local selection

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/bootstrap-xcode.sh
```

### Optional global selection

```bash
sudo xcode-select --switch "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
sudo xcodebuild -license accept
```

## Xcode first-launch components are missing

```bash
sudo env \
  DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild -runFirstLaunch
```

## Clean dependency rebuild

```bash
rm -rf .build .swiftpm Package.resolved dist
rm -rf "$HOME/Library/Caches/org.swift.swiftpm/repositories/SwiftTerm-"*
bash scripts/verify.sh
bash scripts/build-app.sh
```

## App bundle does not start

```bash
codesign --verify --deep --strict --verbose=4 dist/AgenTM5N.app
open dist/AgenTM5N.app
log stream --predicate 'process == "AgenTM5N"' --level debug
```

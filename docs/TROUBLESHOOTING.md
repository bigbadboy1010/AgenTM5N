# Build troubleshooting

## `unable to spawn process 'metal'`

### Cause

SwiftTerm ships a Metal shader. Swift Package Manager invokes `metal` while
building the dependency. `/Library/Developer/CommandLineTools` does not contain
that compiler.

### Diagnose

```bash
xcode-select -p
xcrun --find metal
```

When the first command returns Command Line Tools and the second command fails,
select full Xcode.

### Recommended project-local fix

```bash
export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
bash scripts/bootstrap-xcode.sh
bash scripts/verify.sh
```

### Optional global Xcode selection

```bash
sudo xcode-select --switch "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
sudo xcodebuild -license accept
```

## Full Xcode selected, but `metal` is still unavailable

Xcode 26 distributes the Metal Toolchain as an optional component. Install it
with:

```bash
bash scripts/bootstrap-xcode.sh
```

Equivalent manual command:

```bash
DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild -downloadComponent metalToolchain
```

## Xcode first-launch components are missing

```bash
sudo env \
  DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer" \
  xcodebuild -runFirstLaunch
```

## Clean dependency rebuild

```bash
rm -rf .build .swiftpm
bash scripts/verify.sh
```

## App bundle does not start

```bash
codesign --verify --deep --strict --verbose=4 dist/AgenTM5N.app
open dist/AgenTM5N.app
log stream --predicate 'process == "AgenTM5N"' --level debug
```

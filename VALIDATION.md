# Validation status

Date: 2026-08-06
Version: 0.1.1

## Root causes fixed

The original build selected `/Library/Developer/CommandLineTools`. SwiftTerm
contains `Shaders.metal`, but the standalone Command Line Tools package has no
Metal compiler. The scripts now resolve a full Xcode installation before
invoking Swift Package Manager.

Xcode 26 may also require the optional Metal Toolchain component. The
`bootstrap-xcode.sh` script initializes Xcode and installs that component with
`xcodebuild -downloadComponent metalToolchain`.

## Checks performed in the build workspace

- Swift source parsing
- SwiftPM manifest parsing
- shell syntax validation
- package and executable naming consistency
- scan for placeholder markers, force unwraps, `try!` and forced casts
- Apache-2.0 license alignment
- deterministic SwiftTerm version 1.15.0

## Required target-Mac validation

```bash
bash scripts/bootstrap-xcode.sh
bash scripts/verify.sh
bash scripts/build-app.sh
codesign --verify --deep --strict --verbose=4 dist/AgenTM5N.app
open dist/AgenTM5N.app
```

A complete macOS link and runtime test cannot be executed in the Linux-based
artifact workspace because AppKit, Core ML, Foundation Models and the Xcode
Metal toolchain are unavailable there.

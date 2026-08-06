#!/bin/bash

# Shared Xcode resolver for AgenTM5N build scripts.
# The standalone Command Line Tools package is rejected because SwiftTerm
# contains Metal shaders and requires full Xcode plus the Metal Toolchain.

agentm5n_resolve_xcode() {
  local selected=""
  local candidate=""
  local normalized=""
  local selected_by_xcode_select=""
  local application=""
  local xcode_version=""
  local -a candidates
  local -a applications

  candidates=()
  applications=()

  if [ -n "${AGENTM5N_XCODE_PATH:-}" ]; then
    candidates+=("$AGENTM5N_XCODE_PATH")
  fi

  if [ -n "${DEVELOPER_DIR:-}" ]; then
    candidates+=("$DEVELOPER_DIR")
  fi

  selected_by_xcode_select="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
  if [ -n "$selected_by_xcode_select" ]; then
    candidates+=("$selected_by_xcode_select")
  fi

  candidates+=(
    "/Applications/Xcode.app/Contents/Developer"
    "/Applications/Xcode-beta.app/Contents/Developer"
    "$HOME/Applications/Xcode.app/Contents/Developer"
    "$HOME/Applications/Xcode-beta.app/Contents/Developer"
    "$HOME/Downloads/Xcode.app/Contents/Developer"
    "$HOME/Downloads/Xcode-beta.app/Contents/Developer"
  )

  shopt -s nullglob
  applications+=(/Applications/Xcode*.app)
  applications+=("$HOME"/Applications/Xcode*.app)
  applications+=("$HOME"/Downloads/Xcode*.app)
  shopt -u nullglob

  for application in "${applications[@]}"; do
    candidates+=("$application/Contents/Developer")
  done

  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] || continue

    if [[ "$candidate" == *.app ]]; then
      candidate="$candidate/Contents/Developer"
    fi

    [ -d "$candidate" ] || continue
    normalized="$(cd "$candidate" && pwd -P)"

    if DEVELOPER_DIR="$normalized" /usr/bin/xcodebuild -version >/dev/null 2>&1; then
      selected="$normalized"
      break
    fi
  done

  if [ -z "$selected" ]; then
    cat >&2 <<ERROR
AgenTM5N benötigt eine vollständige Xcode-Installation.

Aktiver xcode-select-Pfad:
  ${selected_by_xcode_select:-nicht gesetzt}

Der Pfad /Library/Developer/CommandLineTools reicht nicht aus. Installiere oder
entpacke Xcode und setze den Pfad entweder dauerhaft:

  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

oder nur für AgenTM5N:

  export AGENTM5N_XCODE_PATH="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
ERROR
    return 1
  fi

  export DEVELOPER_DIR="$selected"
  export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

  xcode_version="$(/usr/bin/xcodebuild -version | tr '\n' ' ')"
  printf 'Xcode Toolchain: %s\n' "$DEVELOPER_DIR"
  printf 'Xcode Version:   %s\n' "$xcode_version"
}

agentm5n_require_metal() {
  local metal_path=""

  if metal_path="$(/usr/bin/xcrun --find metal 2>/dev/null)"; then
    printf 'Metal Compiler:  %s\n' "$metal_path"
    return 0
  fi

  cat >&2 <<ERROR
Der optionale Metal Toolchain ist für dieses Xcode noch nicht installiert.
SwiftTerm enthält Shaders.metal und kann ohne den Compiler nicht gebaut werden.

Installiere die Komponente einmalig:

  DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild -downloadComponent metalToolchain

Oder verwende den vollständigen Bootstrap:

  ./scripts/bootstrap-xcode.sh
ERROR
  return 1
}

agentm5n_configure_xcode() {
  agentm5n_resolve_xcode
  agentm5n_require_metal
}

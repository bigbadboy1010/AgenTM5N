#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Vollständige Verifikation erfordert macOS 26 und Xcode 26 oder neuer." >&2
  exit 1
fi

agentm5n_configure_xcode
cd "$ROOT_DIR"

# Keep local verification responsive on 16 GB Apple-silicon Macs. SwiftPM can
# otherwise spawn enough compiler jobs to create severe unified-memory/swap
# pressure, especially after `swift package clean`. Override explicitly when a
# larger development machine should use more parallelism.
SWIFT_JOBS="${AGENTM5N_SWIFT_JOBS:-4}"
case "$SWIFT_JOBS" in
  ''|*[!0-9]*)
    echo "AGENTM5N_SWIFT_JOBS muss eine positive Ganzzahl sein." >&2
    exit 2
    ;;
esac
if [ "$SWIFT_JOBS" -lt 1 ]; then SWIFT_JOBS=1; fi
if [ "$SWIFT_JOBS" -gt 16 ]; then SWIFT_JOBS=16; fi

printf 'SwiftPM Parallelität: %s Jobs\n' "$SWIFT_JOBS"

swift package resolve
swift package dump-package >/dev/null
swift build -c debug --arch arm64 --jobs "$SWIFT_JOBS"

printf '\n=== AgenTM5N Security Regression Tests ===\n'
swift test --arch arm64 --jobs "$SWIFT_JOBS"

printf '\nAgenTM5N Debug-Build und Tests erfolgreich.\n'

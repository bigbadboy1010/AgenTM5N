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

FREE_PERCENT="$(
  memory_pressure -Q 2>/dev/null \
    | awk '/System-wide memory free percentage/ { value=$5; gsub(/%/, "", value); print int(value + 0); exit }' \
    || true
)"
SWAP_USED_MB="$(
  sysctl -n vm.swapusage 2>/dev/null \
    | awk '{ for (i = 1; i <= NF; i++) { if ($i == "used") { value=$(i + 2); sub(/M$/, "", value); print int(value + 0); exit } } }' \
    || true
)"

RESOURCE_CRITICAL=0
RESOURCE_WARNING=0

if [ -n "$FREE_PERCENT" ]; then
  printf 'Freier Systemspeicher: %s%%\n' "$FREE_PERCENT"
  if [ "$FREE_PERCENT" -lt 15 ]; then
    RESOURCE_CRITICAL=1
  elif [ "$FREE_PERCENT" -lt 30 ]; then
    RESOURCE_WARNING=1
  fi
fi

if [ -n "$SWAP_USED_MB" ]; then
  printf 'Swap belegt: %s MB\n' "$SWAP_USED_MB"
  if [ "$SWAP_USED_MB" -gt 4096 ]; then
    RESOURCE_CRITICAL=1
  elif [ "$SWAP_USED_MB" -gt 2048 ]; then
    RESOURCE_WARNING=1
  fi
fi

if [ "$RESOURCE_CRITICAL" -eq 1 ]; then
  if [ "${AGENTM5N_FORCE_BUILD:-0}" = "1" ]; then
    echo "WARNUNG: Kritischer Memory/Swap-Druck; Build wurde ausdrücklich erzwungen." >&2
  else
    echo "ABBRUCH: Kritischer Memory/Swap-Druck. Fremdlast reduzieren oder Build bewusst erzwingen." >&2
    exit 70
  fi
elif [ "$RESOURCE_WARNING" -eq 1 ] && [ "$SWIFT_JOBS" -gt 2 ]; then
  echo "WARNUNG: Erhöhter Memory/Swap-Druck; SwiftPM wird automatisch auf 2 Jobs reduziert." >&2
  SWIFT_JOBS=2
fi

printf '\n=== Thermal state before verification ===\n'
pmset -g therm 2>/dev/null || true
printf 'SwiftPM Parallelität: %s Jobs\n' "$SWIFT_JOBS"

swift package resolve
swift package dump-package >/dev/null

# `swift test` compiles the package and the test targets. Running an explicit
# debug `swift build` immediately beforehand duplicated compiler work after a
# clean checkout without adding meaningful local verification coverage. Native
# CI still performs its independent strict-concurrency build gate.
printf '\n=== AgenTM5N Build + Security Regression Tests ===\n'
swift test --arch arm64 --jobs "$SWIFT_JOBS"

printf '\nAgenTM5N Build und Tests erfolgreich.\n'

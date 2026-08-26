#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Der M5 Safety Gate Runner ist nur für macOS vorgesehen." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRACE_ROOT="${AGENTM5N_TRACE_DIR:-$ROOT_DIR/.build-artifacts/resource-traces}"
TRACE_RUNNER="$ROOT_DIR/scripts/capture-resource-trace.sh"
DIAGNOSE="$ROOT_DIR/scripts/diagnose-resource-pressure.sh"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/run-m5-safety-gate.sh preflight
  bash scripts/run-m5-safety-gate.sh cold-verify
  bash scripts/run-m5-safety-gate.sh release-build
  bash scripts/run-m5-safety-gate.sh manual-trace <label>
  bash scripts/run-m5-safety-gate.sh analyze [trace.tsv]
  bash scripts/run-m5-safety-gate.sh status

Environment:
  AGENTM5N_TRACE_DIR               Optional trace output directory.
  AGENTM5N_TRACE_INTERVAL_SECONDS  Sampling interval, default 5 seconds.
  AGENTM5N_SWIFT_JOBS              SwiftPM jobs, default 4.
  AGENTM5N_FORCE_BUILD=1           Explicitly overrides critical build admission.

Recommended staged order:
  1. preflight
  2. cold-verify
  3. release-build
  4. manual-trace anemll-only
  5. manual-trace anemll-cancel
  6. manual-trace ollama-only
  7. manual-trace manual-switching

Automatic/adaptive ModelProfile routing remains last and must not be enabled
until the earlier stages are reviewed and the automatic executor is explicitly
wired to the immutable operating snapshot and residency cleanup scope.
EOF
}

require_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    echo "Erforderliche Datei fehlt: $path" >&2
    exit 2
  fi
}

memory_free_percent() {
  memory_pressure -Q 2>/dev/null \
    | awk '/System-wide memory free percentage/ { value=$5; gsub(/%/, "", value); print int(value + 0); exit }' \
    || true
}

swap_used_mb() {
  sysctl -n vm.swapusage 2>/dev/null \
    | awk '{ for (i = 1; i <= NF; i++) { if ($i == "used") { value=$(i + 2); sub(/M$/, "", value); print int(value + 0); exit } } }' \
    || true
}

preflight_admission() {
  local free_percent swap_mb critical warning
  free_percent="$(memory_free_percent)"
  swap_mb="$(swap_used_mb)"
  critical=0
  warning=0

  if [ -n "$free_percent" ]; then
    printf 'Freier Systemspeicher: %s%%\n' "$free_percent"
    if [ "$free_percent" -lt 15 ]; then
      critical=1
    elif [ "$free_percent" -lt 30 ]; then
      warning=1
    fi
  else
    echo "WARNUNG: Freier Systemspeicher konnte nicht bestimmt werden." >&2
    warning=1
  fi

  if [ -n "$swap_mb" ]; then
    printf 'Swap belegt: %s MB\n' "$swap_mb"
    if [ "$swap_mb" -gt 4096 ]; then
      critical=1
    elif [ "$swap_mb" -gt 2048 ]; then
      warning=1
    fi
  else
    echo "WARNUNG: Swap-Nutzung konnte nicht bestimmt werden." >&2
    warning=1
  fi

  if [ "$critical" -eq 1 ]; then
    if [ "${AGENTM5N_FORCE_BUILD:-0}" = "1" ]; then
      echo "PRECHECK=CRITICAL_FORCED" >&2
      echo "WARNUNG: Kritischer Ressourcenstatus wurde ausdrücklich übersteuert." >&2
      return 0
    fi
    echo "PRECHECK=CRITICAL" >&2
    return 70
  fi
  if [ "$warning" -eq 1 ]; then
    echo "PRECHECK=WARNING"
  else
    echo "PRECHECK=PASS"
  fi
}

latest_trace() {
  find "$TRACE_ROOT" -maxdepth 1 -type f -name '*.tsv' -print 2>/dev/null \
    | sort \
    | tail -n 1
}

analyze_trace() {
  local trace_file="$1"
  if [ ! -f "$trace_file" ]; then
    echo "Trace-Datei nicht gefunden: $trace_file" >&2
    return 2
  fi

  awk -F '\t' '
    NR == 1 { next }
    {
      samples++
      if ($2 != "NA" && $2 != "") {
        free = $2 + 0
        if (!haveFree || free < minFree) minFree = free
        haveFree = 1
      }
      if ($3 != "NA" && $3 != "") {
        swap = $3 + 0
        if (!haveSwap || swap > maxSwap) maxSwap = swap
        haveSwap = 1
      }
      agent = $4 + 0
      anemll = $5 + 0
      mlx = $6 + 0
      ollama = $7 + 0
      swiftBuild = $8 + 0
      if (agent > maxAgent) maxAgent = agent
      if (anemll > maxANEMLL) maxANEMLL = anemll
      if (mlx > maxMLX) maxMLX = mlx
      if (ollama > maxOllama) maxOllama = ollama
      if (swiftBuild > maxSwift) maxSwift = swiftBuild
      cpu = $11 + 0
      if (cpu > maxTopCPU) maxTopCPU = cpu
    }
    END {
      status = "PASS"
      if (!haveFree || !haveSwap) {
        status = "WARNING"
      }
      if (haveFree && minFree < 30 && status == "PASS") status = "WARNING"
      if (haveSwap && maxSwap > 2048 && status == "PASS") status = "WARNING"
      if (haveFree && minFree < 15) status = "CRITICAL"
      if (haveSwap && maxSwap > 4096) status = "CRITICAL"

      printf "Trace: samples=%d\n", samples
      if (haveFree) printf "Minimum free memory: %.0f%%\n", minFree
      else printf "Minimum free memory: unavailable\n"
      if (haveSwap) printf "Maximum swap used: %.0f MB\n", maxSwap
      else printf "Maximum swap used: unavailable\n"
      printf "Maximum process counts: AgenTM5N=%d ANEMLL=%d MLX=%d Ollama=%d Swift/build=%d\n", maxAgent, maxANEMLL, maxMLX, maxOllama, maxSwift
      printf "Maximum sampled top-process CPU: %.1f%%\n", maxTopCPU
      printf "RESOURCE_GATE=%s\n", status

      if (status == "CRITICAL") exit 70
    }
  ' "$trace_file"
}

run_traced() {
  local label="$1"
  shift
  local command_status analyze_status trace_file

  mkdir -p "$TRACE_ROOT"

  set +e
  bash "$TRACE_RUNNER" "$label" "$@"
  command_status=$?
  set -e

  trace_file="$(latest_trace)"
  analyze_status=0
  if [ -n "$trace_file" ]; then
    echo
    set +e
    analyze_trace "$trace_file"
    analyze_status=$?
    set -e
  fi

  if [ "$command_status" -ne 0 ]; then
    echo "COMMAND_STATUS=$command_status" >&2
    return "$command_status"
  fi
  if [ "$analyze_status" -ne 0 ]; then
    return "$analyze_status"
  fi
}

require_file "$TRACE_RUNNER"
require_file "$DIAGNOSE"

COMMAND="${1:-}"
case "$COMMAND" in
  preflight)
    mkdir -p "$TRACE_ROOT"
    STAMP="$(date '+%Y%m%d-%H%M%S')"
    SNAPSHOT="$TRACE_ROOT/${STAMP}-preflight.txt"
    bash "$DIAGNOSE" > "$SNAPSHOT" 2>&1 || true
    echo "Preflight snapshot: $SNAPSHOT"
    preflight_admission
    ;;

  cold-verify)
    preflight_admission
    run_traced \
      "cold-verify" \
      bash -lc "cd '$ROOT_DIR' && swift package clean && bash scripts/verify.sh"
    ;;

  release-build)
    preflight_admission
    run_traced \
      "release-build" \
      bash -lc "cd '$ROOT_DIR' && bash scripts/build-app.sh"
    ;;

  manual-trace)
    LABEL="${2:-}"
    if [ -z "$LABEL" ]; then
      echo "manual-trace benötigt ein Label, z. B. anemll-only." >&2
      usage
      exit 2
    fi
    preflight_admission
    echo "Trace läuft. Führe jetzt ausschließlich die Stufe '$LABEL' aus."
    echo "Beenden mit Ctrl-C; das Trace-Skript schreibt laufend nach $TRACE_ROOT."
    exec bash "$TRACE_RUNNER" "$LABEL"
    ;;

  analyze)
    TRACE_FILE="${2:-}"
    if [ -z "$TRACE_FILE" ]; then
      TRACE_FILE="$(latest_trace)"
    fi
    if [ -z "$TRACE_FILE" ]; then
      echo "Keine Trace-Datei in $TRACE_ROOT gefunden." >&2
      exit 2
    fi
    analyze_trace "$TRACE_FILE"
    ;;

  status)
    bash "$DIAGNOSE"
    echo
    preflight_admission
    ;;

  -h|--help|help|"")
    usage
    ;;

  *)
    echo "Unbekanntes Kommando: $COMMAND" >&2
    usage
    exit 2
    ;;
esac

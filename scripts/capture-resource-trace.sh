#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Dieses Trace-Skript ist nur für macOS vorgesehen." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRACE_ROOT="${AGENTM5N_TRACE_DIR:-$ROOT_DIR/.build-artifacts/resource-traces}"
TRACE_INTERVAL="${AGENTM5N_TRACE_INTERVAL_SECONDS:-5}"
LABEL="${1:-manual}"

case "$TRACE_INTERVAL" in
  ''|*[!0-9]*)
    echo "AGENTM5N_TRACE_INTERVAL_SECONDS muss eine positive Ganzzahl sein." >&2
    exit 2
    ;;
esac
if [ "$TRACE_INTERVAL" -lt 1 ]; then TRACE_INTERVAL=1; fi
if [ "$TRACE_INTERVAL" -gt 60 ]; then TRACE_INTERVAL=60; fi

if [ "$#" -gt 0 ]; then
  shift
fi

mkdir -p "$TRACE_ROOT"
STAMP="$(date '+%Y%m%d-%H%M%S')"
SAFE_LABEL="$(printf '%s' "$LABEL" | tr -cs 'A-Za-z0-9._-' '_')"
TRACE_FILE="$TRACE_ROOT/${STAMP}-${SAFE_LABEL}.tsv"
SNAPSHOT_FILE="$TRACE_ROOT/${STAMP}-${SAFE_LABEL}-snapshot.txt"

count_exact() {
  local name="$1"
  local ids
  ids="$(pgrep -x "$name" 2>/dev/null || true)"
  if [ -z "$ids" ]; then
    printf '0'
  else
    printf '%s\n' "$ids" | wc -l | tr -d ' '
  fi
}

count_pattern() {
  local pattern="$1"
  local ids
  ids="$(pgrep -if "$pattern" 2>/dev/null || true)"
  if [ -z "$ids" ]; then
    printf '0'
  else
    printf '%s\n' "$ids" | wc -l | tr -d ' '
  fi
}

memory_free_percent() {
  memory_pressure -Q 2>/dev/null \
    | awk '/System-wide memory free percentage/ { value=$5; gsub(/%/, "", value); print value; exit }' \
    || true
}

swap_used_mb() {
  sysctl -n vm.swapusage 2>/dev/null \
    | awk '{ for (i = 1; i <= NF; i++) { if ($i == "used") { value=$(i + 2); sub(/M$/, "", value); print value; exit } } }' \
    || true
}

thermal_summary() {
  pmset -g therm 2>/dev/null \
    | tr '\n\t' '  ' \
    | tr -s ' ' \
    | sed 's/^ //; s/ $//' \
    || true
}

top_process_fields() {
  ps -axo pid=,%cpu=,rss=,command= \
    | sort -k2 -nr \
    | head -n 1 \
    | awk '{ pid=$1; cpu=$2; rss=$3; $1=""; $2=""; $3=""; sub(/^ +/, "", $0); gsub(/\t/, " ", $0); printf "%s\t%s\t%s\t%s", pid, cpu, rss, $0 }' \
    || true
}

write_sample() {
  local timestamp free_percent swap_mb thermal top_fields
  timestamp="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  free_percent="$(memory_free_percent)"
  swap_mb="$(swap_used_mb)"
  thermal="$(thermal_summary | tr '\t' ' ')"
  top_fields="$(top_process_fields)"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$timestamp" \
    "${free_percent:-NA}" \
    "${swap_mb:-NA}" \
    "$(count_exact AgenTM5N)" \
    "$(count_pattern 'anemll|anemllcli')" \
    "$(count_pattern 'mlx_lm.server')" \
    "$(count_pattern 'ollama')" \
    "$(count_pattern 'swift-frontend|swiftc|swift build|swift test|xcodebuild')" \
    "${thermal:-NA}" \
    "${top_fields:-NA\tNA\tNA\tNA}" \
    "$$" \
    >> "$TRACE_FILE"
}

capture_snapshot() {
  {
    echo "=== TRACE METADATA ==="
    printf 'timestamp=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
    printf 'label=%s\n' "$LABEL"
    printf 'interval_seconds=%s\n' "$TRACE_INTERVAL"
    printf 'trace_file=%s\n' "$TRACE_FILE"
    echo
    "$ROOT_DIR/scripts/diagnose-resource-pressure.sh"
  } > "$SNAPSHOT_FILE" 2>&1 || true
}

stop_sampler() {
  if [ -n "${SAMPLER_PID:-}" ] && kill -0 "$SAMPLER_PID" 2>/dev/null; then
    kill "$SAMPLER_PID" 2>/dev/null || true
    wait "$SAMPLER_PID" 2>/dev/null || true
  fi
}

trap stop_sampler EXIT INT TERM

printf 'timestamp\tfree_memory_pct\tswap_used_mb\tagentm5n_count\tanemll_count\tmlx_count\tollama_count\tswift_build_count\tthermal\ttop_pid\ttop_cpu_pct\ttop_rss_kb\ttop_command\ttrace_pid\n' \
  > "$TRACE_FILE"

capture_snapshot

(
  while true; do
    write_sample
    sleep "$TRACE_INTERVAL"
  done
) &
SAMPLER_PID=$!

printf 'Resource trace: %s\n' "$TRACE_FILE"
printf 'Initial snapshot: %s\n' "$SNAPSHOT_FILE"

if [ "$#" -eq 0 ]; then
  wait "$SAMPLER_PID"
  exit 0
fi

set +e
"$@"
COMMAND_STATUS=$?
set -e

stop_sampler
SAMPLER_PID=""
write_sample

FINAL_SNAPSHOT_FILE="$TRACE_ROOT/${STAMP}-${SAFE_LABEL}-final.txt"
{
  echo "=== TRACE METADATA ==="
  printf 'timestamp=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf 'label=%s\n' "$LABEL"
  printf 'command_status=%s\n' "$COMMAND_STATUS"
  printf 'trace_file=%s\n' "$TRACE_FILE"
  echo
  "$ROOT_DIR/scripts/diagnose-resource-pressure.sh"
} > "$FINAL_SNAPSHOT_FILE" 2>&1 || true

printf 'Final snapshot: %s\n' "$FINAL_SNAPSHOT_FILE"
exit "$COMMAND_STATUS"

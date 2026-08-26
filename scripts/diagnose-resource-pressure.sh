#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Dieses Diagnose-Skript ist nur für macOS vorgesehen." >&2
  exit 1
fi

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

printf '=== TIMESTAMP ===\n'
date '+%Y-%m-%dT%H:%M:%S%z'

printf '\n=== SYSTEM ===\n'
sw_vers || true
uname -m
printf 'Memory bytes: '
sysctl -n hw.memsize || true

printf '\n=== THERMAL ===\n'
pmset -g therm 2>/dev/null || true

printf '\n=== MEMORY PRESSURE ===\n'
if command -v memory_pressure >/dev/null 2>&1; then
  memory_pressure -Q 2>/dev/null || true
fi
vm_stat || true
sysctl vm.swapusage 2>/dev/null || true

printf '\n=== TOP CPU (PS) ===\n'
ps -axo pid,ppid,%cpu,%mem,rss,etime,command \
  | sort -k3 -nr \
  | head -25 || true

printf '\n=== TOP CPU (INSTANTANEOUS SAMPLE) ===\n'
# The first `top` sample contains lifetime-biased values. The second sample is
# materially closer to current CPU use, which is what a thermal incident needs.
top -l 2 -n 15 -stats pid,cpu,mem,time,command 2>/dev/null \
  | tail -25 || true

printf '\n=== AGEN / AI / BUILD PROCESSES ===\n'
ps -axo pid,ppid,%cpu,%mem,rss,etime,command \
  | grep -Ei '[A]genTM5N|[a]nemll|[m]lx|[o]llama|[s]wift|[x]code' \
  || true

printf '\n=== PROCESS COUNTS ===\n'
printf 'AgenTM5N: %s\n' "$(count_exact AgenTM5N)"
printf 'ANEMLL-like: %s\n' "$(count_pattern 'anemll|anemllcli')"
printf 'MLX server: %s\n' "$(count_pattern 'mlx_lm.server')"
printf 'Ollama: %s\n' "$(count_pattern 'ollama')"
printf 'Swift compiler/build: %s\n' "$(count_pattern 'swift-frontend|swiftc|swift build|swift test|xcodebuild')"

printf '\n=== DONE ===\n'

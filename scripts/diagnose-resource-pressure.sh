#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Dieses Diagnose-Skript ist nur für macOS vorgesehen." >&2
  exit 1
fi

printf '=== SYSTEM ===\n'
sw_vers || true
uname -m
printf 'Memory bytes: '
sysctl -n hw.memsize || true

printf '\n=== MEMORY PRESSURE ===\n'
if command -v memory_pressure >/dev/null 2>&1; then
  memory_pressure -Q 2>/dev/null || true
fi
vm_stat || true
sysctl vm.swapusage 2>/dev/null || true

printf '\n=== TOP CPU ===\n'
ps -axo pid,ppid,%cpu,%mem,rss,etime,command \
  | sort -k3 -nr \
  | head -25 || true

printf '\n=== AGEN / AI / BUILD PROCESSES ===\n'
ps -axo pid,ppid,%cpu,%mem,rss,etime,command \
  | grep -Ei '[A]genTM5N|[a]nemll|[m]lx|[o]llama|[s]wift|[x]code' \
  || true

printf '\n=== PROCESS COUNTS ===\n'
printf 'AgenTM5N: '
pgrep -x AgenTM5N 2>/dev/null | wc -l | tr -d ' '
printf '\nANEMLL-like: '
pgrep -if 'anemll|anemllcli' 2>/dev/null | wc -l | tr -d ' '
printf '\nMLX server: '
pgrep -if 'mlx_lm.server' 2>/dev/null | wc -l | tr -d ' '
printf '\nOllama: '
pgrep -if 'ollama' 2>/dev/null | wc -l | tr -d ' '
printf '\nSwift compiler/build: '
pgrep -if 'swift-frontend|swiftc|swift build|swift test|xcodebuild' 2>/dev/null | wc -l | tr -d ' '
printf '\n'

printf '\n=== DONE ===\n'

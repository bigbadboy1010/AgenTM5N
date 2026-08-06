#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT_DIR/scripts/lib/xcode-env.sh"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "AgenTM5N kann nur auf macOS ausgeführt werden." >&2
  exit 1
fi

agentm5n_configure_xcode
cd "$ROOT_DIR"
swift package resolve
swift run AgenTM5N

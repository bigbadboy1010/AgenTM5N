#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AgenTM5N"
APP_DIR="${AGENTM5N_APP_PATH:-$ROOT_DIR/dist/$APP_NAME.app}"
HELPER_DIR="$APP_DIR/Contents/Helpers/ANEMLL"
HELPER="$HELPER_DIR/anemllcli"
MODEL_DIR="$APP_DIR/Contents/Resources/Models/ANEMLL/Qwen3"
META="$MODEL_DIR/meta.yaml"
TOKENIZER="$MODEL_DIR/tokenizer.json"

fail() {
  printf 'PORTABLE ANEMLL CHECK FAILED: %s\n' "$1" >&2
  exit 1
}

[ -d "$APP_DIR" ] || fail "App fehlt: $APP_DIR"
[ -x "$HELPER" ] || fail "ANEMLL Helper fehlt oder ist nicht ausführbar: $HELPER"
[ -f "$META" ] || fail "Qwen3 meta.yaml fehlt: $META"
[ -f "$TOKENIZER" ] || fail "Qwen3 tokenizer.json fehlt: $TOKENIZER"

FFN_COUNT="$(find "$MODEL_DIR" -maxdepth 1 -type d -name '*FFN*' -name '*.mlmodelc' | wc -l | tr -d ' ')"
EMBED_COUNT="$(find "$MODEL_DIR" -maxdepth 1 -type d -name '*embeddings*.mlmodelc' | wc -l | tr -d ' ')"
LM_COUNT="$(find "$MODEL_DIR" -maxdepth 1 -type d -name '*lm_head*.mlmodelc' | wc -l | tr -d ' ')"

[ "$FFN_COUNT" -ge 1 ] || fail "FFN/PREFILL Core-ML-Komponente fehlt."
[ "$EMBED_COUNT" -ge 1 ] || fail "Embedding Core-ML-Komponente fehlt."
[ "$LM_COUNT" -ge 1 ] || fail "LM-Head Core-ML-Komponente fehlt."

codesign --verify --strict --verbose=2 "$HELPER"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

HELPER_SIGNATURE="$(codesign -dv --verbose=4 "$HELPER" 2>&1)"
printf '%s\n' "$HELPER_SIGNATURE" | grep -q 'runtime' \
  || fail "Hardened Runtime ist am ANEMLL Helper nicht sichtbar."

APP_SIZE="$(du -sh "$APP_DIR" | awk '{print $1}')"
MODEL_SIZE="$(du -sh "$MODEL_DIR" | awk '{print $1}')"

printf '\n=== Portable ANEMLL Payload ===\n'
printf 'App:        %s\n' "$APP_DIR"
printf 'Helper:     signiert + hardened\n'
printf 'Model:      Qwen3 eingebettet\n'
printf 'Core ML:    embeddings=%s ffn=%s lm_head=%s\n' "$EMBED_COUNT" "$FFN_COUNT" "$LM_COUNT"
printf 'Model size: %s\n' "$MODEL_SIZE"
printf 'App size:   %s\n' "$APP_SIZE"
printf 'Portable ANEMLL Check: OK\n'

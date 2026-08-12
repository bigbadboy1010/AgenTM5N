#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="${AGENTM5N_ANEMLLCLI:-$ROOT_DIR/.build-artifacts/anemll-runtime/anemllcli}"
DEFAULT_META="$HOME/Downloads/AgenTM5N-Qwen3-ANE/anemll-Qwen-Qwen3-0.6B-ctx512_0.3.4/meta.yaml"
META="${AGENTM5N_ANEMLL_META:-$DEFAULT_META}"
PROMPT="${AGENTM5N_ANEMLL_TEST_PROMPT:-Antworte in einem kurzen Satz: Was ist die Apple Neural Engine?}"
MAX_TOKENS="${AGENTM5N_ANEMLL_TEST_MAX_TOKENS:-64}"
TEMP_DIR="$(mktemp -d -t agentm5n-anemll-test)"
RESPONSE_FILE="$TEMP_DIR/response.txt"
LOG_FILE="$TEMP_DIR/runtime.log"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'ANEMLL QWEN3 TEST FAILED: %s\n' "$1" >&2
  exit 1
}

[ -x "$HELPER" ] || fail "Native Helper fehlt oder ist nicht ausführbar: $HELPER"
[ -f "$META" ] || fail "Qwen3 meta.yaml fehlt: $META"

MODEL_DIR="$(cd "$(dirname "$META")" && pwd)"
for required in \
  tokenizer.json \
  qwen_embeddings.mlmodelc \
  qwen_FFN_PF_lut6_chunk_01of01.mlmodelc \
  qwen_lm_head_lut6.mlmodelc
do
  [ -e "$MODEL_DIR/$required" ] || fail "Modellkomponente fehlt: $MODEL_DIR/$required"
done

printf '\n=== AgenTM5N Native Qwen3 ANE Smoke Test ===\n'
printf 'Helper: %s\n' "$HELPER"
printf 'Meta:   %s\n' "$META"
printf 'Prompt: %s\n' "$PROMPT"
printf 'Tokens: %s\n\n' "$MAX_TOKENS"

"$HELPER" \
  --meta "$META" \
  --prompt "$PROMPT" \
  --max-tokens "$MAX_TOKENS" \
  --temperature 0 \
  --template auto \
  --save "$RESPONSE_FILE" \
  2>&1 | tee "$LOG_FILE"

[ -s "$RESPONSE_FILE" ] || fail "ANEMLL hat keine Antwortdatei erzeugt."

grep -Eq '[0-9]+([.][0-9]+)? t/s, TTFT:' "$LOG_FILE" \
  || fail "ANEMLL Runtime-Metrik fehlt in der Ausgabe."

printf '\n=== NATIVE RESPONSE ===\n'
cat "$RESPONSE_FILE"
printf '\n\n=== NATIVE QWEN3 GATE: OK ===\n'
grep -E '[0-9]+([.][0-9]+)? t/s, TTFT:' "$LOG_FILE" | tail -1 || true

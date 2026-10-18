#!/usr/bin/env bash
# フェーズ1: VRAM に全部乗る Qwen3.6-35B-A3B (UD-Q4_K_XL, 22.4GB) で計測系の動作確認と基準値を取る。
#   - llama.cpp: 2GPU レイヤ分割 / 4090 のみ (--fit が入りきらない分を CPU へ)
#   - Ollama: 既定設定 (コンテキスト長だけ 65536 に揃える)
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase1-$(date +%Y%m%d-%H%M%S).log"
M=Qwen3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf
L=http://127.0.0.1:18081

begin_batch

# 1. llama.cpp 2GPU (layer split、--fit で自動配置)
"${SCRIPTS}/llamacpp.sh" up "$M" -sm layer
bench p1-llamacpp-q36-2gpu "$L" llmb-llamacpp --note "llama.cpp b11718 -sm layer --fit(default), UD-Q4_K_XL"
"${SCRIPTS}/llamacpp.sh" down

# 2. llama.cpp 4090 のみ (入りきらない分は --fit が CPU へ逃がす)
"${SCRIPTS}/llamacpp.sh" up "$M" -dev CUDA0
bench p1-llamacpp-q36-4090 "$L" llmb-llamacpp --note "llama.cpp b11718 -dev CUDA0 --fit(default), UD-Q4_K_XL"
"${SCRIPTS}/llamacpp.sh" down

# 3. Ollama (既定)
start_ollama_bench
bench p1-ollama-q36 http://127.0.0.1:11500 - --model qwen36-ud-q4kxl --note "ollama 0.40.6 default, ctx 65536, same GGUF"
OLLAMA_HOST=127.0.0.1:11500 ollama ps >>"$BATCH_LOG" 2>&1 || true
stop_ollama_bench

log "phase1 done"

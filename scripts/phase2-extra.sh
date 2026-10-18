#!/usr/bin/env bash
# フェーズ2の追加確認 (Qwen3.8-Flash-Next IQ3_S):
#   1. 内容の異なる入力 (configs/workloads.yaml) で速度とエキスパートキャッシュのヒット率が変わるか
#   2. Anthropic Messages API (/v1/messages) 経由でも OpenAI 互換と同じ速度が出るか
# 対象: Strata 4090 単体 (最速だった構成) と llama.cpp 2GPU --fit
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase2-extra-$(date +%Y%m%d-%H%M%S).log"
QUANT=IQ3_S
export STRATA_MODEL="$QUANT"
M="Qwen3.8-Flash-Next-GSQ-RCO/${QUANT}/Qwen3.8-Flash-Next-GSQ-RCO-${QUANT}-00001-of-00002.gguf"

begin_batch

STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0
bench p2x-strata-q38-iq3s-4090-workloads http://127.0.0.1:18080 llmb-strata --config configs/workloads.yaml \
  --note "Strata (docker) GPU=0, MTP spec 4, workloads.yaml"
# サーバーは起動済みなので wait は即座に通る
bench p2x-strata-q38-iq3s-4090-anthropic http://127.0.0.1:18080 llmb-strata --api anthropic \
  --note "Strata (docker) GPU=0, MTP spec 4, Anthropic /v1/messages"
STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down

"${SCRIPTS}/llamacpp.sh" up "$M" -sm layer
bench p2x-llamacpp-q38-iq3s-2gpu-workloads http://127.0.0.1:18081 llmb-llamacpp --config configs/workloads.yaml \
  --note "llama.cpp b11718 -sm layer --fit, workloads.yaml"
bench p2x-llamacpp-q38-iq3s-2gpu-anthropic http://127.0.0.1:18081 llmb-llamacpp --api anthropic \
  --note "llama.cpp b11718 -sm layer --fit, Anthropic /v1/messages"
"${SCRIPTS}/llamacpp.sh" down

log "phase2-extra done"

#!/usr/bin/env bash
# フェーズ6 (続き): 長いコンテキストのやり直しと、合言葉の位置を変えた確認。
#   1. GLM-5.3-Flash / Maya 2GPU を RAM の余裕 14GB で (既定の 6GB では 1M の KV 12GB と合わせて OOM になった)
#   2. Qwen3.8 / Strata の 1M (目標 96万トークン。1,040,000 では tokenizer の都合で 1M を超えた)
#   3. 512K / 約1M × 深さ 0.1 / 0.5 / 0.9: GLM / Maya 2GPU と Qwen3.8 / Strata 4090
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,6p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase6-longctx2-$(date +%Y%m%d-%H%M%S).log"
MAYA_DIR="${HOME}/llm-lab/maya/project-maya"
CTX=1048576
MAYA_VER="$(cat "${MAYA_DIR}/VERSION" 2>/dev/null || echo '?')"
HEADROOM="MAYA_GLM_RAM_HEADROOM_GB=14 STRATA_GLM_RAM_HEADROOM_GB=14"

begin_batch
# Maya の 1M 用設定は phase6-longctx.sh が作ったもの (maya-maya-s24-ctx1048576.json) を使う
MAYA_DOCKER_ENV="$HEADROOM" MAYA_CONFIG="maya-maya-s24-ctx${CTX}.json" "${SCRIPTS}/maya.sh" up --gpus 0,1
bench p6-maya-glm53-s24-2gpu-1m "http://127.0.0.1:18083" llmb-maya --config configs/longctx.yaml \
  --note "Project Maya ${MAYA_VER} Maya-S24 --gpus 0,1 --max-context ${CTX}, RAM headroom 14GB"
bench p6-maya-glm53-s24-2gpu-1m-sweep "http://127.0.0.1:18083" llmb-maya --config configs/longctx-sweep.yaml \
  --note "Project Maya ${MAYA_VER} Maya-S24 --gpus 0,1 --max-context ${CTX}, RAM headroom 14GB, needle depth sweep"
"${SCRIPTS}/maya.sh" down

STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0 "CONFIG=/data/config/strata-iq3_s-ctx${CTX}.json"
bench p6-strata-q38-iq3s-4090-1m-retry "http://127.0.0.1:18080" llmb-strata --config configs/longctx-1m-qwen.yaml \
  --note "Strata IQ3_S GPU=0 --max-context ${CTX} YaRN x4, 1M target lowered to 960000"
bench p6-strata-q38-iq3s-4090-1m-sweep "http://127.0.0.1:18080" llmb-strata --config configs/longctx-sweep-qwen.yaml \
  --note "Strata IQ3_S GPU=0 --max-context ${CTX} YaRN x4, needle depth sweep"
STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down

log "phase6 longctx2 done"

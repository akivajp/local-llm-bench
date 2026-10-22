#!/usr/bin/env bash
# フェーズ6: 長いコンテキスト (32K〜約1M トークン) の確認 (configs/longctx.yaml)。
#   prefill の速度、深い位置での decode の速度、RAM/VRAM、長文の途中に埋めた合言葉を取り出せるか。
#   - GLM-5.3-Flash Maya-S24 / Project Maya: 2GPU / 4090 のみ (--max-context 1048576)
#   - Qwen3.8-Flash-Next IQ3_S / Strata: 4090 のみ (--max-context 1048576、学習時 262K を YaRN ×4 で延長)
#   - DeepSeek-V4.1-Flash-1017 Maya-S / Project Maya: 2GPU (--max-context 1048576)
# 普段使いの設定 (64K) は変えず、コンテキスト長だけを変えた設定を別に作って使う。
# usage: phase6-longctx.sh [target...]
#   target: glm-maya-2gpu glm-maya-4090 qwen-strata-4090 ds-maya-2gpu
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,10p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase6-longctx-$(date +%Y%m%d-%H%M%S).log"
MAYA_DIR="${HOME}/llm-lab/maya/project-maya"
CTX=1048576
MAYA_VER="$(cat "${MAYA_DIR}/VERSION" 2>/dev/null || echo '?')"
ALL=(glm-maya-2gpu glm-maya-4090 qwen-strata-4090 ds-maya-2gpu)
TARGETS=("$@")
[[ $# -eq 0 ]] && TARGETS=("${ALL[@]}")
want() { local t; for t in "${TARGETS[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

# Maya の設定 (maya-<x>.json) からコンテキスト長だけを変えた maya-<x>-ctxN.json を作る (calibrate の env は引き継ぐ)
maya_ctx_config() {
  local base="$1" out="${1%.json}-ctx${CTX}.json"
  python3 - "${MAYA_DIR}/${base}" "${MAYA_DIR}/${out}" "$CTX" <<'PY'
import json, sys
src, dst, ctx = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = json.load(open(src))
a = cfg["args"]
a[a.index("--max-context") + 1] = ctx
json.dump(cfg, open(dst, "w"), indent=1)
PY
  echo "$out"
}

longctx() {
  local label="$1" url="$2" container="$3"; shift 3
  bench "$label" "$url" "$container" --config configs/longctx.yaml "$@"
}

begin_batch
log "phase6 longctx targets=${TARGETS[*]} ctx=${CTX}"

if want glm-maya-2gpu; then
  cfg=$(maya_ctx_config maya-maya-s24.json)
  MAYA_CONFIG="$cfg" "${SCRIPTS}/maya.sh" up --gpus 0,1
  longctx p6-maya-glm53-s24-2gpu-1m http://127.0.0.1:18083 llmb-maya --note "Project Maya ${MAYA_VER} Maya-S24 --gpus 0,1 --max-context ${CTX} (calibrated)"
  "${SCRIPTS}/maya.sh" down
fi
if want glm-maya-4090; then
  cfg=$(maya_ctx_config maya-maya-s24.json)
  MAYA_DOCKER_ENV="MAYA_GLM_RAM_HEADROOM_GB=14 STRATA_GLM_RAM_HEADROOM_GB=14" MAYA_CONFIG="$cfg" "${SCRIPTS}/maya.sh" up --gpu 0
  longctx p6-maya-glm53-s24-4090-1m http://127.0.0.1:18083 llmb-maya --note "Project Maya ${MAYA_VER} Maya-S24 --gpu 0 --max-context ${CTX}, RAM headroom 14GB"
  "${SCRIPTS}/maya.sh" down
fi
if want qwen-strata-4090; then
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" ctx-config "$CTX" >>"$BATCH_LOG"
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0 "CONFIG=/data/config/strata-iq3_s-ctx${CTX}.json"
  longctx p6-strata-q38-iq3s-4090-1m http://127.0.0.1:18080 llmb-strata --note "Strata (docker) IQ3_S GPU=0 --max-context ${CTX} --rope-scaling yarn --rope-scale 4, MTP"
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi
if want ds-maya-2gpu; then
  cfg=$(maya_ctx_config maya-ds4.json)
  MAYA_CONFIG="$cfg" "${SCRIPTS}/maya.sh" up --gpus 0,1
  longctx p6-maya-ds41-s-2gpu-1m http://127.0.0.1:18083 llmb-maya --note "Project Maya ${MAYA_VER} DeepSeek-V4.1 Maya-S --gpus 0,1 --max-context ${CTX}"
  "${SCRIPTS}/maya.sh" down
fi

log "phase6 longctx done"

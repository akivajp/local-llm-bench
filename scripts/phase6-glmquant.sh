#!/usr/bin/env bash
# フェーズ6: GLM-5.3-Flash の上位の量子化 (Project Maya)。Maya-S24 (94.7GB、今までの計測) に対して
#   Maya-M (116GB) / Maya-L (156GB) の速度 (2GPU) と品質 (30問) を比べる。どちらも RAM 89GB + VRAM 44GB に乗りきらない。
# 1つずつ「ダウンロード → setup (pack 作成) → 計測」。ダウンロード中は計測しない (hf_xet の高速モードは RSS が大きい)。
# 環境変数: KEEP=0 で計測後にモデルを消す (既定は残す)
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase6-glmquant-$(date +%Y%m%d-%H%M%S).log"
M=http://127.0.0.1:18083
GGUF="${HOME}/llm-lab/gguf/GLM-5.3-Flash-Maya-GGUF"
MAYA_VER="$(cat "${HOME}/llm-lab/maya/project-maya/VERSION" 2>/dev/null || echo '?')"
# 4090 単体や大きい量子化では既定の 6GB で OOM になることがあるため、全構成で余裕を 14GB にそろえる
HEADROOM="MAYA_GLM_RAM_HEADROOM_GB=14 STRATA_GLM_RAM_HEADROOM_GB=14"
QUANTS=("${@:-Maya-M Maya-L}")
[[ $# -eq 0 ]] && QUANTS=(Maya-M Maya-L)

begin_batch
for q in "${QUANTS[@]}"; do
  lc="$(printf '%s' "$q" | tr 'A-Z' 'a-z')"   # Maya-M → maya-m (setup が書く設定は maya-<lc>.json)
  log "download: ${q}"
  HF_HOME="${HOME}/llm-lab/hf" HF_XET_HIGH_PERFORMANCE=1 uvx --from 'huggingface_hub[hf_xet]' hf download \
    peasantsmith/GLM-5.3-Flash-Maya-GGUF --include "${q}/*" --local-dir "$GGUF" >>"${LOGS}/download-phase6.log" 2>&1
  log "setup: ${q} ($(du -sh "${GGUF}/${q}" | cut -f1))"
  "${SCRIPTS}/maya.sh" setup --model "$q" --gguf-dir "/gguf/GLM-5.3-Flash-Maya-GGUF/${q}" --gpus 0,1 --context 65536 \
    --no-vision --drafting on >>"$BATCH_LOG" 2>&1
  MAYA_DOCKER_ENV="$HEADROOM" MAYA_CONFIG="maya-${lc}.json" "${SCRIPTS}/maya.sh" up --gpus 0,1
  bench "p6-maya-glm53-${lc}-2gpu" "$M" llmb-maya --note "Project Maya ${MAYA_VER} ${q} --gpus 0,1, RAM headroom 14GB"
  (cd "$REPO" && uv run llm-bench quality --label "q-maya-glm53-${lc}-2gpu" --base-url "$M" \
    --sets data/quality/gsm8k-10.jsonl data/quality/mmmlu-ja-20.jsonl --max-tokens 4096 \
    --note "Project Maya ${MAYA_VER} ${q} --gpus 0,1") || log "WARNING: quality ${q}"
  "${SCRIPTS}/maya.sh" down
  if [[ "${KEEP:-1}" == "0" ]]; then log "cleanup: ${GGUF}/${q}"; rm -rf "${GGUF:?}/${q}"; fi
done
# 比較の基準: Maya-S24 も同じ余裕 (14GB) で測り直す
MAYA_DOCKER_ENV="$HEADROOM" MAYA_CONFIG=maya-maya-s24.json "${SCRIPTS}/maya.sh" up --gpus 0,1
bench p6-maya-glm53-s24-2gpu-headroom14 "$M" llmb-maya --note "Project Maya ${MAYA_VER} Maya-S24 --gpus 0,1, RAM headroom 14GB"
"${SCRIPTS}/maya.sh" down
"${SCRIPTS}/collect-env.sh" >"${REPO}/runs/env-phase6.md" 2>&1 || true
log "phase6 glmquant done"

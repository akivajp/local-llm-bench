#!/usr/bin/env bash
# 品質の簡易確認: 量子化 (IQ2_XS / IQ3_S) とエンジン (Strata / llama.cpp) で正答率に明らかな差が出るか。
# 問題集は data/quality/ (llm-bench quality-fetch で取得済みのもの)。
#   - Strata 4090 IQ3_S / Strata 4090 IQ2_XS / llama.cpp 2GPU IQ3_S
#   - Project Maya 2GPU: GLM-5.3-Flash Maya-S24 / DeepSeek-V4.1-Flash-1017 Maya-S (30問・上限 4096。生成が遅く思考が長いため)
# 引数で構成を絞れる (例: phase-quality.sh strata-iq3s)。
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase-quality-$(date +%Y%m%d-%H%M%S).log"
ALL=(strata-iq3s strata-iq2xs llamacpp-iq3s)
# Maya の構成は明示したときだけ実行する (例: phase-quality.sh maya-glm maya-ds)
TARGETS=("$@")
[[ $# -eq 0 ]] && TARGETS=("${ALL[@]}")
want() { local t; for t in "${TARGETS[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

# サーバーの起動を待ってから品質評価を流す。引数: <label> <base_url> <container> [llm-bench quality の追加引数...]
quality() {
  local label="$1" url="$2" container="$3"; shift 3
  log "wait: ${label}"
  if ! (cd "$REPO" && uv run llm-bench wait --base-url "$url" --timeout 1200 --container "$container" --log "${LOGS}/wait-${label}.log"); then
    log "ERROR: ${label} が起動しませんでした (飛ばす)"
    stop_all_servers
    return 0
  fi
  (cd "$REPO" && uv run llm-bench quality --label "$label" --base-url "$url" "$@") || log "WARNING: ${label} にエラーあり"
}

begin_batch

if want strata-iq3s; then
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0
  quality q-strata-q38-iq3s-4090 http://127.0.0.1:18080 llmb-strata --note "Strata (docker) IQ3_S GPU=0, MTP spec 4"
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi

if want strata-iq2xs; then
  STRATA_MODEL=IQ2_XS STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0
  quality q-strata-q38-iq2xs-4090 http://127.0.0.1:18080 llmb-strata --note "Strata (docker) IQ2_XS GPU=0, MTP spec 4"
  STRATA_MODEL=IQ2_XS STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi

if want llamacpp-iq3s; then
  "${SCRIPTS}/llamacpp.sh" up Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf -sm layer
  quality q-llamacpp-q38-iq3s-2gpu http://127.0.0.1:18081 llmb-llamacpp --note "llama.cpp b11718 IQ3_S -sm layer --fit"
  "${SCRIPTS}/llamacpp.sh" down
fi

SMALL=(--sets data/quality/gsm8k-10.jsonl data/quality/mmmlu-ja-20.jsonl --max-tokens 4096)
if want maya-glm; then
  MAYA_RUN=run-maya-maya-s24.sh "${SCRIPTS}/maya.sh" up --gpus 0,1
  quality q-maya-glm53-s24-2gpu http://127.0.0.1:18083 llmb-maya "${SMALL[@]}" --note "Project Maya Maya-S24 --gpus 0,1, MTP"
  "${SCRIPTS}/maya.sh" down
fi

if want maya-ds; then
  MAYA_RUN=run-maya-ds4.sh "${SCRIPTS}/maya.sh" up --gpus 0,1
  quality q-maya-ds41-s-2gpu http://127.0.0.1:18083 llmb-maya "${SMALL[@]}" --note "Project Maya DeepSeek-V4.1 Maya-S --gpus 0,1, DSpark"
  "${SCRIPTS}/maya.sh" down
fi

log "phase-quality done"

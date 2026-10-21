#!/usr/bin/env bash
# フェーズ5: Project Maya (Strata 派生、GLM-5.3-Flash / DeepSeek-V4.1-Flash-1017 専用エンジン) と llama.cpp の比較。
#   - GLM-5.3-Flash (321B/A18B): Maya の Maya-S24 (94.7GB) / llama.cpp b11718 の UD-IQ1_S (93GB)
#   - DeepSeek-V4.1-Flash-1017 (748B): Maya の Maya-S (340GB) / llama.cpp PR #30817 の UD-IQ1_S (233GB)
#   それぞれ 4090 のみ / 2GPU。DeepSeek は RAM に収まらず SSD から読むので configs/slow.yaml (入出力を短く)。
# 事前に scripts/maya.sh setup で各モデルを準備しておくこと (run-maya-maya-s24.sh / run-maya-<ds>.sh ができる)。
# 2026-10-22 から、ストレージは NVMe 3枚の btrfs RAID0 (それ以前のフェーズは NVMe 1枚)。
# usage: phase5.sh [target...]   (省略時は全部)
#   target: glm-llamacpp-4090 glm-llamacpp-2gpu glm-maya-4090 glm-maya-2gpu
#           ds-maya-4090 ds-maya-2gpu ds-llamacpp-4090 ds-llamacpp-2gpu
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,10p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase5-$(date +%Y%m%d-%H%M%S).log"
L=http://127.0.0.1:18081
M=http://127.0.0.1:18083
GLM_GGUF=GLM-5.3-Flash-GGUF/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf
DS_GGUF="$(cd "${HOME}/llm-lab/gguf" && ls DeepSeek-V4.1-Flash-1017-GGUF/UD-IQ1_S/*00001-of-*.gguf 2>/dev/null | head -1 || true)"
DS_RUN="${DS_RUN:-run-maya-ds4.sh}"     # Maya の DeepSeek 用起動スクリプト (setup が書く名前)
MAYA_VER="$(cat "${HOME}/llm-lab/maya/project-maya/VERSION" 2>/dev/null || echo '?')"
ALL=(glm-llamacpp-4090 glm-llamacpp-2gpu glm-maya-4090 glm-maya-2gpu ds-maya-4090 ds-maya-2gpu ds-llamacpp-4090 ds-llamacpp-2gpu)
TARGETS=("$@")
[[ $# -eq 0 ]] && TARGETS=("${ALL[@]}")
want() { local t; for t in "${TARGETS[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

begin_batch
log "phase5 targets=${TARGETS[*]} maya=${MAYA_VER} ds_gguf=${DS_GGUF:-none}"

# --- GLM-5.3-Flash ---
if want glm-llamacpp-4090; then
  "${SCRIPTS}/llamacpp.sh" up "$GLM_GGUF" -dev CUDA0
  bench p5-llamacpp-glm53-iq1s-4090-raid0 "$L" llmb-llamacpp --note "llama.cpp b11718 -dev CUDA0 --fit, UD-IQ1_S, storage NVMe x3 RAID0"
  "${SCRIPTS}/llamacpp.sh" down
fi
if want glm-llamacpp-2gpu; then
  "${SCRIPTS}/llamacpp.sh" up "$GLM_GGUF" -sm layer
  bench p5-llamacpp-glm53-iq1s-2gpu-raid0 "$L" llmb-llamacpp --note "llama.cpp b11718 -sm layer --fit, UD-IQ1_S, storage NVMe x3 RAID0"
  "${SCRIPTS}/llamacpp.sh" down
fi
if want glm-maya-4090; then
  MAYA_RUN=run-maya-maya-s24.sh "${SCRIPTS}/maya.sh" up --gpu 0
  bench p5-maya-glm53-s24-4090 "$M" llmb-maya --note "Project Maya ${MAYA_VER} Maya-S24 --gpu 0, MTP"
  "${SCRIPTS}/maya.sh" down
fi
if want glm-maya-2gpu; then
  MAYA_RUN=run-maya-maya-s24.sh "${SCRIPTS}/maya.sh" up --gpus 0,1
  bench p5-maya-glm53-s24-2gpu "$M" llmb-maya --note "Project Maya ${MAYA_VER} Maya-S24 --gpus 0,1 (layer split auto), MTP"
  "${SCRIPTS}/maya.sh" down
fi

# --- DeepSeek-V4.1-Flash-1017 (SSD から読む。configs/slow.yaml) ---
if want ds-maya-4090; then
  MAYA_RUN="$DS_RUN" "${SCRIPTS}/maya.sh" up --gpu 0
  bench p5-maya-ds41-s-4090 "$M" llmb-maya --config configs/slow.yaml --note "Project Maya ${MAYA_VER} DeepSeek Maya-S --gpu 0"
  "${SCRIPTS}/maya.sh" down
fi
if want ds-maya-2gpu; then
  MAYA_RUN="$DS_RUN" "${SCRIPTS}/maya.sh" up --gpus 0,1
  bench p5-maya-ds41-s-2gpu "$M" llmb-maya --config configs/slow.yaml --note "Project Maya ${MAYA_VER} DeepSeek Maya-S --gpus 0,1"
  "${SCRIPTS}/maya.sh" down
fi
if want ds-llamacpp-4090 && [[ -n "$DS_GGUF" ]]; then
  # unsloth の手順どおり mmap + lazy (Engram 表は SSD から必要な行だけ読む)。--fit を効かせるため -ot は付けない
  LLAMACPP_IMAGE=llmb-llamacpp:deepseek41 "${SCRIPTS}/llamacpp.sh" up "$DS_GGUF" -dev CUDA0 --load-mode mmap --lazy-mode on
  bench p5-llamacpp-ds41-iq1s-4090 "$L" llmb-llamacpp --config configs/slow.yaml --note "llama.cpp PR#30817 (b72050d03) -dev CUDA0 --fit --load-mode mmap --lazy-mode on, UD-IQ1_S"
  "${SCRIPTS}/llamacpp.sh" down
fi
if want ds-llamacpp-2gpu && [[ -n "$DS_GGUF" ]]; then
  LLAMACPP_IMAGE=llmb-llamacpp:deepseek41 "${SCRIPTS}/llamacpp.sh" up "$DS_GGUF" -sm layer --load-mode mmap --lazy-mode on
  bench p5-llamacpp-ds41-iq1s-2gpu "$L" llmb-llamacpp --config configs/slow.yaml --note "llama.cpp PR#30817 (b72050d03) -sm layer --fit --load-mode mmap --lazy-mode on, UD-IQ1_S"
  "${SCRIPTS}/llamacpp.sh" down
fi

log "phase5 done"

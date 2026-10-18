#!/usr/bin/env bash
# フェーズ2: Qwen3.8-Flash-Next (125B MoE, A6B) のエンジン比較。量子化は STRATA_MODEL / QUANT で切り替える (既定 IQ2_XS)。
#   - llama.cpp: 2GPU (--fit) / 4090 のみ (--fit, mmap あり・なし)
#   - Strata 本家: 4090 のみ / 2GPU レイヤ分割
#   - Strata-DualGPU フォーク: 2GPU
#   - Ollama: 同じ GGUF を取り込んだもの (既定設定)
# 事前に scripts/strata.sh setup (本家・フォーク両方) を済ませておくこと。
# 引数で構成を絞れる (例: phase2.sh strata-2gpu llamacpp-2gpu)。省略時は全部。
#
# 注意: llama.cpp の --fit は -ot (tensor override) をユーザーが指定すると黙って無効になる
#       ("tensor_buft_overrides already set by user, abort")。配置は --fit に任せ、-ot は付けない。
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,11p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
QUANT="${QUANT:-IQ2_XS}"
q="$(printf '%s' "$QUANT" | tr 'A-Z' 'a-z')"   # ラベル用 (IQ2_XS → iq2xs)
q="${q//_/}"
BATCH_LOG="${LOGS}/phase2-${q}-$(date +%Y%m%d-%H%M%S).log"
M="Qwen3.8-Flash-Next-GSQ-RCO/${QUANT}/Qwen3.8-Flash-Next-GSQ-RCO-${QUANT}-00001-of-00002.gguf"
L=http://127.0.0.1:18081
S=http://127.0.0.1:18080
LV=b11718
SV=$(grep -m1 -oE 'VERSION *= *"[^"]+"' "${HOME}/llm-lab/strata/Strata/setup.py" | grep -oE '[0-9.]+' || echo '?')
ALL=(llamacpp-2gpu llamacpp-2gpu-cache llamacpp-4090 llamacpp-4090-nommap strata-4090 strata-4090-nomtp strata-2gpu strata-dual-2gpu ollama)
TARGETS=("$@")
[[ $# -eq 0 ]] && TARGETS=("${ALL[@]}")
export STRATA_MODEL="$QUANT"

want() { local t; for t in "${TARGETS[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

begin_batch
log "phase2 quant=${QUANT} targets=${TARGETS[*]}"

if want llamacpp-2gpu; then
  "${SCRIPTS}/llamacpp.sh" up "$M" -sm layer
  bench "p2-llamacpp-q38-${q}-2gpu-fit" "$L" llmb-llamacpp --note "llama.cpp ${LV} -sm layer --fit(default), mmap"
  "${SCRIPTS}/llamacpp.sh" down
fi

if want llamacpp-2gpu-cache; then
  # CPU に残ったエキスパートのうち使用頻度の高いものを VRAM にキャッシュする (PR #30112)
  "${SCRIPTS}/llamacpp.sh" up "$M" -sm layer --moe-cache-mib "${MOE_CACHE_MIB:-6144}"
  bench "p2-llamacpp-q38-${q}-2gpu-fit-moecache" "$L" llmb-llamacpp --note "llama.cpp ${LV} -sm layer --fit(default) --moe-cache-mib ${MOE_CACHE_MIB:-6144}, mmap"
  "${SCRIPTS}/llamacpp.sh" down
fi

if want llamacpp-4090; then
  "${SCRIPTS}/llamacpp.sh" up "$M" -dev CUDA0
  bench "p2-llamacpp-q38-${q}-4090-fit" "$L" llmb-llamacpp --note "llama.cpp ${LV} -dev CUDA0 --fit(default), mmap"
  "${SCRIPTS}/llamacpp.sh" down
fi

if want llamacpp-4090-nommap; then
  # CPU に置く重みを mmap ではなく通常のメモリに読み込む (起動時の警告が推奨する設定)
  "${SCRIPTS}/llamacpp.sh" up "$M" -dev CUDA0 --load-mode none
  bench "p2-llamacpp-q38-${q}-4090-fit-nommap" "$L" llmb-llamacpp --note "llama.cpp ${LV} -dev CUDA0 --fit(default) --load-mode none"
  "${SCRIPTS}/llamacpp.sh" down
fi

if want strata-4090; then
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0
  bench "p2-strata-q38-${q}-4090" "$S" llmb-strata --note "Strata ${SV} (docker) GPU=0, MTP spec 4"
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi

if want strata-4090-nomtp; then
  # MTP を切り、エキスパートの階層キャッシュだけの効果を見る
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" nomtp-config >>"$BATCH_LOG"
  # Strata の設定ファイル名は量子化名の小文字 (IQ2_XS → strata-iq2_xs.json)
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0 "CONFIG=/data/config/strata-$(printf '%s' "$QUANT" | tr 'A-Z' 'a-z')-nomtp.json"
  bench "p2-strata-q38-${q}-4090-nomtp" "$S" llmb-strata --note "Strata ${SV} (docker) GPU=0, MTP off (--mtp/--spec-min-p removed, --spec 4 kept)"
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi

if want strata-2gpu; then
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPUS=0,1
  bench "p2-strata-q38-${q}-2gpu" "$S" llmb-strata --note "Strata ${SV} (docker) GPUS=0,1 layer_split auto, MTP spec 4"
  STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi

if want strata-dual-2gpu; then
  STRATA_VARIANT=dualgpu "${SCRIPTS}/strata.sh" up GPUS=0,1
  bench "p2-strata-dual-q38-${q}-2gpu" "$S" llmb-strata-dual --note "Strata-DualGPU 0.1.38-dual (docker) GPUS=0,1, MTP spec 4"
  STRATA_VARIANT=dualgpu "${SCRIPTS}/strata.sh" down
fi

if want ollama; then
  start_ollama_bench
  bench "p2-ollama-q38-${q}" "http://127.0.0.1:11500" - --model "qwen38-${q}" --note "ollama 0.40.6 default, ctx 65536, same GGUF (${QUANT})"
  OLLAMA_HOST=127.0.0.1:11500 ollama ps >>"$BATCH_LOG" 2>&1 || true
  stop_ollama_bench
fi

log "phase2 done"

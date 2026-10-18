#!/usr/bin/env bash
# フェーズ3: Qwen3.8 以外の大きな MoE を llama.cpp で計測する (Strata は Qwen3.8 専用のため)。
# 1モデルずつ「ダウンロード → 速度 (4090 / 2GPU / 2GPU+MoE キャッシュ) → 品質 → 削除」の順に進める。
#
# usage: phase3.sh <model-key> [...]   (省略時は全部)
#   model-key: qwen35-122b | gpt-oss-120b | nemotron35-super | deepseek-v4-flash | glm53-flash
# 環境変数: KEEP=1 で計測後もモデルを消さない、SKIP_QUALITY=1 で品質評価を省く、SKIP_SPEED=1 で速度計測を省く
#           QUALITY_SETS / QUALITY_MAX_TOKENS で品質評価の問題集・出力上限を変える
#           (既定は GSM8K 10問 + MMMLU-JA 20問、4096 トークン。思考の長いモデルで1時間以上かかるのを避けるため)
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,9p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase3-$(date +%Y%m%d-%H%M%S).log"
GGUF="${HOME}/llm-lab/gguf"
L=http://127.0.0.1:18081
LV=b11718

# key → "HF リポジトリ|--include パターン|1つ目の GGUF の相対パス (リポジトリ直下からの)"
declare -A MODELS=(
  [qwen35-122b]="unsloth/Qwen3.5-122B-A10B-GGUF|UD-IQ4_XS/*|UD-IQ4_XS/Qwen3.5-122B-A10B-UD-IQ4_XS-00001-of-00003.gguf"
  [gpt-oss-120b]="unsloth/gpt-oss-120b-GGUF|gpt-oss-120b-F16.gguf|gpt-oss-120b-F16.gguf"
  [nemotron35-super]="unsloth/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-GGUF|UD-Q3_K_XL/*|UD-Q3_K_XL/NVIDIA-Nemotron-3.5-Super-VL-120B-A12B-UD-Q3_K_XL-00001-of-00003.gguf"
  [deepseek-v4-flash]="unsloth/DeepSeek-V4-Flash-GGUF|UD-IQ1_S/*|UD-IQ1_S/DeepSeek-V4-Flash-UD-IQ1_S-00001-of-00002.gguf"
  [glm53-flash]="unsloth/GLM-5.3-Flash-GGUF|UD-IQ1_S/*|UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf"
)
ORDER=(qwen35-122b gpt-oss-120b nemotron35-super deepseek-v4-flash glm53-flash)
TARGETS=("$@")
[[ $# -eq 0 ]] && TARGETS=("${ORDER[@]}")

download() {
  local repo="$1" include="$2" dir="$3"
  log "download: ${repo} (${include}) → ${dir}"
  HF_HOME="${HOME}/llm-lab/hf" HF_XET_HIGH_PERFORMANCE=1 \
    uvx --from 'huggingface_hub[hf_xet]' hf download "$repo" --include "$include" --local-dir "$dir" \
    >>"${LOGS}/download-phase3.log" 2>&1
}

begin_batch

for key in "${TARGETS[@]}"; do
  IFS='|' read -r repo include first <<<"${MODELS[$key]}"
  dir="${GGUF}/$(basename "$repo")"
  # 分割ファイルの名前は実物から探す (シャード数の想定違いに備える)
  if ! download "$repo" "$include" "$dir"; then
    log "ERROR: ${key} のダウンロードに失敗 (飛ばす)"
    continue
  fi
  model_path="$(cd "$GGUF" && ls "$(basename "$repo")/${first%/*}"/*00001-of-*.gguf 2>/dev/null | head -1 || true)"
  [[ -z "$model_path" ]] && model_path="$(basename "$repo")/${first}"
  log "model: ${model_path} ($(du -sh "$dir" | cut -f1))"

  if [[ "${SKIP_SPEED:-0}" != "1" ]]; then
  "${SCRIPTS}/llamacpp.sh" up "$model_path" -dev CUDA0
  bench "p3-llamacpp-${key}-4090-fit" "$L" llmb-llamacpp --note "llama.cpp ${LV} ${model_path} -dev CUDA0 --fit"
  "${SCRIPTS}/llamacpp.sh" down

  "${SCRIPTS}/llamacpp.sh" up "$model_path" -sm layer --moe-cache-mib "${MOE_CACHE_MIB:-6144}"
  bench "p3-llamacpp-${key}-2gpu-fit-moecache" "$L" llmb-llamacpp --note "llama.cpp ${LV} ${model_path} -sm layer --fit --moe-cache-mib ${MOE_CACHE_MIB:-6144}"
  "${SCRIPTS}/llamacpp.sh" down

  fi

  "${SCRIPTS}/llamacpp.sh" up "$model_path" -sm layer
  if [[ "${SKIP_SPEED:-0}" != "1" ]]; then
    bench "p3-llamacpp-${key}-2gpu-fit" "$L" llmb-llamacpp --note "llama.cpp ${LV} ${model_path} -sm layer --fit"
  else
    (cd "$REPO" && uv run llm-bench wait --base-url "$L" --container llmb-llamacpp --timeout 1200)
  fi
  if [[ "${SKIP_QUALITY:-0}" != "1" ]]; then
    # 2GPU --fit のサーバーをそのまま使って品質評価
    # shellcheck disable=SC2086
    (cd "$REPO" && uv run llm-bench quality --label "q-llamacpp-${key}-2gpu" --base-url "$L" \
      --sets ${QUALITY_SETS:-data/quality/gsm8k-10.jsonl data/quality/mmmlu-ja-20.jsonl} \
      --max-tokens "${QUALITY_MAX_TOKENS:-4096}" --note "llama.cpp ${LV} ${model_path} -sm layer --fit") || log "WARNING: q-${key} にエラーあり"
  fi
  "${SCRIPTS}/llamacpp.sh" down

  # 再現用にモデルのリビジョンを残してから消す
  "${SCRIPTS}/collect-env.sh" >"${REPO}/runs/env-p3-${key}.md" 2>&1 || true
  if [[ "${KEEP:-0}" != "1" ]]; then
    log "cleanup: ${dir} を削除"
    rm -rf "$dir"
  fi
done

log "phase3 done"

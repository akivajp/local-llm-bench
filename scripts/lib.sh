#!/usr/bin/env bash
# フェーズごとの一括計測スクリプトから source する共通関数。
# 方針: GPU を共有する常駐コンテナ (GPU テナント、scripts/gpu-tenant.sh) を止めるのはバッチ全体で1回。
#       終了時 (失敗・Ctrl-C を含む) には LLM サーバーを全部止め、GPU_TENANT_RESTORE=1 なら相手を戻す (trap)。

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="${REPO}/scripts"
LOGS="${HOME}/llm-lab/logs"
mkdir -p "$LOGS"

log() { echo "$(date '+%F %T') [batch] $*" | tee -a "${BATCH_LOG:-${LOGS}/batch.log}"; }

# 計測用のサーバーをすべて止める (存在しなければ何もしない)
stop_all_servers() {
  "${SCRIPTS}/llamacpp.sh" down >/dev/null 2>&1 || true
  for c in llmb-strata llmb-strata-dual; do
    if docker inspect "$c" >/dev/null 2>&1; then
      docker logs "$c" >"${LOGS}/${c}-$(date +%Y%m%d-%H%M%S).log" 2>&1 || true
      docker stop -t 60 "$c" >/dev/null 2>&1 || true
      docker rm -f "$c" >/dev/null 2>&1 || true
    fi
  done
  stop_ollama_bench
}

# 計測用 Ollama (127.0.0.1:11500) の起動・停止。システムの Ollama (11434) には触れない
start_ollama_bench() {
  stop_ollama_bench
  OLLAMA_HOST=127.0.0.1:11500 OLLAMA_MODELS="${HOME}/llm-lab/ollama" OLLAMA_KEEP_ALIVE=-1 \
    OLLAMA_NO_CLOUD=1 OLLAMA_CONTEXT_LENGTH=65536 \
    nohup ollama serve >>"${LOGS}/ollama-bench.log" 2>&1 &
  echo $! >"${LOGS}/ollama-bench.pid"
}
stop_ollama_bench() {
  local f="${LOGS}/ollama-bench.pid"
  if [[ -f "$f" ]]; then
    kill "$(cat "$f")" 2>/dev/null || true
    rm -f "$f"
    sleep 2
  fi
}

# バッチ終了時の後始末。GPU_TENANT_RESTORE=1 のときだけ GPU テナントを戻す
# (連続して何バッチも流すときに毎回戻さないよう、既定では戻さない)
cleanup() {
  log "cleanup: サーバー停止"
  stop_all_servers
  if [[ "${GPU_TENANT_RESTORE:-0}" == "1" ]]; then
    log "cleanup: GPU テナント起動"
    "${SCRIPTS}/gpu-tenant.sh" start || log "WARNING: GPU テナントの起動確認に失敗"
  fi
}

begin_batch() {
  trap cleanup EXIT
  # shellcheck disable=SC1091
  [[ -f "${SCRIPTS}/local.env" ]] && source "${SCRIPTS}/local.env"
  if [[ -n "${GPU_TENANT_CONTAINER:-}" && "$(docker inspect -f '{{.State.Running}}' "$GPU_TENANT_CONTAINER" 2>/dev/null)" == "true" ]]; then
    log "GPU テナント (${GPU_TENANT_CONTAINER}) を停止"
    "${SCRIPTS}/gpu-tenant.sh" stop
  fi
  # 再現条件 (バージョン・ダイジェスト等) をバッチごとに記録する
  "${SCRIPTS}/collect-env.sh" >"${REPO}/runs/env-$(date +%Y%m%d-%H%M%S).md" 2>&1 || true
}

# サーバーの起動を待ってから計測する。引数: <label> <base_url> <container|-> [llm-bench run の追加引数...]
# container を渡すと、待機中にコンテナが落ちた時点で打ち切る (起動失敗で1時間待ち続けないように)
bench() {
  local label="$1" url="$2" container="$3"; shift 3
  log "wait: ${label} (${url})"
  local t0=$SECONDS
  local wait_args=(--base-url "$url" --timeout 1200 --log "${LOGS}/wait-${label}.log")
  [[ "$container" != "-" ]] && wait_args+=(--container "$container")
  if ! (cd "$REPO" && uv run llm-bench wait "${wait_args[@]}"); then
    log "ERROR: ${label} が起動しませんでした (この構成は飛ばす)"
    stop_all_servers
    return 0
  fi
  log "ready: ${label} (起動 $((SECONDS - t0))s)"
  # 起動時間を結果ディレクトリに残す
  mkdir -p "${REPO}/runs/${label}"
  echo "$((SECONDS - t0))" >"${REPO}/runs/${label}/startup_seconds.txt"
  (cd "$REPO" && uv run llm-bench run --label "$label" --base-url "$url" "$@") || log "WARNING: ${label} にエラーあり"
}

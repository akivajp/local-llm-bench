#!/usr/bin/env bash
# 同じ GPU を常用している別サービスのコンテナ (GPU テナント) を、計測中だけ止める・戻す補助スクリプト。
# 必ず「LLM サーバーを止めてから start」の順で戻すこと (VRAM の取り合いで相手が OOM しないように)。
# 対象のコンテナ名は環境変数 GPU_TENANT_CONTAINER か scripts/local.env (Git 管理外) で指定する。
set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
[[ -f "${_here}/local.env" ]] && source "${_here}/local.env"
CONTAINER="${GPU_TENANT_CONTAINER:-}"
LOG="${HOME}/llm-lab/logs/gpu-tenant.log"

usage() {
  cat <<EOF
usage: $(basename "$0") {stop|start|status} [-h|--help]

  stop    ${CONTAINER} を停止する (停止時刻をログに残す)
  start   ${CONTAINER} を起動し、health が 200 になるまで待つ
  status  コンテナの状態と GPU の使用状況を表示する

対象: GPU_TENANT_CONTAINER=${CONTAINER:-(未設定: 何もしない)}  ログ: ${LOG}
EOF
}

log() { mkdir -p "$(dirname "$LOG")"; echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

case "${1:-}" in
  -h|--help|"") usage; exit 0 ;;
esac
# 対象が未設定なら何もしない (GPU を他と共有していない環境)
if [[ -z "$CONTAINER" ]]; then echo "GPU_TENANT_CONTAINER 未設定: skip"; exit 0; fi

case "${1:-}" in
  stop)
    log "stop ${CONTAINER}"
    docker stop -t 30 "$CONTAINER" >/dev/null
    log "stopped"
    ;;
  start)
    log "start ${CONTAINER}"
    docker start "$CONTAINER" >/dev/null
    # health check が通るまで最大5分待つ (Whisper のロードに時間がかかる)
    for _ in $(seq 1 150); do
      st=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo unknown)
      if [[ "$st" == "healthy" ]]; then log "healthy"; exit 0; fi
      sleep 2
    done
    log "WARNING: healthy にならないまま5分経過 (status=$st)"
    exit 1
    ;;
  status)
    docker ps -a --filter "name=${CONTAINER}" --format '{{.Names}}\t{{.Status}}'
    nvidia-smi --query-gpu=index,name,memory.used,memory.total --format=csv,noheader
    ;;
  *) usage; exit 2 ;;
esac

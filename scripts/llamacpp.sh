#!/usr/bin/env bash
# llama.cpp (llama-server) を Docker で起動・停止する補助スクリプト。
# モデルは ~/llm-lab/gguf を読み取り専用で /models にマウントする。
set -euo pipefail

IMAGE="${LLAMACPP_IMAGE:-ghcr.io/ggml-org/llama.cpp:server-cuda}"
NAME="${LLAMACPP_NAME:-llmb-llamacpp}"
PORT="${LLAMACPP_PORT:-18081}"
GGUF_ROOT="${GGUF_ROOT:-${HOME}/llm-lab/gguf}"
LOG_DIR="${HOME}/llm-lab/logs"

usage() {
  cat <<EOF
usage: $(basename "$0") up <gguf の相対パス> [llama-server の追加引数...]
       $(basename "$0") down | logs | -h | --help

  up    コンテナ ${NAME} を起動する (127.0.0.1:${PORT} → コンテナの 8080)。
        共通引数: -c 65536 --jinja --host 0.0.0.0 --port 8080 (追加引数で上書き可)
        例: $(basename "$0") up Qwen3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf -sm layer --fit-target 1024
  down  コンテナを停止・削除する (ログは ${LOG_DIR}/${NAME}-<時刻>.log に保存)
  logs  コンテナのログを追う (docker logs -f)

環境変数: LLAMACPP_IMAGE, LLAMACPP_NAME, LLAMACPP_PORT, GGUF_ROOT
EOF
}

case "${1:-}" in
  -h|--help|"") usage ;;
  up)
    shift
    model="${1:?gguf の相対パスを指定してください}"; shift
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    # --ulimit memlock: mlock/pinned memory を使う場合の制限を外す
    docker run -d --name "$NAME" --gpus all --ipc=host --ulimit memlock=-1 \
      -p "127.0.0.1:${PORT}:8080" -v "${GGUF_ROOT}:/models:ro" \
      "$IMAGE" -m "/models/${model}" -c 65536 --jinja --host 0.0.0.0 --port 8080 "$@" >/dev/null
    echo "started ${NAME} on 127.0.0.1:${PORT} (model=${model}, args=$*)"
    ;;
  down)
    mkdir -p "$LOG_DIR"
    if docker inspect "$NAME" >/dev/null 2>&1; then
      f="${LOG_DIR}/${NAME}-$(date +%Y%m%d-%H%M%S).log"
      docker logs "$NAME" >"$f" 2>&1 || true
      docker rm -f "$NAME" >/dev/null
      echo "stopped ${NAME} (log: $f)"
    else
      echo "${NAME} is not running"
    fi
    ;;
  logs) docker logs -f "$NAME" ;;
  *) usage; exit 2 ;;
esac

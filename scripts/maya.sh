#!/usr/bin/env bash
# Project Maya (https://github.com/mw00/project-maya) を CUDA ビルド用コンテナ (docker/cuda-build.Dockerfile) の中で
# セットアップ・起動・停止する補助スクリプト。Maya には Docker 版もビルド済みの Linux エンジンも無く、
# ソースからのビルドに CUDA Toolkit が要るため、ホストに Toolkit が無い環境ではコンテナ内で動かす。
#   - リポジトリは ~/llm-lab/maya/project-maya (git clone 済み)、ビルド成果物・.venv もそこに入る
#   - ホストのユーザー権限で動かす (root 所有のファイルを作らない)。HOME は ~/llm-lab/maya/home
#   - ネットワークはホストと共有し、Maya 自身が 127.0.0.1:${MAYA_PORT} で待ち受ける
#   - モデルは ~/llm-lab/gguf を /gguf にマウント (Maya は pack をモデルのフォルダに書くので書き込み可)
set -euo pipefail

IMAGE="${MAYA_IMAGE:-llmb-cuda-build}"
NAME="${MAYA_NAME:-llmb-maya}"
PORT="${MAYA_PORT:-18083}"
LAB="${HOME}/llm-lab"
LOG_DIR="${LAB}/logs"

usage() {
  cat <<EOF
usage: $(basename "$0") setup [maya.sh の引数...]   ビルドとモデルの準備だけ (--setup --yes --plain --no-start を付ける)
       $(basename "$0") up [maya.sh の引数...]      サーバーを起動 (127.0.0.1:${PORT})
       $(basename "$0") down | logs | -h | --help

例: $(basename "$0") setup --model Maya-S24 --gguf-dir /gguf/GLM-5.3-Flash-Maya-GGUF/Maya-S24 --gpus 0,1 --no-vision
    $(basename "$0") up --gpu 0
環境変数: MAYA_IMAGE, MAYA_NAME, MAYA_PORT, MAYA_RUN (起動スクリプト名。例: run-maya-maya-s24.sh)
EOF
}

common_args() {
  # memlock 無制限: Maya は空き RAM を pinned memory として固定する
  echo --gpus all --ipc=host --network host --ulimit memlock=-1 --stop-timeout 120 \
    --user "$(id -u):$(id -g)" -e HOME=/maya/home -e MAYA_UPDATE_CHECK=0 \
    -v "${LAB}/maya:/maya" -v "${LAB}/gguf:/gguf" -w /maya/project-maya
  # MAYA_DOCKER_ENV="K=V K2=V2": エンジンの設定をコンテナの環境変数として渡す
  # (例: MAYA_GLM_RAM_HEADROOM_GB=14。既定の 6GB では常駐の他プロセスと合わせて OOM になることがある)
  local kv
  for kv in ${MAYA_DOCKER_ENV:-}; do printf -- '-e %s\n' "$kv"; done
  # MAYA_DOCKER_ARGS: docker run への追加引数 (例: ストレージ帯域を絞る --device-read-bps /dev/nvme0n1:2400mb)
  echo "${MAYA_DOCKER_ARGS:-}"
}

case "${1:-}" in
  -h|--help|"") usage ;;
  setup)
    shift
    mkdir -p "${LAB}/maya/home" "$LOG_DIR"
    f="${LOG_DIR}/${NAME}-setup-$(date +%Y%m%d-%H%M%S).log"
    echo "setup (log: $f)"
    # shellcheck disable=SC2046
    docker run --rm --name "${NAME}-setup" $(common_args) "$IMAGE" \
      ./maya.sh --setup --yes --plain --no-start --port "$PORT" "$@" </dev/null >"$f" 2>&1
    echo "setup done (exit=$?)"
    ;;
  up)
    shift
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    # Maya は「最後に使った設定」で起動するため、モデルを切り替えるときは MAYA_RUN でモデルごとの
    # 起動スクリプト (setup が書く run-maya-<model>.sh) を明示する
    start=(./maya.sh)
    [[ -n "${MAYA_RUN:-}" ]] && start=("./${MAYA_RUN}")
    # shellcheck disable=SC2046
    docker run -d --name "$NAME" $(common_args) "$IMAGE" "${start[@]}" --plain --port "$PORT" "$@" >/dev/null
    echo "started ${NAME} on 127.0.0.1:${PORT} (${start[*]}) args=$*"
    ;;
  down)
    mkdir -p "$LOG_DIR"
    if docker inspect "$NAME" >/dev/null 2>&1; then
      f="${LOG_DIR}/${NAME}-$(date +%Y%m%d-%H%M%S).log"
      docker logs "$NAME" >"$f" 2>&1 || true
      docker stop -t 120 "$NAME" >/dev/null 2>&1 || true
      docker rm -f "$NAME" >/dev/null
      echo "stopped ${NAME} (log: $f)"
    else
      echo "${NAME} is not running"
    fi
    ;;
  logs) docker logs -f "$NAME" ;;
  *) usage; exit 2 ;;
esac

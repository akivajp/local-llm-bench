#!/usr/bin/env bash
# Strata (本家 / DualGPU フォーク) を Docker で準備・起動・停止する補助スクリプト。
# イメージは ~/llm-lab/strata の各リポジトリから docker build したもの (llmb-strata:upstream / :dualgpu)。
set -euo pipefail

VARIANT="${STRATA_VARIANT:-upstream}"      # upstream | dualgpu
MODEL="${STRATA_MODEL:-IQ2_XS}"
CONTEXT="${STRATA_CONTEXT:-65536}"
GGUF_DIR="${STRATA_GGUF_DIR:-${HOME}/llm-lab/gguf/Qwen3.8-Flash-Next-GSQ-RCO/${MODEL}}"
DATA_DIR="${HOME}/llm-lab/strata/docker-data-${VARIANT}"
PORT="${STRATA_PORT:-18080}"
LOG_DIR="${HOME}/llm-lab/logs"
if [[ "$VARIANT" == "dualgpu" ]]; then NAME=llmb-strata-dual; else NAME=llmb-strata; fi
IMAGE="llmb-strata:${VARIANT}"

usage() {
  cat <<EOF
usage: $(basename "$0") setup | up [ENV=VAL...] | down | logs | -h | --help

  setup  モデルの変換と MTP 層の取得だけを行う (起動しない)。GPUS=0,1 で構成を記録する
  up     サーバーを起動する。追加の ENV=VAL はコンテナの環境変数として渡す
         例: $(basename "$0") up GPU=0          (4090 のみ)
             $(basename "$0") up GPUS=0,1       (2GPU レイヤ分割)
  down   停止・削除 (ログは ${LOG_DIR}/${NAME}-<時刻>.log)
  logs   ログを追う

環境変数: STRATA_VARIANT (upstream|dualgpu), STRATA_MODEL, STRATA_CONTEXT, STRATA_GGUF_DIR, STRATA_PORT
データ: ${DATA_DIR}
EOF
}

common_args() {
  # memlock 無制限: Strata は RAM 上のエキスパートを pinned memory として固定する
  echo --gpus all --ipc=host --ulimit memlock=-1 --stop-timeout 60 \
    -v "${DATA_DIR}:/data" -v "${GGUF_DIR}:/gguf:${GGUF_MOUNT_MODE:-ro}" \
    -e "MODEL=${MODEL}" -e "CONTEXT=${CONTEXT}" -e GGUF_DIR=/gguf -e VISION=no
}

case "${1:-}" in
  -h|--help|"") usage ;;
  setup)
    mkdir -p "$DATA_DIR" "$LOG_DIR"
    f="${LOG_DIR}/${NAME}-setup-$(date +%Y%m%d-%H%M%S).log"
    echo "setup ${VARIANT} ${MODEL} (log: $f)"
    # entrypoint はセットアップ後にサーバーを起動するので、setup.py を直接 --no-start で呼ぶ。
    # 生成される設定 (strata-<model>.json) はコンテナ内に書かれるため、entrypoint が読む /data/config へ写す
    tag="$(printf '%s' "$MODEL" | tr 'A-Z' 'a-z')"
    # 0.1.38 (DualGPU フォーク) の setup は GGUF の隣に完了マーカー (.done) を書くため、setup 時だけ書き込み可でマウントする
    # shellcheck disable=SC2046
    GGUF_MOUNT_MODE=rw; docker run --rm --name "${NAME}-setup" $(common_args) --entrypoint sh "$IMAGE" -c \
      ".venv/bin/python setup.py --setup --yes --no-start --family qwen --model ${MODEL} --context ${CONTEXT} \
         --vision no --data-dir /data --gguf-dir /gguf --gpus 0,1 --host 0.0.0.0 --port 8080 \
       && mkdir -p /data/config && cp -f strata-${tag}.json /data/config/" >"$f" 2>&1
    echo "setup done (exit=$?)"
    ;;
  nomtp-config)
    # MTP (投機的デコード) を切った設定を作る: --mtp / --spec-min-p とその値を取り除く。
    # --spec T (検証窓) はネイティブ (IQ) パックでは必須なので残す (--mtp が無ければ下書きは出ない)。
    # 使い方: up CONFIG=/data/config/strata-<model>-nomtp.json
    # /data/config はコンテナ内の root が作ったディレクトリなので、書き込みもコンテナ内で行う
    tag="$(printf '%s' "$MODEL" | tr 'A-Z' 'a-z')"
    src="/data/config/strata-${tag}.json"
    dst="/data/config/strata-${tag}-nomtp.json"
    docker run --rm -i -v "${DATA_DIR}:/data" --entrypoint /opt/strata/.venv/bin/python "$IMAGE" - "$src" "$dst" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
cfg = json.load(open(src))
args, out, skip = cfg["args"], [], False
for a in args:
    if skip:
        skip = False
        continue
    if a in ("--mtp", "--spec-min-p"):
        skip = True  # 値も一緒に落とす
        continue
    out.append(a)
cfg["args"] = out
json.dump(cfg, open(dst, "w"), indent=1)
print(dst, out)
PY
    ;;
  ctx-config)
    # コンテキスト長だけを変えた設定を作る: strata.sh ctx-config 1048576 → strata-<model>-ctx1048576.json
    # 学習時の 262144 を超える分は setup と同じく YaRN (--rope-scaling yarn --rope-scale 長さ/262144) を付ける
    ctx="${2:?コンテキスト長を指定してください}"
    tag="$(printf '%s' "$MODEL" | tr 'A-Z' 'a-z')"
    docker run --rm -i -v "${DATA_DIR}:/data" --entrypoint /opt/strata/.venv/bin/python "$IMAGE" - \
      "/data/config/strata-${tag}.json" "/data/config/strata-${tag}-ctx${ctx}.json" "$ctx" <<'PY'
import json, sys
src, dst, ctx = sys.argv[1], sys.argv[2], int(sys.argv[3])
cfg = json.load(open(src))
args, out, skip = cfg["args"], [], False
for a in args:
    if skip:
        skip = False
        continue
    if a in ("--max-context", "--rope-scaling", "--rope-scale"):
        skip = True
        continue
    out.append(a)
out += ["--max-context", str(ctx)]
if ctx > 262144:
    out += ["--rope-scaling", "yarn", "--rope-scale", f"{ctx / 262144:g}"]
cfg["args"] = out
json.dump(cfg, open(dst, "w"), indent=1)
print(dst, out)
PY
    ;;
  up)
    shift
    envs=()
    for kv in "$@"; do envs+=(-e "$kv"); done
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    # shellcheck disable=SC2046
    docker run -d --name "$NAME" $(common_args) -p "127.0.0.1:${PORT}:8080" "${envs[@]}" "$IMAGE" >/dev/null
    echo "started ${NAME} (${VARIANT}, ${MODEL}) on 127.0.0.1:${PORT} env=$*"
    ;;
  down)
    mkdir -p "$LOG_DIR"
    if docker inspect "$NAME" >/dev/null 2>&1; then
      f="${LOG_DIR}/${NAME}-$(date +%Y%m%d-%H%M%S).log"
      docker logs "$NAME" >"$f" 2>&1 || true
      docker stop -t 60 "$NAME" >/dev/null 2>&1 || true
      docker rm -f "$NAME" >/dev/null
      echo "stopped ${NAME} (log: $f)"
    else
      echo "${NAME} is not running"
    fi
    ;;
  logs) docker logs -f "$NAME" ;;
  *) usage; exit 2 ;;
esac

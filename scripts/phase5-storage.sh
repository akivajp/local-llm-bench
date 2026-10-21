#!/usr/bin/env bash
# フェーズ5の追加: ストレージ帯域の効果。RAM に収まらず SSD から読む DeepSeek-V4.1-Flash-1017 (Maya, 4090 のみ) で、
# NVMe 3枚の btrfs RAID0 そのままと、各 NVMe の読み込みを cgroup (docker --device-read-bps) で絞って
# SSD 1枚相当 (合計 7.2GB/s = T500 の公称の順次読み込み) にした場合を比べる。
# 注意: 再現するのは帯域だけ (SSD 1枚のときのレイテンシ・キュー深さは再現しない)。ページキャッシュは root が無いと
#       落とせないため、両条件とも直前の実行のキャッシュが残った状態から始まる (順番を入れ替えて2回ずつ測る)。
# 環境変数: PER_DEV (各 NVMe の上限、既定 2400mb)、SUFFIX (ラベルの接尾辞)、MAYA_DOCKER_ENV (エンジンの設定。
#           例: "DS4_STREAM_THREADS=8" で SSD から読むスレッドを既定の2本から増やす)、ROUNDS (既定 "a b")
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,8p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase5-storage-$(date +%Y%m%d-%H%M%S).log"
M=http://127.0.0.1:18083
PER_DEV="${PER_DEV:-2400mb}"
DEVS=(nvme0n1 nvme1n1 nvme2n1)
THROTTLE=""
for d in "${DEVS[@]}"; do THROTTLE+=" --device-read-bps /dev/${d}:${PER_DEV}"; done
MAYA_VER="$(cat "${HOME}/llm-lab/maya/project-maya/VERSION" 2>/dev/null || echo '?')"

run() {
  local label="$1" extra="$2"
  MAYA_DOCKER_ARGS="$extra" MAYA_RUN=run-maya-ds4.sh "${SCRIPTS}/maya.sh" up --gpu 0
  bench "$label" "$M" llmb-maya --config configs/slow.yaml \
    --note "Project Maya ${MAYA_VER} DeepSeek Maya-S --gpu 0, env: ${MAYA_DOCKER_ENV:-default}, storage: ${extra:-NVMe x3 RAID0 (no limit)}"
  "${SCRIPTS}/maya.sh" down
}

begin_batch
log "storage experiment: per-device limit ${PER_DEV} on ${DEVS[*]}"
S="${SUFFIX:-}"
log "engine env: ${MAYA_DOCKER_ENV:-(default)}"
for r in ${ROUNDS:-a b}; do
  # 順番の影響 (ページキャッシュの状態) を打ち消すため、ラウンドごとに順番を入れ替える
  if [[ "$r" == a ]]; then
    run "p5s-maya-ds41-4090-raid0${S}-${r}" ""
    run "p5s-maya-ds41-4090-limit7g${S}-${r}" "$THROTTLE"
  else
    run "p5s-maya-ds41-4090-limit7g${S}-${r}" "$THROTTLE"
    run "p5s-maya-ds41-4090-raid0${S}-${r}" ""
  fi
done
log "phase5-storage done"

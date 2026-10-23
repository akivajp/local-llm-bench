#!/usr/bin/env bash
# この機械の帯域 (RAM / VRAM / PCIe) を測り、Markdown で標準出力に書き出す (root 不要)。
#   - RAM: tools/membw.c (Read / Copy / Triad、OpenMP。スレッド数を変えて最大値を見る)
#   - VRAM / PCIe: tools/gpubw.cu (デバイス内コピー、pinned memory との H2D / D2H)。CUDA ビルド用コンテナで実行
#   - PCIe のリンク: GPU と上流ポートの max / current (転送中は nvidia-smi で記録)
# DIMM の規格・速度は dmidecode (要 root) でしか取れないので、別途 `sudo dmidecode -t memory` で確認する。
# usage: scripts/hw-bandwidth.sh > runs/hw-bandwidth.md
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,8p' "$0"; exit 0 ;; esac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "# 帯域の実測 ($(date '+%F %T %Z'))"
echo
echo '## RAM (tools/membw.c、配列 2GiB × 3本、10回の最速)'
echo
echo '```'
gcc -O3 -march=native -fopenmp -o "$TMP/membw" "${REPO}/tools/membw.c"
for t in 1 4 8 16 32; do OMP_NUM_THREADS=$t OMP_PROC_BIND=spread "$TMP/membw"; done
echo '```'
echo
echo '## VRAM / PCIe (tools/gpubw.cu、4GiB の転送)'
echo
echo '```'
# 転送中のリンクの世代・幅を記録する (アイドル時は省電力で Gen1 に落ちるため)
(for _ in $(seq 1 40); do
   nvidia-smi --query-gpu=index,pcie.link.gen.current,pcie.link.width.current,utilization.gpu --format=csv,noheader
   sleep 0.25
 done | sort | uniq -c) >"$TMP/link.txt" &
w=$!
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "${REPO}/tools:/src:ro" -v "$TMP:/out" \
  --entrypoint bash llmb-cuda-build -c "nvcc -O3 -o /out/gpubw /src/gpubw.cu && /out/gpubw 4096" 2>&1 | grep -E "^GPU"
wait "$w"
echo '```'
echo
echo '## PCIe のリンク (計測中の回数, GPU, 世代, 幅, 使用率)'
echo
echo '```'
cat "$TMP/link.txt"
echo
echo "# GPU と上流ポートの max / current"
for g in $(nvidia-smi --query-gpu=pci.bus_id --format=csv,noheader); do
  d=$(echo "$g" | tr 'A-Z' 'a-z' | sed 's/^00000000/0000/')
  p=$(readlink -f "/sys/bus/pci/devices/$d")
  for x in "$p" "$(dirname "$p")"; do
    [[ -f "$x/max_link_width" ]] && printf '%s  max=%s x%s  cur=%s x%s\n' "$(basename "$x")" \
      "$(cat "$x/max_link_speed")" "$(cat "$x/max_link_width")" "$(cat "$x/current_link_speed")" "$(cat "$x/current_link_width")"
  done
done
echo '```'

#!/usr/bin/env bash
# フェーズ6: Project Maya のチューニングの効果 (GLM-5.3-Flash Maya-S24、2GPU)。
#   - --calibrate の後の既定設定 (MTP で下書き) と、DFlash2 の下書きモデル (--draft dflash2) を比べる
#   - DFlash2 のライセンスは CC BY-NC-ND 4.0 (非営利のみ)。業務での利用には使えない点に注意
# 事前に scripts/maya.sh exec --calibrate と、maya-maya-s24-dflash2.json (setup --draft dflash2 の設定の控え) を用意する。
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,5p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase6-tune-$(date +%Y%m%d-%H%M%S).log"
M=http://127.0.0.1:18083
MAYA_VER="$(cat "${HOME}/llm-lab/maya/project-maya/VERSION" 2>/dev/null || echo '?')"

begin_batch
for variant in mtp dflash2; do
  cfg=maya-maya-s24.json
  [[ "$variant" == dflash2 ]] && cfg=maya-maya-s24-dflash2.json
  MAYA_CONFIG="$cfg" "${SCRIPTS}/maya.sh" up --gpus 0,1
  bench "p6-maya-glm53-s24-2gpu-${variant}" "$M" llmb-maya --note "Project Maya ${MAYA_VER} Maya-S24 --gpus 0,1, draft=${variant}, after --calibrate (engine defaults kept)"
  bench "p6-maya-glm53-s24-2gpu-${variant}-workloads" "$M" llmb-maya --config configs/workloads.yaml --note "draft=${variant}, workloads.yaml"
  "${SCRIPTS}/maya.sh" down
done
log "phase6 tune done"

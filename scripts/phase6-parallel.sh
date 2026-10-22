#!/usr/bin/env bash
# フェーズ6: 複数の要求の同時処理 (Project Maya の --parallel)。GLM-5.3-Flash Maya-S24 を --parallel 4 で起動し、
# 同時に送る数を 1 / 2 / 4 と変えて、1件あたりと全体の生成速度を測る (エージェントを複数同時に動かす場合の目安)。
# 普段の設定は変えず、--parallel 4 を書いた設定の複製 (maya-maya-s24-par4.json) を使う。
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,4p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase6-parallel-$(date +%Y%m%d-%H%M%S).log"
M=http://127.0.0.1:18083
MAYA_DIR="${HOME}/llm-lab/maya/project-maya"
MAYA_VER="$(cat "${MAYA_DIR}/VERSION" 2>/dev/null || echo '?')"
HEADROOM="MAYA_GLM_RAM_HEADROOM_GB=14 STRATA_GLM_RAM_HEADROOM_GB=14"

python3 - "${MAYA_DIR}/maya-maya-s24.json" "${MAYA_DIR}/maya-maya-s24-par4.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1]))
a = cfg["args"]
if "--parallel" in a:
    a[a.index("--parallel") + 1] = "4"
else:
    a += ["--parallel", "4"]
json.dump(cfg, open(sys.argv[2], "w"), indent=1)
PY

begin_batch
for gpus in "0,1" "0"; do
  tag=2gpu; arg=(--gpus 0,1)
  [[ "$gpus" == 0 ]] && tag=4090 && arg=(--gpu 0)
  MAYA_DOCKER_ENV="$HEADROOM" MAYA_CONFIG=maya-maya-s24-par4.json "${SCRIPTS}/maya.sh" up "${arg[@]}"
  for c in 1 2 4; do
    bench "p6-maya-glm53-s24-${tag}-par4-c${c}" "$M" llmb-maya --scenarios short,ctx8k --concurrency "$c" \
      --note "Project Maya ${MAYA_VER} Maya-S24 ${arg[*]} --parallel 4, ${c} requests at once"
  done
  "${SCRIPTS}/maya.sh" down
done
log "phase6 parallel done"

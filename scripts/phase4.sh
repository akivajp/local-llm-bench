#!/usr/bin/env bash
# フェーズ4: ローカル LLM を Anthropic 互換 API のバックエンドにして Claude Code (claude -p --bare) を動かす。
# cc-tasks/ の各課題を作業ディレクトリに複製して解かせ、終了後に pytest で成否を判定する。
#   - Strata 4090 IQ3_S (最速構成) / llama.cpp 2GPU IQ3_S
# ユーザーの Claude Code 設定には触れない: CLAUDE_CONFIG_DIR を専用ディレクトリにし、--bare でフック等を無効化する。
# 引数で構成を絞れる (例: phase4.sh strata-iq3s)。
set -euo pipefail
case "${1:-}" in -h|--help) sed -n '2,6p' "$0"; exit 0 ;; esac

source "$(dirname "$0")/lib.sh"
BATCH_LOG="${LOGS}/phase4-$(date +%Y%m%d-%H%M%S).log"
WORK="${HOME}/llm-lab/cc-work"
VENV="${HOME}/llm-lab/cc-venv"          # pytest 入りの venv (課題の実行用)
MODEL_NAME=qwen3.8-flash-next
TASK_TIMEOUT="${TASK_TIMEOUT:-1500}"     # 1課題の上限秒数
ALL=(strata-iq3s llamacpp-iq3s)
TARGETS=("$@")
[[ $# -eq 0 ]] && TARGETS=("${ALL[@]}")
want() { local t; for t in "${TARGETS[@]}"; do [[ "$t" == "$1" ]] && return 0; done; return 1; }

# 1課題を解かせる。引数: <label> <base_url> <task>
run_task() {
  local label="$1" url="$2" task="$3"
  local dir="${WORK}/${label}/${task}" out="${REPO}/runs/${label}"
  rm -rf "$dir"; mkdir -p "$dir" "$out"
  cp -r "${REPO}/cc-tasks/${task}/." "$dir/"
  rm -f "$dir/prompt.txt"
  (cd "$dir" && git init -q && git add -A && git -c user.email=bench@localhost -c user.name=bench commit -q --allow-empty -m init)
  log "claude: ${label} ${task}"
  local t0=$SECONDS rc=0
  # Claude Code の全リクエスト (背景の小型モデル用も含む) をローカルサーバーへ向ける
  (cd "$dir" && PATH="${VENV}/bin:${PATH}" \
    CLAUDE_CONFIG_DIR="${HOME}/llm-lab/cc-config" \
    ANTHROPIC_BASE_URL="$url" ANTHROPIC_API_KEY=dummy \
    ANTHROPIC_MODEL="$MODEL_NAME" ANTHROPIC_DEFAULT_HAIKU_MODEL="$MODEL_NAME" ANTHROPIC_SMALL_FAST_MODEL="$MODEL_NAME" \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 CLAUDE_CODE_MAX_OUTPUT_TOKENS=8192 \
    timeout "$TASK_TIMEOUT" claude -p --bare --model "$MODEL_NAME" --output-format json \
      --permission-mode acceptEdits \
      --allowedTools "Read" "Write" "Edit" "Glob" "Grep" "Bash(python3 -m pytest*)" "Bash(python3 *)" "Bash(pytest*)" "Bash(ls*)" "Bash(cat *)" \
      < "${REPO}/cc-tasks/${task}/prompt.txt" >"${out}/${task}.json" 2>"${out}/${task}.stderr") || rc=$?
  local wall=$((SECONDS - t0))
  # 成否はこちらで判定する (モデルの自己申告は使わない)
  local verdict
  if (cd "$dir" && PATH="${VENV}/bin:${PATH}" python3 -m pytest -q -p no:cacheprovider >"${out}/${task}.pytest" 2>&1); then
    verdict=pass
  else
    verdict=fail
  fi
  # テストコードを書き換えて通していないか (t2) も記録する
  local test_changed=no
  if [[ "$task" == t2-bugfix ]] && ! (cd "$dir" && git diff --quiet HEAD -- test_stats.py); then test_changed=yes; fi
  (cd "$dir" && git add -A && git diff --cached --stat HEAD) >"${out}/${task}.diffstat" 2>&1 || true
  (cd "$dir" && git diff --cached HEAD) >"${out}/${task}.diff" 2>&1 || true
  python3 - "$out/${task}.json" "$label" "$task" "$wall" "$rc" "$verdict" "$test_changed" >>"${REPO}/runs/phase4-results.jsonl" <<'PY'
import json, sys
path, label, task, wall, rc, verdict, test_changed = sys.argv[1:]
try:
    d = json.load(open(path))
except Exception as e:  # 途中で落ちた場合も記録だけは残す
    d = {"parse_error": str(e)}
print(json.dumps({
    "label": label, "task": task, "wall_s": int(wall), "exit": int(rc), "pytest": verdict,
    "test_file_changed": test_changed == "yes",
    "num_turns": d.get("num_turns"), "duration_ms": d.get("duration_ms"),
    "is_error": d.get("is_error"), "subtype": d.get("subtype"),
    "usage": d.get("usage"), "result_head": (d.get("result") or "")[:300],
}, ensure_ascii=False))
PY
  log "result: ${label} ${task} pytest=${verdict} wall=${wall}s exit=${rc} test_changed=${test_changed}"
}

begin_batch
mkdir -p "${HOME}/llm-lab/cc-config"

if want strata-iq3s; then
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" up GPU=0
  if (cd "$REPO" && uv run llm-bench wait --base-url http://127.0.0.1:18080 --container llmb-strata --timeout 1200); then
    for t in t1-fizzbuzz t2-bugfix; do run_task p4-cc-strata-q38-iq3s-4090 http://127.0.0.1:18080 "$t"; done
  fi
  STRATA_MODEL=IQ3_S STRATA_VARIANT=upstream "${SCRIPTS}/strata.sh" down
fi

if want llamacpp-iq3s; then
  "${SCRIPTS}/llamacpp.sh" up Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf -sm layer
  if (cd "$REPO" && uv run llm-bench wait --base-url http://127.0.0.1:18081 --container llmb-llamacpp --timeout 1200); then
    for t in t1-fizzbuzz t2-bugfix; do run_task p4-cc-llamacpp-q38-iq3s-2gpu http://127.0.0.1:18081 "$t"; done
  fi
  "${SCRIPTS}/llamacpp.sh" down
fi

log "phase4 done"

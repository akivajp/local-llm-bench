#!/usr/bin/env bash
# 成否の判定: 全テストが通り、--csv が実際に CSV を書き出し、既存のテストが変更されていないこと
set -euo pipefail
uv run pytest -q
mkdir -p /tmp/llmb-verify-$$/runs/a /tmp/llmb-verify-$$/runs/b
for l in a b; do
  printf '{"label":"%s","scenarios":[{"scenario":"short","prefill_tps_median":100.0,"decode_tps_median":10.0}],"resources":{}}' "$l" \
    > /tmp/llmb-verify-$$/runs/$l/summary.json
done
uv run llm-bench compare /tmp/llmb-verify-$$/runs/a /tmp/llmb-verify-$$/runs/b --csv /tmp/llmb-verify-$$/out.csv
test "$(wc -l < /tmp/llmb-verify-$$/out.csv)" -ge 3
head -3 /tmp/llmb-verify-$$/out.csv
git diff --quiet HEAD -- tests/test_metrics.py

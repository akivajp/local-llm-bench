# local-llm-bench

ローカル LLM 推論エンジン (llama.cpp / Strata / Ollama 等) の速度を、
OpenAI 互換 (`/v1/chat/completions`) または Anthropic 互換 (`/v1/messages`) API 越しに同じ定義で計測するツールと、
異種2GPU (RTX 4090 24GB + RTX 4000 Ada 20GB) での計測結果。

主な関心は「**VRAM に乗りきらない大きな MoE モデルを、エキスパートを RAM に逃がしながらどれだけの速度で動かせるか**」。

## 計測の定義

- prefill tok/s = 入力トークン数 / TTFT (送信から最初の生成トークンまで)
- decode tok/s = (出力トークン数 − 1) / (最初のトークンから最後のトークンまでの秒数)
- いずれもクライアント側の時刻で計算する (エンジンの自己申告値は `server_timings` に参考として残すだけ)
- トークン数は API の usage から取る
- プロンプト先頭に毎回ランダムな ID を入れ、prefix キャッシュの影響を除く
- 計測中は GPU ごとの VRAM・使用率とホスト RAM を 0.5 秒間隔で記録する

## 使い方

```sh
uv sync
uv run pytest

# サーバーの起動 (モデル読み込み) を待つ。--container を付けるとコンテナが落ちた時点で打ち切る
uv run llm-bench wait --base-url http://127.0.0.1:18081 --container llmb-llamacpp
# 計測 (設定は configs/default.yaml、コマンドライン指定が優先)
uv run llm-bench run --label my-run --base-url http://127.0.0.1:18081 --note "起動オプション等"
# Anthropic API 経由で計測
uv run llm-bench run --label my-run-anthropic --api anthropic --base-url http://127.0.0.1:18081
# 比較表 (Markdown 出力も可)
uv run llm-bench compare runs/p2-* --markdown runs/compare.md
```

結果は `runs/<label>/` に保存される:
`config.yaml` (実効設定と起動メモ)、`results.jsonl` (1リクエスト1行)、`summary.json`、
`monitor.csv` (VRAM/RAM の時系列)、`bench.log`、`startup_seconds.txt` (サーバーの起動待ち時間)。

## 設定ファイル

| ファイル | 内容 |
|---|---|
| `configs/default.yaml` | short (入力約120 → 出力512) / ctx8k (約7,800 → 256) / ctx32k (約31,500 → 128) |
| `configs/workloads.yaml` | 内容の異なる入力: 日本語の随筆 / コード生成 / 8K トークンのコード読み込み |

## 計測スクリプト (scripts/)

モデルは `~/llm-lab/gguf/` に置く前提。エンジンは Docker で起動する。

| スクリプト | 内容 |
|---|---|
| `llamacpp.sh` | llama.cpp (`ghcr.io/ggml-org/llama.cpp:server-cuda`) の起動・停止 |
| `strata.sh` | [Strata](https://github.com/Niko1221/Strata) / [Strata-DualGPU](https://github.com/Hardin22/Strata-DualGPU) の setup・起動・停止・MTP なし設定の生成 |
| `phase1.sh` | VRAM に全部乗るモデル (Qwen3.6-35B-A3B) での基準値 |
| `phase2.sh` | Qwen3.8-Flash-Next (125B MoE) のエンジン・GPU 構成の比較 (`QUANT=IQ2_XS` / `IQ3_S`) |
| `phase2-extra.sh` | 入力の内容・Anthropic API による違い |
| `phase-quality.sh` | 品質の簡易確認 (GSM8K / MMMLU 日本語、`llm-bench quality`) |
| `phase3.sh` | 他の大きな MoE を1モデルずつ「ダウンロード → 計測 → 削除」 |
| `phase4.sh` | ローカル LLM をバックエンドにした Claude Code に `cc-tasks/` の課題を解かせる |
| `collect-env.sh` | 再現条件 (ドライバ・イメージのダイジェスト・モデルのリビジョン等) を Markdown で出力 |
| `gpu-tenant.sh` | 同じ GPU を常用している別サービスのコンテナを計測中だけ止める (`scripts/local.env` で指定) |

Strata の Docker イメージは各リポジトリで `docker build -t llmb-strata:upstream --build-arg CUDA_ARCHITECTURES=89 --build-arg BUILD_VISION=0 .`
(フォークは `llmb-strata:dualgpu`) としてビルドしたもの。Linux 向けのビルド済みエンジンは配布されていない。

## 計測結果 (RTX 4090 + RTX 4000 Ada, Ryzen 9 9950X3D, 96GB RAM)

decode tok/s (短い入力 → 512 トークン生成)。いずれも VRAM 合計 44GB に乗らないモデル。

| モデル / エンジン | 4090 のみ | 2GPU |
|---|---|---|
| Qwen3.8-Flash-Next IQ3_S / **Strata** (MTP あり) | **143** | 100 |
| Qwen3.8-Flash-Next IQ3_S / Strata (MTP なし) | 100 | - |
| Qwen3.8-Flash-Next IQ3_S / llama.cpp `--fit` | 41 | 41 |
| gpt-oss-120b / llama.cpp | 34 | 39 |
| Qwen3.5-122B-A10B UD-IQ4_XS / llama.cpp | 30 | 31 |
| Nemotron 3.5 Super UD-Q3_K_XL / llama.cpp | 22 | 24 |
| DeepSeek-V4-Flash UD-IQ1_S / llama.cpp | 22 | 20 |
| GLM-5.3-Flash UD-IQ1_S / llama.cpp | 16 | 16 |
| GLM-5.3-Flash Maya-S24 / **Project Maya** (MTP) | 38 | **53** |
| DeepSeek-V4.1-Flash-1017 (748B) Maya-S / **Project Maya** (DSpark) ※ | 19 | **22** |
| DeepSeek-V4.1-Flash-1017 UD-IQ1_S / llama.cpp PR #30817 ※ | 13 | 16 |

※ RAM に収まらず SSD から読む (256 トークン生成、`configs/slow.yaml`)。フェーズ5 (Maya と DeepSeek) のストレージは
NVMe 3枚の btrfs RAID0、それ以前は NVMe 1枚 (`runs/NOTE-phase5.md`)。

詳細は `runs/compare-*.md`、品質は `runs/q-*/quality-summary.json`、Claude Code は `runs/phase4-results.jsonl`、
計測環境は `runs/env-final.md` (フェーズ3の各モデルのリビジョンは `runs/env-p3-*.md`)。

## ライセンス

MIT License. Copyright (c) 2026 Akiva Miura

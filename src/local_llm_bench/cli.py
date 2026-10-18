"""llm-bench コマンドの入口。

サブコマンド:
  run      設定ファイルのシナリオを順に流し、runs/<label>/ に結果を保存する
  wait     サーバーが応答するまで待ち、起動 (モデル読み込み) にかかった秒数を表示する
  compare  複数の runs/<label>/results.jsonl を並べて比較表を出す
"""

from __future__ import annotations

import argparse
import json
import logging
import subprocess
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

import httpx
import yaml
from rich.console import Console
from rich.logging import RichHandler
from rich.progress import (
    BarColumn,
    MofNCompleteColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TimeElapsedColumn,
)
from rich.table import Table

from .client import run_request
from .metrics import RequestResult, ScenarioSummary, summarize
from .monitor import ResourceMonitor, gpu_info, host_used_gib
from .prompts import build_prompt

console = Console()
log = logging.getLogger("llm-bench")

# 設定ファイルの値をコマンドラインで上書きできる項目 (引数名 → 設定キー)
_OVERRIDES = {
    "api": "api",
    "base_url": "base_url",
    "model": "model",
    "api_key": "api_key",
    "timeout": "timeout",
    "warmup": "warmup",
    "repeats": "repeats",
    "seed": "seed",
}


def setup_logging(log_path: Path | None) -> None:
    """コンソール (rich) とログファイルの両方に日時付きで出力する。"""
    handlers: list[logging.Handler] = [RichHandler(console=console, show_path=False)]
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        fh = logging.FileHandler(log_path, encoding="utf-8")
        fh.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
        handlers.append(fh)
    logging.basicConfig(level=logging.INFO, format="%(message)s", handlers=handlers, force=True)
    # httpx はリクエストごとに INFO を出すので抑える
    logging.getLogger("httpx").setLevel(logging.WARNING)


def load_config(args: argparse.Namespace) -> dict[str, Any]:
    """YAML を読み、コマンドライン引数で上書きした実効設定を返す。"""
    with open(args.config, encoding="utf-8") as f:
        cfg: dict[str, Any] = yaml.safe_load(f) or {}
    for arg_name, key in _OVERRIDES.items():
        v = getattr(args, arg_name, None)
        if v is not None:
            cfg[key] = v
    if args.extra_body:
        cfg["extra_body"] = {**(cfg.get("extra_body") or {}), **json.loads(args.extra_body)}
    if args.scenarios:
        wanted = [s.strip() for s in args.scenarios.split(",") if s.strip()]
        known = {s["name"]: s for s in cfg["scenarios"]}
        missing = [w for w in wanted if w not in known]
        if missing:
            raise SystemExit(f"未知のシナリオ: {missing} (定義済み: {list(known)})")
        cfg["scenarios"] = [known[w] for w in wanted]
    if args.max_tokens is not None:
        for s in cfg["scenarios"]:
            s["max_tokens"] = args.max_tokens
    return cfg


def cmd_run(args: argparse.Namespace) -> int:
    """シナリオを実行して結果を保存する。"""
    cfg = load_config(args)
    out_dir = Path(args.out_dir) / args.label
    out_dir.mkdir(parents=True, exist_ok=True)
    setup_logging(Path(args.log) if args.log else out_dir / "bench.log")

    # 実効設定を表示・保存する (再現用)
    cfg_to_save = {**cfg, "label": args.label, "note": args.note, "started_at": datetime.now().isoformat()}
    (out_dir / "config.yaml").write_text(
        yaml.safe_dump(cfg_to_save, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
    log.info("label=%s api=%s base_url=%s model=%s", args.label, cfg["api"], cfg["base_url"], cfg["model"])
    log.info(
        "warmup=%s repeats=%s scenarios=%s extra_body=%s",
        cfg["warmup"],
        cfg["repeats"],
        [(s["name"], s["prompt_tokens"], s["max_tokens"]) for s in cfg["scenarios"]],
        cfg.get("extra_body"),
    )
    for line in gpu_info():
        log.info("GPU: %s", line)
    log.info("host RAM used: %.1f GiB", host_used_gib())
    if args.note:
        log.info("note: %s", args.note)

    monitor = ResourceMonitor(interval=cfg.get("monitor_interval", 0.5), csv_path=out_dir / "monitor.csv")
    monitor.start()
    results: list[RequestResult] = []
    jsonl = (out_dir / "results.jsonl").open("a", encoding="utf-8")
    plan = [(s, i, i < cfg["warmup"]) for s in cfg["scenarios"] for i in range(cfg["warmup"] + cfg["repeats"])]

    try:
        with Progress(
            SpinnerColumn(),
            TextColumn("[bold]{task.description}"),
            BarColumn(),
            MofNCompleteColumn(),
            TextColumn("{task.fields[info]}"),
            TimeElapsedColumn(),
            console=console,
        ) as progress:
            overall = progress.add_task("全体", total=len(plan), info="")
            for scen, idx, is_warmup in plan:
                tag = "warmup" if is_warmup else f"#{idx - cfg['warmup'] + 1}"
                req_task = progress.add_task(
                    f"{scen['name']} {tag}", total=scen["max_tokens"], info="prefill 中…"
                )
                t_start = time.perf_counter()

                def on_token(n: int, _task: int = req_task, _t0: float = t_start) -> None:
                    """受信チャンク数で進捗バーを進める。"""
                    progress.update(_task, completed=n, info=f"{n} chunk / {time.perf_counter() - _t0:.1f}s")

                # シナリオごとに指示文・詰め物ファイルを上書きできる
                prompt = build_prompt(
                    scen["prompt_tokens"],
                    scen.get("instruction", cfg["instruction"]),
                    nonce=uuid.uuid4().hex,
                    seed=cfg["seed"],
                    filler_file=scen.get("filler_file"),
                )
                r = run_request(
                    api=cfg["api"],
                    base_url=cfg["base_url"],
                    model=cfg["model"],
                    prompt=prompt,
                    max_tokens=scen["max_tokens"],
                    scenario=scen["name"],
                    repeat=idx - cfg["warmup"],
                    api_key=cfg["api_key"],
                    timeout=cfg["timeout"],
                    extra_body=cfg.get("extra_body") or None,
                    on_token=on_token,
                )
                progress.remove_task(req_task)
                rec = r.to_record()
                rec["warmup"] = is_warmup
                jsonl.write(json.dumps(rec, ensure_ascii=False) + "\n")
                jsonl.flush()
                if r.error:
                    log.error("%s %s: %s", scen["name"], tag, r.error)
                else:
                    log.info(
                        "%s %s: in=%s out=%s ttft=%.2fs prefill=%s decode=%s finish=%s",
                        scen["name"],
                        tag,
                        r.prompt_tokens,
                        r.completion_tokens,
                        r.ttft or -1,
                        _fmt(r.prefill_tps),
                        _fmt(r.decode_tps),
                        r.finish_reason,
                    )
                if not is_warmup:
                    results.append(r)
                progress.advance(overall)
                if r.error and args.stop_on_error:
                    break
    finally:
        monitor.stop()
        jsonl.close()

    summaries = summarize(results)
    peaks = monitor.peaks()
    (out_dir / "summary.json").write_text(
        json.dumps(
            {"label": args.label, "scenarios": [s.__dict__ for s in summaries], "resources": peaks},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    print_summary(args.label, summaries, peaks)
    log.info("結果: %s", out_dir)
    return 0 if all(s.n_err == 0 for s in summaries) else 1


def _fmt(v: float | None, digits: int = 1) -> str:
    """None を '-' にして数値を整形する。"""
    return "-" if v is None else f"{v:.{digits}f}"


def print_summary(label: str, summaries: list[ScenarioSummary], peaks: dict[str, float]) -> None:
    """1回分の結果をテーブル表示する。"""
    table = Table(title=f"{label}")
    for col in ("scenario", "ok/err", "in tok", "out tok", "TTFT s", "prefill tok/s", "decode tok/s"):
        table.add_column(col, justify="right" if col != "scenario" else "left")
    for s in summaries:
        table.add_row(
            s.scenario,
            f"{s.n_ok}/{s.n_err}",
            _fmt(s.prompt_tokens, 0),
            _fmt(s.completion_tokens, 0),
            _fmt(s.ttft_median, 2),
            f"[cyan]{_fmt(s.prefill_tps_median)}[/]",
            f"[green]{_fmt(s.decode_tps_median)}[/]",
        )
    console.print(table)
    if peaks:
        console.print(
            "peak: "
            + ", ".join(f"{k}={v:.0f}" if "mib" in k else f"{k}={v:.1f}" for k, v in peaks.items())
        )


def cmd_wait(args: argparse.Namespace) -> int:
    """サーバーが応答するまで待つ。起動時間の計測にも使う。"""
    setup_logging(Path(args.log) if args.log else None)
    t0 = time.perf_counter()
    deadline = t0 + args.timeout
    paths = [p.strip() for p in args.paths.split(",")]
    while time.perf_counter() < deadline:
        if args.container and not _container_running(args.container):
            log.error("コンテナ %s が停止しています (起動失敗)。docker logs を確認してください", args.container)
            return 2
        for p in paths:
            try:
                r = httpx.get(args.base_url.rstrip("/") + p, timeout=5)
                if r.status_code == 200:
                    log.info("ready: %s%s (%.1fs)", args.base_url, p, time.perf_counter() - t0)
                    return 0
            except httpx.HTTPError:
                pass
        time.sleep(args.interval)
        elapsed = time.perf_counter() - t0
        if int(elapsed) % 30 < args.interval:
            log.info("待機中… %.0fs (host RAM used %.1f GiB)", elapsed, host_used_gib())
    log.error("timeout: %s が %ss 以内に応答しませんでした", args.base_url, args.timeout)
    return 1


def cmd_quality_fetch(args: argparse.Namespace) -> int:
    """品質評価用の問題集を取得して data/quality/ に保存する。"""
    from .quality import fetch_set

    setup_logging(None)
    for name, n in (("gsm8k", args.n_gsm8k), ("mmmlu-ja", args.n_mmmlu)):
        out = Path(args.data_dir) / f"{name}-{n}.jsonl"
        if out.exists() and not args.force:
            log.info("%s: 取得済み (%s)。取り直すには --force", name, out)
            continue
        items = fetch_set(name, n, out)
        log.info("%s: %d 問 → %s", name, len(items), out)
    return 0


def cmd_quality(args: argparse.Namespace) -> int:
    """問題集を順に解かせて正答率を出す。"""
    from .quality import extract_answer, is_correct, load_set

    out_dir = Path(args.out_dir) / args.label
    out_dir.mkdir(parents=True, exist_ok=True)
    setup_logging(Path(args.log) if args.log else out_dir / "quality.log")
    extra = json.loads(args.extra_body) if args.extra_body else None
    items = [it for p in args.sets for it in load_set(Path(p))]
    log.info("label=%s api=%s base_url=%s 問題数=%d max_tokens=%d extra_body=%s note=%s",
             args.label, args.api, args.base_url, len(items), args.max_tokens, extra, args.note)
    (out_dir / "quality-config.yaml").write_text(
        yaml.safe_dump({**vars(args), "func": None, "started_at": datetime.now().isoformat()},
                       allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )
    stats: dict[str, dict[str, float]] = {}
    with (out_dir / "quality.jsonl").open("w", encoding="utf-8") as f, Progress(
        SpinnerColumn(), TextColumn("[bold]{task.description}"), BarColumn(), MofNCompleteColumn(),
        TextColumn("{task.fields[info]}"), TimeElapsedColumn(), console=console,
    ) as progress:
        task = progress.add_task("品質評価", total=len(items), info="")
        for it in items:
            r = run_request(
                api=args.api, base_url=args.base_url, model=args.model, prompt=it["prompt"],
                max_tokens=args.max_tokens, scenario=it["set"], repeat=int(it["id"]),
                timeout=args.timeout, extra_body=extra, keep_content=True,
            )
            content = r.extra.get("content", "")
            pred = extract_answer(it["set"], content) if not r.error else None
            ok = is_correct(it["set"], pred, it["answer"])
            st = stats.setdefault(it["set"], {"n": 0, "ok": 0, "no_answer": 0, "truncated": 0, "tokens": 0})
            st["n"] += 1
            st["ok"] += int(ok)
            st["no_answer"] += int(pred is None)
            st["truncated"] += int(r.finish_reason in ("length", "max_tokens"))
            st["tokens"] += r.completion_tokens or 0
            rec = {**it, "pred": pred, "correct": ok, "finish_reason": r.finish_reason, "error": r.error,
                   "completion_tokens": r.completion_tokens, "decode_tps": r.decode_tps,
                   "reasoning_chars": r.extra.get("reasoning_chars"), "content": content}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
            f.flush()
            acc = " ".join(f"{k}={v['ok']:.0f}/{v['n']:.0f}" for k, v in stats.items())
            progress.update(task, advance=1, info=acc)
            if r.error:
                log.error("%s #%s: %s", it["set"], it["id"], r.error)

    table = Table(title=f"{args.label} 品質")
    for col in ("set", "正答", "正答率", "答え無し", "打ち切り", "平均出力 tok"):
        table.add_column(col, justify="right" if col != "set" else "left")
    summary = {}
    for k, v in stats.items():
        summary[k] = {**v, "accuracy": v["ok"] / v["n"] if v["n"] else None}
        table.add_row(k, f"{v['ok']:.0f}/{v['n']:.0f}", f"{100 * v['ok'] / v['n']:.1f}%",
                      f"{v['no_answer']:.0f}", f"{v['truncated']:.0f}", f"{v['tokens'] / v['n']:.0f}")
    console.print(table)
    (out_dir / "quality-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    log.info("結果: %s", out_dir)
    return 0


def _container_running(name: str) -> bool:
    """Docker コンテナが実行中かどうかを返す (存在しなければ False)。"""
    try:
        out = subprocess.run(
            ["docker", "inspect", "-f", "{{.State.Running}}", name],
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.TimeoutExpired):
        return True  # 判定できないときは待機を続ける
    return out.returncode == 0 and out.stdout.strip() == "true"


def cmd_compare(args: argparse.Namespace) -> int:
    """複数ラベルの summary.json を並べて表示する。"""
    rows: list[tuple[str, dict[str, Any]]] = []
    for d in args.run_dirs:
        p = Path(d) / "summary.json"
        if not p.exists():
            console.print(f"[yellow]skip: {p} がありません[/]")
            continue
        rows.append((Path(d).name, json.loads(p.read_text(encoding="utf-8"))))
    scen_names: list[str] = []
    for _, s in rows:
        for sc in s["scenarios"]:
            if sc["scenario"] not in scen_names:
                scen_names.append(sc["scenario"])

    table = Table(title="比較 (中央値, tok/s)")
    table.add_column("label")
    for name in scen_names:
        table.add_column(f"{name}\nprefill", justify="right")
        table.add_column(f"{name}\ndecode", justify="right")
    table.add_column("VRAM peak MiB", justify="right")
    table.add_column("RAM peak GiB", justify="right")
    md = ["| label | " + " | ".join(f"{n} prefill | {n} decode" for n in scen_names) + " | VRAM peak (MiB) | RAM peak (GiB) |"]
    md.append("|" + "---|" * (1 + 2 * len(scen_names) + 2))
    for label, s in rows:
        by = {sc["scenario"]: sc for sc in s["scenarios"]}
        cells: list[str] = []
        for name in scen_names:
            sc = by.get(name) or {}
            cells += [_fmt(sc.get("prefill_tps_median")), _fmt(sc.get("decode_tps_median"))]
        res = s.get("resources") or {}
        vram = " / ".join(f"{res[k]:.0f}" for k in sorted(res) if k.endswith("_mem_peak_mib"))
        ram = _fmt(res.get("host_used_peak_gib"))
        table.add_row(label, *cells, vram, ram)
        md.append(f"| {label} | " + " | ".join(cells) + f" | {vram} | {ram} |")
    console.print(table)
    if args.markdown:
        Path(args.markdown).write_text("\n".join(md) + "\n", encoding="utf-8")
        console.print(f"Markdown: {args.markdown}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    """引数パーサーを組み立てる。"""
    p = argparse.ArgumentParser(prog="llm-bench", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="シナリオを実行して計測する")
    r.add_argument("--config", default="configs/default.yaml", help="設定 YAML (既定: %(default)s)")
    r.add_argument("--label", required=True, help="結果の保存名 (runs/<label>/)")
    r.add_argument("--note", default="", help="エンジン・量子化・起動オプション等のメモ (config.yaml に保存)")
    r.add_argument("--out-dir", default="runs", help="結果の親ディレクトリ (既定: %(default)s)")
    r.add_argument("--log", help="ログファイル (既定: runs/<label>/bench.log)")
    r.add_argument("--api", choices=["openai", "anthropic"])
    r.add_argument("--base-url")
    r.add_argument("--model")
    r.add_argument("--api-key")
    r.add_argument("--timeout", type=float)
    r.add_argument("--warmup", type=int)
    r.add_argument("--repeats", type=int)
    r.add_argument("--seed", type=int)
    r.add_argument("--scenarios", help="実行するシナリオ名をカンマ区切りで (例: short,ctx8k)")
    r.add_argument("--max-tokens", type=int, help="全シナリオの生成上限を上書き")
    r.add_argument("--extra-body", help='ボディに足す JSON (例: \'{"chat_template_kwargs":{"enable_thinking":false}}\')')
    r.add_argument("--stop-on-error", action="store_true", help="エラーが出たら残りを中止する")
    r.set_defaults(func=cmd_run)

    w = sub.add_parser("wait", help="サーバーの起動を待つ")
    w.add_argument("--base-url", default="http://127.0.0.1:8080")
    w.add_argument("--paths", default="/health,/v1/models", help="確認するパス (カンマ区切り、どれか1つが 200 なら完了)")
    w.add_argument("--timeout", type=float, default=1800)
    w.add_argument("--interval", type=float, default=2.0)
    w.add_argument("--log", help="ログファイル")
    w.add_argument("--container", help="監視する Docker コンテナ名 (停止したら即座に失敗で終了)")
    w.set_defaults(func=cmd_wait)

    qf = sub.add_parser("quality-fetch", help="品質評価用の問題集を取得する (GSM8K / MMMLU 日本語)")
    qf.add_argument("--data-dir", default="data/quality")
    qf.add_argument("--n-gsm8k", type=int, default=30)
    qf.add_argument("--n-mmmlu", type=int, default=40)
    qf.add_argument("--force", action="store_true", help="取得済みでも取り直す")
    qf.set_defaults(func=cmd_quality_fetch)

    q = sub.add_parser("quality", help="問題集を解かせて正答率を出す")
    q.add_argument("--label", required=True, help="結果の保存名 (runs/<label>/quality.jsonl)")
    q.add_argument("--sets", nargs="+", default=["data/quality/gsm8k-30.jsonl", "data/quality/mmmlu-ja-40.jsonl"])
    q.add_argument("--api", choices=["openai", "anthropic"], default="openai")
    q.add_argument("--base-url", default="http://127.0.0.1:8080")
    q.add_argument("--model", default="default")
    q.add_argument("--max-tokens", type=int, default=6144)
    q.add_argument("--timeout", type=float, default=1800)
    q.add_argument("--extra-body", help="ボディに足す JSON")
    q.add_argument("--note", default="")
    q.add_argument("--out-dir", default="runs")
    q.add_argument("--log", help="ログファイル (既定: runs/<label>/quality.log)")
    q.set_defaults(func=cmd_quality)

    c = sub.add_parser("compare", help="複数の結果を比較表にする")
    c.add_argument("run_dirs", nargs="+", help="runs/<label> ディレクトリ")
    c.add_argument("--markdown", help="Markdown 表の出力先")
    c.set_defaults(func=cmd_compare)
    return p


def main(argv: list[str] | None = None) -> int:
    """コマンドラインの入口。"""
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

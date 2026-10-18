"""量子化・エンジンの違いによる出力品質の差を、正解のある小さな問題集で比べる。

- GSM8K (英語の算数、数値で答える) と MMMLU の日本語版 (JA_JP、4択) から等間隔に抜き出す。
- 問題は HF の datasets-server API で取得し、data/quality/*.jsonl に保存して使い回す (再現用)。
- 本文 (思考部分を除く) の「答え: X」から解答を取り出して採点する。

速度計測ではないので、少数の問題での「明らかな劣化が無いか」の確認に留まる (統計的な差は言えない)。
"""

from __future__ import annotations

import csv
import io
import json
import re
import time
from pathlib import Path
from typing import Any

import httpx

DATASETS_SERVER = "https://datasets-server.huggingface.co/rows"

# 問題集の定義: (名前, HF データセット, config, split, 全件数, 抜き出す件数)
SETS: dict[str, dict[str, Any]] = {
    "gsm8k": {"dataset": "openai/gsm8k", "config": "main", "split": "test", "total": 1319},
    "mmmlu-ja": {
        "dataset": "openai/MMMLU", "config": "JA_JP", "split": "test", "total": 14042,
        "csv": "https://huggingface.co/datasets/openai/MMMLU/resolve/main/test/mmlu_JA-JP.csv",
    },
}

PROMPT_GSM8K = (
    "次の算数の問題を解いてください。最後の行に「答え: <数値>」の形式で、数値だけを書いてください。\n\n{q}"
)
PROMPT_MMMLU = (
    "次の問題に答えてください。選択肢から1つ選び、最後の行に「答え: <A/B/C/D>」の形式で書いてください。\n\n"
    "{q}\n\nA. {a}\nB. {b}\nC. {c}\nD. {d}"
)


def fetch_set(name: str, n: int, out_path: Path) -> list[dict[str, Any]]:
    """問題集から n 件を等間隔に取得して JSONL に保存し、その内容を返す。"""
    spec = SETS[name]
    stride = spec["total"] // n
    items: list[dict[str, Any]] = []
    if "csv" in spec:
        # CSV が置かれているものは1回のダウンロードで済ませる (datasets-server のレート制限を避ける)
        rows = _download_csv(spec["csv"])
        items = [_normalize(name, i * stride, rows[i * stride]) for i in range(n)]
        _write_jsonl(out_path, items)
        return items
    with httpx.Client(timeout=60) as client:
        for i in range(n):
            offset = i * stride
            params = {
                "dataset": spec["dataset"],
                "config": spec["config"],
                "split": spec["split"],
                "offset": offset,
                "length": 1,
            }
            # datasets-server はときどき 502 を返すので数回やり直す
            for attempt in range(5):
                r = client.get(DATASETS_SERVER, params=params)
                if r.status_code < 500:
                    break
                time.sleep(2 * (attempt + 1))
            r.raise_for_status()
            row = r.json()["rows"][0]["row"]
            items.append(_normalize(name, offset, row))
    _write_jsonl(out_path, items)
    return items


def _write_jsonl(out_path: Path, items: list[dict[str, Any]]) -> None:
    """問題集を JSONL で保存する。"""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8") as f:
        for it in items:
            f.write(json.dumps(it, ensure_ascii=False) + "\n")


def _download_csv(url: str) -> list[dict[str, str]]:
    """CSV をダウンロードして行の辞書のリストで返す (8MB 程度なのでメモリに載せてよい)。"""
    r = httpx.get(url, timeout=120, follow_redirects=True)
    r.raise_for_status()
    return list(csv.DictReader(io.StringIO(r.content.decode("utf-8-sig"))))


def _normalize(name: str, offset: int, row: dict[str, Any]) -> dict[str, Any]:
    """データセットの行を {id, prompt, answer} に揃える。"""
    if name == "gsm8k":
        # 正解は "#### 72" の形で末尾にある
        ans = row["answer"].split("####")[-1].strip().replace(",", "")
        return {"set": name, "id": offset, "prompt": PROMPT_GSM8K.format(q=row["question"]), "answer": ans}
    if name == "mmmlu-ja":
        prompt = PROMPT_MMMLU.format(q=row["Question"], a=row["A"], b=row["B"], c=row["C"], d=row["D"])
        return {"set": name, "id": offset, "prompt": prompt, "answer": row["Answer"].strip(), "subject": row["Subject"]}
    raise ValueError(name)


def load_set(path: Path) -> list[dict[str, Any]]:
    """保存済みの問題集 (JSONL) を読む。"""
    with path.open(encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


_ANS_RE = re.compile(r"答え\s*[:：]\s*\**\s*([^\n*]+)")


def extract_answer(set_name: str, text: str) -> str | None:
    """本文から解答を取り出す。見つからなければ None。"""
    m = _ANS_RE.findall(text)
    tail = m[-1] if m else text[-200:]
    if set_name == "gsm8k":
        nums = re.findall(r"-?\d[\d,]*(?:\.\d+)?", tail)
        if not nums:
            return None
        v = nums[-1].replace(",", "")
        # 72.0 のような表記は整数に揃える
        if re.fullmatch(r"-?\d+\.0+", v):
            v = v.split(".")[0]
        return v
    # 4択: 全角も含めて A-D を探す
    tail = tail.translate(str.maketrans("ＡＢＣＤ", "ABCD"))
    letters = re.findall(r"\b([ABCD])\b", tail) or re.findall(r"([ABCD])", tail)
    return letters[0] if m and letters else (letters[-1] if letters else None)


def is_correct(set_name: str, pred: str | None, gold: str) -> bool:
    """解答と正解が一致するか。"""
    if pred is None:
        return False
    if set_name == "gsm8k":
        try:
            return float(pred) == float(gold)
        except ValueError:
            return False
    return pred.upper() == gold.upper()

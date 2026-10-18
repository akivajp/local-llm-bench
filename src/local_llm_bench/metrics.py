"""1リクエスト分の計測値から prefill / decode 速度を求める。

クライアント側の時刻だけで計算するため、エンジンの種類によらず同じ定義で比較できる。
- prefill tok/s = 入力トークン数 / TTFT (送信から最初の生成トークン受信まで)
- decode  tok/s = (出力トークン数 - 1) / (最初のトークン受信から最後のトークン受信まで)
  最初の1トークンは prefill 側の時間に含まれるため、decode からは除く。
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from statistics import mean, median
from typing import Any


@dataclass
class RequestResult:
    """1リクエストの計測結果。"""

    scenario: str
    repeat: int
    prompt_tokens: int | None
    completion_tokens: int | None
    t_send: float
    t_first: float | None
    t_last: float | None
    finish_reason: str | None = None
    error: str | None = None
    # エンジンが独自に返した計測値 (llama.cpp の timings 等) をそのまま残す
    server_timings: dict[str, Any] | None = None
    text_head: str = ""
    extra: dict[str, Any] = field(default_factory=dict)

    @property
    def ttft(self) -> float | None:
        """送信から最初の生成トークンまでの秒数。"""
        if self.t_first is None:
            return None
        return self.t_first - self.t_send

    @property
    def prefill_tps(self) -> float | None:
        """入力の処理速度 (tok/s)。"""
        ttft = self.ttft
        if ttft is None or ttft <= 0 or not self.prompt_tokens:
            return None
        return self.prompt_tokens / ttft

    @property
    def decode_tps(self) -> float | None:
        """生成速度 (tok/s)。出力が2トークン未満なら算出しない。"""
        if self.t_first is None or self.t_last is None or not self.completion_tokens:
            return None
        if self.completion_tokens < 2:
            return None
        span = self.t_last - self.t_first
        if span <= 0:
            return None
        return (self.completion_tokens - 1) / span

    def to_record(self) -> dict[str, Any]:
        """JSONL に書き出すための辞書を返す (派生値も含める)。"""
        rec = asdict(self)
        rec["ttft"] = self.ttft
        rec["prefill_tps"] = self.prefill_tps
        rec["decode_tps"] = self.decode_tps
        return rec


@dataclass
class ScenarioSummary:
    """シナリオ単位の集計値。"""

    scenario: str
    n_ok: int
    n_err: int
    prompt_tokens: float | None
    completion_tokens: float | None
    ttft_median: float | None
    prefill_tps_median: float | None
    decode_tps_median: float | None
    decode_tps_mean: float | None


def _med(values: list[float]) -> float | None:
    """空リストなら None を返す中央値。"""
    return median(values) if values else None


def summarize(results: list[RequestResult]) -> list[ScenarioSummary]:
    """シナリオごとに中央値などを集計する (出現順を保つ)。"""
    order: list[str] = []
    groups: dict[str, list[RequestResult]] = {}
    for r in results:
        if r.scenario not in groups:
            order.append(r.scenario)
            groups[r.scenario] = []
        groups[r.scenario].append(r)

    out: list[ScenarioSummary] = []
    for name in order:
        rs = groups[name]
        ok = [r for r in rs if r.error is None]
        prefill = [v for r in ok if (v := r.prefill_tps) is not None]
        decode = [v for r in ok if (v := r.decode_tps) is not None]
        ttfts = [v for r in ok if (v := r.ttft) is not None]
        ptoks = [float(r.prompt_tokens) for r in ok if r.prompt_tokens]
        ctoks = [float(r.completion_tokens) for r in ok if r.completion_tokens]
        out.append(
            ScenarioSummary(
                scenario=name,
                n_ok=len(ok),
                n_err=len(rs) - len(ok),
                prompt_tokens=mean(ptoks) if ptoks else None,
                completion_tokens=mean(ctoks) if ctoks else None,
                ttft_median=_med(ttfts),
                prefill_tps_median=_med(prefill),
                decode_tps_median=_med(decode),
                decode_tps_mean=mean(decode) if decode else None,
            )
        )
    return out

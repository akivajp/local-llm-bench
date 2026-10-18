"""OpenAI 互換 / Anthropic 互換 API へのストリーミングリクエストと時刻計測。

SSE を自前で読み、最初の生成トークン (本文・思考のどちらでも) を受け取った時刻と、
最後の生成トークンを受け取った時刻を記録する。トークン数は usage から取り、
usage を返さないエンジンではチャンク数で代用して extra["tokens_estimated"] を立てる。
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable, Iterator
from typing import Any

import httpx

from .metrics import RequestResult

# 進捗表示用のコールバック: (これまでに受け取った生成チャンク数) を受け取る
TokenCallback = Callable[[int], None]


def _iter_sse(resp: httpx.Response) -> Iterator[tuple[str | None, str]]:
    """SSE の (event 名, data 文字列) を順に返す。"""
    event: str | None = None
    data_lines: list[str] = []
    for line in resp.iter_lines():
        if line == "":
            # 空行でイベントが確定する
            if data_lines:
                yield event, "\n".join(data_lines)
            event, data_lines = None, []
            continue
        if line.startswith(":"):
            continue  # コメント行 (keep-alive 等)
        if line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data_lines.append(line[5:].lstrip())
    if data_lines:
        yield event, "\n".join(data_lines)


def _headers(api: str, api_key: str) -> dict[str, str]:
    """API 種別に応じた認証ヘッダーを返す。"""
    if api == "anthropic":
        return {"x-api-key": api_key, "anthropic-version": "2023-06-01"}
    return {"Authorization": f"Bearer {api_key}"}


def run_request(
    *,
    api: str,
    base_url: str,
    model: str,
    prompt: str,
    max_tokens: int,
    scenario: str,
    repeat: int,
    api_key: str = "dummy",
    timeout: float = 1800.0,
    extra_body: dict[str, Any] | None = None,
    on_token: TokenCallback | None = None,
) -> RequestResult:
    """1リクエストを送り、計測結果を返す。例外は握りつぶさず error 欄に入れて返す。

    Args:
        api: "openai" (/v1/chat/completions) または "anthropic" (/v1/messages)。
        base_url: 例 "http://127.0.0.1:8080" (末尾の /v1 は付けない)。
        model: リクエストに入れるモデル名。
        prompt: user メッセージの本文。
        max_tokens: 生成上限。
        scenario: 結果に記録するシナリオ名。
        repeat: 結果に記録する繰り返し番号。
        api_key: 認証キー (ローカルエンジンでは大抵任意の値でよい)。
        timeout: 読み取りタイムアウト秒。
        extra_body: エンジン固有のパラメータ (chat_template_kwargs 等) をボディに足す。
        on_token: 生成チャンクを受け取るたびに呼ばれるコールバック。
    """
    base = base_url.rstrip("/")
    body: dict[str, Any] = {
        "model": model,
        "max_tokens": max_tokens,
        "stream": True,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0.0,
    }
    if api == "openai":
        url = f"{base}/v1/chat/completions"
        body["stream_options"] = {"include_usage": True}
    elif api == "anthropic":
        url = f"{base}/v1/messages"
    else:
        raise ValueError(f"unknown api: {api}")
    if extra_body:
        body.update(extra_body)

    result = RequestResult(
        scenario=scenario,
        repeat=repeat,
        prompt_tokens=None,
        completion_tokens=None,
        t_send=time.perf_counter(),
        t_first=None,
        t_last=None,
    )
    n_chunks = 0
    text: list[str] = []

    def mark_token(piece: str) -> None:
        """生成チャンク受信時の共通処理 (時刻記録と進捗通知)。"""
        nonlocal n_chunks
        now = time.perf_counter()
        if result.t_first is None:
            result.t_first = now
        result.t_last = now
        n_chunks += 1
        if sum(len(t) for t in text) < 400:
            text.append(piece)
        if on_token is not None:
            on_token(n_chunks)

    try:
        t = httpx.Timeout(timeout, connect=30.0)
        with httpx.Client(timeout=t) as client:
            result.t_send = time.perf_counter()
            with client.stream("POST", url, json=body, headers=_headers(api, api_key)) as resp:
                if resp.status_code != 200:
                    resp.read()
                    result.error = f"HTTP {resp.status_code}: {resp.text[:500]}"
                    return result
                if api == "openai":
                    _consume_openai(resp, result, mark_token)
                else:
                    _consume_anthropic(resp, result, mark_token)
    except Exception as e:  # noqa: BLE001 - 計測を止めずに記録する
        result.error = f"{type(e).__name__}: {e}"
        return result

    if result.completion_tokens is None and n_chunks:
        # usage を返さないエンジン向けの代用 (1チャンク ≈ 1トークン)
        result.completion_tokens = n_chunks
        result.extra["tokens_estimated"] = True
    result.extra["n_chunks"] = n_chunks
    result.text_head = "".join(text)[:400]
    return result


def _consume_openai(
    resp: httpx.Response, result: RequestResult, mark_token: Callable[[str], None]
) -> None:
    """OpenAI 互換のストリームを読み、結果に反映する。"""
    for _event, data in _iter_sse(resp):
        if data == "[DONE]":
            break
        chunk = json.loads(data)
        for choice in chunk.get("choices") or []:
            delta = choice.get("delta") or {}
            # 本文のほか、思考の文 (reasoning_content / reasoning) も生成トークンとして数える
            for key in ("content", "reasoning_content", "reasoning"):
                piece = delta.get(key)
                if piece:
                    mark_token(piece)
            if choice.get("finish_reason"):
                result.finish_reason = choice["finish_reason"]
        usage = chunk.get("usage")
        if usage:
            result.prompt_tokens = usage.get("prompt_tokens", result.prompt_tokens)
            result.completion_tokens = usage.get("completion_tokens", result.completion_tokens)
        if chunk.get("timings"):
            result.server_timings = chunk["timings"]


def _consume_anthropic(
    resp: httpx.Response, result: RequestResult, mark_token: Callable[[str], None]
) -> None:
    """Anthropic Messages のストリームを読み、結果に反映する。"""
    for event, data in _iter_sse(resp):
        msg = json.loads(data)
        kind = msg.get("type") or event
        if kind == "message_start":
            usage = (msg.get("message") or {}).get("usage") or {}
            if usage.get("input_tokens") is not None:
                result.prompt_tokens = usage["input_tokens"]
        elif kind == "content_block_delta":
            delta = msg.get("delta") or {}
            piece = delta.get("text") or delta.get("thinking")
            if piece:
                mark_token(piece)
        elif kind == "message_delta":
            usage = msg.get("usage") or {}
            if usage.get("output_tokens") is not None:
                result.completion_tokens = usage["output_tokens"]
            # 一部のエンジンは input_tokens を最後に返す
            if usage.get("input_tokens"):
                result.prompt_tokens = usage["input_tokens"]
            stop = (msg.get("delta") or {}).get("stop_reason")
            if stop:
                result.finish_reason = stop
        elif kind == "error":
            result.error = f"stream error: {json.dumps(msg, ensure_ascii=False)[:500]}"
        elif kind == "message_stop":
            break

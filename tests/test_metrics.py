"""速度計算と SSE 解析のテスト。"""

from __future__ import annotations

import httpx

from local_llm_bench.client import run_request
from local_llm_bench.metrics import RequestResult, summarize
from local_llm_bench.prompts import build_prompt


def _r(scenario: str, pt: int, ct: int, send: float, first: float, last: float) -> RequestResult:
    return RequestResult(scenario, 0, pt, ct, send, first, last)


def test_prefill_and_decode_tps() -> None:
    # 1000 トークンを 2 秒で処理、残り 100 トークンを 4 秒で生成
    r = _r("s", 1000, 101, 10.0, 12.0, 16.0)
    assert r.ttft == 2.0
    assert r.prefill_tps == 500.0
    assert r.decode_tps == 25.0


def test_decode_none_when_too_short() -> None:
    assert _r("s", 10, 1, 0.0, 1.0, 1.0).decode_tps is None
    assert RequestResult("s", 0, None, None, 0.0, None, None).prefill_tps is None


def test_summarize_excludes_errors_and_keeps_order() -> None:
    rs = [
        _r("b", 100, 11, 0, 1, 2),
        _r("a", 100, 11, 0, 1, 3),
        _r("b", 100, 11, 0, 2, 3),
    ]
    rs.append(RequestResult("a", 1, None, None, 0, None, None, error="boom"))
    s = summarize(rs)
    assert [x.scenario for x in s] == ["b", "a"]
    assert s[0].n_ok == 2 and s[0].decode_tps_median == 10.0
    assert s[1].n_ok == 1 and s[1].n_err == 1


def test_build_prompt_is_deterministic_except_nonce() -> None:
    a = build_prompt(500, "指示", nonce="x", seed=1)
    b = build_prompt(500, "指示", nonce="y", seed=1)
    assert a.split("\n", 1)[1] == b.split("\n", 1)[1]
    assert a != b
    assert build_prompt(0, "指示", nonce="z").endswith("指示")


def test_build_prompt_with_filler_file(tmp_path) -> None:
    # 短いファイルは目標の長さまで繰り返して詰める (1トークン ≈ 3.5 文字)
    src = tmp_path / "a.py"
    src.write_text("def f():\n    return 1\n")
    p = build_prompt(100, "説明して", nonce="n", filler_file=str(src))
    body = p.split("```\n", 1)[1].rsplit("\n```", 1)[0]
    assert len(body) == 350
    assert body.startswith("def f():")
    assert p.endswith("説明して")


def _sse(events: list[str]) -> bytes:
    return ("".join(f"{e}\n\n" for e in events)).encode()


def test_openai_stream_parsing(monkeypatch) -> None:
    body = _sse(
        [
            'data: {"choices":[{"delta":{"reasoning_content":"考"}}]}',
            'data: {"choices":[{"delta":{"content":"答"}}]}',
            'data: {"choices":[{"delta":{},"finish_reason":"length"}]}',
            'data: {"choices":[],"usage":{"prompt_tokens":7,"completion_tokens":2},"timings":{"predicted_per_second":9}}',
            "data: [DONE]",
        ]
    )
    _patch_transport(monkeypatch, body)
    r = run_request(api="openai", base_url="http://x", model="m", prompt="p", max_tokens=2, scenario="s", repeat=0)
    assert r.error is None
    assert (r.prompt_tokens, r.completion_tokens, r.finish_reason) == (7, 2, "length")
    assert r.server_timings == {"predicted_per_second": 9}
    assert r.text_head == "考答"


def test_anthropic_stream_parsing(monkeypatch) -> None:
    body = _sse(
        [
            'event: message_start\ndata: {"type":"message_start","message":{"usage":{"input_tokens":5}}}',
            'event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"t"}}',
            'event: content_block_delta\ndata: {"type":"content_block_delta","delta":{"type":"text_delta","text":"a"}}',
            'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"max_tokens"},"usage":{"output_tokens":2}}',
            'event: message_stop\ndata: {"type":"message_stop"}',
        ]
    )
    _patch_transport(monkeypatch, body)
    r = run_request(api="anthropic", base_url="http://x", model="m", prompt="p", max_tokens=2, scenario="s", repeat=0)
    assert r.error is None
    assert (r.prompt_tokens, r.completion_tokens, r.finish_reason) == (5, 2, "max_tokens")
    assert r.t_first is not None and r.t_last is not None


def test_http_error_is_recorded(monkeypatch) -> None:
    _patch_transport(monkeypatch, b"nope", status=500)
    r = run_request(api="openai", base_url="http://x", model="m", prompt="p", max_tokens=2, scenario="s", repeat=0)
    assert r.error is not None and r.error.startswith("HTTP 500")


def _patch_transport(monkeypatch, body: bytes, status: int = 200) -> None:
    """httpx.Client を固定応答の MockTransport に差し替える。"""
    transport = httpx.MockTransport(lambda req: httpx.Response(status, content=body))
    orig = httpx.Client

    def factory(*args, **kwargs):  # type: ignore[no-untyped-def]
        kwargs["transport"] = transport
        return orig(*args, **kwargs)

    monkeypatch.setattr(httpx, "Client", factory)

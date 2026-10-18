"""指定トークン数前後の入力プロンプトを決定的に生成する。

実際のトークン数はエンジンの tokenizer 次第なので、ここでは「おおよそ」の長さを作り、
正確な値は API の usage から取る。先頭にリクエストごとのランダム文字列を置き、
prefix キャッシュの再利用で prefill が速く見える現象を防ぐ。
"""

from __future__ import annotations

import random

# 英単語はおおむね 1語 ≈ 1.3 トークン。和文を混ぜると tokenizer 間の差が大きくなるため、
# 長さの基準となる詰め物は英語にし、指示文だけ日本語にする。
_WORDS = (
    "system memory expert router token layer cache tensor kernel stream batch "
    "latency throughput model weight matrix vector query key value attention "
    "pipeline device host transfer bandwidth compute offload schedule queue "
    "report summary analysis budget contract meeting schedule review project "
    "river mountain forest harbor village market winter summer morning evening"
).split()
_TOKENS_PER_WORD = 1.3


# ソースコードはおおむね 1トークン ≈ 3.5 文字
_CHARS_PER_TOKEN_CODE = 3.5


def build_prompt(
    target_tokens: int,
    instruction: str,
    nonce: str,
    seed: int = 0,
    filler_file: str | None = None,
) -> str:
    """詰め物テキスト + 指示文からなるプロンプトを返す。

    Args:
        target_tokens: 詰め物部分のおおよそのトークン数。0 なら詰め物なし。
        instruction: 末尾に置く指示文 (生成させたい内容)。
        nonce: 先頭に置く、リクエストごとに異なる文字列 (キャッシュ無効化用)。
        seed: 詰め物の乱数シード (同じ値なら同じ文面になる)。
        filler_file: 指定すると、乱数の英単語の代わりにこのファイルの先頭部分を詰め物にする
            (コードを読ませる状況の再現用。足りなければ繰り返す)。
    """
    parts = [f"[request-id: {nonce}]"]
    if target_tokens > 0 and filler_file:
        with open(filler_file, encoding="utf-8", errors="replace") as f:
            src = f.read()
        n_chars = int(target_tokens * _CHARS_PER_TOKEN_CODE)
        body = (src * (n_chars // max(1, len(src)) + 1))[:n_chars]
        parts.append("以下は参考資料のソースコードです。\n```\n" + body + "\n```")
    elif target_tokens > 0:
        rng = random.Random(seed)
        n_words = max(1, int(target_tokens / _TOKENS_PER_WORD))
        words = [rng.choice(_WORDS) for _ in range(n_words)]
        # 20語ごとに改行と番号を入れ、極端な繰り返し文にならないようにする
        lines = [
            f"{i // 20 + 1}. " + " ".join(words[i : i + 20]) for i in range(0, n_words, 20)
        ]
        parts.append("以下は参考資料です。\n" + "\n".join(lines))
    parts.append(instruction)
    return "\n\n".join(parts)

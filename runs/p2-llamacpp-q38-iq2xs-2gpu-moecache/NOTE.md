# 注記 (2026-10-18 追記)

この計測では `-ot "ple_ngram_embd=CPU"` を指定したため、llama.cpp の `--fit` は
"tensor_buft_overrides already set by user, abort" で**無効になっていた**。
結果として n-gram 表 (shard 2) 以外の重みは 2GPU (24GB + 20GB) に**すべて VRAM 配置**されている
(VRAM ピーク 22.6GB / 18.4GB)。CPU 側にエキスパートが無いため `--moe-cache-mib` は効果なし。
「エキスパート全体が VRAM に収まる場合」の参考値として扱う。

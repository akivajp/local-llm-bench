# 計測環境 (2026-10-19 06:33:14 JST)

## OS / カーネル

```
PRETTY_NAME="Ubuntu 26.04.1 LTS"
7.0.0-38-generic
```

## CPU / メモリ

```
モデル名:                            AMD Ryzen 9 9950X3D 16-Core Processor
コアあたりのスレッド数:              2
ソケットあたりのコア数:              16
               total        used        free      shared  buff/cache   available
Mem:              89          10          11           0          68          78
(dmidecode は root 権限が必要なため未取得)
```

## GPU / ドライバ / PCIe

```
index, name, memory.total [MiB], driver_version, pcie.link.gen.max, pcie.link.width.max, power.limit [W]
0, NVIDIA GeForce RTX 4090, 24564 MiB, 595.99.02, 4, 16, 450.00 W
1, NVIDIA RTX 4000 Ada Generation, 20475 MiB, 595.99.02, 4, 16, 130.00 W
| NVIDIA-SMI 595.99.02              Driver Version: 595.99.02      CUDA Version: 13.2     |
	[4mGPU0	GPU1	CPU Affinity	NUMA Affinity	GPU NUMA ID[0m
GPU0	 X 	PHB	0-31	0		N/A
GPU1	PHB	 X 	0-31	0		N/A

```

## Docker / イメージのダイジェスト

```
Docker version 29.1.3, build 29.1.3-0ubuntu4.1
ghcr.io/ggml-org/llama.cpp:server-cuda  id=sha256:b4e561932a1d  repo_digest=ghcr.io/ggml-org/llama.cpp@sha256:b4e561932a1dd460ec2f9d2875ad0d9535cbfd3d2d6a48bdb3c9d50804088bff  created=2026-10-18T06:10:57.161244472Z
llmb-strata:upstream  id=sha256:a098d16e7c8d  repo_digest=llmb-strata@sha256:a098d16e7c8d9a8e441a1c1ce7364b79be08acd28bc1276fffde50febe7b3e58  created=2026-10-18T22:27:04.170904046+09:00
llmb-strata:dualgpu  id=sha256:45fc2d0fa5a0  repo_digest=llmb-strata@sha256:45fc2d0fa5a040aaa67f46bd8bbf7a61e0157d6309cd65b8ca3685b9786e16e1  created=2026-10-18T22:28:09.616727732+09:00
version: 0.7.0-dev (build 11718, commit 547208dca)
```

## エンジンのソース (Strata は docker build 時のコミット)

```
Strata  477ac13cbe8e582c20484871ce459d20d82df09d 2026-10-16 22:39:03 +0200
Strata-DualGPU  03a5ec955ba152a5f499a18a0f2f2ac192309c28 2026-10-03 23:38:14 +0200
ollama version is 0.40.6
```

## モデルファイル (HF リビジョンは hf download のメタデータから)

```
GLM-5.3-Flash-GGUF/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00001-of-00003.gguf  0.01GB  rev=a38483c8cd5df544f53d70fb281afe97369d5ab6  sha256=909a8a2dedb493c5a694facfd1e0e9a3309ac66fbb9d270c024ff5d12e0d565f
GLM-5.3-Flash-GGUF/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00002-of-00003.gguf  49.62GB  rev=a38483c8cd5df544f53d70fb281afe97369d5ab6  sha256=b99c4dd929601884ff95d9ddeb581a5ef93fd281c37c162e48b2981bf23c0830
GLM-5.3-Flash-GGUF/UD-IQ1_S/GLM-5.3-Flash-UD-IQ1_S-00003-of-00003.gguf  43.46GB  rev=a38483c8cd5df544f53d70fb281afe97369d5ab6  sha256=9bb0ff754968d588793d795c715cc2a7d5292280ff9d0df46b7e1edd57da34a1
Qwen3.6-35B-A3B/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf  22.36GB  rev=a483e9e6cbd595906af30beda3187c2663a1118c  sha256=707a55a8a4397ecde44de0c499d3e68c1ad1d240d1da65826b4949d1043f4450
Qwen3.8-Flash-Next-GSQ-RCO/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00001-of-00002.gguf  39.23GB  rev=ed59f92082b1e93c0e96d60a8b11aab089b52f09  sha256=92cee27ae5bbadcd732416a0f7a7f0acc092399dbbe8f5a5efa707c2ec0a49d7
Qwen3.8-Flash-Next-GSQ-RCO/IQ2_XS/Qwen3.8-Flash-Next-GSQ-RCO-IQ2_XS-00002-of-00002.gguf  28.80GB  rev=ed59f92082b1e93c0e96d60a8b11aab089b52f09  sha256=316b46f3a2dbd68c900f43136ab9449f9dcc3725dfd8c794847c204bc161e113
Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf  54.82GB  rev=ed59f92082b1e93c0e96d60a8b11aab089b52f09  sha256=4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3
Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf  28.80GB  rev=?  sha256=?
```

## 計測ツール

```
8d78600c231926d8c45f31513a2733c677d9d943 2026-10-19 01:38:30 +0900
 M scripts/phase3.sh
?? data/quality/gsm8k-10.jsonl
?? data/quality/mmmlu-ja-20.jsonl
?? runs/env-20261019-023934.md
?? runs/env-20261019-031550.md
?? runs/env-p3-deepseek-v4-flash.md
?? runs/env-p3-glm53-flash.md
?? runs/env-p3-gpt-oss-120b.md
?? runs/env-p3-nemotron35-super.md
?? runs/env-p3-qwen35-122b.md
?? runs/p3-llamacpp-deepseek-v4-flash-2gpu-fit-moecache/
?? runs/p3-llamacpp-deepseek-v4-flash-2gpu-fit/
?? runs/p3-llamacpp-deepseek-v4-flash-4090-fit/
?? runs/p3-llamacpp-glm53-flash-2gpu-fit-moecache/
?? runs/p3-llamacpp-glm53-flash-2gpu-fit/
?? runs/p3-llamacpp-glm53-flash-4090-fit/
?? runs/p3-llamacpp-gpt-oss-120b-2gpu-fit-moecache/
?? runs/p3-llamacpp-gpt-oss-120b-2gpu-fit/
?? runs/p3-llamacpp-gpt-oss-120b-4090-fit/
?? runs/p3-llamacpp-nemotron35-super-2gpu-fit-moecache/
```

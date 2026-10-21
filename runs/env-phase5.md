# 計測環境 (2026-10-22 04:48:28 JST)

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
Mem:              89           9           0           0          79          79
(dmidecode は root 権限が必要なため未取得)
```

## ストレージ (2026-10-22 から NVMe 3枚の btrfs RAID0。それ以前のフェーズは NVMe 1枚)

```
/dev/nvme1n1p1[/@] btrfs rw,relatime,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@
Data, RAID0: total=1.41TiB, used=1.38TiB
System, RAID1C3: total=32.00MiB, used=128.00KiB
Metadata, RAID1C3: total=8.00GiB, used=6.52GiB
GlobalReserve, single: total=512.00MiB, used=0.00B
nvme0n1 CT2000T500SSD8 link=16.0 GT/s PCIe x4
nvme1n1 CT2000T500SSD8 link=16.0 GT/s PCIe x4
nvme2n1 CT2000T500SSD8 link=16.0 GT/s PCIe x4
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
llmb-strata:dualgpu  id=  repo_digest=  created=
llmb-llamacpp:deepseek41  id=  repo_digest=  created=
llmb-cuda-build  id=sha256:f6ceee7f9bba  repo_digest=llmb-cuda-build@sha256:f6ceee7f9bbad249c27c8b4d8ff6ab9d7e1dee91c61278304addf2d241876eb1  created=2026-10-22T02:47:12.639744711+09:00
version: 0.7.0-dev (build 11718, commit 547208dca)
```

## エンジンのソース (Strata は docker build 時のコミット)

```
Strata  477ac13cbe8e582c20484871ce459d20d82df09d 2026-10-16 22:39:03 +0200
Strata-DualGPU  03a5ec955ba152a5f499a18a0f2f2ac192309c28 2026-10-03 23:38:14 +0200
project-maya  35bb2b22a2e2c65b91e24a41d4b026bfa4e89557 2026-10-21 08:31:58 +0100
llama.cpp  b72050d03ae14bb3cb5138ecefab3f3f65157d31 2026-10-19 07:59:37 -0700
ollama version is 0.40.6
```

## モデルファイル (HF リビジョンは hf download のメタデータから)

```
DeepSeek-V4.1-Flash-1017-Maya-GGUF/Maya-S/DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00001-of-00006.gguf  47.89GB  rev=276e0badcfb4a6d8f6c2b9d4da1b468cd339c221  sha256=1f3437f57042e69f94c141ffbcba0d5610dab63feb07244fb468be4940d6763f
DeepSeek-V4.1-Flash-1017-Maya-GGUF/Maya-S/DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00002-of-00006.gguf  47.67GB  rev=276e0badcfb4a6d8f6c2b9d4da1b468cd339c221  sha256=66501fee8702ffd54e6f065323ab54bb3150d20b10b01922c589e7462c7b5ba6
DeepSeek-V4.1-Flash-1017-Maya-GGUF/Maya-S/DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00003-of-00006.gguf  47.10GB  rev=276e0badcfb4a6d8f6c2b9d4da1b468cd339c221  sha256=3195b23f33337c46a07c48583946d99147c3635412bc4adc6acdc4cf42bf30ad
DeepSeek-V4.1-Flash-1017-Maya-GGUF/Maya-S/DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00004-of-00006.gguf  35.53GB  rev=276e0badcfb4a6d8f6c2b9d4da1b468cd339c221  sha256=d60dba35fac9601cd5c6026439dd980c457a5bb1c009192ea539b220108ea0db
DeepSeek-V4.1-Flash-1017-Maya-GGUF/Maya-S/DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00005-of-00006.gguf  80.64GB  rev=276e0badcfb4a6d8f6c2b9d4da1b468cd339c221  sha256=c98d46f96a25d17c4c54da5a60782c130255c364a22e621ea28d5c98a692ceb2
DeepSeek-V4.1-Flash-1017-Maya-GGUF/Maya-S/DeepSeek-V4.1-Flash-1017-Maya-S-IQ2_XXS-00006-of-00006.gguf  80.64GB  rev=276e0badcfb4a6d8f6c2b9d4da1b468cd339c221  sha256=98d65ef4f36e0b193935d44c3586241ca09b1b47e90f118e85332cfdb5860263
GLM-5.3-Flash-Maya-GGUF/Maya-S24/GLM-5.3-Flash-Maya-S24-IQ2_XXS_S-00001-of-00003.gguf  46.89GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=8ebd5c74bcf65ece2a8699b7b6fd2b8d177f350ed252cee252fdd99b86a0138c
GLM-5.3-Flash-Maya-GGUF/Maya-S24/GLM-5.3-Flash-Maya-S24-IQ2_XXS_S-00002-of-00003.gguf  46.98GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=4bd445da3a0128a9c5b32228c924e0a622aa4a132c7a8dc9a2c207a4beea8e34
GLM-5.3-Flash-Maya-GGUF/Maya-S24/GLM-5.3-Flash-Maya-S24-IQ2_XXS_S-00003-of-00003.gguf  0.83GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=a6fd4e88007ac49b431c7d02be34e43ab7a09224d53a0c52782327613cb41917
Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf  54.82GB  rev=ed59f92082b1e93c0e96d60a8b11aab089b52f09  sha256=4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3
Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf  28.80GB  rev=?  sha256=?
```

## 計測ツール

```
43d8b721b5f2399bd1d82b493d8ed51781fb140e 2026-10-19 06:36:42 +0900
 M runs/phase4-results.jsonl
 M scripts/collect-env.sh
 M scripts/lib.sh
 M scripts/phase-quality.sh
 M scripts/phase4.sh
 M src/local_llm_bench/cli.py
 M src/local_llm_bench/monitor.py
 M tests/test_metrics.py
?? configs/slow.yaml
?? docker/
?? runs/env-20261022-030517.md
?? runs/env-20261022-035750.md
?? runs/env-20261022-040138.md
?? runs/env-20261022-041145.md
?? runs/env-20261022-042118.md
?? runs/env-20261022-044156.md
?? runs/env-phase5.md
?? runs/p4-cc-maya-ds41-s-2gpu/
?? runs/p4-cc-maya-glm53-s24-2gpu/
?? runs/p5-llamacpp-ds41-iq1s-2gpu/
```

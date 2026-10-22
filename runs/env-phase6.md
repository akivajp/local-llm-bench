# 計測環境 (2026-10-23 03:14:25 JST)

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
Mem:              89           9          68           0          12          80
(dmidecode は root 権限が必要なため未取得)
```

## ストレージ (2026-10-22 から NVMe 3枚の btrfs RAID0。それ以前のフェーズは NVMe 1枚)

```
/dev/nvme1n1p1[/@] btrfs rw,relatime,ssd,discard=async,space_cache=v2,subvolid=256,subvol=/@
Data, RAID0: total=1.40TiB, used=1.37TiB
System, RAID1C3: total=32.00MiB, used=128.00KiB
Metadata, RAID1C3: total=9.00GiB, used=6.86GiB
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
GLM-5.3-Flash-Maya-GGUF/Maya-L/GLM-5.3-Flash-Maya-L-IQ3_S-00001-of-00004.gguf  47.72GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=c41aeaf3a3e0022150b7c355e7f4df6c92ba68c4794e3e827e02e56b54886b9e
GLM-5.3-Flash-Maya-GGUF/Maya-L/GLM-5.3-Flash-Maya-L-IQ3_S-00002-of-00004.gguf  47.96GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=351d59366afb7be7dfc3fb7af91281f7ccf00760b17dc45f82090325a7b34f64
GLM-5.3-Flash-Maya-GGUF/Maya-L/GLM-5.3-Flash-Maya-L-IQ3_S-00003-of-00004.gguf  47.31GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=3685962fdfeaf130b74f98d3ce703ee33d818aa9991725932cb305b7c48db8af
GLM-5.3-Flash-Maya-GGUF/Maya-L/GLM-5.3-Flash-Maya-L-IQ3_S-00004-of-00004.gguf  13.34GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=1af62cd72de6460c85369d988abbb790d6ec3a97507df51faf9bf32aa2b600d0
GLM-5.3-Flash-Maya-GGUF/Maya-M/GLM-5.3-Flash-Maya-M-IQ2_S-00001-of-00003.gguf  47.68GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=3f740d1b1022b4a0ddad50cd861bb071dd415bde94afa1292d0476641186c638
GLM-5.3-Flash-Maya-GGUF/Maya-M/GLM-5.3-Flash-Maya-M-IQ2_S-00002-of-00003.gguf  47.82GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=285951d2afa0cd98285b03d0dc4aa68d83daf1a6f4a2594fe40b0cdd27ade485
GLM-5.3-Flash-Maya-GGUF/Maya-M/GLM-5.3-Flash-Maya-M-IQ2_S-00003-of-00003.gguf  20.50GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=ebf1ce713f71207747e10eeebed87597969d8b5e1d9dd817420d2c2f7ca51e0e
GLM-5.3-Flash-Maya-GGUF/Maya-S24/GLM-5.3-Flash-Maya-S24-IQ2_XXS_S-00001-of-00003.gguf  46.89GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=8ebd5c74bcf65ece2a8699b7b6fd2b8d177f350ed252cee252fdd99b86a0138c
GLM-5.3-Flash-Maya-GGUF/Maya-S24/GLM-5.3-Flash-Maya-S24-IQ2_XXS_S-00002-of-00003.gguf  46.98GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=4bd445da3a0128a9c5b32228c924e0a622aa4a132c7a8dc9a2c207a4beea8e34
GLM-5.3-Flash-Maya-GGUF/Maya-S24/GLM-5.3-Flash-Maya-S24-IQ2_XXS_S-00003-of-00003.gguf  0.83GB  rev=f16ee4ba50d8fd2bb726ea1862ca6ca14ba188da  sha256=a6fd4e88007ac49b431c7d02be34e43ab7a09224d53a0c52782327613cb41917
Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00001-of-00002.gguf  54.82GB  rev=ed59f92082b1e93c0e96d60a8b11aab089b52f09  sha256=4c1eb2ceb4915e1192f4f386021897bde56a97f40a0bb78bb86465e0f7d2aca3
Qwen3.8-Flash-Next-GSQ-RCO/IQ3_S/Qwen3.8-Flash-Next-GSQ-RCO-IQ3_S-00002-of-00002.gguf  28.80GB  rev=?  sha256=?
```

## 計測ツール

```
44fd3950974b1c31afa83ba1f060dd1fd9e271e0 2026-10-22 22:43:51 +0900
 M cc-tasks/README.ja.md
 M scripts/phase4.sh
?? cc-tasks/t3-feature/
?? configs/longctx-1m-qwen.yaml
?? configs/longctx-sweep-qwen.yaml
?? configs/longctx-sweep.yaml
?? runs/env-20261022-223333.md
?? runs/env-20261022-224342.md
?? runs/env-20261023-001655.md
?? runs/env-20261023-023655.md
?? runs/env-phase6.md
?? runs/p6-maya-ds41-s-2gpu-1m/
?? runs/p6-maya-glm53-maya-l-2gpu/
?? runs/p6-maya-glm53-maya-m-2gpu/
?? runs/p6-maya-glm53-s24-2gpu-1m-sweep/
?? runs/p6-maya-glm53-s24-2gpu-1m/
?? runs/p6-maya-glm53-s24-2gpu-dflash2-workloads/
?? runs/p6-maya-glm53-s24-2gpu-dflash2/
?? runs/p6-maya-glm53-s24-2gpu-headroom14/
?? runs/p6-maya-glm53-s24-2gpu-mtp-workloads/
```

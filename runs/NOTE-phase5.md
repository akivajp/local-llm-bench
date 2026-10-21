# フェーズ5 の補足 (2026-10-22)

- ストレージは NVMe 3枚 (Crucial T500 2TB, PCIe 4.0 x4) の btrfs RAID0 (データ RAID0 / メタデータ RAID1C3)。
  フェーズ1〜4 は同じ T500 1枚。実測 (O_DIRECT): 順次1本 5.8GB/s、順次4並列・1MiB ランダム16並列とも約 10GB/s。
- 削除済みのため `env-phase5.md` に載っていないモデル:
  - unsloth/GLM-5.3-Flash-GGUF UD-IQ1_S: rev a38483c8cd5df544f53d70fb281afe97369d5ab6 (フェーズ3と同じ。`env-p3-glm53-flash.md`)
  - unsloth/DeepSeek-V4.1-Flash-1017-GGUF UD-IQ1_S: rev 60ad3651641b5c97679c807e064ab1d7a3ca1455
    (ダウンロード時点の main。最終更新 2026-10-20、ダウンロードは 2026-10-22)
- llama.cpp の DeepSeek-V4.1 対応は未マージの PR #30817 (commit b72050d03) を `.devops/cuda.Dockerfile` (target server,
  CUDA_DOCKER_ARCH=89) でビルドしたもの。
- Maya の GLM を 4090 のみで動かすと、既定の RAM 余裕 6GB では OOM で落ちたため `MAYA_GLM_RAM_HEADROOM_GB=14` で計測
  (`p5-maya-glm53-s24-4090`)。2GPU は既定のまま。
- `p5s-*` はストレージ帯域の比較 (`scripts/phase5-storage.sh`): 各 NVMe を cgroup で 2.4GB/s (合計 7.2GB/s) に絞った
  `limit7g` と制限なしの `raid0`。`-st8` は `DS4_STREAM_THREADS=8`。帯域だけを絞っており、SSD 1枚のレイテンシは再現しない。

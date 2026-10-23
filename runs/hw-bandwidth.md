# 帯域の実測 (2026-10-23 18:04:40 JST)

## RAM (tools/membw.c、配列 2GiB × 3本、10回の最速)

```
threads=1  Read: 21.6 GB/s  Copy: 36.3 GB/s  Triad: 39.0 GB/s  (check 118097.0 2.0)
threads=4  Read: 60.7 GB/s  Copy: 41.5 GB/s  Triad: 45.3 GB/s  (check 118097.0 2.0)
threads=8  Read: 63.0 GB/s  Copy: 41.1 GB/s  Triad: 44.5 GB/s  (check 118097.0 2.0)
threads=16  Read: 61.5 GB/s  Copy: 40.1 GB/s  Triad: 43.6 GB/s  (check 118097.0 2.0)
threads=32  Read: 58.5 GB/s  Copy: 39.1 GB/s  Triad: 42.8 GB/s  (check 118097.0 2.0)
```

## VRAM / PCIe (tools/gpubw.cu、4GiB の転送)

```
GPU0 NVIDIA GeForce RTX 4090: VRAM copy 920 GB/s | PCIe H2D 13.4 GB/s, D2H 13.2 GB/s (buffer 4096 MiB)
GPU1 NVIDIA RTX 4000 Ada Generation: VRAM copy 303 GB/s | PCIe H2D 13.4 GB/s, D2H 13.2 GB/s (buffer 4096 MiB)
```

## PCIe のリンク (計測中の回数, GPU, 世代, 幅, 使用率)

```
      3 0, 1, 8, 0 %
      9 0, 4, 8, 0 %
     26 0, 4, 8, 100 %
      2 0, 4, 8, 99 %
     32 1, 1, 8, 0 %
      1 1, 4, 8, 0 %
      7 1, 4, 8, 100 %

# GPU と上流ポートの max / current
0000:01:00.0  max=16.0 GT/s PCIe x16  cur=16.0 GT/s PCIe x8
0000:00:01.1  max=32.0 GT/s PCIe x8  cur=16.0 GT/s PCIe x8
0000:03:00.0  max=16.0 GT/s PCIe x16  cur=16.0 GT/s PCIe x8
0000:00:01.3  max=32.0 GT/s PCIe x8  cur=16.0 GT/s PCIe x8
```

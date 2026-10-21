# Project Maya 等、CUDA Toolkit でソースからビルドするエンジン用の実行環境。
# ホストに CUDA Toolkit が無く sudo も使えない環境で、リポジトリをマウントしてコンテナ内でビルド・実行する。
# 例: docker build -t llmb-cuda-build -f docker/cuda-build.Dockerfile docker/
FROM nvidia/cuda:13.0.0-devel-ubuntu24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      python3 python3-venv python3-pip python3-dev g++ git curl ca-certificates cmake ninja-build pciutils \
    && rm -rf /var/lib/apt/lists/*

#!/usr/bin/env bash
# 作業ディレクトリ ($1) に、計測ツールのリポジトリをコミット済みの状態で複製する (runs/ の計測データは除く)
set -euo pipefail
dir="$1"
git clone -q "$REPO" "$dir.tmp"
rm -rf "$dir.tmp/runs" "$dir.tmp/.git"
cp -r "$dir.tmp/." "$dir/" && rm -rf "$dir.tmp"

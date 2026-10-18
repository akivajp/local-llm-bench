#!/usr/bin/env bash
# 計測の再現条件 (ハード・ドライバ・エンジンのバージョン・イメージのダイジェスト・モデルのリビジョン) を
# Markdown で標準出力に書き出す。公開時の「検証環境」節の元データにする。
set -uo pipefail
case "${1:-}" in -h|--help) sed -n '2,3p' "$0"; echo "usage: $(basename "$0") > runs/env.md"; exit 0 ;; esac

LAB="${HOME}/llm-lab"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section() { printf '\n## %s\n\n```\n' "$1"; }
endsec() { printf '```\n'; }

echo "# 計測環境 ($(date '+%F %T %Z'))"

section "OS / カーネル"
grep PRETTY_NAME /etc/os-release; uname -r
endsec

section "CPU / メモリ"
lscpu | grep -E "モデル名|Model name|^CPU\(s\)|コアあたり|Thread|ソケットあたり|Core\(s\)"
free -g | head -2
# メモリの速度は dmidecode (要 root) でしか取れないので、取れなければその旨を残す
sudo -n dmidecode -t memory 2>/dev/null | grep -E "^\s+(Size|Speed|Configured Memory Speed|Part Number):" | sort | uniq -c \
  || echo "(dmidecode は root 権限が必要なため未取得)"
endsec

section "GPU / ドライバ / PCIe"
nvidia-smi --query-gpu=index,name,memory.total,driver_version,pcie.link.gen.max,pcie.link.width.max,power.limit --format=csv
nvidia-smi | grep -E "CUDA Version"
nvidia-smi topo -m | head -4
endsec

section "Docker / イメージのダイジェスト"
docker --version
for img in ghcr.io/ggml-org/llama.cpp:server-cuda llmb-strata:upstream llmb-strata:dualgpu; do
  printf '%s  id=%s  repo_digest=%s  created=%s\n' "$img" \
    "$(docker image inspect -f '{{.Id}}' "$img" 2>/dev/null | cut -c1-19)" \
    "$(docker image inspect -f '{{join .RepoDigests ","}}' "$img" 2>/dev/null)" \
    "$(docker image inspect -f '{{.Created}}' "$img" 2>/dev/null)"
done
docker run --rm ghcr.io/ggml-org/llama.cpp:server-cuda --version 2>&1 | grep -E "^version" || true
endsec

section "エンジンのソース (Strata は docker build 時のコミット)"
for d in "${LAB}/strata/Strata" "${LAB}/strata/Strata-DualGPU"; do
  [[ -d "$d/.git" ]] && printf '%s  %s\n' "$(basename "$d")" "$(git -C "$d" log -1 --format='%H %cd' --date=iso)"
done
grep -m1 -oE 'VERSION *= *"[^"]+"' "${LAB}/strata/Strata/setup.py" 2>/dev/null || true
ollama --version 2>&1 | tail -1
endsec

section "モデルファイル (HF リビジョンは hf download のメタデータから)"
find "${LAB}/gguf" -name '*.gguf' -printf '%s %p\n' 2>/dev/null | sort -k2 | while read -r size path; do
  # --include でサブフォルダに落としたファイルは、local-dir 直下の .cache/ 以下に同じ相対パスで記録される
  meta="$(find "${LAB}/gguf" -path "*/.cache/huggingface/download/*" -name "$(basename "$path").metadata" 2>/dev/null | head -1)"
  # hf download --local-dir のメタデータ: 1行目がコミットハッシュ、2行目が etag (sha256)
  rev="$(sed -n 1p "$meta" 2>/dev/null)"; etag="$(sed -n 2p "$meta" 2>/dev/null)"
  printf '%s  %.2fGB  rev=%s  sha256=%s\n' "${path#"${LAB}"/gguf/}" "$(echo "$size/1000000000" | bc -l)" "${rev:-?}" "${etag:-?}"
done
endsec

section "計測ツール"
git -C "$REPO" log -1 --format='%H %cd' --date=iso 2>/dev/null || echo "(未コミット)"
git -C "$REPO" status --short 2>/dev/null | head -20
endsec

"""計測中の GPU (VRAM・使用率) とホスト RAM を一定間隔で記録するバックグラウンド監視。

nvidia-smi を定期的に呼ぶだけの単純な実装。ピーク値をサマリーに使い、
時系列はログ用に CSV で残す。
"""

from __future__ import annotations

import re
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Sample:
    """ある時点の GPU とホストのメモリ状況。"""

    t: float
    gpu_mem_mib: list[int]
    gpu_util: list[int]
    host_used_gib: float
    # NVMe ディスク (全台の合計) の累積読み込みバイト数。SSD から読みながら動くモデルの帯域の確認用
    disk_read_bytes: int = 0


@dataclass
class ResourceMonitor:
    """GPU / RAM の使用状況をサンプリングするスレッド。"""

    interval: float = 0.5
    csv_path: Path | None = None
    samples: list[Sample] = field(default_factory=list)
    _stop: threading.Event = field(default_factory=threading.Event)
    _thread: threading.Thread | None = None

    def start(self) -> None:
        """監視スレッドを開始する。"""
        self._thread = threading.Thread(target=self._loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        """監視スレッドを止め、CSV を書き出す。"""
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)
        if self.csv_path is not None and self.samples:
            self.csv_path.parent.mkdir(parents=True, exist_ok=True)
            with self.csv_path.open("w") as f:
                n = len(self.samples[0].gpu_mem_mib)
                cols = [f"gpu{i}_mem_mib" for i in range(n)] + [f"gpu{i}_util" for i in range(n)]
                f.write(",".join(["t", *cols, "host_used_gib", "disk_read_gbps"]) + "\n")
                prev = self.samples[0]
                for s in self.samples:
                    vals = [str(v) for v in s.gpu_mem_mib + s.gpu_util]
                    gbps = _rate_gbps(prev, s)
                    prev = s
                    f.write(",".join([f"{s.t:.2f}", *vals, f"{s.host_used_gib:.2f}", f"{gbps:.3f}"]) + "\n")

    def peaks(self) -> dict[str, float]:
        """GPU ごとの VRAM ピーク (MiB)、平均使用率 (%)、ホスト RAM ピーク (GiB) を返す。"""
        if not self.samples:
            return {}
        n = len(self.samples[0].gpu_mem_mib)
        out: dict[str, float] = {}
        for i in range(n):
            out[f"gpu{i}_mem_peak_mib"] = max(s.gpu_mem_mib[i] for s in self.samples)
            utils = [s.gpu_util[i] for s in self.samples]
            out[f"gpu{i}_util_mean"] = sum(utils) / len(utils)
        out["host_used_peak_gib"] = max(s.host_used_gib for s in self.samples)
        # ディスク読み込み: 全体の平均とピーク (GB/s)、合計 (GB)
        first, last = self.samples[0], self.samples[-1]
        if last.t > first.t:
            out["disk_read_total_gb"] = (last.disk_read_bytes - first.disk_read_bytes) / 1e9
            out["disk_read_mean_gbps"] = out["disk_read_total_gb"] / (last.t - first.t)
            rates = [_rate_gbps(a, b) for a, b in zip(self.samples, self.samples[1:])]
            out["disk_read_peak_gbps"] = max(rates) if rates else 0.0
        return out

    def _loop(self) -> None:
        """一定間隔でサンプルを取る。"""
        t0 = time.perf_counter()
        while not self._stop.is_set():
            try:
                self.samples.append(_sample(time.perf_counter() - t0))
            except Exception:  # noqa: BLE001 - 監視の失敗で計測を止めない
                pass
            self._stop.wait(self.interval)


def _sample(t: float) -> Sample:
    """nvidia-smi と /proc/meminfo から1サンプルを取る。"""
    out = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=memory.used,utilization.gpu",
            "--format=csv,noheader,nounits",
        ],
        capture_output=True,
        text=True,
        timeout=5,
        check=True,
    ).stdout
    mem, util = [], []
    for line in out.strip().splitlines():
        m, u = (int(x.strip()) for x in line.split(","))
        mem.append(m)
        util.append(u)
    return Sample(t=t, gpu_mem_mib=mem, gpu_util=util, host_used_gib=host_used_gib(),
                  disk_read_bytes=nvme_read_bytes())


def _rate_gbps(a: Sample, b: Sample) -> float:
    """2サンプル間のディスク読み込み速度 (GB/s)。"""
    dt = b.t - a.t
    return (b.disk_read_bytes - a.disk_read_bytes) / 1e9 / dt if dt > 0 else 0.0


_NVME_DISK = re.compile(r"nvme\d+n\d+$")   # パーティション (nvme0n1p1) は除き、ディスク全体だけ数える


def nvme_read_bytes(path: str = "/proc/diskstats") -> int:
    """全 NVMe ディスクの累積読み込みバイト数 (/proc/diskstats の読み込みセクタ数 × 512)。"""
    total = 0
    try:
        with open(path) as f:
            for line in f:
                p = line.split()
                if len(p) > 5 and _NVME_DISK.match(p[2]):
                    total += int(p[5]) * 512
    except OSError:
        return 0
    return total


def host_used_gib() -> float:
    """ホストの使用中メモリ (MemTotal - MemAvailable) を GiB で返す。"""
    info: dict[str, int] = {}
    with open("/proc/meminfo") as f:
        for line in f:
            k, v = line.split(":", 1)
            info[k] = int(v.strip().split()[0])  # kB
    return (info["MemTotal"] - info["MemAvailable"]) / 1024 / 1024


def gpu_info() -> list[str]:
    """GPU の名前と総 VRAM の一覧を返す (実行時の表示用)。"""
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=index,name,memory.total,memory.used", "--format=csv,noheader"],
            capture_output=True,
            text=True,
            timeout=5,
            check=True,
        ).stdout
    except Exception as e:  # noqa: BLE001
        return [f"(nvidia-smi 失敗: {e})"]
    return [line.strip() for line in out.strip().splitlines()]

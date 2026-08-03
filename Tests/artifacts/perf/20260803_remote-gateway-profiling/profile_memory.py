#!/usr/bin/env python3
"""MEMORY PROFILE phase: peak RSS for status_payload + host_metrics (N=20).

Measurement only -- no production optimizations.
Uses resource.getrusage (Darwin ru_maxrss = bytes) + periodic ps RSS samples.
Optional lightweight tracemalloc snapshot.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import platform
import resource
import statistics
import subprocess
import sys
import tempfile
import time
import tracemalloc
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[4]
AGENT_PATH = REPO / "RemoteAgent" / "model_switchboard_agent.py"
RUN_DIR = Path(__file__).resolve().parent

# Budget from BUDGETS.md
AGENT_RSS_BUDGET_MB = 80.0
AGENT_RSS_SOFT_MB = 50.0


def load_agent():
    spec = importlib.util.spec_from_file_location("model_switchboard_agent", AGENT_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["model_switchboard_agent"] = mod
    spec.loader.exec_module(mod)
    return mod


def ru_maxrss_bytes() -> int:
    """Peak RSS for this process (Darwin: bytes; Linux: kilobytes)."""
    val = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    if platform.system() == "Darwin":
        return int(val)
    return int(val) * 1024


def current_rss_bytes() -> int:
    """Current RSS via ps (macOS/Linux: RSS column is KiB)."""
    out = subprocess.check_output(
        ["ps", "-o", "rss=", "-p", str(os.getpid())],
        text=True,
    ).strip()
    return int(out) * 1024


def mb(n_bytes: float) -> float:
    return float(n_bytes) / (1024.0 * 1024.0)


def write_profile_env(profiles_dir: Path, name: str, port: int) -> None:
    content = (
        f"REQUEST_MODEL={name}\n"
        f"PORT={port}\n"
        f"MODEL=/models/{name}.gguf\n"
        f"LLAMA_BIN=llama-server\n"
    )
    (profiles_dir / f"{name}.env").write_text(content, encoding="utf-8")


def write_claim(scan_root: Path, port: int) -> None:
    claim = scan_root / str(port)
    claim.mkdir(parents=True, exist_ok=True)
    (claim / "flags.env").write_text(
        f'MODEL="${{MODEL:-/models/x.gguf}}"\nPORT="${{PORT:-{port}}}"\nLLAMA_BIN=llama-server\n',
        encoding="utf-8",
    )
    launch = claim / "launch.sh"
    launch.write_text("#!/bin/sh\n", encoding="utf-8")
    launch.chmod(0o755)


def free_port() -> int:
    import socket

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def build_fixture(agent, n_profiles: int, n_claims: int = 5):
    tmp = tempfile.TemporaryDirectory(prefix="ms-mem-profile-")
    root = Path(tmp.name)
    profiles = root / "model-profiles"
    profiles.mkdir()
    stack = root / "stack"
    stack.mkdir()
    base_port = 19000
    for i in range(n_profiles):
        write_profile_env(profiles, f"profile{i:02d}", base_port + i)
    for i in range(n_claims):
        write_claim(stack, base_port + 500 + i)
    cfg = agent.AgentConfiguration(
        root=root,
        host="127.0.0.1",
        port=free_port(),
        profiles_dir=profiles,
        allow_unauthenticated=True,
    )
    svc = agent.AgentService(cfg)
    old_scan = os.environ.get(agent.SCAN_ROOTS_ENV)
    os.environ[agent.SCAN_ROOTS_ENV] = str(stack)
    return tmp, svc, old_scan


def restore_scan(agent, old_scan):
    if old_scan is None:
        os.environ.pop(agent.SCAN_ROOTS_ENV, None)
    else:
        os.environ[agent.SCAN_ROOTS_ENV] = old_scan


def snap(label: str, samples: list[dict[str, Any]]) -> dict[str, Any]:
    row = {
        "label": label,
        "ts": time.time(),
        "current_rss_bytes": current_rss_bytes(),
        "peak_rss_bytes_rusage": ru_maxrss_bytes(),
    }
    row["current_rss_mb"] = round(mb(row["current_rss_bytes"]), 3)
    row["peak_rss_mb_rusage"] = round(mb(row["peak_rss_bytes_rusage"]), 3)
    samples.append(row)
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--n", type=int, default=20, help="timed samples per path")
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--profiles", type=int, default=20)
    ap.add_argument("--out", type=Path, default=RUN_DIR / "memory-profile.json")
    ap.add_argument(
        "--tracemalloc",
        action="store_true",
        default=True,
        help="lightweight tracemalloc around status loop (default on)",
    )
    ap.add_argument("--no-tracemalloc", action="store_true")
    args = ap.parse_args()
    use_tm = args.tracemalloc and not args.no_tracemalloc

    samples: list[dict[str, Any]] = []
    report: dict[str, Any] = {
        "run_id": "20260803_remote-gateway-profiling",
        "phase": "MEMORY-PROFILE",
        "mode": "LOCAL-ONLY",
        "captured_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "platform": {
            "system": platform.system(),
            "machine": platform.machine(),
            "python": sys.version.split()[0],
            "ru_maxrss_unit": "bytes" if platform.system() == "Darwin" else "kilobytes*1024",
        },
        "n_profiles": args.profiles,
        "n_samples": args.n,
        "warmup": args.warmup,
        "budget": {
            "agent_rss_peak_mb": AGENT_RSS_BUDGET_MB,
            "agent_rss_soft_investigate_mb": AGENT_RSS_SOFT_MB,
            "metric_ids": ["A.agent_rss_peak", "B.agent_rss_peak", "C.agent_rss_peak"],
            "source": "BUDGETS.md",
        },
        "method": {
            "peak": "resource.getrusage(RUSAGE_SELF).ru_maxrss (normalized to bytes)",
            "current": "ps -o rss= (KiB * 1024)",
            "fixture": "N profile .env + 5 claims (same class as profile_cpu.py / bench_baseline.py)",
            "paths": ["status_payload()", "host_metrics_payload()"],
        },
    }

    snap("before_agent_import", samples)

    agent = load_agent()
    report["agent_version"] = getattr(agent, "AGENT_VERSION", None)
    snap("after_agent_import", samples)

    tmp, svc, old_scan = build_fixture(agent, args.profiles)
    snap("after_fixture", samples)

    status_current: list[int] = []
    metrics_current: list[int] = []
    status_wall_ms: list[float] = []
    metrics_wall_ms: list[float] = []
    tm_snapshot: dict[str, Any] | None = None

    try:
        for _ in range(args.warmup):
            svc.status_payload()
            agent.host_metrics_payload()
        snap("after_warmup", samples)

        peak_before_status = ru_maxrss_bytes()
        current_before_status = current_rss_bytes()

        if use_tm:
            tracemalloc.start(10)

        for i in range(args.n):
            t0 = time.perf_counter()
            svc.status_payload()
            status_wall_ms.append((time.perf_counter() - t0) * 1000.0)
            status_current.append(current_rss_bytes())
            if i == 0 or i == args.n - 1 or (i + 1) % 5 == 0:
                snap(f"status_loop_i{i}", samples)

        if use_tm:
            current_tm, peak_tm = tracemalloc.get_traced_memory()
            top = tracemalloc.take_snapshot().statistics("lineno")[:15]
            tm_snapshot = {
                "current_traced_bytes": current_tm,
                "peak_traced_bytes": peak_tm,
                "current_traced_mb": round(mb(current_tm), 4),
                "peak_traced_mb": round(mb(peak_tm), 4),
                "top_lineno": [
                    {
                        "file": str(s.traceback[0].filename) if s.traceback else "?",
                        "line": s.traceback[0].lineno if s.traceback else -1,
                        "size_bytes": s.size,
                        "size_mb": round(mb(s.size), 4),
                        "count": s.count,
                    }
                    for s in top
                ],
            }
            tracemalloc.stop()

        peak_after_status = ru_maxrss_bytes()
        snap("after_status_loop", samples)

        if hasattr(agent, "_GPU_METRICS_CACHE"):
            agent._GPU_METRICS_CACHE["at"] = 0.0
            agent._GPU_METRICS_CACHE["payload"] = None
        t0 = time.perf_counter()
        cold = agent.host_metrics_payload()
        cold_ms = (time.perf_counter() - t0) * 1000.0
        for _ in range(2):
            agent.host_metrics_payload()
        for i in range(args.n):
            t0 = time.perf_counter()
            agent.host_metrics_payload()
            metrics_wall_ms.append((time.perf_counter() - t0) * 1000.0)
            metrics_current.append(current_rss_bytes())
            if i == 0 or i == args.n - 1:
                snap(f"metrics_loop_i{i}", samples)

        peak_after_metrics = ru_maxrss_bytes()
        snap("after_metrics_loop", samples)

        sample = svc.status_payload()
        snap("after_final_status", samples)

        peak_final = ru_maxrss_bytes()
        current_final = current_rss_bytes()

        # Peak of observed current samples during scenario windows
        all_scenario_current = status_current + metrics_current
        peak_current_scenario = max(all_scenario_current) if all_scenario_current else current_final
        peak_rusage_scenario = max(peak_after_status, peak_after_metrics, peak_final)

        report["sample_tags"] = {
            "statuses_len": len(sample.get("statuses") or []),
            "gpu_source": cold.get("gpu_source"),
            "n_gpus": len(cold.get("gpus") or []),
            "host_metrics_cold_ms": round(cold_ms, 3),
        }
        report["status_wall_ms"] = {
            "n": len(status_wall_ms),
            "mean": statistics.fmean(status_wall_ms) if status_wall_ms else None,
            "p50": sorted(status_wall_ms)[len(status_wall_ms) // 2] if status_wall_ms else None,
            "p95": sorted(status_wall_ms)[max(0, int(len(status_wall_ms) * 0.95) - 1)]
            if status_wall_ms
            else None,
            "max": max(status_wall_ms) if status_wall_ms else None,
        }
        report["host_metrics_wall_ms"] = {
            "n": len(metrics_wall_ms),
            "mean": statistics.fmean(metrics_wall_ms) if metrics_wall_ms else None,
            "max": max(metrics_wall_ms) if metrics_wall_ms else None,
        }

        report["rss"] = {
            "before_status_loop": {
                "current_mb": round(mb(current_before_status), 3),
                "peak_rusage_mb": round(mb(peak_before_status), 3),
            },
            "after_status_loop": {
                "peak_rusage_mb": round(mb(peak_after_status), 3),
                "current_samples_mb": {
                    "min": round(mb(min(status_current)), 3) if status_current else None,
                    "max": round(mb(max(status_current)), 3) if status_current else None,
                    "mean": round(mb(statistics.fmean(status_current)), 3)
                    if status_current
                    else None,
                    "n": len(status_current),
                },
            },
            "after_metrics_loop": {
                "peak_rusage_mb": round(mb(peak_after_metrics), 3),
                "current_samples_mb": {
                    "min": round(mb(min(metrics_current)), 3) if metrics_current else None,
                    "max": round(mb(max(metrics_current)), 3) if metrics_current else None,
                    "mean": round(mb(statistics.fmean(metrics_current)), 3)
                    if metrics_current
                    else None,
                    "n": len(metrics_current),
                },
            },
            "scenario_peak": {
                "peak_rusage_bytes": peak_rusage_scenario,
                "peak_rusage_mb": round(mb(peak_rusage_scenario), 3),
                "peak_current_sampled_bytes": peak_current_scenario,
                "peak_current_sampled_mb": round(mb(peak_current_scenario), 3),
                "final_current_mb": round(mb(current_final), 3),
                "final_peak_rusage_mb": round(mb(peak_final), 3),
                # Primary gate: rusage peak for process during scenario (high-water)
                "primary_peak_mb": round(mb(peak_rusage_scenario), 3),
                "primary_metric": "ru_maxrss_bytes during status+metrics window",
            },
        }

        peak_mb = mb(peak_rusage_scenario)
        report["budget_check"] = {
            "metric": "C.agent_rss_peak / A.agent_rss_peak / B.agent_rss_peak",
            "budget_mb": AGENT_RSS_BUDGET_MB,
            "soft_investigate_mb": AGENT_RSS_SOFT_MB,
            "measured_peak_mb": round(peak_mb, 3),
            "headroom_mb": round(AGENT_RSS_BUDGET_MB - peak_mb, 3),
            "vs_budget": "PASS" if peak_mb <= AGENT_RSS_BUDGET_MB else "FAIL",
            "vs_soft": "above_soft" if peak_mb > AGENT_RSS_SOFT_MB else "within_soft",
            "prior_sample_mb": 32.0,
            "prior_note": "BUDGETS.md ~32 MB sample 2026-08-01",
        }

        if tm_snapshot is not None:
            report["tracemalloc"] = tm_snapshot

        report["timeline"] = samples

    finally:
        restore_scan(agent, old_scan)
        tmp.cleanup()

    text = json.dumps(report, indent=2, default=str)
    args.out.write_text(text, encoding="utf-8")
    print(f"wrote {args.out}", file=sys.stderr)
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

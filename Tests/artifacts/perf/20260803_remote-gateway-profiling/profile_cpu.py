#!/usr/bin/env python3
"""CPU PROFILE phase: drive status_payload + host_metrics with MSW_PERF spans.

Reuses fixture patterns from bench_baseline.py. Measurement only -- no optimizes.
Writes:
  - cpu-spans.jsonl  (via MSW_PERF_JSONL)
  - optional cprofile.txt when --cprofile
  - summary JSON to stdout / --out
"""
from __future__ import annotations

import argparse
import cProfile
import importlib.util
import json
import math
import os
import pstats
import statistics
import sys
import tempfile
import time
from io import StringIO
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[4]
AGENT_PATH = REPO / "RemoteAgent" / "model_switchboard_agent.py"
RUN_DIR = Path(__file__).resolve().parent


def load_agent():
    spec = importlib.util.spec_from_file_location("model_switchboard_agent", AGENT_PATH)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules["model_switchboard_agent"] = mod
    spec.loader.exec_module(mod)
    return mod


def percentile(sorted_vals: list[float], p: float) -> float:
    if not sorted_vals:
        return float("nan")
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    k = (len(sorted_vals) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_vals[int(k)]
    return sorted_vals[f] * (c - k) + sorted_vals[c] * (k - f)


def summarize_ms(times_ms: list[float]) -> dict[str, Any]:
    ms = sorted(times_ms)
    n = len(ms)
    return {
        "n": n,
        "unit": "ms",
        "mean": statistics.fmean(ms) if ms else float("nan"),
        "stdev": statistics.stdev(ms) if n >= 2 else 0.0,
        "min": ms[0] if ms else float("nan"),
        "max": ms[-1] if ms else float("nan"),
        "p50": percentile(ms, 50),
        "p95": percentile(ms, 95),
        "p99": percentile(ms, 99),
    }


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
    tmp = tempfile.TemporaryDirectory(prefix="ms-cpu-profile-")
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


def aggregate_stages(records: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """Per-stage mean/p50/p95/sum across span records that have stages_ms."""
    buckets: dict[str, list[float]] = {}
    for rec in records:
        stages = rec.get("stages_ms") or {}
        if not isinstance(stages, dict):
            continue
        for name, val in stages.items():
            try:
                buckets.setdefault(str(name), []).append(float(val))
            except (TypeError, ValueError):
                continue
    out: dict[str, dict[str, Any]] = {}
    for name, vals in buckets.items():
        s = summarize_ms(vals)
        s["sum"] = sum(vals)
        s["share_of_stage_sums"] = None  # filled later
        out[name] = s
    total_sum = sum(v["sum"] for v in out.values()) or 1.0
    for name, s in out.items():
        s["share_of_stage_sums"] = s["sum"] / total_sum
    return dict(sorted(out.items(), key=lambda kv: -kv[1]["sum"]))


def load_jsonl(path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not path.is_file():
        return rows
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--n", type=int, default=20, help="timed samples per path")
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--profiles", type=int, default=20, help="N profile .env files")
    ap.add_argument(
        "--jsonl",
        type=Path,
        default=RUN_DIR / "cpu-spans.jsonl",
        help="MSW_PERF_JSONL path",
    )
    ap.add_argument("--out", type=Path, default=RUN_DIR / "cpu-profile-summary.json")
    ap.add_argument("--cprofile", type=Path, default=None, help="write cProfile text report")
    ap.add_argument(
        "--cprofile-n",
        type=int,
        default=20,
        help="status_payload iterations inside cProfile (default 20)",
    )
    args = ap.parse_args()

    # Gate instrumentation BEFORE loading agent (env read is live per span, but set early)
    os.environ["MSW_PERF_PROFILE"] = "1"
    os.environ["MSW_PERF_JSONL"] = str(args.jsonl.resolve())
    # fresh JSONL for this run
    if args.jsonl.exists():
        args.jsonl.unlink()
    args.jsonl.parent.mkdir(parents=True, exist_ok=True)

    agent = load_agent()
    if not agent._perf_profile_enabled():
        print("ERROR: MSW_PERF_PROFILE not enabled after set", file=sys.stderr)
        return 2

    tmp, svc, old_scan = build_fixture(agent, args.profiles)
    report: dict[str, Any] = {
        "run_id": "20260803_remote-gateway-profiling",
        "phase": "CPU-PROFILE",
        "mode": "LOCAL-ONLY",
        "captured_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "agent_version": getattr(agent, "AGENT_VERSION", None),
        "n_profiles": args.profiles,
        "n_samples": args.n,
        "warmup": args.warmup,
        "jsonl": str(args.jsonl),
        "flags": {
            "MSW_PERF_PROFILE": os.environ.get("MSW_PERF_PROFILE"),
            "MSW_PERF_JSONL": os.environ.get("MSW_PERF_JSONL"),
        },
    }

    try:
        # Warmup (spans recorded -- keep small)
        for _ in range(args.warmup):
            svc.status_payload()
            agent.host_metrics_payload()

        # Timed wall for status + host metrics (spans also written to JSONL)
        status_wall: list[float] = []
        for _ in range(args.n):
            t0 = time.perf_counter()
            svc.status_payload()
            status_wall.append((time.perf_counter() - t0) * 1000.0)

        # Clear GPU cache for one cold metrics sample, then warm loop
        if hasattr(agent, "_GPU_METRICS_CACHE"):
            agent._GPU_METRICS_CACHE["at"] = 0.0
            agent._GPU_METRICS_CACHE["payload"] = None
        t0 = time.perf_counter()
        cold = agent.host_metrics_payload()
        cold_ms = (time.perf_counter() - t0) * 1000.0
        for _ in range(2):
            agent.host_metrics_payload()
        metrics_wall: list[float] = []
        for _ in range(args.n):
            t0 = time.perf_counter()
            agent.host_metrics_payload()
            metrics_wall.append((time.perf_counter() - t0) * 1000.0)

        sample = svc.status_payload()
        report["status_payload_wall"] = summarize_ms(status_wall)
        report["host_metrics_wall_warm"] = summarize_ms(metrics_wall)
        report["host_metrics_cold_ms"] = cold_ms
        report["sample_tags"] = {
            "statuses_len": len(sample.get("statuses") or []),
            "gpu_source": cold.get("gpu_source"),
            "n_gpus": len(cold.get("gpus") or []),
        }

        # Optional cProfile on status_payload only (same fixture still live)
        if args.cprofile is not None:
            pr = cProfile.Profile()
            pr.enable()
            for _ in range(args.cprofile_n):
                svc.status_payload()
            pr.disable()
            buf = StringIO()
            stats = pstats.Stats(pr, stream=buf)
            stats.sort_stats("cumulative")
            stats.print_stats(60)
            buf.write("\n\n=== sort by tottime (top 40) ===\n")
            stats.sort_stats("tottime")
            stats.print_stats(40)
            args.cprofile.write_text(buf.getvalue(), encoding="utf-8")
            report["cprofile"] = str(args.cprofile)
            report["cprofile_n"] = args.cprofile_n
    finally:
        restore_scan(agent, old_scan)
        tmp.cleanup()

    # Aggregate stages from JSONL
    records = load_jsonl(args.jsonl)
    by_span: dict[str, list[dict[str, Any]]] = {}
    for rec in records:
        by_span.setdefault(str(rec.get("span") or "unknown"), []).append(rec)

    stage_aggs: dict[str, Any] = {}
    for span_name, rows in by_span.items():
        durations = [float(r["duration_ms"]) for r in rows if "duration_ms" in r]
        stage_aggs[span_name] = {
            "span_count": len(rows),
            "duration_ms": summarize_ms(durations) if durations else {},
            "stages_ranked": aggregate_stages(rows),
            # last-row tags (illustrative)
            "example_tags": {
                k: rows[-1].get(k)
                for k in rows[-1]
                if k not in ("stages_ms", "span", "duration_ms", "ts")
            }
            if rows
            else {},
        }
    report["spans"] = stage_aggs
    report["jsonl_lines"] = len(records)

    text = json.dumps(report, indent=2, default=str)
    args.out.write_text(text, encoding="utf-8")
    print(f"wrote {args.out}", file=sys.stderr)
    print(f"wrote {args.jsonl} ({len(records)} lines)", file=sys.stderr)
    if args.cprofile:
        print(f"wrote {args.cprofile}", file=sys.stderr)
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

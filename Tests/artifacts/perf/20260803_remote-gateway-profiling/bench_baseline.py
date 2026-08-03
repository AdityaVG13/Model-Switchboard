#!/usr/bin/env python3
"""LOCAL-ONLY wall-clock baseline harness (BASELINE phase).

Measures:
  C) status_payload() on-host for N profiles (in-process)
  B) host_metrics_payload() warm (and cold first-sample) on-host
  HTTP: loopback GET /api/status and /api/host/metrics via ephemeral serve

Does not optimize production code. Writes JSON summary to stdout / --out.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import statistics
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[4]
# file is Tests/artifacts/perf/<run-id>/bench_baseline.py -> parents[4] = repo
# parents: 0=run-id, 1=perf, 2=artifacts, 3=Tests, 4=repo
AGENT_PATH = REPO / "RemoteAgent" / "model_switchboard_agent.py"


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
    d0 = sorted_vals[f] * (c - k)
    d1 = sorted_vals[c] * (k - f)
    return d0 + d1


def summarize(times_s: list[float]) -> dict[str, Any]:
    ms = sorted(t * 1000.0 for t in times_s)
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
        "times_ms": ms,
        "provisional": n < 10,
    }


def write_profile_env(profiles_dir: Path, name: str, port: int) -> None:
    # Plain values: shell defaults are NOT expanded by Profile loader and break health probes.
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


def build_fixture(agent, n_profiles: int, n_claims: int = 5):
    tmp = tempfile.TemporaryDirectory(prefix="ms-baseline-")
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
    port = free_port()
    cfg = agent.AgentConfiguration(
        root=root,
        host="127.0.0.1",
        port=port,
        profiles_dir=profiles,
        allow_unauthenticated=True,
    )
    svc = agent.AgentService(cfg)
    old_scan = os.environ.get(agent.SCAN_ROOTS_ENV)
    os.environ[agent.SCAN_ROOTS_ENV] = str(stack)
    return tmp, root, profiles, stack, cfg, svc, old_scan


def restore_scan(agent, old_scan):
    if old_scan is None:
        os.environ.pop(agent.SCAN_ROOTS_ENV, None)
    else:
        os.environ[agent.SCAN_ROOTS_ENV] = old_scan


def time_calls(fn, n: int, warmup: int) -> list[float]:
    for _ in range(warmup):
        fn()
    times: list[float] = []
    for _ in range(n):
        t0 = time.perf_counter()
        fn()
        times.append(time.perf_counter() - t0)
    return times


def free_port() -> int:
    import socket

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def run_http_bench(agent, cfg, svc, n: int, warmup: int, token: str | None) -> dict[str, Any]:
    port = free_port()
    cfg.port = port
    # rebuild service/server with final port
    svc = agent.AgentService(cfg)
    server = agent.make_server(svc)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = f"http://127.0.0.1:{port}"
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    def get(path: str) -> None:
        req = urllib.request.Request(base + path, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as resp:
            resp.read()

    # wait ready
    for _ in range(50):
        try:
            get("/api/status")
            break
        except Exception:
            time.sleep(0.05)
    else:
        server.shutdown()
        raise RuntimeError("agent HTTP did not become ready")

    status_times = time_calls(lambda: get("/api/status"), n=n, warmup=warmup)
    # cold host metrics: clear GPU cache if possible
    if hasattr(agent, "_GPU_METRICS_CACHE"):
        agent._GPU_METRICS_CACHE["at"] = 0.0
        agent._GPU_METRICS_CACHE["payload"] = None
    cold_t0 = time.perf_counter()
    get("/api/host/metrics")
    cold_s = time.perf_counter() - cold_t0
    # warm remaining
    metrics_times = [cold_s] + time_calls(
        lambda: get("/api/host/metrics"), n=n - 1 if n > 1 else 0, warmup=max(0, warmup - 1)
    )
    # re-warm metrics properly: warm then measure
    for _ in range(3):
        get("/api/host/metrics")
    metrics_warm = time_calls(lambda: get("/api/host/metrics"), n=n, warmup=0)

    server.shutdown()
    thread.join(timeout=2)
    return {
        "port": port,
        "http_status": summarize(status_times),
        "http_host_metrics_cold_first_ms": cold_s * 1000.0,
        "http_host_metrics_warm": summarize(metrics_warm),
        "http_host_metrics_mixed_incl_cold": summarize(metrics_times),
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=50, help="timed samples per metric")
    ap.add_argument("--warmup", type=int, default=5)
    ap.add_argument("--profiles", type=str, default="5,20", help="comma list of profile counts")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--skip-http", action="store_true")
    ap.add_argument("--http-n", type=int, default=20)
    args = ap.parse_args()

    agent = load_agent()
    profile_counts = [int(x) for x in args.profiles.split(",") if x.strip()]

    report: dict[str, Any] = {
        "run_id": "20260803_remote-gateway-profiling",
        "phase": "BASELINE",
        "mode": "LOCAL-ONLY",
        "host": "loopback Mac (see fingerprint.json)",
        "git_sha": None,
        "captured_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "agent_path": str(AGENT_PATH),
        "agent_version": getattr(agent, "AGENT_VERSION", None),
        "n_default": args.n,
        "warmup": args.warmup,
        "scenarios": {},
    }

    # Scenario C + B in-process for each N
    for n_prof in profile_counts:
        tmp, root, profiles, stack, cfg, svc, old_scan = build_fixture(agent, n_prof)
        try:
            # status_payload
            st_times = time_calls(lambda: svc.status_payload(), n=args.n, warmup=args.warmup)
            sample = svc.status_payload()
            # host metrics: cold
            if hasattr(agent, "_GPU_METRICS_CACHE"):
                agent._GPU_METRICS_CACHE["at"] = 0.0
                agent._GPU_METRICS_CACHE["payload"] = None
            t0 = time.perf_counter()
            cold_payload = agent.host_metrics_payload()
            cold_s = time.perf_counter() - t0
            # warm host metrics
            for _ in range(3):
                agent.host_metrics_payload()
            hm_times = time_calls(lambda: agent.host_metrics_payload(), n=args.n, warmup=0)

            key = f"N{n_prof}"
            report["scenarios"][key] = {
                "n_profiles": n_prof,
                "status_payload": summarize(st_times),
                "status_payload_sample": {
                    "statuses_len": len(sample.get("statuses") or []),
                    "claims_len": len((sample.get("discovery") or {}).get("claims") or []),
                    "keys": sorted(sample.keys()),
                },
                "host_metrics_warm": summarize(hm_times),
                "host_metrics_cold_ms": cold_s * 1000.0,
                "host_metrics_sample": {
                    "host": cold_payload.get("host"),
                    "cpu_percent": cold_payload.get("cpu_percent"),
                    "gpu_source": cold_payload.get("gpu_source"),
                    "gpus_len": len(cold_payload.get("gpus") or []),
                },
            }
        finally:
            restore_scan(agent, old_scan)
            tmp.cleanup()

    # HTTP path with N=20 fixture (primary)
    if not args.skip_http:
        n_prof = 20 if 20 in profile_counts else profile_counts[-1]
        tmp, root, profiles, stack, cfg, svc, old_scan = build_fixture(agent, n_prof)
        try:
            # unauthenticated loopback
            cfg.auth_token = None
            cfg.allow_unauthenticated = True
            cfg.host = "127.0.0.1"
            http = run_http_bench(agent, cfg, svc, n=args.http_n, warmup=3, token=None)
            report["scenarios"]["http_loopback"] = {
                "n_profiles": n_prof,
                **http,
            }
        except Exception as exc:
            report["scenarios"]["http_loopback"] = {"error": repr(exc)}
        finally:
            restore_scan(agent, old_scan)
            tmp.cleanup()

    text = json.dumps(report, indent=2, default=str)
    if args.out:
        args.out.write_text(text, encoding="utf-8")
        print(f"wrote {args.out}", file=sys.stderr)
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import secrets
import subprocess
import sys
from typing import BinaryIO

from contracts import (
    BenchmarkLatestReportPayload,
    BenchmarkLatestRowPayload,
    BenchmarkPrefillCasePayload,
    BenchmarkStatusPayload,
)

from msctl.paths import BENCH_RESULTS_DIR, BENCH_SCRIPT, RUN_DIR
from msctl.profiles import process_alive, read_pid
from msctl.security import with_mutation_lock

def prefill_cases_from_results(results: list[dict]) -> list[BenchmarkPrefillCasePayload]:
    """Extract prefill-scaling cases (context suite: prefill-1k/4k/8k) from raw case results."""
    cases: list[BenchmarkPrefillCasePayload] = []
    for result in results:
        if not isinstance(result, dict) or result.get("category") != "prefill":
            continue
        ttft_ms = result.get("ttft_ms")
        if ttft_ms is None:
            continue
        prompt_tokens = result.get("prompt_est_tokens")
        name = str(result.get("benchmark") or "")
        label = name.removeprefix("prefill-")
        if not label:
            label = f"{round(prompt_tokens / 1024)}k" if prompt_tokens else "?"
        cases.append(
            {
                "label": label,
                "prompt_est_tokens": prompt_tokens if isinstance(prompt_tokens, int) else None,
                "ttft_ms": ttft_ms,
                "decode_tokens_per_sec": result.get("decode_tokens_per_sec"),
            }
        )
    cases.sort(key=lambda case: (case["prompt_est_tokens"] is None, case["prompt_est_tokens"] or 0))
    return cases


def latest_benchmark_report() -> BenchmarkLatestReportPayload | None:
    latest_json = BENCH_RESULTS_DIR / "latest.json"
    latest_md = BENCH_RESULTS_DIR / "latest.md"
    if not latest_json.exists():
        return None
    try:
        payload = json.loads(latest_json.read_text())
    except json.JSONDecodeError:
        return None
    rows: list[BenchmarkLatestRowPayload] = []
    for item in payload.get("benchmarks", []):
        avg = item.get("averages", {})
        row: BenchmarkLatestRowPayload = {
            "profile": item.get("profile"),
            "runtime": item.get("runtime"),
            "ttft_ms": avg.get("ttft_ms"),
            "decode_tokens_per_sec": avg.get("decode_tokens_per_sec"),
            "e2e_tokens_per_sec": avg.get("e2e_tokens_per_sec"),
            "rss_mb": item.get("rss_mb"),
        }
        prefill_cases = prefill_cases_from_results(item.get("results", []))
        if prefill_cases:
            row["prefill_cases"] = prefill_cases
        rows.append(row)
    return {
        "generated_at": payload.get("generated_at"),
        "suite": payload.get("suite"),
        "profiles": payload.get("profiles", []),
        "rows": rows,
        "json_path": str(latest_json),
        "markdown_path": str(latest_md),
    }


def benchmark_pid_path() -> pathlib.Path:
    return RUN_DIR / "benchmark.pid"


def benchmark_log_dir() -> pathlib.Path:
    return RUN_DIR / "logs"


def benchmark_log_pointer_path() -> pathlib.Path:
    return RUN_DIR / "benchmark.log.path"


def secure_benchmark_log_dir() -> pathlib.Path:
    log_dir = benchmark_log_dir()
    log_dir.mkdir(parents=True, exist_ok=True)
    log_dir.chmod(0o700)
    return log_dir


def benchmark_log_path() -> pathlib.Path:
    pointer = benchmark_log_pointer_path()
    if pointer.exists():
        try:
            path = pathlib.Path(pointer.read_text(encoding="utf-8").strip())
        except OSError:
            path = pathlib.Path()
        if path.is_absolute() and path.parent == benchmark_log_dir():
            return path
    return benchmark_log_dir() / "benchmark.log"


def open_benchmark_log_file(path: pathlib.Path) -> BinaryIO:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    return os.fdopen(fd, "ab", buffering=0)


def create_benchmark_log_file() -> tuple[pathlib.Path, BinaryIO]:
    log_dir = secure_benchmark_log_dir()
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    for _ in range(32):
        path = log_dir / f"benchmark-{timestamp}-{secrets.token_hex(8)}.log"
        try:
            return path, open_benchmark_log_file(path)
        except FileExistsError:
            continue
    raise RuntimeError("could not create unique benchmark log")


def write_benchmark_log_pointer(path: pathlib.Path) -> None:
    pointer = benchmark_log_pointer_path()
    pointer.parent.mkdir(parents=True, exist_ok=True)
    temp_path = pointer.with_suffix(".tmp")
    temp_path.write_text(f"{path}\n", encoding="utf-8")
    temp_path.chmod(0o600)
    temp_path.replace(pointer)


def benchmark_status() -> BenchmarkStatusPayload:
    pid = read_pid("benchmark")
    alive = bool(pid and process_alive(pid))
    if pid and not alive:
        benchmark_pid_path().unlink(missing_ok=True)
        pid = None
    return {
        "running": alive,
        "pid": pid,
        "log_path": str(benchmark_log_path()),
        "latest": latest_benchmark_report(),
    }


@with_mutation_lock
def start_benchmark(
    profiles: list[str] | None = None,
    *,
    suite: str = "quick",
    allow_concurrent: bool = False,
    keep_running: bool = False,
) -> BenchmarkStatusPayload:
    current = benchmark_status()
    if current["running"]:
        return current
    selected = profiles or ["all"]
    cmd = [sys.executable, str(BENCH_SCRIPT), "--suite", suite, "--profiles", *selected]
    if allow_concurrent:
        cmd.append("--allow-concurrent")
    if keep_running:
        cmd.append("--keep-running")
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    log_path, log_fp = create_benchmark_log_file()
    with log_fp, open(os.devnull, "rb") as stdin_fp:
        proc = subprocess.Popen(
            cmd,
            stdin=stdin_fp,
            stdout=log_fp,
            stderr=log_fp,
            start_new_session=True,
            close_fds=True,
        )
    write_benchmark_log_pointer(log_path)
    benchmark_pid_path().write_text(f"{proc.pid}\n")
    return benchmark_status()

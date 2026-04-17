#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import time
import urllib.error
import urllib.request
from typing import Any

from modelctl import (
    base_url,
    load_profiles,
    start_profile,
    status_for_profile,
    status_snapshot,
    stop_profile,
)

BASE = pathlib.Path(__file__).resolve().parent
OUTPUT_DIR = BASE / "benchmark-results"

def estimated_tokens(text: str) -> int:
    return max(1, round(len(text.encode("utf-8")) / 4))


LONG_CONTEXT_BLOCK = """
The local-model operator notebook includes practical guidance gathered from real inference sessions:
- TTFT is dominated by prefill, not decode, on long prompts.
- Decode speed is usually bounded by memory bandwidth once the model is resident.
- KV cache growth changes whether a run stays fully on the fast path or spills into a slower memory tier.
- Thermal throttling can make the third and fourth run materially slower than the first if cooling is ignored.
- Small prompt tests can hide serious regressions that only appear after 4K+ prompt tokens.
- Steady-state decode needs a longer output target than short chat replies, otherwise the number is mostly noise.
- Real users care about short interactive latency, coding quality, and long-context summaries at the same time.
""".strip()


def build_long_context_prompt(target_tokens: int, *, instruction: str, topic: str) -> str:
    sections = [
        f"You are evaluating a local model for {topic}.",
        "Read the operator notes below. Use them as the only source of truth.",
    ]
    chunk = 0
    while estimated_tokens("\n\n".join(sections)) < target_tokens:
        chunk += 1
        sections.append(f"Section {chunk}\n{LONG_CONTEXT_BLOCK}")
    sections.append(instruction)
    return "\n\n".join(sections)


PROMPT_SUITES: dict[str, list[dict[str, Any]]] = {
    "quick": [
        {
            "name": "interactive-chat",
            "category": "interactive",
            "prompt": "Answer in one sentence: what matters more for a responsive local coding assistant, TTFT or peak decode tokens per second, and why?",
            "max_tokens": 80,
        },
        {
            "name": "code-edit",
            "category": "coding",
            "prompt": "Write a Python function that groups file paths by extension and returns a stable dict ordered alphabetically by extension. Keep it concise.",
            "max_tokens": 220,
        },
        {
            "name": "kv-analysis",
            "category": "analysis",
            "prompt": "In 5 bullet points, explain how KV cache size and prompt length affect throughput on a local inference server.",
            "max_tokens": 220,
        },
    ],
    "local": [
        {
            "name": "interactive-latency",
            "category": "interactive",
            "prompt": "Reply in exactly one sentence: why does TTFT dominate perceived snappiness for a local model?",
            "max_tokens": 48,
        },
        {
            "name": "sustained-decode",
            "category": "decode",
            "prompt": "Write a compact operator checklist for keeping a laptop-hosted local model stable during a 30 minute coding session. Use 10 numbered items.",
            "max_tokens": 384,
        },
        {
            "name": "prefill-4k",
            "category": "prefill",
            "prompt": build_long_context_prompt(
                4096,
                instruction="Summarize the three main performance bottlenecks in 6 bullets and finish with one sentence recommending the safest optimization order.",
                topic="Mac-hosted local LLM operations",
            ),
            "max_tokens": 96,
        },
        {
            "name": "code-review",
            "category": "coding",
            "prompt": "Review a local-model launch script that mixes `--ctx-size 32768`, `--threads 14`, `--flash-attn`, and aggressive speculative decode. List the top five risks and the first two fixes you would make.",
            "max_tokens": 220,
        },
    ],
    "context": [
        {
            "name": "prefill-1k",
            "category": "prefill",
            "prompt": build_long_context_prompt(
                1024,
                instruction="Return 4 bullets about why context growth changes latency much more than short-chat benchmarks reveal.",
                topic="local long-context inference",
            ),
            "max_tokens": 64,
        },
        {
            "name": "prefill-4k",
            "category": "prefill",
            "prompt": build_long_context_prompt(
                4096,
                instruction="Return 5 bullets on how long-context prompts expose memory bandwidth limits and cache policy mistakes.",
                topic="local long-context inference",
            ),
            "max_tokens": 64,
        },
        {
            "name": "prefill-8k",
            "category": "prefill",
            "prompt": build_long_context_prompt(
                8192,
                instruction="Return 6 bullets explaining why prefill must be measured separately from decode when comparing local runtimes.",
                topic="local long-context inference",
            ),
            "max_tokens": 72,
        },
    ],
    "coding": [
        {
            "name": "refactor-plan",
            "category": "coding",
            "prompt": "You are reviewing a Python CLI tool that mixes HTTP requests, process control, and UI rendering in one file. Give a direct refactor plan with modules, responsibilities, and test priorities.",
            "max_tokens": 260,
        },
        {
            "name": "implementation",
            "category": "coding",
            "prompt": "Implement a Python function `atomic_write_json(path, payload)` that writes JSON atomically on macOS. Include type hints and basic error handling.",
            "max_tokens": 260,
        },
        {
            "name": "debugging",
            "category": "analysis",
            "prompt": "A local OpenAI-compatible endpoint returns blank `content` but fills `reasoning_content`. Explain the likely client/server mismatch and the safest mitigation for a coding-agent workflow.",
            "max_tokens": 260,
        },
    ],
}


class StreamResult(dict):
    pass



def stream_chat(base: str, model: str, prompt: str, *, temperature: float, max_tokens: int, timeout: float) -> StreamResult:
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": temperature,
        "max_tokens": max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    request = urllib.request.Request(
        f"{base}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Accept": "text/event-stream"},
    )

    pieces: list[str] = []
    usage: dict[str, Any] = {}
    first_token_at: float | None = None
    started = time.perf_counter()

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8", errors="ignore").strip()
                if not line or not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    break
                try:
                    obj = json.loads(data)
                except json.JSONDecodeError:
                    continue
                if obj.get("usage"):
                    usage = obj["usage"]
                for choice in obj.get("choices", []):
                    delta = choice.get("delta") or {}
                    piece = delta.get("content") or delta.get("reasoning_content") or choice.get("text") or ""
                    if piece:
                        if first_token_at is None:
                            first_token_at = time.perf_counter()
                        pieces.append(piece)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="ignore")
        raise RuntimeError(f"HTTP {exc.code}: {detail or exc.reason}") from exc

    finished = time.perf_counter()
    content = "".join(pieces)
    completion_tokens = usage.get("completion_tokens") or estimated_tokens(content)
    prompt_tokens = usage.get("prompt_tokens")
    ttft_ms = round(((first_token_at or finished) - started) * 1000, 1)
    total_ms = round((finished - started) * 1000, 1)
    gen_window = max(0.001, finished - (first_token_at or started))
    decode_tps = round(completion_tokens / gen_window, 2)
    e2e_tps = round(completion_tokens / max(0.001, finished - started), 2)
    return StreamResult(
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        ttft_ms=ttft_ms,
        total_ms=total_ms,
        decode_tokens_per_sec=decode_tps,
        e2e_tokens_per_sec=e2e_tps,
        content=content,
        usage_source="server" if usage.get("completion_tokens") else "estimated",
    )



def failed_result(error: str) -> StreamResult:
    return StreamResult(
        prompt_tokens=None,
        completion_tokens=None,
        ttft_ms=None,
        total_ms=None,
        decode_tokens_per_sec=None,
        e2e_tokens_per_sec=None,
        content="",
        usage_source="error",
        error=error,
    )



def run_case(base: str, model: str, prompt: str, *, temperature: float, max_tokens: int, timeout: float, retries: int = 2) -> StreamResult:
    last_error = ""
    for attempt in range(retries + 1):
        try:
            return stream_chat(
                base,
                model,
                prompt,
                temperature=temperature,
                max_tokens=max_tokens,
                timeout=timeout,
            )
        except Exception as exc:  # noqa: BLE001
            last_error = str(exc)
            if attempt < retries:
                time.sleep(2)
    return failed_result(last_error or "unknown error")



def mean_or_none(values: list[float | None], digits: int) -> float | None:
    usable = [value for value in values if value is not None]
    if not usable:
        return None
    return round(sum(usable) / len(usable), digits)


def summarize_category(results: list[dict[str, Any]], category: str) -> dict[str, Any]:
    scoped = [item for item in results if item.get("category") == category]
    return {
        "category": category,
        "cases": [item["benchmark"] for item in scoped],
        "ttft_ms": mean_or_none([item["ttft_ms"] for item in scoped], 1),
        "total_ms": mean_or_none([item["total_ms"] for item in scoped], 1),
        "decode_tokens_per_sec": mean_or_none([item["decode_tokens_per_sec"] for item in scoped], 2),
        "e2e_tokens_per_sec": mean_or_none([item["e2e_tokens_per_sec"] for item in scoped], 2),
    }



def stop_other_profiles(target_profile: str) -> None:
    for item in status_snapshot():
        if item["profile"] == target_profile:
            continue
        if item["running"]:
            stop_profile(item["profile"])



def benchmark_profile(
    profile_name: str,
    env: dict[str, str],
    prompts: list[dict[str, Any]],
    *,
    temperature: float,
    timeout: float,
    keep_running: bool,
    isolate: bool,
) -> dict[str, Any]:
    if isolate:
        stop_other_profiles(profile_name)

    try:
        start_profile(profile_name)
        status = status_for_profile(profile_name, env)
        if not status["ready"]:
            raise RuntimeError(f"Profile {profile_name} did not become ready")

        base = base_url(env)
        model = env["REQUEST_MODEL"]
        results: list[dict[str, Any]] = []

        warmup = run_case(
            base,
            model,
            "Reply with READY only.",
            temperature=0.0,
            max_tokens=24,
            timeout=timeout,
        )

        for spec in prompts:
            prompt_tokens_estimate = estimated_tokens(spec["prompt"])
            result = run_case(
                base,
                model,
                spec["prompt"],
                temperature=temperature,
                max_tokens=spec["max_tokens"],
                timeout=timeout,
            )
            result.update(
                benchmark=spec["name"],
                category=spec.get("category", "general"),
                prompt=spec["prompt"],
                prompt_est_tokens=prompt_tokens_estimate,
                max_tokens=spec["max_tokens"],
                output_preview=result["content"][:220].replace("\n", " ").strip(),
            )
            results.append(result)

        final_status = status_for_profile(profile_name, env)
        categories = sorted({item["category"] for item in results})
        return {
            "profile": profile_name,
            "display_name": env["DISPLAY_NAME"],
            "runtime": env.get("RUNTIME", "llama.cpp"),
            "request_model": env["REQUEST_MODEL"],
            "base_url": base,
            "pid": final_status["pid"],
            "rss_mb": final_status["rss_mb"],
            "warmup": warmup,
            "results": results,
            "averages": {
                "ttft_ms": mean_or_none([item["ttft_ms"] for item in results], 1),
                "total_ms": mean_or_none([item["total_ms"] for item in results], 1),
                "decode_tokens_per_sec": mean_or_none([item["decode_tokens_per_sec"] for item in results], 2),
                "e2e_tokens_per_sec": mean_or_none([item["e2e_tokens_per_sec"] for item in results], 2),
            },
            "category_averages": [summarize_category(results, category) for category in categories],
        }
    finally:
        if not keep_running:
            stop_profile(profile_name)



def write_outputs(report: dict[str, Any]) -> tuple[pathlib.Path, pathlib.Path]:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    json_path = OUTPUT_DIR / f"benchmark-{stamp}.json"
    md_path = OUTPUT_DIR / f"benchmark-{stamp}.md"
    latest_json = OUTPUT_DIR / "latest.json"
    latest_md = OUTPUT_DIR / "latest.md"
    json_path.write_text(json.dumps(report, indent=2) + "\n")

    lines = [
        "# Local Model Benchmark",
        "",
        f"- Generated: {report['generated_at']}",
        f"- Suite: `{report['suite']}`",
        f"- Temperature: `{report['temperature']}`",
        f"- Profiles: {', '.join(report['profiles'])}",
        f"- Isolation mode: `{'exclusive' if report['isolate'] else 'concurrent'}`",
        "- Output files: timestamped JSON and Markdown plus `latest.json` / `latest.md` in `Controller/benchmark-results/`",
        "",
        "## Summary",
        "",
        "| Profile | Runtime | Avg TTFT ms | Avg Decode tok/s | Avg E2E tok/s | RSS MB |",
        "| --- | --- | ---: | ---: | ---: | ---: |",
    ]

    for item in report["benchmarks"]:
        avg = item["averages"]
        lines.append(
            f"| {item['profile']} | {item['runtime']} | {avg['ttft_ms'] or 'n/a'} | {avg['decode_tokens_per_sec'] or 'n/a'} | {avg['e2e_tokens_per_sec'] or 'n/a'} | {item['rss_mb'] or 'n/a'} |"
        )

    for item in report["benchmarks"]:
        lines.extend(
            [
                "",
                f"## {item['display_name']}",
                "",
                f"- Profile: `{item['profile']}`",
                f"- Runtime: `{item['runtime']}`",
                f"- Request model: `{item['request_model']}`",
                f"- Base URL: `{item['base_url']}`",
                f"- PID: `{item['pid']}`",
                f"- RSS MB: `{item['rss_mb']}`",
                f"- Warmup TTFT: `{item['warmup']['ttft_ms'] or 'n/a'} ms`",
                f"- Warmup decode tok/s: `{item['warmup']['decode_tokens_per_sec'] or 'n/a'}`",
                f"- Warmup state: `{item['warmup'].get('error', 'ok')}`",
                "",
                "| Category | Cases | Avg TTFT ms | Avg Decode tok/s | Avg E2E tok/s |",
                "| --- | --- | ---: | ---: | ---: |",
            ]
        )
        for category in item.get("category_averages", []):
            lines.append(
                f"| {category['category']} | {', '.join(category['cases'])} | {category['ttft_ms'] or 'n/a'} | {category['decode_tokens_per_sec'] or 'n/a'} | {category['e2e_tokens_per_sec'] or 'n/a'} |"
            )
        lines.extend(
            [
                "",
                "| Benchmark | Category | Prompt est tokens | Max output | TTFT ms | Total ms | Decode tok/s | E2E tok/s | Token source | Preview | Error |",
                "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |",
            ]
        )
        for result in item["results"]:
            preview = result.get("output_preview", "").replace("|", "\\|")
            error = (result.get("error") or "").replace("|", "\\|")
            lines.append(
                f"| {result['benchmark']} | {result['category']} | {result['prompt_est_tokens']} | {result['max_tokens']} | {result['ttft_ms'] or 'n/a'} | {result['total_ms'] or 'n/a'} | {result['decode_tokens_per_sec'] or 'n/a'} | {result['e2e_tokens_per_sec'] or 'n/a'} | {result['usage_source']} | {preview} | {error} |"
            )

    md_path.write_text("\n".join(lines) + "\n")
    latest_json.write_text(json_path.read_text())
    latest_md.write_text(md_path.read_text())
    return json_path, md_path



def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Benchmark local model profiles")
    parser.add_argument("--profiles", nargs="+", default=["qwen35-a3b"], help="Profile names or 'all'")
    parser.add_argument("--suite", choices=sorted(PROMPT_SUITES), default="quick")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--keep-running", action="store_true")
    parser.add_argument("--allow-concurrent", action="store_true", help="Do not stop other running model profiles before benchmarking")
    return parser.parse_args()



def main() -> None:
    args = parse_args()
    profiles = load_profiles()
    selected = sorted(profiles) if args.profiles == ["all"] else args.profiles
    prompts = PROMPT_SUITES[args.suite]
    benchmarks = []
    initial_running = {item["profile"] for item in status_snapshot() if item["running"]}

    try:
        for name in selected:
            if name not in profiles:
                raise SystemExit(f"Unknown profile: {name}")
            print(f"[INFO] benchmarking {name}")
            benchmarks.append(
                benchmark_profile(
                    name,
                    profiles[name],
                    prompts,
                    temperature=args.temperature,
                    timeout=args.timeout,
                    keep_running=args.keep_running,
                    isolate=not args.allow_concurrent,
                )
            )
    finally:
        if not args.keep_running:
            final_running = {item["profile"] for item in status_snapshot() if item["running"]}
            for name in sorted(initial_running - final_running):
                start_profile(name)

    report = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "suite": args.suite,
        "temperature": args.temperature,
        "profiles": selected,
        "isolate": not args.allow_concurrent,
        "benchmarks": benchmarks,
    }
    json_path, md_path = write_outputs(report)
    print(f"json={json_path}")
    print(f"markdown={md_path}")


if __name__ == "__main__":
    main()

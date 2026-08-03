# CPU-PROFILE — status_payload + host_metrics_payload

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** PROFILE CPU (measurement only — **no optimizations**)  
**Mode:** LOCAL-ONLY (Mac loopback fixture; same class as BASELINE)  
**Captured:** 2026-08-03T18:26:29Z  
**Agent:** `RemoteAgent/model_switchboard_agent.py` v**1.1.2**  
**Prior:** DEFINE / fingerprint / BASELINE (status p95 ~47 ms N=20) / INSTRUMENT (`MSW_PERF_PROFILE` spans)

---

## Method

| Item | Value |
|------|-------|
| Fixture | N=**20** profile `.env` + 5 claim dirs under `MODEL_SWITCHBOARD_SCAN_ROOTS` (temp root) |
| Samples | **20** timed `status_payload()` + **20** warm `host_metrics_payload()` after 3 warmups |
| Flags | `MSW_PERF_PROFILE=1`, `MSW_PERF_JSONL=…/cpu-spans.jsonl` |
| Harness | [`profile_cpu.py`](./profile_cpu.py) (fixture patterns from [`bench_baseline.py`](./bench_baseline.py)) |
| Optional | `python -m cProfile` style via `cProfile.Profile` on **20** extra `status_payload` loops → [`cprofile.txt`](./cprofile.txt) |

**Evidence**

| File | Role |
|------|------|
| [`cpu-spans.jsonl`](./cpu-spans.jsonl) | 70 span lines (warmup + timed + sample + cProfile + host metrics) |
| [`cprofile.txt`](./cprofile.txt) | cumulative + tottime top functions for status loop |
| [`cpu-profile-summary.json`](./cpu-profile-summary.json) | machine summary (all JSONL rows incl. cProfile) |
| [`profile_cpu.py`](./profile_cpu.py) | reproducible driver |

Stage rankings below use the **timed N=20** subset only (exclude warmup/cProfile contamination for fair share %). Full-file aggregates are in `cpu-profile-summary.json` and agree on ordering.

Reproduce:

```bash
python3 Tests/artifacts/perf/20260803_remote-gateway-profiling/profile_cpu.py \
  --n 20 --warmup 3 --profiles 20 \
  --jsonl Tests/artifacts/perf/20260803_remote-gateway-profiling/cpu-spans.jsonl \
  --out Tests/artifacts/perf/20260803_remote-gateway-profiling/cpu-profile-summary.json \
  --cprofile Tests/artifacts/perf/20260803_remote-gateway-profiling/cprofile.txt \
  --cprofile-n 20
```

---

## Wall-clock check vs BASELINE

| Path | This PROFILE (n=20) | BASELINE (n=50, N=20) | Notes |
|------|--------------------:|----------------------:|-------|
| `status_payload` mean | **7.58 ms** (wall) / **7.49 ms** (span) | 9.88 ms | Same order; quieter load |
| `status_payload` p50 | **2.94 / 2.85 ms** | 2.83 ms | Body ~3 ms |
| `status_payload` p95 | **48.8 / 48.6 ms** | **47.3 ms** | Tail matches BASELINE |
| `host_metrics` warm p95 | **~0.01–0.06 ms** | 0.008 ms | Noise floor |
| `host_metrics` cold | **2.0–2.1 ms** | 2.22–2.33 ms | GPU path probe when uncached |
| Tags | 20 profiles → 25 statuses; 14 listeners; 5 claims; `n_live=0` | same fixture class | full_discovery=true |

No product behavior change; spans only.

---

## Ranked stages — `status_payload` (timed N=20)

Span duration: mean **7.49 ms**, p50 **2.85 ms**, p95 **48.6 ms**, max **49.4 ms**.

| Rank | Stage | Share of Σ stages | mean ms | p50 | p95 | max | Role |
|-----:|-------|------------------:|--------:|----:|----:|----:|------|
| **1** | **`list_listening_tcp`** | **61.1%** | 4.58 | **0.003** | **45.2** | **46.3** | OS listening inventory (lsof/ss/subprocess); **tail driver** |
| **2** | **`profile_statuses`** | **21.8%** | 1.63 | 1.57 | 1.84 | 2.03 | Per-profile `status()` + health probe (20 profiles) |
| **3** | **`scan_port_claim_directories`** | **10.5%** | 0.79 | 0.76 | 0.95 | 1.02 | Claim dir walk under scan roots |
| **4** | **`profiles_load`** | **5.4%** | 0.40 | 0.38 | 0.50 | 0.54 | Load/parse profile `.env` files |
| 5 | `merge_discovery` | 0.45% | 0.034 | 0.017 | 0.039 | 0.34 | Merge claims/listeners into statuses |
| 6 | `benchmark_status` | 0.40% | 0.030 | 0.027 | 0.042 | 0.05 | Benchmark block |
| 7 | `discover_live_model_endpoints` | 0.32% | 0.024 | 0.023 | 0.030 | 0.03 | Live endpoint discovery (0 live here) |

### Interpretation (status)

1. **Body vs tail split is almost entirely `list_listening_tcp`.**  
   - p50 stage ≈ **0.003 ms** (cache hit / fast path)  
   - p95 stage ≈ **45 ms** (uncached inventory: subprocess + poll)  
   - Two of 20 timed samples paid ~45–46 ms inventory; those alone produce the ~48 ms span p95.
2. **Steady work when inventory is cheap:** `profile_statuses` (~1.6 ms) + claim scan (~0.8 ms) + profiles_load (~0.4 ms) ≈ **2.8 ms** — matches p50 total.
3. Discovery merge / live endpoints / benchmark are **noise** on this fixture (`n_live=0`, no models).

Example high-tail JSONL row (timed):

```json
{"duration_ms":49.445,"stages_ms":{"list_listening_tcp":46.304,"profile_statuses":1.831,"scan_port_claim_directories":0.87,"profiles_load":0.357,...},"n_profiles":20,"n_statuses":25,"n_listeners":14,"full_discovery":true}
```

---

## Ranked stages — `host_metrics_payload`

### Warm (timed N=20)

Span: mean **0.010 ms**, p95 **0.012 ms** — effectively free on this Mac when GPU is unavailable and cache is warm.

| Rank | Stage | Share | mean ms | Notes |
|-----:|-------|------:|--------:|-------|
| 1 | `cpu` | 40.6% | 0.004 | `_sample_cpu_percent` |
| 2 | `memory` | 39.6% | 0.004 | `_sample_memory` |
| 3 | `assemble` | 19.8% | 0.002 | hostname + dict |
| 4 | `gpu` | **0%** | 0.000 | cache hit / no nvidia |

### Cold (1 sample)

| Stage | ms | Notes |
|-------|---:|-------|
| **`gpu`** | **1.94** | Dominant cold cost (probe path even when `gpu_source=unavailable`) |
| memory | 0.046 | |
| assemble | 0.022 | |
| cpu | 0.014 | |
| **total** | **2.03** | Aligns with BASELINE cold ~2.2 ms |

On this host: warm host metrics is not a CPU hotspot; cold is a one-shot GPU-source probe, not sustained load.

---

## cProfile corroboration (`status_payload` × 20)

[`cprofile.txt`](./cprofile.txt): **0.321 s** total for 20 calls (~16 ms/call mean under profiler overhead); 491k calls.

### By cumulative time (top agent-ish frames)

| cumtime (20 calls) | percall | Symbol |
|-------------------:|--------:|--------|
| 0.321 | 0.016 | `status_payload` |
| **0.191** | **0.010** | **`list_listening_tcp`** → `_list_listening_tcp_uncached` |
| 0.188 | 0.004 | `subprocess.run` (inventory helpers) |
| 0.114 | 0.003 | `process_command` / `cmdline` (PID cmdline resolve) |
| 0.108 | — | `subprocess.communicate` / `select.poll` wait |
| 0.068 | 0.000 | `AgentService.status` ×400 (20×20 profiles) |
| 0.047 | — | `_probe_health` (urllib connect fail-fast) |
| 0.037 | 0.002 | `scan_port_claim_directories` |
| 0.013 | 0.001 | `profiles.load` |

### By tottime (true CPU/wait sinks)

| tottime | ncalls | Symbol |
|--------:|-------:|--------|
| **0.102** | 88 | **`select.poll`** (subprocess I/O wait for inventory tools) |
| 0.037 | 185 | `posix.read` |
| 0.025 | 48 | `_posixsubprocess.fork_exec` |
| 0.014 | 400 | `socket.connect` (health probes to dead profile ports) |
| 0.009 | 1080 | `io.open` (env/claim files) |

**Cross-check:** span rank #1 `list_listening_tcp` ↔ cProfile `list_listening_tcp` + `subprocess` + `poll`. Span rank #2 `profile_statuses` ↔ `status` + `_probe_health` + `connect`. Span rank #3 claim scan ↔ `scan_port_claim_directories`. No disagreement.

---

## Hotspot summary (for later OPTIMIZE — not done here)

| Priority | Hotspot | Evidence | Character |
|---------:|---------|----------|-----------|
| **P0** | **`list_listening_tcp` / OS inventory** | 61% stage share; p95~45 ms; cProfile 0.191 s / 20; poll+fork | **Latency tail**, not steady Python CPU; caching already present (hit = ~0 ms) — misses dominate p95 |
| **P1** | **`profile_statuses` / health probes** | 22% stage share; ~1.6 ms steady; 400 probes / 20 calls | Steady work scales with N profiles; fail-fast connect |
| **P2** | **`scan_port_claim_directories`** | 11% stage share; ~0.8 ms | FS walk + claim parse |
| **P3** | **`profiles_load`** | 5% stage share; ~0.4 ms | `.env` parse |
| — | host_metrics warm | <0.02 ms | Not a candidate on Mac non-GPU |
| — | host_metrics cold `gpu` | ~2 ms once | Only matters for first poll / cache expiry |

**Not a pure-Python CPU bound problem on the p95 path:** wall tail is **subprocess + poll wait** inside listening inventory. Body is profile status assembly + claim scan.

---

## What was not done

- No code changes to agent production paths beyond existing INSTRUMENT spans.
- No optimizations, caching redesign, parallelization, or algorithm changes.
- No git commit.
- No py-spy (cProfile + MSW spans sufficient; py-spy optional if deeper sample needed).
- No remote Spark / multi-gateway client path.
- No nvidia cold GPU budget evaluation (`gpu_source=unavailable`).

---

## Next (outside this phase)

OPTIMIZE candidates should attack **inventory miss latency** and optionally **probe fan-out**, guided by these ranks — only after explicit OPTIMIZE mission. Re-run this harness with `MSW_PERF_JSONL` to compare stage shares before/after.

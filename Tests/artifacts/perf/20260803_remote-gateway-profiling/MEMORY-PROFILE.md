# MEMORY-PROFILE — agent peak RSS (status_payload + host_metrics)

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** PROFILE MEMORY (measurement only -- **no optimizations**)  
**Mode:** LOCAL-ONLY (Mac arm64 loopback fixture; same class as BASELINE / CPU-PROFILE)  
**Captured:** 2026-08-03T18:30:01Z  
**Agent:** `RemoteAgent/model_switchboard_agent.py` v**1.1.2**  
**Prior:** DEFINE / fingerprint / BASELINE / INSTRUMENT / CPU-PROFILE (`list_listening_tcp` dominates p95)

---

## Method

| Item | Value |
|------|-------|
| Fixture | N=**20** profile `.env` + 5 claim dirs under `MODEL_SWITCHBOARD_SCAN_ROOTS` (temp root) |
| Workload | warmup 3× each path; **20**× `status_payload()`; cold + warm **20**× `host_metrics_payload()` |
| Peak RSS | `resource.getrusage(RUSAGE_SELF).ru_maxrss` (Darwin unit = **bytes**) |
| Current RSS | `ps -o rss=` (KiB × 1024) sampled each loop iteration |
| Optional | `tracemalloc` during status loop only (Python heap high-water) |
| Corroboration | `/usr/bin/time -l` on same fixture class without tracemalloc |
| Harness | [`profile_memory.py`](./profile_memory.py) |

**Evidence**

| File | Role |
|------|------|
| [`memory-profile.json`](./memory-profile.json) | machine summary + timeline + budget check |
| [`profile_memory.py`](./profile_memory.py) | reproducible driver |
| [`time-l.err`](./time-l.err) | `/usr/bin/time -l` full resource report |

Reproduce:

```bash
python3 Tests/artifacts/perf/20260803_remote-gateway-profiling/profile_memory.py \
  --n 20 --warmup 3 --profiles 20 \
  --out Tests/artifacts/perf/20260803_remote-gateway-profiling/memory-profile.json
```

Corroborate (no in-process sampling):

```bash
/usr/bin/time -l python3 -c '... N=20 status + host_metrics fixture ...'
# see time-l.err for the captured command output
```

---

## Peak RSS result (primary)

| Metric | Value | Source |
|--------|------:|--------|
| **Scenario peak RSS** | **37.422 MB** (39 239 680 B) | `ru_maxrss` high-water after status+metrics |
| Peak current sampled (status loop) | 36.688 MB | `ps` max during 20× status |
| Peak current sampled (metrics loop) | 37.422 MB | `ps` during 20× host_metrics |
| Final current RSS | 37.422 MB | end of scenario |
| After agent import (baseline floor) | 31.578 MB | before fixture work |
| After warmup | 35.656 MB current / 35.953 MB peak | pre-timed loops |

### Timeline (selected)

| Stage | current MB | peak rusage MB |
|-------|----------:|---------------:|
| before_agent_import | 24.312 | 24.312 |
| after_agent_import | 31.578 | 31.578 |
| after_fixture | 31.594 | 31.594 |
| after_warmup | 35.656 | 35.953 |
| status_loop end | 36.688 | 36.688 |
| after_status (+tracemalloc stop) | 37.422 | 37.422 |
| after_metrics (flat) | 37.422 | 37.422 |

**Interpretation**

1. Most RSS is **process baseline + import** (~32 MB after loading the agent module).
2. Fixture + first status/host_metrics work adds ~4 MB (warmup → ~36 MB).
3. The N=20 status loop is **flat**: current RSS moves ~0.8 MB (35.9 → 36.7); no unbounded growth across iterations.
4. Warm `host_metrics_payload` adds **no further RSS** (flat 37.422 MB for all 20 samples).
5. Python-traced heap during status is tiny vs process RSS (see tracemalloc).

---

## Budget comparison (`BUDGETS.md`)

From consolidated peak RSS and scenario C:

| Metric ID | Budget | Soft investigate | Measured | Status |
|-----------|-------:|-----------------:|---------:|--------|
| `A.agent_rss_peak` | **≤ 80 MB** | > 50 MB | **37.422 MB** | **PASS** |
| `B.agent_rss_peak` | **≤ 80 MB** | > 50 MB | **37.422 MB** | **PASS** |
| `C.agent_rss_peak` | **≤ 80 MB** | > 50 MB | **37.422 MB** | **PASS** |

| Check | Value |
|-------|------:|
| Headroom vs hard 80 MB | **42.578 MB** (~53% of budget free) |
| vs soft 50 MB | **within_soft** (37.4 < 50) |
| Prior BUDGETS note | ~32 MB sample 2026-08-01 |
| Delta vs prior sample | ~+5.4 MB (same order; local fixture + Python 3.14 + tracemalloc sampling) |

**Verdict:** Agent process peak RSS under status+metrics load (N=20 profiles) is **comfortably under** the hard ≤ 80 MB contract. Soft investigate threshold (50 MB) also not crossed.

Mac app RSS (`A.mac_rss_peak` / `B.mac_rss_peak` ≤ 250 MB) is **out of scope** for this agent-only pass.

---

## `/usr/bin/time -l` corroboration

Same fixture class (N=20 status + N=20 host_metrics), **no** tracemalloc / in-loop `ps`:

| Field | Bytes | MB |
|-------|------:|---:|
| maximum resident set size | 35 028 992 | **33.406** |
| peak memory footprint | 21 479 904 | 20.485 |

Both corroboration and instrumented harness **PASS** vs 80 MB. Instrumented peak is ~4 MB higher (tracemalloc + sampling overhead), which is expected.

Evidence: [`time-l.err`](./time-l.err).

---

## Optional tracemalloc (status loop only)

| Item | Value |
|------|------:|
| Peak traced | **0.659 MB** (691 049 B) |
| Current at stop | 0.356 MB |
| Share of process RSS | ~1.8% of 37 MB |

Top Python allocations (by size) are dominated by stdlib **`pathlib`** path construction, then small agent-line hits (`model_switchboard_agent.py` ~18 KB @ L2005, ~7 KB @ L1923). No multi-MB Python heap leak signal on this fixture.

Full top-15 list: [`memory-profile.json`](./memory-profile.json) → `tracemalloc.top_lineno`.

---

## Wall-clock note (not a latency gate)

This run recorded status p50/p95 ~102 / 107 ms while tracemalloc was active. That is **not** comparable to BASELINE/CPU-PROFILE (~3–50 ms). Use:

- [`BASELINE.md`](./BASELINE.md) / [`CPU-PROFILE.md`](./CPU-PROFILE.md) for latency
- this file for RSS only

Warm host_metrics remains ~0.08 ms mean (noise floor; GPU unavailable).

Tags: 25 statuses, 0 live GPUs, `gpu_source=unavailable`, host_metrics cold ~2.5 ms.

---

## Relation to CPU profile finding

CPU-PROFILE showed `list_listening_tcp` dominates **latency** p95 via subprocess inventory. Memory profile shows that path does **not** produce large RSS growth: process stays ~37 MB peak with flat per-iteration current samples. Latency hot path ≠ memory growth on this fixture.

---

## Non-goals / not done this pass

- No production code changes
- No commits
- No Mac app RSS measurement
- No remote Linux/spark re-baseline (local Darwin only)
- No sustained 5 min soak RSS (steady-state N=20 loops only)

---

## Summary

| Gate | Result |
|------|--------|
| Agent peak RSS ≤ 80 MB | **PASS** at **37.422 MB** (rusage) / **33.4 MB** (`time -l`) |
| Soft investigate > 50 MB | not triggered |
| Growth across N=20 status | none material (~0.8 MB then flat) |
| host_metrics RSS | no incremental growth |

**DONE** -- evidence in `memory-profile.json` + `time-l.err` + this document.
)

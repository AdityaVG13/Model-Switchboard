# UPDATED OPPORTUNITY-MATRIX — after passes 1–3

**Run ID:** `20260803_remote-gateway-optimization` / pass-04 rescore  
**Date:** 2026-08-03  
**Source profile:** `Tests/artifacts/perf/20260803_remote-gateway-profiling/`  
**Rule:** Score = Impact × Confidence / Effort (1–5 each). **Ready only if Score ≥ 2.0.**

**Convergence:** See [`pass-04-rescore/CONVERGENCE.md`](./pass-04-rescore/CONVERGENCE.md).  
**Decision this pass:** **ZERO-CHANGE** -- no residual lever ≥ 2.0.

---

## Disposition of original ready queue

| Opportunity | Original I×C/E | Disposition | Residual score |
|-------------|----------------|-------------|----------------|
| Extend listening-TCP inventory cache / TTL | **10.0** (4×5/2) | **SHIPPED** pass-01: `LISTENING_TCP_CACHE_TTL_SECONDS` 0.075 → **2.0** | n/a (done) |
| Parallelize `RemoteHostMetricsMonitor.pollOnce` | **6.0** (4×3/2) | **SHIPPED** pass-02: concurrent `withTaskGroup` fan-out | n/a (done) |
| Reduce `profile_statuses` probe cost | **2.67** (2×4/3) | **ZERO-CHANGE** pass-03; isomorphic port-probe skip already present; health connect required for ready | **≤ 1.33** |

---

## Residual opportunity matrix (post cache + parallel)

| Opportunity | Impact | Confidence | Effort | Score | Hypothesis / evidence | Lever class (if ever) | Ready (≥2.0)? |
|-------------|-------:|-----------:|-------:|------:|----------------------|------------------------|:-------------:|
| Soft-stale inventory + background refresh | 2 | 3 | 4 | **1.5** | Spaced 10 s UI still one miss/tick after TTL=2.0; pass-01 out-of-scope soft-stale; budgets PASS | Dual soft/hard TTL + async refill while serving last snapshot | **no** |
| `scan_port_claim_directories` (~0.8 ms) | 1 | 5 | 3 | **1.67** | HOTSPOTS rank 5; CPU-PROFILE ~11% on hit path; H8 rejects hang | Claim-root cache / shallower walk | **no** |
| `profiles_load` (~0.4 ms) | 1 | 5 | 3 | **1.67** | HOTSPOTS rank 6; body floor | Profile parse cache | **no** |
| Parallel N× `_probe_health` | 1 | 3 | 3 | **1.0** | ~1.6 ms @ N=20; green N=50; pass-03 closed skip | Concurrent fail-fast health (keep ready semantics) | **no** |
| Inventory-gated skip of `_probe_health` when port down | 2 | 2 | 3 | **≤1.33** | Pass-03: false-negative ready within TTL | *(rejected -- semantic change)* | **no** |
| Non-lsof inventory path (macOS) | 2 | 2 | 4 | **1.0** | No `/proc`/`ss` on profile host | Alternate LISTEN source | **no** |
| Warm `host_metrics` | 1 | 5 | 3 | **1.67** | H3 reject | *(none -- floor)* | **no** |
| Agent RSS | 1 | 5 | 3 | **1.67** | H4 reject | *(none -- under budget)* | **no** |
| Adaptive poll / cancel-in-flight | 1 | 2 | 3 | **0.67** | Parallel already addresses N×RTT; multi-remote wall N/E | Cadence policy | **no** |
| Mac UI SwiftUI body | — | 1 | — | **N/E** | Not instrumented this campaign | *(out of package)* | **no** |

### Ready queue (score ≥ 2.0)

**Empty.**

### Explicitly not ready (score &lt; 2.0)

All residual rows above. **Do not open a new optimization pass** on these without new measurements that raise Impact or Confidence.

---

## Dimension rubric (unchanged)

| Dimension | Meaning |
|-----------|---------|
| **Impact** | Expected product latency/cadence/memory gain if the lever works (1 = noise / already green; 5 = dominates user-visible or cadence breach) |
| **Confidence** | Strength of measured evidence (1 = guess; 5 = multi-artifact + clear code path) |
| **Effort** | Relative engineering + verification cost (1 = tiny; 5 = cross-cutting / golden risk) |
| **Score** | I×C/E |

### Impact honesty after passes 1–3

| Residual | Why this Impact |
|----------|-----------------|
| Soft-stale bg refresh | **2** -- remaining spaced-poll miss is real (~45–100 ms) but cadence is ~10 s and hard status budget is 1000 ms; TTL=2.0 already covers bursts / multi-client |
| claim scan / profiles_load | **1** -- sub-ms to ~1 ms body; share % inflated only after inventory hit |
| Parallel health | **1** -- absolute steady cost already tiny vs budgets |
| host_metrics / RSS | **1** -- reject evidence from H3/H4 |

### Confidence honesty

| Residual | Why |
|----------|-----|
| Soft-stale | **3** -- design clear, not prototyped; lag races unmeasured |
| claim / load / host / RSS | **5** -- measured and/or reject-strong |
| Parallel health | **3** -- stage known; concurrency side effects not measured |
| SwiftUI | **1** -- no campaign data |

### Effort honesty

| Residual | Why |
|----------|-----|
| Soft-stale | **4** -- dual threshold + background + clear coalescing |
| claim / load / health parallel | **3** -- correctness-adjacent or discovery semantics |
| Rejected floors | **3** -- cost of a wasted pass |

---

## Scenario map (updated)

| Scenario | What still matters |
|----------|--------------------|
| **A** `multi_gateway_status_refresh` | Inventory miss on spacing &gt; TTL only; soft-stale optional polish (score &lt; 2.0). Parallel poll if metrics co-run -- **shipped**. |
| **B** `remote_host_metrics_poll` | Sequential wall **shipped** concurrent. Re-baseline multi-remote when remotes exist (measurement, not new lever by default). |
| **C** `agent_status_payload_many_profiles` | Body = profile_statuses + claim + load (~2.8 ms @ N=20 hit). No ready lever. |

---

## Pass log

| Pass | Artifact | Result |
|-----:|----------|--------|
| 01 | [`pass-01-inventory-cache/`](./pass-01-inventory-cache/) | PRODUCTIVE -- TTL 2.0 s |
| 02 | [`pass-02-parallel-poll/`](./pass-02-parallel-poll/) | PRODUCTIVE -- concurrent pollOnce |
| 03 | [`pass-03-profile-statuses/ZERO-CHANGE.md`](./pass-03-profile-statuses/ZERO-CHANGE.md) | ZERO-CHANGE -- rescore ≤ 1.33 |
| 04 | [`pass-04-rescore/CONVERGENCE.md`](./pass-04-rescore/CONVERGENCE.md) | **CONVERGENCE** -- max residual **1.67** |

---

## Status

**DONE** -- Matrix re-scored after productive cache + parallel and profile_statuses zero-change. **Ready queue empty.** **ZERO-CHANGE** this pass. No production edits. No commit.

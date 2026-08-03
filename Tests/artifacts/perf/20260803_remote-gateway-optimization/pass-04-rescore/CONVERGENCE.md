# Pass 04 -- Rescore / CONVERGENCE

**Decision: ZERO-CHANGE** (no production code edited this pass).

**Date:** 2026-08-03  
**Campaign:** `20260803_remote-gateway-optimization`  
**Source profile package:** `Tests/artifacts/perf/20260803_remote-gateway-profiling/`  
**Prior optimization passes:**

| Pass | Lever | Outcome | Prior score |
|-----:|-------|---------|------------:|
| **01** | Inventory TTL `0.075` → `2.0` s | **PRODUCTIVE** | **10.0** |
| **02** | Parallel `RemoteHostMetricsMonitor.pollOnce` | **PRODUCTIVE** | **6.0** |
| **03** | `profile_statuses` / health-probe amortization | **ZERO-CHANGE** (rescore ≤ **1.33**) | was **2.67** |

**Rule:** Optimize only when Score = Impact × Confidence / Effort ≥ **2.0**.

---

## Verdict

**Nothing remains with Score ≥ 2.0 after passes 1–3.**

All ready-queue rows from the original opportunity matrix are either **shipped** or **honestly rescored below threshold**. Residual HOTSPOT ranks are secondary body costs already far under budgets, or optional polish with effort that does not clear the gate.

**CONVERGED** for this remote-gateway optimization loop. Stop optimizing product code until new profile evidence (multi-remote wall, larger N, remote RTT, Mac UI instrumentation) changes scores.

---

## Residual matrix (post cache + parallel)

| Opportunity | I | C | E | Score | Ready? | Notes |
|-------------|--:|--:|--:|------:|:------:|-------|
| Soft-stale inventory + background refresh | 2 | 3 | 4 | **1.5** | **no** | Spaced 10 s UI still pays one miss/tick after TTL=2.0; budgets already PASS ≫20×; dual soft/hard + bg path is real effort; pass-01 accepted hard TTL as lag policy |
| Further inventory path (avoid `lsof` on macOS) | 2 | 2 | 4 | **1.0** | **no** | Host has no `/proc`, no `ss`; uncached path remains lsof; no alternate measured |
| Parallel N× `_probe_health` inside `profile_statuses` | 1 | 3 | 3 | **1.0** | **no** | ~1.6 ms @ N=20; green at N=50; correctness-adjacent; pass-03 closed isomorphic skip |
| `profile_statuses` inventory-gated health skip | 2 | 2 | 3 | **≤1.33** | **no** | Pass-03: preferred port-probe skip already shipped; remaining connect is ready truth |
| `scan_port_claim_directories` | 1 | 5 | 3 | **1.67** | **no** | ~**0.8 ms** mean (N=20); H8 rejects hang; share ~11% only because inventory is cheap on hit |
| `profiles_load` | 1 | 5 | 3 | **1.67** | **no** | ~**0.4 ms** mean; busy parse floor |
| Warm `host_metrics` agent path | 1 | 5 | 3 | **1.67** | **no** | H3 reject; warm p95 ~0.01 ms |
| Agent RSS | 1 | 5 | 3 | **1.67** | **no** | H4 reject; 37 MB ≪ 80 MB |
| Adaptive poll interval / cancel-in-flight after parallel | 1 | 2 | 3 | **0.67** | **no** | Parallel already addresses N×RTT wall; multi-remote still N/E |
| Mac UI SwiftUI body cost | — | 1 | — | **N/E** | **no** | Out of agent profile package; no body instrumentation this campaign |

**Max residual Score among scored levers: 1.67** (`scan_port_claim_directories` / `profiles_load` / warm host_metrics / RSS ties). **None ≥ 2.0.**

---

## Dimension honesty (key residuals)

### Soft-stale background refresh (best remaining inventory idea)

| Dim | Value | Why |
|-----|------:|-----|
| Impact | **2** | Hides request-path lsof on spaced polls (serve last snapshot, refresh async). Absolute win ~45–100 ms per 10 s UI tick -- still noise vs 1000 ms status budget and vs post-TTL multi-client hits already free. |
| Confidence | **3** | Mechanism clear; **not** measured as a prototype; lag/race/`clear_listening_tcp_cache` semantics unproven. |
| Effort | **4** | Dual soft/hard TTL, bg thread or async refresh, coalescing, tests for stampede + clear mid-refresh. Pass-01 deliberately chose single hard TTL. |
| Score | **1.5** | Below 2.0 |

### `scan_port_claim_directories` (~0.8 ms)

| Dim | Value | Why |
|-----|------:|-----|
| Impact | **1** | Secondary busy FS; not tail driver; budgets green; H8 rejects deep-walk hang on this fixture |
| Confidence | **5** | Stage ranks + cProfile agree |
| Effort | **3** | Claim-root policy / caching touches correctness of discovery |
| Score | **1.67** | Below 2.0 |

### Mac UI SwiftUI

Out of package unless a clear measured body cost appears. LOCAL profiling was agent on-host + model of Mac pollOnce (pass-02 shipped concurrency). No SwiftUI Instruments / body-time baseline → do not invent a ready lever.

---

## Post-ship state of original ready queue

| Original row | Original score | After |
|--------------|---------------:|-------|
| Listening-TCP inventory cache / TTL | **10.0** | **Shipped** pass-01 (`LISTENING_TCP_CACHE_TTL_SECONDS = 2.0`) |
| Parallelize `pollOnce` | **6.0** | **Shipped** pass-02 (`withTaskGroup` fan-out) |
| `profile_statuses` probe cost | **2.67** → **≤1.33** | **ZERO-CHANGE** pass-03 (isomorphic skip already present) |

---

## Budgets still green (LOCAL evaluable, pre-pass profile anchors)

| Metric | Budget | Anchor | Notes |
|--------|-------:|--------|-------|
| `C.status_payload_p95` N=20 | ≤ 1000 ms | **47.3 ms** | Even more hit-friendly after TTL 2.0 for burst paths |
| `C.status_payload_mean` stretch | ≤ 50 ms | **9.9 ms** | Body ~2.8 ms when inventory hits |
| `B.agent_host_metrics` warm | ≤ 200 ms | **~0.01 ms** | Floor |
| Agent RSS | ≤ 80 MB | **37.4 MB** | Not a hotspot |
| `B.poll_once` multi-remote wall | ≤ 1000 ms (N=2 model) | model only | Pass-02 removes sequential N×RTT; multi-remote wall still N/E for re-baseline |

---

## Explicit non-actions this pass

- No production code changes (agent or Mac app)
- No further TTL / soft-stale / claim-scan / health-parallel work
- No commit
- No new microbench required for convergence declaration (rescore is interpretive from HOTSPOTS + pass 01–03 artifacts)

---

## Evidence anchors

- Profile: `../20260803_remote-gateway-profiling/HOTSPOTS.md`, `OPPORTUNITY-MATRIX.md`, `CPU-PROFILE.md`, `HYPOTHESIS-LEDGER.md` (H1–H9)
- Pass 01: `../pass-01-inventory-cache/ISOMORPHISM.md`, `MEASURE.md`
- Pass 02: `../pass-02-parallel-poll/ISOMORPHISM.md`
- Pass 03: `../pass-03-profile-statuses/ZERO-CHANGE.md`
- Updated matrix: [`../UPDATED-OPPORTUNITY-MATRIX.md`](../UPDATED-OPPORTUNITY-MATRIX.md)

---

## Status

**DONE -- CONVERGENCE.** Max residual score **1.67** &lt; **2.0**. **ZERO-CHANGE.** No product code. No commit.

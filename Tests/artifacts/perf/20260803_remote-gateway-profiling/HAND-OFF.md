# HAND-OFF — extreme-software-optimization

**From skill:** `profiling-software-performance`  
**To skill:** `extreme-software-optimization`  
**Run ID:** `20260803_remote-gateway-profiling`  
**Package root:** `Tests/artifacts/perf/20260803_remote-gateway-profiling/`  
**Date:** 2026-08-03  
**Mode:** LOCAL-ONLY agent fixture (Mac M5 Max loopback); multi-remote RTT / Mac UI E2E largely N/E  

---

## Explicit stop line

**This skill stops here. Do not implement optimizations in this pass.**

Profiling, interpretation, hypothesis scoring, and opportunity ranking only.  
No production code changes. No commit from this hand-off.

---

## Scenario IDs

| ID | Name | What it covers |
|----|------|----------------|
| **A** | `multi_gateway_status_refresh` | Mac GatewayHub multi-store status refresh (local + N remotes); 10s activeRuntime cadence |
| **B** | `remote_host_metrics_poll` | Mac `RemoteHostMetricsMonitor` sequential `pollOnce` at 3s + agent `host_metrics_payload` |
| **C** | `agent_status_payload_many_profiles` | On-host `status_payload()` cost vs profile count (N=5/20/50 ladder) |

Definitions: [`SCENARIO.md`](./SCENARIO.md)  
Budgets / SLOs: [`BUDGETS.md`](./BUDGETS.md)

---

## Baseline fingerprint pointer

| Item | Path / value |
|------|----------------|
| **Fingerprint** | [`fingerprint.json`](./fingerprint.json) |
| Host | Apple M5 Max, 18 cores, 48 GB, macOS 26.5, AC power |
| Branch | `feature/remote-gateways` |
| Git (ENVIRONMENT) | `a25d02e` |
| Git (BASELINE measure) | `7d2e5da` (re-fingerprint if comparing build/RSS artifacts) |
| Baseline narrative | [`BASELINE.md`](./BASELINE.md) |
| Baseline numbers | `baseline_inprocess.json`, `baseline-status-payload.json`, `baseline-host-metrics.json`, `baseline-derived-http-*.json`, `baseline_N50.json` |
| Campaign limit | **LOCAL-ONLY** — no Spark/tailnet remote this run; remote client RTT and multi-gateway E2E are N/E |

---

## Top 5 hotspots (with evidence)

| Rank | Hotspot | Evidence summary | Primary refs |
|-----:|---------|------------------|--------------|
| **1** | `list_listening_tcp` cache **miss** → `lsof` (macOS) | ~**61%** of `status_payload` stage Σ; stage p95 **~45 ms** vs warm TTL hit **~0.001 ms**; forced cold mean **~57 ms**; cProfile `list_listening_tcp` **0.191 s** / 0.321 s (20×); dominant tottime `select.poll` **0.102 s** | [`HOTSPOTS.md`](./HOTSPOTS.md) rank 1; [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json); [`cprofile.txt`](./cprofile.txt); [`CPU-PROFILE.md`](./CPU-PROFILE.md); H1 **supports** |
| **2** | `profile_statuses` (N × status + fail-fast `_probe_health`) | ~**22%** stages; mean **~1.6 ms** at N=20; steady-state **body** when inventory hits TTL; scales ~O(N) (p50 1.36 → 2.83 → 5.77 ms for N=5/20/50) | [`HOTSPOTS.md`](./HOTSPOTS.md) rank 2; [`cpu-profile-summary.json`](./cpu-profile-summary.json); H9 **supports** |
| **3** | `RemoteHostMetricsMonitor.pollOnce` — **sequential** remotes @ **3 s** | Wall model `N × (RTT + server)`; N=10 @ ~200 ms RTT ≈ **2.0 s** (tight vs 3 s / 25% slack); N≥10 @ ~500 ms **overruns** interval. Multi-remote wall **unmeasured** this campaign | [`HOTSPOTS.md`](./HOTSPOTS.md) rank 3; [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md); H5 **supports** (model); `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift` |
| **4** | `host_metrics` **cold** GPU probe path | Cold total **~2.1–2.3 ms** (gpu stage ~1.9 ms even when `gpu_source=unavailable`); **warm p95 ~0.008 ms** (floor). Not a sustained bottleneck | [`HOTSPOTS.md`](./HOTSPOTS.md) rank 4; [`BASELINE.md`](./BASELINE.md) B; H3 **rejects** warm as UI bottleneck; H6 **supports** cold-only |
| **5** | `scan_port_claim_directories` | ~**11%** stages; mean **~0.8 ms** (N=20, 5 claim dirs) — secondary busy FS, not tail driver | [`HOTSPOTS.md`](./HOTSPOTS.md) rank 5; [`CPU-PROFILE.md`](./CPU-PROFILE.md) |

**Explicit non-hotspots (do not optimize first):**

| Item | Why |
|------|-----|
| Agent RSS | Peak **37.4 MB** rusage / **33.4 MB** `time -l` vs hard **≤ 80 MB**; flat under status + metrics loops — H4 **rejects** |
| Warm `host_metrics_payload` | Already floor; HTTP loopback p95 **~6.2 ms** vs budget **200 ms** |

Full ranking + scaling law: [`HOTSPOTS.md`](./HOTSPOTS.md)  
Hypothesis verdicts: [`HYPOTHESIS-LEDGER.md`](./HYPOTHESIS-LEDGER.md)

---

## Opportunity Matrix (summary)

Score = **Impact × Confidence / Effort** (each 1–5).  
**Ready to optimize** only if **Score ≥ 2.0**.  
Lever class only -- **not** the fix.

| Opportunity | Impact (1–5) | Confidence (1–5) | Effort (1–5) | Score (I×C/E) | Hypothesis | Suggested lever class ONLY | Ready? |
|-------------|-------------:|-----------------:|-------------:|--------------:|------------|----------------------------|:------:|
| Extend or smarter listening-TCP inventory cache / avoid `lsof` on warm path when possible | 4 | 5 | 2 | **10.0** | H1 supports; H7 bimodal TTL hit/miss | **Cache policy / inventory snapshot reuse** (TTL, hit-rate, path selection) -- not a rewrite of discovery semantics | **yes** |
| Parallelize `RemoteHostMetricsMonitor.pollOnce` across remotes (value only when **N×RTT** large) | 4 | 3 | 2 | **6.0** | H5 supports (model; multi-remote wall N/E) | **Concurrency / independent fan-out** of remote `fetchHostMetrics` (preserve interval + error isolation) | **yes** |
| Reduce `status_payload` probe cost (`profile_statuses`) when profile **N** is large | 2 | 4 | 3 | **2.67** | H9 supports body O(N); H2 rejects super-linear p95 | **Probe amortization / batch or skip redundant health connects** on cached inventory path | **yes** |
| Optimize warm `host_metrics` agent path | 1 | 5 | 3 | **1.67** | H3 rejects | *(none -- already floor)* | **no** |
| Optimize agent process RSS | 1 | 5 | 3 | **1.67** | H4 rejects | *(none -- under budget, no leak signal)* | **no** |

Table form: [`OPPORTUNITY-MATRIX.md`](./OPPORTUNITY-MATRIX.md)

### Scoring notes (honesty)

- **Inventory cache (10.0):** Dominant measured p95 driver on this Mac (lsof miss ~45–57 ms). Hard status budgets already **PASS** (p95 **47.3 ms** ≪ **1000 ms**); opportunity is tail quality / miss rate under spaced polls (activeRuntime 10 s always exceeds 75 ms TTL), not a budget breach.
- **Parallel pollOnce (6.0):** Product cadence risk at large N / high RTT is real in code + math; **Confidence 3** because this campaign never measured multi-remote `pollOnce`. Do not ship without re-baseline of B metrics when remotes exist. Low value for N=1–2 LAN.
- **profile_statuses (2.67):** Real rank-2 body cost; already green at N=20/50. Worth a lever only if profile counts grow or live probes stop fail-fasting.
- **host_metrics warm / RSS:** Explicitly **not** ready (score &lt; 2.0). Do not spend an optimization pass here first.

---

## LOCAL budget snapshot (evaluable)

| Metric | Budget | Measured | Verdict |
|--------|-------:|---------:|---------|
| `C.status_payload_p95` N=20 | ≤ 1000 ms | **47.3 ms** | PASS |
| `C.status_payload_mean` stretch | ≤ 50 ms | **9.9 ms** | PASS stretch |
| `C.scaling_ratio` p95(20)/p95(5) | ≤ 5.0 | **1.83** | PASS |
| `B.agent_host_metrics_p95` warm | ≤ 200 ms | **~0.01 ms** / HTTP **6.2 ms** | PASS |
| `A/B/C.agent_rss_peak` | ≤ 80 MB | **37.4 MB** | PASS |
| `B.poll_once_p95` N=2 / remote RTT / A.e2e | various | — | **N/E** |

---

## Constraints for the next skill

1. One lever at a time; prove golden + budget after each change (`BUDGETS.md` golden gates).
2. Prefer **ready** rows (score ≥ 2.0); order by score unless product priority differs.
3. Re-fingerprint / re-baseline after any lever that can move status or metrics walls.
4. When Spark (or any remote) is available: fill N/E rows before claiming multi-gateway wins.
5. Do not treat LOCAL fixture means as comparable to prior Spark pre-opt ~303 ms inventory class.

---

## Evidence index (minimum read set)

| Doc | Role |
|-----|------|
| [`SCENARIO.md`](./SCENARIO.md) | A/B/C definitions |
| [`BUDGETS.md`](./BUDGETS.md) | SLOs, cadences, golden gates |
| [`fingerprint.json`](./fingerprint.json) | Host fingerprint |
| [`BASELINE.md`](./BASELINE.md) | Walls + budget map |
| [`HOTSPOTS.md`](./HOTSPOTS.md) | Ranked attribution |
| [`HYPOTHESIS-LEDGER.md`](./HYPOTHESIS-LEDGER.md) | supports/rejects |
| [`CPU-PROFILE.md`](./CPU-PROFILE.md) / [`cprofile.txt`](./cprofile.txt) | Stage + tottime |
| [`MEMORY-PROFILE.md`](./MEMORY-PROFILE.md) | RSS PASS |
| [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md) | Wait vs busy; sequential poll model |
| [`OPPORTUNITY-MATRIX.md`](./OPPORTUNITY-MATRIX.md) | Full matrix table |

---

## Status

**DONE** -- Opportunity Matrix inputs finalized; hand-off package complete for `extreme-software-optimization`.

**This skill stops here. Do not implement optimizations in this pass.**

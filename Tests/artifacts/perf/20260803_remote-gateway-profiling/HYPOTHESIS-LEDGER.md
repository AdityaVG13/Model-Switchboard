# HYPOTHESIS-LEDGER — remote-gateway profiling

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** HYPOTHESIS (evaluate only -- **no optimizations**)  
**Mode:** LOCAL-ONLY (Mac M5 Max loopback fixture) + prior Spark notes where cited  
**Date:** 2026-08-03  
**Prior evidence:** [`HOTSPOTS.md`](./HOTSPOTS.md), [`BASELINE.md`](./BASELINE.md), [`CPU-PROFILE.md`](./CPU-PROFILE.md), [`MEMORY-PROFILE.md`](./MEMORY-PROFILE.md), [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md), [`VARIANCE.md`](./VARIANCE.md)

Verdicts: **supports** | **rejects** | **inconclusive**. Each row is one line of evidence + path.

---

## Named hypotheses (required set)

| # | Hypothesis | Verdict | Evidence (1 line) | Evidence path |
|---|------------|---------|-------------------|---------------|
| **H1** | `status_payload` p95 is dominated by inventory subprocess (`lsof`/`ss`) cache miss | **supports** | Stage `list_listening_tcp` ~61% of Σ; stage p50 **0.003 ms** (TTL hit) vs p95 **~45 ms** (miss); cProfile `list_listening_tcp` **0.191 s** / 0.321 s total for 20×; forced cold mean **~57 ms**; dominant tottime `select.poll` **0.102 s** (wait-ish `lsof`) | [`HOTSPOTS.md`](./HOTSPOTS.md) rank 1; [`CPU-PROFILE.md`](./CPU-PROFILE.md); [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json); [`cprofile.txt`](./cprofile.txt) |
| **H2** | Profile count N drives **super-linear** p95 | **rejects** | p95(20)/p95(5)=**1.83** (≤ budget 5.0); p95(50)/p95(5)=**2.90**; mean scales ~linear (2.03× / 4.94×); p95 sub-linear because **shared O(1) inventory miss** sets the tail, not N× work | [`BASELINE.md`](./BASELINE.md) Scenario C; [`baseline-status-payload.json`](./baseline-status-payload.json); [`HOTSPOTS.md`](./HOTSPOTS.md) scaling law |
| **H3** | `host_metrics` is a multi-gateway UI bottleneck **today (local)** | **rejects** | Warm on-host p95 **~0.008 ms** / HTTP loopback p95 **~6.2 ms** -- free vs 200 ms budget; cold non-GPU **~2.3 ms**; multi-remote `pollOnce` wall **N/E** this campaign (architecture risk is sequential RTT, not agent host_metrics CPU) | [`BASELINE.md`](./BASELINE.md) B; [`baseline-host-metrics.json`](./baseline-host-metrics.json); [`HOTSPOTS.md`](./HOTSPOTS.md) rank 4; [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md) §b |
| **H4** | Agent memory leak / high RSS under status loops | **rejects** | Peak RSS **37.422 MB** (rusage) / **33.4 MB** (`time -l`) vs hard **≤ 80 MB**; status loop flat (~0.8 MB then stable); host_metrics adds **no** further RSS; soft 50 MB not crossed | [`MEMORY-PROFILE.md`](./MEMORY-PROFILE.md); [`memory-profile.json`](./memory-profile.json); [`time-l.err`](./time-l.err); [`BUDGETS.md`](./BUDGETS.md) `A/B/C.agent_rss_peak` |
| **H5** | Sequential Mac `pollOnce` will breach **3 s** interval for large N at high RTT | **supports** (model; multi-remote unmeasured) | Code is **strict sequential** over enabled remotes at **3 s**; wall model `N × (R + server)`; N=10 @ ~200 ms RTT ≈ **2.0 s** (tight vs 3 s / 25% slack); N≥10 @ ~500 ms ≈ **5 s** overruns interval -- product risk, not observed multi-remote wall this LOCAL campaign | [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md) §b–c; [`HOTSPOTS.md`](./HOTSPOTS.md) rank 3; `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift`; [`BUDGETS.md`](./BUDGETS.md) `B.poll_once_p95` / `B.poll_cycle_slack` |
| **H6** | GPU / nvidia path is **cold-path-only** cost on this Mac fingerprint | **supports** | `gpu_source=unavailable`; warm `gpu` stage **0%** share / ~0 ms; cold total **~2.1–2.3 ms** with `gpu` stage **~1.9 ms** (probe path, no nvidia-smi); warm path amortized by **2.0 s** `_GPU_METRICS_TTL`; real nvidia cold budget **N/E** here | [`CPU-PROFILE.md`](./CPU-PROFILE.md) host_metrics cold/warm; [`BASELINE.md`](./BASELINE.md) B; [`fingerprint.json`](./fingerprint.json); agent `_GPU_METRICS_TTL_SECONDS` |

---

## Additional hypotheses (warranted by evidence)

| # | Hypothesis | Verdict | Evidence (1 line) | Evidence path |
|---|------------|---------|-------------------|---------------|
| **H7** | Within-run status latency is **bimodal** (inventory TTL hit vs miss), not measurement noise | **supports** | Hyperfine `/api/status` times cluster ~**9 ms** (hit-ish) vs ~**55–100+ ms** (miss); p95/p50 ≈ **10×**; in-process N=20 p50 **2.83** vs p95 **47.3** ms (same split) | [`baseline-derived-http-status.json`](./baseline-derived-http-status.json) `times_ms`; [`baseline-status-payload.json`](./baseline-status-payload.json); [`VARIANCE.md`](./VARIANCE.md) |
| **H8** | Deep `$HOME` / claim-folder walk still dominates status wall | **rejects** | `scan_port_claim_directories` ~**11%** / mean **~0.8 ms** (N=20); residual stages &lt;1.2%; no multi-second hang on this fixture (prior hang was pre-shallow-home fix) | [`CPU-PROFILE.md`](./CPU-PROFILE.md) ranks 3/5–7; [`HOTSPOTS.md`](./HOTSPOTS.md); prior [`20260801T164821Z_6cacd65/hypothesis.md`](../20260801T164821Z_6cacd65/hypothesis.md) |
| **H9** | Steady-state body cost scales ~O(N) via `profile_statuses` when inventory is cached | **supports** | When inventory hits TTL, body ≈ profile_statuses **~1.6** + claim **~0.8** + load **~0.4** ≈ **2.8 ms** ≈ p50; p50 grows 1.36 → 2.83 → 5.77 ms across N=5/20/50 | [`CPU-PROFILE.md`](./CPU-PROFILE.md); [`BASELINE.md`](./BASELINE.md) N table; [`HOTSPOTS.md`](./HOTSPOTS.md) finding 2 |
| **H10** | Client wall on loopback is mostly agent inventory + curl, not pure Python CPU | **supports** | Hyperfine status user+sys ~**4 ms** vs wall mean **35.6** / p95 **100**; host_metrics user+sys ~**4 ms** vs wall ~**5.8 ms** (curl spawn dominates small warm payload) | [`BASELINE.md`](./BASELINE.md) hyperfine tables; [`baseline-derived-http-*.json`](./baseline-derived-http-status.json) |

---

## Cross-check vs prior run (`20260801T164821Z_6cacd65`)

| Topic | Prior Spark/tailnet | This LOCAL Mac | Same conclusion? |
|-------|---------------------|----------------|------------------|
| Inventory dominates status | **supports** (`list_listening` mean ~234 ms on Spark) | **supports** (miss ~45–57 ms lsof; still p95 driver) | Yes (class same; magnitude differs by OS path) |
| Super-linear N | not primary focus | **rejects** (ratio 1.83) | Local scaling clean |
| Client wall = RTT + agent | **supports** (~203 ms RTT residual) | Loopback: RTT≈0; wall = agent + client spawn | Different path; both agent-heavy server-side |
| UI decode as latency source | **rejects** | Not re-opened (agent-first campaign) | Prior reject stands |

---

## Budget / hotspot alignment (hypothesis → action class)

| Hypothesis | If optimizing later (not this phase) | Priority class from HOTSPOTS |
|------------|--------------------------------------|------------------------------|
| H1 inventory miss | Attack miss latency / TTL / path (lsof vs /proc) | P0 latency tail |
| H2 super-linear N | Do **not** prioritize N-linearization of p95 first | Rejected -- false lead |
| H3 host_metrics local UI | Do **not** optimize warm host_metrics CPU first | Rejected on local |
| H4 RSS leak | Do **not** optimize agent RSS first | Memory non-issue |
| H5 sequential poll | Product math for large N / high RTT (parallel or batch) | Rank 3 architecture risk |
| H6 GPU cold only | Leave warm path alone; measure nvidia on GPU hosts | Cold one-shot only |

---

## Open / N/E (do not over-claim)

| Gap | Effect on ledger |
|-----|------------------|
| Multi-remote Mac `pollOnce` wall unmeasured | H5 is **model-supported**, not a measured breach on N remotes |
| No nvidia host this fingerprint | H6 cold nvidia ≤500 ms budget **N/E**; Mac cold probe only |
| No multi-gateway `refreshAll` E2E | H3 reject is **local agent/metrics**, not full UI E2E |
| Mac app RSS unmeasured | H4 is **agent-only** |
| Spark re-baseline not this host | Cross-host p95 must not be treated as same-fingerprint variance |

---

## Explicit non-actions

- **No optimizations** applied or prescribed as code changes.
- **No commit.**
- Variance detail: [`VARIANCE.md`](./VARIANCE.md).

---

## Status

**DONE** -- Six required hypotheses + four warranted extras scored with supports/rejects/inconclusive, evidence paths, and one-line evidence. H5 alone is model-forward with multi-remote N/E noted.

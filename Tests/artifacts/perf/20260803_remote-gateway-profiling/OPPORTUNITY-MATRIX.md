# OPPORTUNITY-MATRIX — remote-gateway profiling

**Run ID:** `20260803_remote-gateway-profiling`  
**Source package:** `Tests/artifacts/perf/20260803_remote-gateway-profiling/`  
**Consumers:** `HAND-OFF.md` → skill `extreme-software-optimization`  
**Date:** 2026-08-03  

**Rule:** Score = Impact × Confidence / Effort (each dimension integer 1–5).  
**Ready to optimize** only if **Score ≥ 2.0**.  
**Lever class only** -- not an implementation recipe.  
**This skill stops here. Do not implement optimizations in this pass.**

---

## Matrix

| Opportunity | Impact (1–5) | Confidence (1–5) | Effort (1–5) | Score (I×C/E) | Hypothesis | Suggested lever class ONLY | Ready (≥2.0)? |
|-------------|-------------:|-----------------:|-------------:|--------------:|------------|----------------------------|:-------------:|
| Extend or smarter listening-TCP inventory cache / avoid `lsof` on warm path when possible | 4 | 5 | 2 | **10.0** | **H1 supports** (miss dominates p95); **H7 supports** (bimodal hit/miss) | Cache policy / inventory snapshot reuse (TTL, hit-rate under spaced polls, path selection) | **yes** |
| Parallelize `RemoteHostMetricsMonitor.pollOnce` across remotes (latency value only when **N×RTT** is large) | 4 | 3 | 2 | **6.0** | **H5 supports** (model; multi-remote wall N/E this campaign) | Concurrency / independent fan-out of remote `fetchHostMetrics` (keep interval + per-remote error isolation) | **yes** |
| Reduce `status_payload` probe cost (`profile_statuses`) when profile **N** is large | 2 | 4 | 3 | **2.67** | **H9 supports** (body ~O(N) when inventory cached); **H2 rejects** super-linear p95 | Probe amortization / batch or skip redundant health connects on the steady path | **yes** |
| Optimize warm `host_metrics` agent path | 1 | 5 | 3 | **1.67** | **H3 rejects** (local warm is free vs budgets) | *(none -- already floor)* | **no** |
| Optimize agent process RSS | 1 | 5 | 3 | **1.67** | **H4 rejects** (37 MB ≪ 80 MB; no growth/leak) | *(none -- under budget)* | **no** |

---

## Dimension rubric (this campaign)

| Dimension | Meaning |
|-----------|---------|
| **Impact** | Expected product latency/cadence/memory gain if the lever works (1 = noise / already green floor; 5 = dominates user-visible or cadence breach) |
| **Confidence** | Strength of measured evidence that this is a real lever (1 = guess; 5 = multi-artifact supports + code path clear) |
| **Effort** | Relative engineering + verification cost (1 = tiny localized; 5 = cross-cutting / high risk to golden) |
| **Score** | I×C/E -- higher first among ready rows unless product priority overrides |

### Impact honesty for ready rows

| Opportunity | Why this Impact |
|-------------|-----------------|
| Inventory cache | **4** -- Rank-1 tail driver (~61% stage share; miss ~45–57 ms). Hard budgets already PASS (status p95 47.3 ms ≪ 1000 ms); impact is p95 quality / miss rate under polls spaced &gt; 75 ms TTL (e.g. 10 s activeRuntime), not a current SLO fail. |
| Parallel pollOnce | **4** -- Sequential `N × (RTT + server)` can burn 3 s interval + 25% slack at large N / high RTT (model). Low product impact for N=1–2 low-RTT. Multi-remote wall not measured here. |
| profile_statuses | **2** -- Rank-2 body (~1.6 ms @ N=20). Green at N=50 mean ~24 ms. Only matters if profile counts or live-probe cost grow. |

### Confidence honesty

| Opportunity | Why this Confidence |
|-------------|---------------------|
| Inventory cache | **5** -- cold/warm JSON, stage p95, cProfile `list_listening_tcp` + `select.poll`, H1/H7 |
| Parallel pollOnce | **3** -- sequential code + interval math confirmed; **no** measured multi-remote `pollOnce` this LOCAL campaign |
| profile_statuses | **4** -- stage ranks + N ladder; smaller absolute cost than inventory miss |
| host_metrics warm / RSS | **5** that they are **not** worth optimizing (reject evidence) |

### Effort honesty

| Opportunity | Why this Effort |
|-------------|-----------------|
| Inventory cache | **2** -- cache policy / TTL / path class; golden inventory shape must still hold |
| Parallel pollOnce | **2** -- localized Swift monitor concurrency; needs cadence + error-isolation tests |
| profile_statuses | **3** -- probe behavior is correctness-adjacent (health truth vs speed) |
| Rejected rows | **3** -- effort of a wasted pass, not a proposed lever size |

---

## Ready queue (score ≥ 2.0 only)

Recommended default order by score (optimizer may reorder for product risk):

1. **Listening-TCP inventory cache** -- Score **10.0** -- Scenario **C** / **A** on-host status tail  
2. **Parallelize pollOnce** -- Score **6.0** -- Scenario **B** cadence at large N×RTT  
3. **profile_statuses probe cost** -- Score **2.67** -- Scenario **C** body when N large  

---

## Explicitly not ready (score &lt; 2.0)

| Opportunity | Score | Directive |
|-------------|------:|-----------|
| Warm `host_metrics` agent path | 1.67 | **Do not optimize** -- already floor (H3) |
| Agent RSS | 1.67 | **Do not optimize** -- under budget, no leak (H4) |

---

## Scenario → opportunity map

| Scenario | Ready opportunities that primarily touch it |
|----------|-----------------------------------------------|
| **A** `multi_gateway_status_refresh` | Inventory cache (per-agent status wall); pollOnce only if metrics panel co-runs |
| **B** `remote_host_metrics_poll` | Parallel pollOnce (when N×RTT large); **not** warm host_metrics CPU |
| **C** `agent_status_payload_many_profiles` | Inventory cache (p95); profile_statuses (p50/body at large N) |

---

## Baseline / fingerprint anchors

| Anchor | Path |
|--------|------|
| Fingerprint | [`fingerprint.json`](./fingerprint.json) |
| Baseline narrative | [`BASELINE.md`](./BASELINE.md) |
| Hotspots | [`HOTSPOTS.md`](./HOTSPOTS.md) |
| Hypotheses | [`HYPOTHESIS-LEDGER.md`](./HYPOTHESIS-LEDGER.md) |
| Hand-off prose | [`HAND-OFF.md`](./HAND-OFF.md) |

---

## Status

**DONE** -- Matrix scored honestly from campaign evidence. Ready rows ≥ 2.0 only. No production changes. No commit.

**This skill stops here. Do not implement optimizations in this pass.**

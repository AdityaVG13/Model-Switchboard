# VARIANCE — envelope note (baseline JSON)

**Run ID:** `20260803_remote-gateway-profiling`  
**Policy ([`BUDGETS.md`](./BUDGETS.md)):** ≤10% p95 drift vs prior **same-host fingerprinted** run → noise; >10% investigate; >20% or 3× consecutive >10% → escalate.  
**Phase:** HYPOTHESIS companion -- measurement interpretation only.

---

## Summary

| Series | p50 | p95 | p95/p50 | Within-run envelope | Character |
|--------|----:|----:|--------:|---------------------|-----------|
| In-process `status_payload` N=20 (n=50) | 2.83 ms | 47.3 ms | **~16.7×** | ≫10% | **Bimodal** (inventory TTL hit/miss) |
| Hyperfine `GET /api/status` (n=20) | 9.8 ms | 100.3 ms | **~10.2×** | ≫10% | **Bimodal** (+ curl) |
| In-process `host_metrics` warm N=20 (n=50) | 0.0073 ms | 0.0081 ms | **~1.11×** | ~**7–11%** p95 vs p50 | Tight / noise-scale |
| Hyperfine `GET /api/host/metrics` warm (n=20) | 5.79 ms | 6.21 ms | **~1.07×** | **~7%** (stdev/mean ~4.6%) | **≤10% envelope** -- unimodal |
| `list_listening_tcp` cold (n=5 clear) | 56.1 ms | 63.3 ms | ~1.13× | modest within-mode | Miss mode only |
| `list_listening_tcp` warm TTL (n=20) | 0.001 ms | 0.002 ms | ~2× on noise floor | n/a | Hit mode only |

**Headline:** Status paths are **not** a ≤10% single-mode envelope -- they are **intentionally bimodal** (75 ms inventory TTL). Host-metrics warm **is** within a ≤10% noise band. Do not treat status p95/p50 as measurement failure.

---

## Status -- bimodal, not under-sampled

### In-process (primary agent truth)

Source: [`baseline-status-payload.json`](./baseline-status-payload.json) `N20_status_payload`

| metric | ms |
|--------|---:|
| mean | 9.88 |
| stdev | 20.6 |
| p50 | 2.83 |
| p95 | 47.29 |
| p99 | 90.81 |
| max | 91.7 |
| n | 50 |

- Body samples sit ~**2.5–3 ms** (cache hit path: profile_statuses + claims + load).
- Tail samples sit ~**45–90 ms** when `list_listening_tcp` misses (lsof ~45–65 ms).
- High stdev relative to mean is **expected** for two modes, not bad n (n=50, `provisional: false`).

### Hyperfine HTTP loopback

Source: [`baseline-derived-http-status.json`](./baseline-derived-http-status.json) `times_ms`

| Cluster (approx) | Count | Wall |
|------------------|------:|------|
| ~9.0–9.8 ms | 12 / 20 | hit-ish body + curl |
| ~55–58 ms | 6 / 20 | one inventory miss class |
| ~97–162 ms | 2 / 20 | heavier miss / scheduling tail |

- **p95/p50 ≈ 10.2** -- far above a 10% noise envelope.
- user+sys ≈ **4 ms** → variance is agent inventory + localhost, not curl CPU.

### Cross-run same-class (CPU-PROFILE vs BASELINE)

| Path | BASELINE p95 | CPU-PROFILE p95 | Δ |
|------|-------------:|----------------:|--:|
| status N=20 | 47.3 ms | 48.8 ms | **~+3%** |
| host_metrics warm | 0.008 ms | ~0.01–0.06 ms | noise floor |
| host_metrics cold | 2.22–2.33 ms | 2.0–2.1 ms | same order |

Same-host, same fixture class: p95 drift **≤10%** on status → **noise / load**, not regression.

---

## Host metrics -- tight unimodal envelope

Source: [`baseline-derived-http-host-metrics.json`](./baseline-derived-http-host-metrics.json), [`baseline-host-metrics.json`](./baseline-host-metrics.json)

| metric | hyperfine HTTP warm | in-process warm |
|--------|--------------------:|----------------:|
| mean | 5.80 ms | 0.0074 ms |
| stdev | 0.27 ms (~4.6% of mean) | 0.00048 ms |
| p50 | 5.79 ms | 0.0073 ms |
| p95 | 6.21 ms | 0.0081 ms |
| p95/p50 | **1.07** | **1.11** |
| min–max | 5.28–6.22 ms | 0.0067–0.0096 ms |

- All 20 hyperfine samples lie in a **~1 ms** band -- **≤10% envelope** satisfied for warm host metrics.
- Cold first sample (~2.3 ms on-host) is a **separate mode** (GPU probe once); not mixed into warm n=50 after warmup.

---

## Inventory cold/warm (explains status bimodality)

Source: [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json)

| Mode | mean | p50 | p95 |
|------|-----:|----:|----:|
| Cold clear-cache | 56.9 ms | 56.1 | 63.3 |
| Warm within 75 ms TTL | 0.001 ms | 0.001 | 0.002 |

Ratio of modes: **~5e4×**. Any sample mix of hit/miss yields status p95 ≫ p50. TTL = `LISTENING_TCP_CACHE_TTL_SECONDS=0.075`.

---

## Scaling ratios (not variance, but stability of law)

Source: [`baseline-status-payload.json`](./baseline-status-payload.json)

| Ratio | Value | vs budget |
|-------|------:|-----------|
| p95(20)/p95(5) | 1.83 | ≤ 5.0 hard **PASS** |
| p95(50)/p95(5) | 2.90 | ≤ 12 soft **OK** |
| mean(20)/mean(5) | 2.03 | near-linear body |
| mean(50)/mean(5) | 4.94 | near-linear body |

p95 grows slower than N because tail is **shared inventory miss**, not N× probes (see H2 reject).

---

## Policy application

| Check | Result |
|-------|--------|
| Treat status p95/p50 >1.1 as "bad measurement"? | **No** -- bimodal by design (H7) |
| Warm host_metrics ≤10% envelope? | **Yes** (~7% p95/p50 hyperfine) |
| Same-class re-run status p95 drift (BASELINE vs CPU-PROFILE)? | **~3%** → noise |
| Cross-host Spark 303 ms mean vs LOCAL 10 ms mean? | **Do not compare as variance** -- different inventory class / fingerprint ([`BASELINE.md`](./BASELINE.md) comparison table) |
| Prior tailnet status p95 640 ms | Different host + RTT; not envelope vs this LOCAL run |

---

## Evidence index

| File | Role |
|------|------|
| [`baseline-status-payload.json`](./baseline-status-payload.json) | In-process p50/p95/stdev N=5/20/50 |
| [`baseline-derived-http-status.json`](./baseline-derived-http-status.json) | Hyperfine times + p95/p50 status |
| [`baseline-derived-http-host-metrics.json`](./baseline-derived-http-host-metrics.json) | Hyperfine times host_metrics (tight) |
| [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json) | Two inventory modes |
| [`CPU-PROFILE.md`](./CPU-PROFILE.md) | Cross-run p95 corroboration |
| [`BUDGETS.md`](./BUDGETS.md) | ≤10% / >10% / >20% drift rules |
| [`HYPOTHESIS-LEDGER.md`](./HYPOTHESIS-LEDGER.md) | H1/H7 linkage |

---

## Status

**DONE** -- Variance note: status = bimodal cache hit/miss (envelope ≫10% within-run by design); host_metrics warm ≤10% unimodal; same-class re-run ~3% p95 drift. No optimizations. No commit.

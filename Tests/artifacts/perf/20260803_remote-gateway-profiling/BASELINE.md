# BASELINE — multi-gateway menu bar + remote host metrics

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** BASELINE only (no instrumentation, no production changes)  
**Mode:** **LOCAL-ONLY** (Mac loopback agent; no Spark / tailnet remote available this pass)  
**Host fingerprint:** [`fingerprint.json`](./fingerprint.json) — Apple M5 Max, macOS 26.5, AC power  
**Agent under test:** `RemoteAgent/model_switchboard_agent.py` v**1.1.2**  
**Captured (in-process):** 2026-08-03T18:17:31Z  
**Load during measure:** ~3.7 / 3.3 / 3.4 (18 cores) — quieter than ENVIRONMENT capture (~5.4)  
**Git at measure:** `7d2e5da` (ENVIRONMENT fingerprint recorded `a25d02e`; re-fingerprint if comparing RSS/build artifacts)

---

## Scope and method

| Approach | What it measures | Samples |
|----------|------------------|--------:|
| In-process `AgentService.status_payload()` | Scenario **C** + A.on-host status (CPU truth) | **50** timed (warmup 5) for N=5,20; **30** for N=50 |
| In-process `host_metrics_payload()` | Scenario **B** on-host warm/cold | **50** warm + 1 cold |
| Ephemeral `make_server` + urllib HTTP | Loopback agent HTTP path | **20** |
| **hyperfine** curl loopback | Client wall for `/api/status`, `/api/host/metrics` | **20** (+ warmup 3) |
| `swift test --filter HostMetricsPresentationTests` | Toolchain only (not product SLO) | 1 wall |

**Fixture (agent root):** temp dir with `N` profile `.env` files (plain `PORT`/`REQUEST_MODEL`), 5 claim dirs under `MODEL_SWITCHBOARD_SCAN_ROOTS`, `allow_unauthenticated` loopback. No live model servers — health probes fail fast; inventory is real macOS `list_listening_tcp`.

**Variance policy:** n≥10 for primary agent paths → **not provisional**. High p95/p50 ratio on status is real (listening inventory / probe tails), not under-sampling.

**Not done this pass:** OS tuning, sudo, production edits, Mac UI E2E, multi-gateway `refreshAll`, remote client RTT, agent RSS sampling under sustained load, nvidia GPU cold path.

Evidence files:

| File | Content |
|------|---------|
| `baseline_inprocess.json` | Full in-process + urllib HTTP times |
| `baseline_N50.json` | N=50 status microbench |
| `baseline-status-payload.json` | Compact C / A.on-host summaries + scaling |
| `baseline-host-metrics.json` | Compact B on-host + HTTP |
| `baseline-http-api-status.json` | hyperfine raw `/api/status` |
| `baseline-http-api-host-metrics.json` | hyperfine raw `/api/host/metrics` |
| `baseline-derived-http-*.json` | p50/p95/p99 from hyperfine times |
| `baseline-swift-HostMetricsPresentationTests.json` | Toolchain wall |
| `bench_baseline.py` | Reproducible harness (artifact only) |

---

## Scenario C — `agent_status_payload_many_profiles` (primary, LOCAL)

### On-host `status_payload()` (ms)

| N profiles | n | mean | p50 | p95 | p99 | max | statuses returned |
|-----------:|--:|-----:|----:|----:|----:|----:|------------------:|
| 5 | 50 | 4.88 | 1.36 | 25.83 | 67.64 | 88.0 | 10 (5 profile + claims/listeners) |
| **20** | **50** | **9.88** | **2.83** | **47.29** | **90.81** | 91.7 | **25** |
| 50 | 30 | 24.07 | 5.77 | 75.02 | — | — | 55 |

### Scaling

| Ratio | Value | Notes |
|-------|------:|-------|
| p95(N=20) / p95(N=5) | **1.83** | Sub-linear in p95 (shared inventory tails dominate) |
| mean(N=20) / mean(N=5) | **~2.03** | ~linear in profile count for body of distribution |
| mean(N=50) / mean(N=5) | **~4.94** | Near-linear mean; p50(N=50)~5.8 ms |

Body of distribution is **~1.3–3 ms** (N=5/20); rare **~45–90 ms** spikes pull p95. Consistent with listening-TCP inventory / health-probe tails on a busy laptop (not a multi-second home-walk regression).

### Budget check (C + A.on-host)

| Metric ID | Budget | Measured | Verdict |
|-----------|--------|----------|---------|
| `C.status_payload_p95` (N=20) | ≤ 1000 ms hard (`A.agent_status_onhost_p95`) | **47.3 ms** | **PASS** |
| `C.status_payload_mean` (N=20) | ≤ 50 ms stretch (`A.agent_status_onhost_mean`) | **9.9 ms** | **PASS (stretch)** |
| `C.scaling_ratio` | near-linear assembly | mean ~2× for 4× profiles | **OK** (no super-linear defect signal) |
| `C.agent_rss_peak` | ≤ 80 MB hard | **not measured** | **N/E** |

Prior context (not this host path): mock inventory p95 ~17.5 ms; Spark pre-opt mean ~303 ms. This LOCAL mock-like fixture is closer to the mock class than Spark real inventory.

---

## Scenario B — `remote_host_metrics_poll` (partial, LOCAL)

### On-host `host_metrics_payload()` (ms)

| Mode | n | mean | p50 | p95 | Notes |
|------|--:|-----:|----:|----:|-------|
| Warm (after 3 warmups) | 50 | **0.007** | 0.007 | 0.008 | GPU cache N/A; CPU+mem only |
| Cold first sample | 1 | **2.22–2.33** | — | — | No `nvidia-smi` on Mac |

### Loopback HTTP `GET /api/host/metrics` (warm)

| Source | n | mean | p50 | p95 | p99 |
|--------|--:|-----:|----:|----:|----:|
| urllib (harness) | 20 | 0.23 | 0.23 | 0.25 | 0.25 |
| **hyperfine curl** | **20** | **5.80** | **5.79** | **6.21** | **6.22** |

Hyperfine includes curl process spawn + HTTP; in-process payload is sub-0.01 ms. Product path is HTTP — use hyperfine for client-comparable local walls; use in-process for agent CPU truth.

`gpu_source`: **`unavailable`** (expected on this Mac). Cold GPU budget (≤500 ms with nvidia-smi) **cannot** be evaluated here.

### Budget check (B)

| Metric ID | Budget | Measured | Verdict |
|-----------|--------|----------|---------|
| `B.agent_host_metrics_p95` warm | ≤ 200 ms | **0.008 ms** in-process / **6.2 ms** hyperfine HTTP | **PASS** |
| `B.agent_host_metrics_p95` cold GPU | ≤ 500 ms | cold non-GPU ~2.3 ms | **PASS (partial)** — no GPU query |
| `B.client_host_metrics_p95` remote | ≤ 400 ms | — | **N/E** (no remote) |
| `B.poll_once_p95` N=2 / N=4 | ≤ 1000 / 2000 ms | — | **N/E** (no Mac multi-remote poll) |
| `B.poll_cycle_slack` | ≥ 750 ms | — | **N/E** |
| `B.sustained_error_rate` | ≤ 1% | — | **N/E** |
| `B.mac_rss_peak` | ≤ 250 MB | — | **N/E** |

---

## Scenario A — `multi_gateway_status_refresh` (mostly N/E locally)

### Local pieces that **can** be scored

| Metric ID | Budget | Measured | Verdict |
|-----------|--------|----------|---------|
| `A.per_store_status_p95` **local** loopback | ≤ 500 ms | hyperfine p95 **~100 ms** (mean 35.6, high σ) | **PASS** |
| `A.agent_status_onhost_p95` | ≤ 1000 ms | **47.3 ms** (N=20) | **PASS** |
| `A.agent_status_onhost_mean` stretch | ≤ 50 ms | **9.9 ms** | **PASS (stretch)** |

### Hyperfine `GET /api/status` loopback (N=20 profiles fixture)

| mean | stdev | p50 | p95 | p99 | max | n |
|-----:|------:|----:|----:|----:|----:|--:|
| 35.6 ms | 40.1 ms | 9.8 ms | **100.3 ms** | 150.0 ms | 162.4 ms | 20 |

Client user+sys ~4 ms → wall is mostly agent + localhost. Tail variance matches in-process status spikes.

### Cannot evaluate without remote + Mac app

| Metric ID | Why N/E |
|-----------|---------|
| `A.e2e_refresh_p95` (N=2 remotes / N=4) | Needs ModelSwitchboardApp `refreshAll` + configured gateways |
| `A.per_store_status_p95` **remote direct** | Needs tailnet/LAN agent (Spark) |
| `A.per_store_refresh_p95` | Needs client store refresh path |
| `A.sustained_poll_ok` 5 min | Needs long-running UI + agents |
| `A.mac_rss_peak` / soft 150 MB | Needs app process sample |
| `A.agent_rss_peak` | Not instrumented this pass |
| `A.throughput` refreshes/min | Needs sustained activeRuntime |

---

## Toolchain baseline (optional)

`swift test --filter HostMetricsPresentationTests`: **real 2.37 s** (build ~0.7 s + 4 Swift Testing cases ~0.001 s). Not a product SLO.

---

## LOCAL-ONLY budget map (summary)

| Budget class | Evaluable now? | Result |
|--------------|----------------|--------|
| On-host status (A/C hard + stretch mean) | **Yes** | **PASS** |
| On-host / loopback host metrics warm (B hard) | **Yes** | **PASS** |
| Local loopback per-store status (A hard) | **Yes** | **PASS** |
| Cold nvidia host metrics | **No** (no GPU agent) | N/E |
| Remote client RTT (A/B) | **No** | N/E |
| Multi-gateway E2E / pollOnce / RSS / sustained | **No** | N/E |

When Spark (or any remote agent) is available: re-run hyperfine against `http://<remote>:port/api/status` and `/api/host/metrics` with auth; attach remote `fingerprint.json`; fill remote rows in a follow-up BASELINE addendum without invalidating LOCAL numbers.

---

## Comparison to prior run `20260801T164821Z_6cacd65`

| Metric | Prior | This run (LOCAL) |
|--------|------:|-----------------:|
| Tailnet GET /api/status p95 | 640 ms | N/E remote; loopback p95 ~100 ms |
| On-host status_payload mean (Spark real) | ~303 ms | N/E Spark; LOCAL fixture mean ~10 ms (N=20) |
| Mock inventory status p95 | ~17.5 ms | N=20 p95 ~47 ms (real listeners + N profiles) |

Do **not** treat LOCAL fixture mean as a regression vs Spark pre-opt 303 ms — inventory class differs.

---

## What was already correct

- DEFINE scenarios A/B/C and BUDGETS map cleanly onto measurable agent surfaces (`status_payload`, `host_metrics_payload`, HTTP routes).
- Agent HTTP routes `/api/status` and `/api/host/metrics` respond on ephemeral `make_server` without code changes.
- Warm host metrics on macOS is effectively free when GPU is unavailable; budgets still leave headroom for nvidia hosts.
- On-host status at N=20 is well under 1 s hard budget and under 50 ms stretch **mean** on this fixture.
- Hyperfine available and used for n=20 HTTP samples.

---

## Next phase (not this pass)

1. **INSTRUMENT** — env-gated spans on `status_payload` / `host_metrics_payload` / client refresh / pollOnce.  
2. Re-baseline remote when Spark is up.  
3. Optional: agent RSS under status+metrics load for `A.agent_rss_peak` / `C.agent_rss_peak`.

---

## Reproduce (local)

```bash
# In-process + HTTP harness
python3 Tests/artifacts/perf/20260803_remote-gateway-profiling/bench_baseline.py \
  --n 50 --warmup 5 --profiles 5,20 --http-n 20 \
  --out Tests/artifacts/perf/20260803_remote-gateway-profiling/baseline_inprocess.json

# Hyperfine against a warm loopback agent (see agent start snippet in session log):
hyperfine --warmup 3 --runs 20 --export-json baseline-http-api-status.json \
  "curl -sS -m 15 http://127.0.0.1:\$PORT/api/status -o /dev/null"
```

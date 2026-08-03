# HOTSPOTS — ranked interpretation (INTERPRET only)

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** INTERPRET ranked hotspots — **no optimizations**  
**Mode:** LOCAL-ONLY (Mac M5 Max loopback agent fixture; no remote Spark/tailnet RTT)  
**Prior phases:** `SCENARIO.md`, `BUDGETS.md`, `fingerprint.json`, `BASELINE.md`, `INSTRUMENTATION.md`, `CPU-PROFILE.md`, `MEMORY-PROFILE.md`, `IO-NETWORK-PROFILE.md`  
**Agent:** `RemoteAgent/model_switchboard_agent.py` v1.1.2  
**Date:** 2026-08-03

This document **attributes** measured cost. It does **not** propose or apply fixes.

---

## Ranked hotspot table

| Rank | Location | Metric | Value | Category | Evidence |
|-----:|----------|--------|------:|----------|----------|
| **1** | `list_listening_tcp` cache **miss** → `_list_listening_tcp_uncached` → `lsof -nP -iTCP -sTCP:LISTEN` (macOS; no `/proc`, no `ss`) | stage share of Σ / p95 / cold mean | **~61%** of `status_payload` stages; stage p95 **~45 ms**; forced cold mean **~57 ms** (warm TTL hit **~0.001 ms**) | **Wait-ish I/O** (subprocess + `select.poll`) — **latency tail driver** | [`CPU-PROFILE.md`](./CPU-PROFILE.md) stages rank #1; [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json); [`cprofile.txt`](./cprofile.txt) `list_listening_tcp` 0.191 s / 20, `select.poll` tottime 0.102 s; [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md) §a; code TTL `LISTENING_TCP_CACHE_TTL_SECONDS=0.075` |
| **2** | `profile_statuses` (`AgentService.status` × N profiles + `_probe_health` fail-fast connect) | stage share / mean steady | **~22%** of stages; mean **~1.6 ms** (N=20); cProfile 400× `status` + 400× connect | **Busy + wait-ish** steady work — scales with profile count | [`CPU-PROFILE.md`](./CPU-PROFILE.md) rank #2; [`cpu-profile-summary.json`](./cpu-profile-summary.json) `profile_statuses`; [`cprofile.txt`](./cprofile.txt) `status` / `_probe_health` / `socket.connect` |
| **3** | `RemoteHostMetricsMonitor.pollOnce` — **sequential** `for runtime in runtimes { fetchHostMetrics }` at **3 s** interval | architecture / estimated wall | Local LB: ~**6 ms × N** HTTP; with RTT R: **N × (R + server)**; N=10 @ 200 ms RTT ≈ **2.0 s** (tight vs 3 s); N≥10 @ 500 ms **overruns** interval | **Wait-ish network** accumulation (no overlap) — product risk at large N / high RTT | [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md) §b–c; `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift`; [`INSTRUMENTATION.md`](./INSTRUMENTATION.md) span `RemoteHostMetricsMonitor.pollOnce`; [`BUDGETS.md`](./BUDGETS.md) `B.poll_once_p95` / 25% slack; **not measured multi-remote this campaign** (LOCAL-ONLY) |
| **4** | `host_metrics_payload` **cold** stage `gpu` (probe path even when `gpu_source=unavailable`; nvidia-smi on GPU hosts not exercised) | cold wall / warm wall | Cold total **~2.1–2.3 ms** (gpu stage **~1.9 ms**); warm p95 **~0.008–0.06 ms** (effectively free) | **One-shot cold probe** — not sustained CPU | [`CPU-PROFILE.md`](./CPU-PROFILE.md) host_metrics cold/warm; [`BASELINE.md`](./BASELINE.md) B on-host; [`baseline-status-payload.json`](./baseline-status-payload.json) `host_metrics_cold_ms`; TTL 2.0 s `_GPU_METRICS_TTL_SECONDS` in agent |
| **5** | `scan_port_claim_directories` | stage share / mean | **~11%**; mean **~0.8 ms** (N=20, 5 claim dirs) | **Busy FS walk** | [`CPU-PROFILE.md`](./CPU-PROFILE.md) rank #3; [`cprofile.txt`](./cprofile.txt) 0.037 s / 20 |
| **6** | `profiles_load` (parse N `.env` profiles) | stage share / mean | **~5%**; mean **~0.4 ms** (N=20) | **Busy** parse | [`CPU-PROFILE.md`](./CPU-PROFILE.md) rank #4 |
| **7** | HTTP loopback client overhead (`curl`/urllib vs in-process) | hyperfine p95 | `/api/status` p95 **~100 ms** (mean 35.6, high σ); `/api/host/metrics` p95 **~6.2 ms** vs in-process ~0 | **Client + bimodal inventory cache** on status | [`BASELINE.md`](./BASELINE.md); [`baseline-derived-http-status.json`](./baseline-derived-http-status.json); [`baseline-derived-http-host-metrics.json`](./baseline-derived-http-host-metrics.json) |
| **8** | Residual status stages (`merge_discovery`, `benchmark_status`, `discover_live_model_endpoints`) | share of Σ | **&lt;1.2%** combined on this fixture (`n_live=0`) | Noise | [`CPU-PROFILE.md`](./CPU-PROFILE.md) ranks 5–7 |
| **—** | **Agent process RSS** (status + host_metrics N=20) | peak `ru_maxrss` | **37.422 MB** (corroboration `/usr/bin/time -l` **33.4 MB**) vs hard budget **≤ 80 MB** | **NOT a hotspot** — memory is not the issue | [`MEMORY-PROFILE.md`](./MEMORY-PROFILE.md); [`memory-profile.json`](./memory-profile.json); [`time-l.err`](./time-l.err); [`BUDGETS.md`](./BUDGETS.md) `A/B/C.agent_rss_peak` |

---

## Top findings (must-read)

### 1. `list_listening_tcp` cache miss / `lsof` is the p95 driver

- On this Mac: `proc_net_tcp=false`, `ss=false`, `lsof=true` → uncached inventory always takes the **lsof subprocess** path.
- **Bimodal stage:** p50 ≈ **0.003 ms** (75 ms TTL hit, shallow copy) vs p95 ≈ **45 ms** (miss → spawn + `communicate` + `select.poll` wait).
- Forced cold/clear-cache mean **~57 ms** ([`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json)); warm within TTL **~0.001 ms**.
- cProfile: **`list_listening_tcp` 0.191 s** of 0.321 s total for 20× `status_payload`; dominant tottime is **`select.poll` (0.102 s)** — wait-ish, not pure Python CPU.
- TTL is already **0.075 s**; back-to-back polls absorb miss cost, but any spacing &gt; TTL re-pays lsof. That explains status span p95 **~48 ms** matching BASELINE **47.3 ms**.

### 2. `profile_statuses` is the steady-state body cost

- When inventory is cached, remaining work is essentially **profile_statuses (~1.6 ms) + claim scan (~0.8 ms) + profiles_load (~0.4 ms) ≈ 2.8 ms** — matches status p50.
- Scales with **N profiles** (N× `status` + health probe). Rank #2 by stage share (~22%), not by tail.

### 3. Sequential `RemoteHostMetricsMonitor` poll

- Product path: **strict sequential** fetch of all enabled remotes every **3 s** (code comment: MainActor simplicity; few remotes expected).
- LOCAL campaign measured **per-agent** host metrics only (warm free; HTTP ~6 ms). Multi-remote `pollOnce` wall and remote RTT are **N/E**.
- Scaling model (from [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md)): `pollOnce ≈ N × (HTTP_RTT + server)`. Fine for small N / LAN; high RTT or large N burns the 3 s interval and 25% slack budget (`B.poll_cycle_slack ≥ 750 ms`).

### 4. Host metrics cold GPU probe

- Warm path on this host is **noise** (&lt;0.1 ms). Cold first sample **~2.1–2.3 ms**, dominated by **`gpu` stage (~1.9 ms)** even with `gpu_source=unavailable` (no nvidia-smi).
- Real **nvidia-smi cold** budget (≤ 500 ms hard) was **not evaluable** here. GPU cache TTL **2.0 s** amortizes warm polls under the 3 s client cadence.

### 5. Memory is **not** the issue (RSS **37 MB**)

| Check | Budget | Measured | Verdict |
|-------|-------:|---------:|---------|
| `A/B/C.agent_rss_peak` hard | ≤ 80 MB | **37.422 MB** rusage / **33.4 MB** `time -l` | **PASS** (~53% headroom) |
| Soft investigate | > 50 MB | 37.4 MB | not triggered |
| Growth across 20× status | — | ~0.8 MB then flat | no leak signal |
| host_metrics RSS | — | no incremental growth | flat |

Process baseline + import is ~32 MB; fixture/warmup adds a few MB. Latency hot path (`list_listening_tcp`) does **not** show up as RSS growth. Mac app RSS still unmeasured (out of agent-only scope).

---

## Scaling law notes (BASELINE N=5 / 20 / 50)

Source: [`BASELINE.md`](./BASELINE.md), [`baseline-status-payload.json`](./baseline-status-payload.json), [`baseline_N50.json`](./baseline_N50.json). On-host `status_payload()`, LOCAL fixture, real macOS listeners.

### Measured walls (ms)

| N profiles | n | mean | p50 | p95 | statuses returned |
|-----------:|--:|-----:|----:|----:|------------------:|
| 5 | 50 | 4.88 | 1.36 | 25.83 | 10 |
| **20** | **50** | **9.88** | **2.83** | **47.29** | **25** |
| 50 | 30 | 24.07 | 5.77 | 75.02 | 55 |

### Ratios vs N=5

| Ratio | Value | Interpretation |
|-------|------:|----------------|
| p95(20)/p95(5) | **1.83** | Sub-linear in p95 — **shared inventory tails** (same lsof miss cost) dominate extremes, not 4× profile work |
| mean(20)/mean(5) | **~2.03** | Near-linear mean with profile count for the body |
| mean(50)/mean(5) | **~4.94** | Near-linear mean for 10× profiles |
| p95(50)/p95(5) | **~2.90** | Still sub-linear p95; budget `C.scaling_ratio` p95(20)/p95(5) ≤ 5.0 → **OK** |

### Law (qualitative + evidence-backed)

1. **Body cost ≈ O(N_profiles)** for `profile_statuses` + `profiles_load` (plus fixed claim-scan / merge noise). p50 grows ~1.4 → 2.8 → 5.8 ms across 5/20/50.
2. **Tail cost ≈ O(1) inventory miss + O(N)** probes** — a single uncached `list_listening_tcp` (~45–65 ms lsof) sets p95/p99 more than profile count does. Hence p95(20)/p95(5) ≪ 20/5.
3. **Cache hit rate on the 75 ms TTL** controls whether a given sample is body (~3 ms) or tail (~48 ms). HTTP hyperfine p95 ~100 ms is the same bimodality plus client spawn.
4. **No super-linear discovery defect** on this fixture (no multi-second `$HOME` walk regression).
5. **Host metrics:** warm independent of N profiles (~0); cold GPU probe O(1) once per TTL.
6. **Mac sequential poll:** wall **O(N_remotes × RTT)** — orthogonal to agent profile scaling; product risk surface for scenario B at large N, not measured multi-remote here.

Budget gates on evaluable LOCAL metrics: **all PASS** (`C.status_payload_p95` 47 ms ≪ 1000; stretch mean 9.9 ms ≤ 50; B warm host metrics free; agent RSS 37 MB ≪ 80). Open / N/E: multi-gateway E2E, remote RTT, pollOnce N=2/4, nvidia cold GPU, Mac app RSS.

---

## Budget map vs hotspots (LOCAL evaluable)

| Metric ID | Budget | Baseline / profile | Hotspot link | Verdict |
|-----------|-------:|-------------------:|--------------|---------|
| `C.status_payload_p95` N=20 | ≤ 1000 ms | **47.3 ms** | Rank 1 tail | **PASS** |
| `C.status_payload_mean` stretch | ≤ 50 ms | **9.9 ms** | Rank 2 body | **PASS stretch** |
| `C.scaling_ratio` p95(20)/p95(5) | ≤ 5.0 | **1.83** | Scaling law | **PASS** |
| `A.agent_status_onhost_p95` | ≤ 1000 ms | same 47.3 | Rank 1 | **PASS** |
| `B.agent_host_metrics_p95` warm | ≤ 200 ms | **~0.01 ms** / HTTP 6.2 | Rank 4 warm not hot | **PASS** |
| `B.agent_host_metrics_p95` cold GPU | ≤ 500 ms | cold non-GPU ~2.3 ms | Rank 4 | **PASS partial** (no nvidia) |
| `A/B/C.agent_rss_peak` | ≤ 80 MB | **37.4 MB** | Memory non-issue | **PASS** |
| `B.poll_once_p95` N=2 | ≤ 1000 ms | — | Rank 3 | **N/E** |
| `A.e2e_refresh_p95` | ≤ 3000 ms | — | multi-gateway | **N/E** |
| Remote client status/metrics | per BUDGETS | — | RTT | **N/E** |

---

## Category taxonomy (this campaign)

| Category | Dominant symbols | Character |
|----------|------------------|-----------|
| Wait-ish I/O | `lsof` via `subprocess` + `select.poll` | Sets **p95** of status |
| Busy + probe | `profile_statuses`, fail-fast `connect` | Sets **p50** body; scales with N |
| Busy FS | claim dir walk, `.env` load | Secondary steady cost |
| Wait-ish network (Mac) | sequential `fetchHostMetrics` | Cadence risk; unmeasured multi-remote |
| Cold probe | host_metrics `gpu` stage | One-shot; amortized by 2 s TTL |
| Memory | process RSS | **Healthy** — do not optimize for RSS first |

---

## Explicit non-actions

- **No optimizations** applied or prescribed as code changes in this phase.
- **No commit.**
- OPTIMIZE (future skill pass), if authorized, should start from **Rank 1 inventory miss latency** and **Rank 3 sequential poll** product math — guided by re-run of `profile_cpu.py` / spans — not from RSS.

---

## Evidence index

| Path | Role |
|------|------|
| [`SCENARIO.md`](./SCENARIO.md) | A/B/C definitions, cadences |
| [`BUDGETS.md`](./BUDGETS.md) | SLOs and slack rules |
| [`fingerprint.json`](./fingerprint.json) | Host M5 Max, branch `feature/remote-gateways` |
| [`BASELINE.md`](./BASELINE.md) / [`baseline-status-payload.json`](./baseline-status-payload.json) | N=5/20/50 walls + scaling ratios |
| [`INSTRUMENTATION.md`](./INSTRUMENTATION.md) | Span names / flags |
| [`CPU-PROFILE.md`](./CPU-PROFILE.md) / [`cpu-profile-summary.json`](./cpu-profile-summary.json) / [`cpu-spans.jsonl`](./cpu-spans.jsonl) / [`cprofile.txt`](./cprofile.txt) | Stage ranks + cProfile |
| [`MEMORY-PROFILE.md`](./MEMORY-PROFILE.md) / [`memory-profile.json`](./memory-profile.json) / [`time-l.err`](./time-l.err) | RSS 37 MB PASS |
| [`IO-NETWORK-PROFILE.md`](./IO-NETWORK-PROFILE.md) / [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json) | Wait vs busy; sequential poll model |
| Code | `RemoteAgent/model_switchboard_agent.py`; `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift` |

---

## Status

**DONE** — Ranked HOTSPOT table with evidence paths; required findings (lsof miss, profile_statuses, sequential poll, cold gpu, RSS non-issue) and N=5/20/50 scaling notes captured. No optimizations. No commit.

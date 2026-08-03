# BUDGETS — multi-gateway menu bar + remote host metrics

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** DEFINE (performance contract only)  
**Scenarios:** see `SCENARIO.md`  
**Hardware:** *not declared this pass* — ENVIRONMENT phase fills reference hosts. Budgets below are product SLOs; same-host comparisons still require matching `fingerprint.json`.

Prior agent-status budgets from `20260801T164821Z_6cacd65/BUDGETS.md` remain valid for single-endpoint discovery and are **superseded/extended** here for multi-gateway + host metrics.

---

## Optimization workflow (future skills)

1. Profile — measure before changing anything  
2. Change — one lever at a time  
3. Prove — golden behavior unchanged **and** budget metrics improve  

This DEFINE pass does **not** optimize code.

---

## "Fast enough" definitions

| Surface | User-visible meaning | Contract |
|---------|----------------------|----------|
| Multi-gateway status refresh | Manual refresh and active auto-refresh (10s) never stack; board updates while menu is open | E2E and per-store walls **≪ 10s**; healthy path finishes in low single-digit seconds on tailnet |
| Host metrics strip / Remote Hosts panel | CPU/RAM/GPU numbers feel live without stalling UI | Full sequential poll of N remotes finishes **inside 3s** interval with ≥25% headroom |
| Agent status under many profiles | Adding profiles does not return multi-second hangs | On-host `status_payload` p95 **≤ 1s** at N=20; stretch mean **≤ 50ms** on Linux remote with real inventory |
| Memory | Menu bar stays a light utility | Mac app peak RSS during multi-gateway steady state **≤ 250 MB**; agent peak RSS **≤ 80 MB** under status+metrics load |

---

## Variance envelope

- ≤10% p95 drift vs prior same-host fingerprinted run → noise  
- >10% → investigate  
- >20% or 3 consecutive >10% → escalate  

---

## Cadence constants (code ground truth)

| Constant | Value | Source |
|----------|------:|--------|
| Auto-refresh idle | 600 s | `AutoRefreshPolicy.idleInterval` |
| Auto-refresh activeRuntime | 10 s | `AutoRefreshPolicy.activeRuntimeInterval` |
| Auto-refresh pendingAction | 5 s | `AutoRefreshPolicy.pendingActionInterval` |
| Host metrics poll | 3 s | `RemoteHostMetricsMonitor` default |
| Manual refreshAll debounce | 0.75 s | `GatewayHub.refreshAll` |
| Remote client request timeout | 5 s | `GatewayHub.makeRemoteStore` |
| Remote client resource timeout | 15 s | `GatewayHub.makeRemoteStore` |
| GPU metrics cache TTL | 2.0 s | `_GPU_METRICS_TTL_SECONDS` |
| Listening TCP inventory cache TTL | 0.075 s | `LISTENING_TCP_CACHE_TTL_SECONDS` |

Cadence budgets: work per tick must complete with **slack ≥ 25% of the interval** on the primary path.

---

## Scenario A — `multi_gateway_status_refresh`

Reference workload: **1 local + 2 remote (direct)** gateways, activeRuntime (≥1 ready/running), warm agents.

| Metric ID | Metric | Budget | Hard / stretch | Prior / notes |
|-----------|--------|-------:|----------------|---------------|
| `A.e2e_refresh_p95` | Wall `refreshAll` → last store done | **≤ 3000 ms** | hard | Must stay ≪ 10s active interval; 3s leaves ~70% slack |
| `A.e2e_refresh_p95` (N=4 remotes) | Same, 1 local + 4 remote | **≤ 5000 ms** | hard | Sequential client timeouts still must not dominate |
| `A.per_store_status_p95` local | Client `GET /api/status` loopback | **≤ 500 ms** | hard | Local should be inventory-bound, not RTT |
| `A.per_store_status_p95` remote direct | Client `GET /api/status` tailnet/LAN | **≤ 1000 ms** | hard | Same as prior single-gateway tailnet budget (was PASS @ 640 ms) |
| `A.per_store_refresh_p95` | Full store refresh (status+doctor+apply) | **≤ 1500 ms** remote; **≤ 800 ms** local | hard | Doctor is best-effort (`try?`); status dominates |
| `A.agent_status_onhost_p95` | On-host `status_payload` | **≤ 1000 ms** | hard | Prior mean ~303 ms pre-opt; assembly must not regress to multi-second |
| `A.agent_status_onhost_mean` | On-host mean | **≤ 50 ms** | stretch | Pass-13 aspirational; requires real inventory re-baseline |
| `A.sustained_poll_ok` | 5 min activeRuntime | **0** hard failures; no unbounded task growth | hard | Coalesce via `isRefreshing` expected |
| `A.mac_rss_peak` | ModelSwitchboardApp peak RSS | **≤ 250 MB** | hard | Menu-bar utility; flag if >150 MB for investigation |
| `A.mac_rss_peak` investigate | — | **> 150 MB** | soft | Not a fail; triggers memory profile phase focus |
| `A.agent_rss_peak` | Remote agent peak RSS | **≤ 80 MB** | hard | Prior sample ~32 MB; allow headroom for larger inventories |
| `A.throughput` | Successful status refreshes / store / min | **≥ 5** in activeRuntime (≈ every 10s) | supporting | Cadence integrity, not max QPS |

### A — slack check

```
active_interval = 10s
require: A.e2e_refresh_p95 ≤ 0.75 * active_interval   # 7500 ms absolute ceiling
product budget tighter: ≤ 3000 ms for N=2
```

---

## Scenario B — `remote_host_metrics_poll`

Reference workload: **2** enabled remotes, 3s interval, sequential `pollOnce`, warm GPU cache unless noted.

| Metric ID | Metric | Budget | Hard / stretch | Prior / notes |
|-----------|--------|-------:|----------------|---------------|
| `B.agent_host_metrics_p95` | On-host `/api/host/metrics` | **≤ 200 ms** warm GPU cache | hard | nvidia-smi cold may be slower; measure both |
| `B.agent_host_metrics_p95` cold GPU | On-host after cache miss | **≤ 500 ms** | hard | Includes one `nvidia-smi` query |
| `B.client_host_metrics_p95` | Mac → remote direct | **≤ 400 ms** warm | hard | RTT-dominated; prior status RTT ~200 ms Mac↔Spark |
| `B.poll_once_p95` N=2 | Sequential two remotes | **≤ 1000 ms** | hard | 3s interval × 0.75 slack → 2250 ms ceiling; product tighter |
| `B.poll_once_p95` N=4 | Sequential four remotes | **≤ 2000 ms** | hard | Must remain < 3s |
| `B.poll_cycle_slack` | `3000 − poll_once_p95` | **≥ 750 ms** (25% of 3s) | hard | Prevents poll pile-up |
| `B.sustained_error_rate` | Failures / attempts over 5 min healthy | **≤ 1%** | hard | Excludes intentional unsupported-agent tests |
| `B.mac_rss_peak` | App RSS metrics steady state | **≤ 250 MB** | hard | Same app ceiling as A |
| `B.agent_rss_peak` | Agent under 3s poll | **≤ 80 MB** | hard | Same agent ceiling as A |
| `B.throughput_polls` | Successful polls / min (N=2) | **≥ 35** (~20 cycles × 2) | supporting | ~40 expected; ≥35 allows rare skips |

### B — slack check

```
metrics_interval = 3s
require: B.poll_once_p95 ≤ 0.75 * metrics_interval   # 2250 ms
product budget: ≤ 1000 ms for N=2
```

### B — unsupported agent (behavioral, not latency)

| Case | Expectation |
|------|-------------|
| Agent without `/api/host/metrics` | `unsupported == true` within one request timeout; no crash; message stable |
| SSH not established | No HTTP attempt hang; entry shows tunnel message |

---

## Scenario C — `agent_status_payload_many_profiles`

Reference workload: **N=20** profiles, ~8 listeners, 3–8 claims, on-host agent.

| Metric ID | Metric | Budget | Hard / stretch | Prior / notes |
|-----------|--------|-------:|----------------|---------------|
| `C.status_payload_p95` N=20 | On-host p95 | **≤ 1000 ms** | hard | Menu-bar safe |
| `C.status_payload_mean` N=20 real inventory | On-host mean | **≤ 50 ms** | stretch | Prior aspirational (spark) |
| `C.status_payload_p95` N=20 mock inventory | Local microbench | **≤ 50 ms** | hard | Pass-13 ~17 ms p95; regression guard |
| `C.scaling_ratio` p95(20)/p95(5) | Ratio | **≤ 5.0** | hard | Near-linear; >5 implies super-linear discovery |
| `C.scaling_ratio` p95(50)/p95(5) | Ratio | **≤ 12.0** | soft | Record; escalate if >> linear |
| `C.list_listening_tcp_mean` | Inventory share | **≤ 50 ms** | stretch | Prior ~234 ms pre /proc opts; re-baseline |
| `C.agent_rss_peak` | During microbench | **≤ 80 MB** | hard | Same agent ceiling |
| `C.golden` | `test_perf_golden` + status shape | **pass** | hard | Behavior lock |

---

## Inherited single-endpoint budgets (still in force)

From prior DEFINE/BUDGETS (discovery era). Re-check when baselining A/C.

| Scenario | Metric | Budget | Last known |
|----------|--------|-------:|------------|
| api_status (tailnet) | p95 wall | ≤ 1000 ms | 640 ms PASS |
| api_ports (tailnet) | p95 wall | ≤ 1000 ms | 576 ms PASS |
| scan_port_claims | mean wall | ≤ 100 ms | ~41 ms PASS |
| list_listening_tcp | mean wall | ≤ 50 ms | ~234 ms **stretch open** until spark re-baseline |

---

## Throughput summary

This product is **poll-cadence limited**, not max-QPS. Primary throughput contracts:

| Path | Expected rate | Budget meaning |
|------|---------------|----------------|
| Status auto-refresh per store (active) | ~6/min | Must complete each cycle with slack; do not optimize for higher rate |
| Status auto-refresh (idle) | 0.1/min | Cadence only |
| Host metrics per remote | ~20/min | Sequential N×20/min system-wide on Mac client |
| Agent status under UI storm | Burst up to N stores concurrent | `isRefreshing` + inventory TTL absorb; no error spike |

Do **not** set artificial high RPS load tests as the primary gate; optional stress is out of DEFINE scope.

---

## Peak RSS budgets (consolidated)

| Process | Peak RSS budget | Soft investigate | Prior evidence |
|---------|----------------:|-----------------:|----------------|
| ModelSwitchboardApp (macOS) | **≤ 250 MB** | > 150 MB | Not measured this DEFINE |
| RemoteAgent (`model_switchboard_agent.py`) | **≤ 80 MB** | > 50 MB | ~32 MB sample 2026-08-01 |
| Controller (local, if separate) | **≤ 100 MB** | > 60 MB | Not in prior multi-gateway focus |

RSS is **peak during scenario window**, not idle minimum.

---

## Golden / behavior gates (must not regress when optimizing later)

| Gate | How |
|------|-----|
| Status shape | `statuses` array; claim rows keep discovery fields; `log_path` string when applicable |
| Host metrics shape | Decodes to `HostMetricsPayload`; units documented in model |
| Unsupported metrics | Clear 404/not-found → unsupported message, no crash |
| Unit + golden | `python3 -m unittest discover -s RemoteAgent/tests`; `test_perf_golden` green |
| No home deep-walk hang | Full status must not return to multi-second $HOME walks |

---

## Out of budget scope

- Inference TTFT / tokens-sec  
- First SSH tunnel establish  
- App cold launch to first paint  
- UI frame time / menu open animation  
- Cross-host A/B without fingerprint match  

---

## Baseline column (fill in BASELINE phase)

| Metric ID | Budget | Baseline | Status |
|-----------|-------:|---------:|--------|
| `A.e2e_refresh_p95` | ≤ 3000 ms | *TBD* | open |
| `A.per_store_status_p95` remote | ≤ 1000 ms | *TBD* (prior 640) | open |
| `A.mac_rss_peak` | ≤ 250 MB | *TBD* | open |
| `B.client_host_metrics_p95` | ≤ 400 ms | *TBD* | open |
| `B.poll_once_p95` N=2 | ≤ 1000 ms | *TBD* | open |
| `B.poll_cycle_slack` | ≥ 750 ms | *TBD* | open |
| `C.status_payload_p95` N=20 | ≤ 1000 ms | *TBD* | open |
| `C.status_payload_mean` stretch | ≤ 50 ms | *TBD* | open |

---

## Emergency rollback (when optimization starts later)

If a same-host fingerprinted rerun breaches hard p95 or RSS after a code change: revert the single lever, re-run ≥20 sample baseline, do not stack further changes.
)

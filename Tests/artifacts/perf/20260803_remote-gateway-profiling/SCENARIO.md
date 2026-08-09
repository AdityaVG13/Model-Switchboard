# SCENARIO — multi-gateway menu bar + remote host metrics

**Run ID:** `20260803_remote-gateway-profiling`  
**Branch (expected):** `feature/remote-gateways`  
**Phase:** DEFINE only (no baseline, fingerprint, profile, or optimization this pass)  
**Skill:** profiling-software-performance  
**Product surface:** ModelSwitchboardApp (macOS menu bar) + Python RemoteAgent

Prior single-agent discovery work lives under
`Tests/artifacts/perf/20260801T164821Z_6cacd65/` (status/ports discovery only).
This DEFINE expands the product path to **multi-gateway refresh cadence** and
**host metrics polling**, which the menu bar now exercises continuously.

---

## Stakeholder / decision

User via `/profiling-software-performance` skill loop pass 1 of 10. Decision
hinges on: where multi-gateway menu bar latency and memory land relative to
cadence budgets before any extreme-software-optimization pass.

---

## Shared ground rules (all scenarios)

| Item | Rule |
|------|------|
| Cold vs warm | **Warm** agent process (already `serve`); first-request after cold start is out of band |
| Network modes | Measure **direct** (loopback or tailnet) and **SSH tunnel** separately when both apply; never blend |
| Variance envelope | ≤10% p95 drift same host → noise; >10% investigate; >20% or 3 consecutive >10% → escalate |
| Sample size | Wall baselines: ≥20 runs (hyperfine or equivalent); microbench assembly: ≥50 after 3–5 warmups |
| Fingerprint | Deferred to ENVIRONMENT phase — do **not** invent host numbers here |
| Out of scope (global) | Model inference TTFT/TPS, CUDA load of user models, SSH establish first-connect, full app cold-start, UI layout/FPS, doctor report content quality |

### Code anchors (measurement-only reference)

| Component | Path | Cadence / behavior |
|-----------|------|--------------------|
| Multi-gateway hub | `Sources/ModelSwitchboardApp/Gateways/GatewayHub.swift` | `refreshAll()` fans out `Task { await store.refresh() }` per store; manual debounce 0.75s |
| Per-store refresh | `Sources/ModelSwitchboardApp/SwitchboardStore/SwitchboardStore+Refresh.swift` | `fetchStatus()` + `fetchDoctorReport()`; `isRefreshing` coalesces |
| Auto-refresh policy | `Sources/ModelSwitchboardCore/RefreshPolicy.swift` | idle **600s**, activeRuntime **10s**, benchmarking **10s**, pendingAction **5s** |
| Host metrics monitor | `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift` | default interval **3s**; **sequential** poll of enabled remotes |
| Client routes | `Sources/ModelSwitchboardCore/ControllerClient.swift` | `GET /api/status`, `GET /api/host/metrics` |
| Agent status | `RemoteAgent/model_switchboard_agent.py` → `AgentService.status_payload` | one `list_listening_tcp` + claims + discovery when full list |
| Agent host metrics | `host_metrics_payload()` + route `GET /api/host/metrics` | CPU + memory + GPU (`nvidia-smi` cache TTL **2.0s**) |

**Doc drift note:** `HelpView` still says "polls every 30 seconds while a model is live"; `AutoRefreshPolicy.activeRuntimeInterval` is **10s**. DEFINE and budgets use **code (10s)** as ground truth.

---

## Scenario A — `multi_gateway_status_refresh`

### Name
`multi_gateway_status_refresh`

### What we measure
End-to-end status board refresh when **one local** SwitchboardStore and **N remote**
gateway stores all run `refresh()` under GatewayHub (manual `refreshAll` and
auto-refresh cadence).

### Inputs

| Parameter | Default for baseline | Notes |
|-----------|---------------------:|-------|
| Local gateway | 1 (loopback controller) | Always present |
| Remote gateways (N) | **2** enabled | Product-typical; also record N=1 and N=4 if available |
| Remote kind | `direct` (tailnet) preferred; separate card for `ssh` if tunnel established | SSH needs tunnel `.established` |
| Models live | **activeRuntime** mode (≥1 ready/running on ≥1 gateway) | Forces 10s auto-refresh interval |
| Idle control | optional second card with **0** ready/running | Forces 600s idle interval (cadence only; not latency) |
| Agent profiles per remote | representative remote inventory (≤8 claimed ports, handful of profiles) | Match prior spark-like load when possible |
| Client timeouts (remote) | request 5s / resource 15s | From `GatewayHub.makeRemoteStore` |

### Workload steps

1. App (or harness) has local store + N remote stores attached and auto-refresh started for direct remotes / established tunnels.
2. Trigger **one** `GatewayHub.refreshAll()` (manual path) **or** wait one auto-refresh tick per store.
3. Each store: `ControllerClient.fetchStatus()` → apply payload; optionally doctor in parallel (`async let`).
4. Observe completion of all in-flight store refreshes (wall from kick to last store `lastUpdated`).

### Expected output (golden / behavioral)

- Every healthy gateway produces a status payload with `statuses` array; each status row retains string `log_path` when present (parity with prior golden).
- Hub aggregate summary remains coherent: local + remote ready/total counts update without empty board while agents respond 200.
- No store stuck with `isRefreshing == true` after client timeout budget.
- Cached fallback only when controller truly unavailable (not on successful path).

### Success metrics

| Metric ID | Definition | Primary? |
|-----------|------------|:--------:|
| `A.e2e_refresh_p95` | Wall from `refreshAll()` kick → last participating store finishes apply | **yes** |
| `A.per_store_status_p95` | Client wall for single `GET /api/status` (local vs each remote) | yes |
| `A.per_store_refresh_p95` | Full `SwitchboardStore.refresh()` wall (status + doctor + apply) | yes |
| `A.agent_status_onhost_p95` | On-host agent `status_payload()` (no network) | supporting |
| `A.sustained_poll_ok` | Under activeRuntime (10s): no refresh pile-up (overlapping refresh skipped via coalesce; error rate 0 on healthy agents over 5 min) | yes |
| `A.mac_rss_peak` | Peak RSS of ModelSwitchboardApp during 5 min multi-gateway active refresh | yes |
| `A.agent_rss_peak` | Peak RSS of each remote agent process during same window | supporting |

### "Fast enough" (product)

- A multi-gateway refresh must finish **well under the active auto-refresh interval (10s)** so the next tick does not stack.
- Menu bar should not feel stuck after manual refresh: e2e across 1 local + 2 remotes should complete in **low single-digit seconds** on tailnet (see BUDGETS.md).

### Measurement plan (later phases; not this pass)

- Agent/client wall: hyperfine or scripted curl ≥20 against `/api/status` per endpoint.
- App e2e: env-gated `perf.profile.*` spans on `SwitchboardStore.refresh` / `GatewayHub.refreshAll` (INSTRUMENT phase).
- RSS: `sample` / Activity Monitor / `ps` for app; `ps` RSS on agent host (as in prior `agent_rss.txt`).

### Scope boundary

Out of scope for A: host metrics route, SSH first connect, model start/stop actions, benchmark panel.

---

## Scenario B — `remote_host_metrics_poll`

### Name
`remote_host_metrics_poll`

### What we measure
The continuous **Remote Hosts** metrics path: Mac `RemoteHostMetricsMonitor`
polling each enabled remote `GET /api/host/metrics`, plus agent
`host_metrics_payload()` cost (CPU sample, memory, optional `nvidia-smi`).

### Inputs

| Parameter | Default for baseline | Notes |
|-----------|---------------------:|-------|
| Remote gateways (N) | **2** enabled | Sequential poll in `pollOnce` |
| Poll interval | **3s** (default `RemoteHostMetricsMonitor`) | Product default |
| Tunnel state (SSH) | `.established` for SSH remotes; skip/error path measured separately | Monitor short-circuits when not established |
| GPU | Prefer one remote **with** nvidia-smi and one without if available | Exercises cache hit vs unavailable |
| Duration (steady) | **5 minutes** continuous poll for RSS + error rate | Cadence product path |

### Workload steps

1. Attach monitor to GatewayHub; `start()` with interval 3s.
2. Each cycle: for each enabled remote runtime, `client.fetchHostMetrics()` sequentially.
3. Agent serves `host_metrics_payload()` (GPU snapshot may hit 2.0s TTL cache).
4. UI entries update `metrics` / `error` / `unsupported` without dropping last good metrics on transient failure.

### Expected output (golden / behavioral)

- JSON decodes to `HostMetricsPayload` (`host`, `collected_at`, `cpu_percent`, `memory`, `gpus`, `gpu_source`, `processes`, `agent_version`).
- Older agents without the route → `unsupported` true with clear message (not a crash).
- Transient errors preserve last good `metrics` when present.
- SSH not established → explicit tunnel message, no hung poll beyond client timeouts.

### Success metrics

| Metric ID | Definition | Primary? |
|-----------|------------|:--------:|
| `B.agent_host_metrics_p95` | On-host wall for `host_metrics_payload()` / `GET /api/host/metrics` local | **yes** |
| `B.client_host_metrics_p95` | Client wall Mac → remote `GET /api/host/metrics` (direct) | **yes** |
| `B.poll_once_p95` | Full sequential `pollOnce` across N remotes | **yes** |
| `B.poll_cycle_slack` | `interval (3s) − poll_once_p95` must stay **positive** with margin | yes |
| `B.sustained_error_rate` | Failed polls / total over 5 min on healthy agents | yes |
| `B.mac_rss_peak` | App RSS during 5 min metrics-only steady state (status idle if possible) | supporting |
| `B.agent_rss_peak` | Agent RSS during metrics poll storm (3s client cadence) | supporting |
| `B.throughput_polls` | Successful host-metrics polls per minute (N remotes × ~20/min at 3s) | supporting |

### "Fast enough" (product)

- A single host-metrics fetch must be cheap enough that **N sequential remotes finish inside the 3s interval** with headroom (see BUDGETS.md).
- GPU path must not block the panel: `nvidia-smi` cost amortized by **2s TTL** — measure cold vs warm cache separately.

### Measurement plan (later phases; not this pass)

- hyperfine ≥20 on `/api/host/metrics` (warm cache and forced cold if injectable).
- App: spans on `RemoteHostMetricsMonitor.pollOnce` / `fetch`.
- Attribute wait vs busy: network RTT vs agent CPU (prior status path showed ~200ms RTT Mac↔Spark).

### Scope boundary

Out of scope for B: full status discovery inventory, doctor, benchmarks, model VRAM of inference engines except as reported fields.

---

## Scenario C — `agent_status_payload_many_profiles` (optional third)

### Name
`agent_status_payload_many_profiles`

### What we measure
Agent-side assembly cost of `status_payload()` as profile count and discovery
surface grow (profiles + claims + listeners), independent of Mac UI.

### Inputs

| Parameter | Default for baseline | Notes |
|-----------|---------------------:|-------|
| Profile count | **20** `.env` profiles | Scaling ladder: 5 / 20 / 50 if cheap |
| Listening TCP rows | **8** model-like (or real) | Prior spark baseline used 8 |
| Port claims | **3–8** under scan roots | Prior golden used 3 |
| Probes | Prefer inventory-backed; document whether live HTTP probes enabled | Live probes only if intentional |
| Host | On-host agent (no tailnet) for CPU truth; optional client wall separate | |

### Workload steps

1. Configure agent root with N profiles and claim dirs.
2. Warm: 3–5 × `status_payload()`.
3. Time ≥50 × `status_payload()` (or hyperfine HTTP `/api/status` on-host).
4. Optional cProfile / py-spy one-shot for INTERPRET later.

### Expected output (golden / behavioral)

- `statuses` length ≥ profile count (plus claim/listener extras when full list).
- Claim discovery shape covered by Swift `RemoteAgentConformanceTests` (Python golden suite removed).
- No home-directory deep-walk regression (prior hang ~15s must not return).

### Success metrics

| Metric ID | Definition | Primary? |
|-----------|------------|:--------:|
| `C.status_payload_p95` | On-host `status_payload()` p95 for N=20 | **yes** |
| `C.status_payload_mean` | Mean for comparison to prior ~16ms mock / ~303ms pre-opt spark | yes |
| `C.scaling_ratio` | p95(N) / p95(5) for N in {5,20,50} | yes |
| `C.agent_rss_peak` | Peak RSS during status microbench | yes |
| `C.list_listening_share` | Fraction of wall in `list_listening_tcp` (profile phase) | supporting |

### "Fast enough" (product)

- On-host assembly stays **interactive** for menu bar 10s cadence: p95 well below 1s even at 20 profiles; aspirational mean ≤50ms remains the stretch target from prior loop (see BUDGETS.md).
- Scaling should be near-linear in profiles for pure assembly; super-linear inventory is a defect signal.

### Scope boundary

Out of scope for C: Mac UI, host metrics route, multi-gateway fan-out (covered in A).

---

## Scenario matrix (what later phases must produce)

| Scenario | Primary walls | RSS | Throughput / cadence |
|----------|---------------|-----|----------------------|
| A multi_gateway_status_refresh | e2e refreshAll; per-store status | Mac app + agents | No pile-up at 10s active |
| B remote_host_metrics_poll | host metrics client + pollOnce | Mac app + agents | Completes inside 3s interval |
| C agent_status_payload_many_profiles | status_payload on-host | Agent only | ops/sec optional microbench |

---

## Prior numbers (context only — not this run's baseline)

From `20260801T164821Z_6cacd65` + pass-13 hand-off (status discovery era):

| Source | Metric | Value |
|--------|--------|------:|
| Tailnet GET /api/status | p95 | 640 ms |
| Tailnet GET /api/ports | p95 | 576 ms |
| Spark on-host status_payload (pre skill-loop opts) | mean | ~303 ms |
| list_listening_tcp share | mean | ~234 ms |
| Local mock-inventory status_payload ×50 (post opts) | p95 | ~17.5 ms |
| Agent process RSS sample | RSS | ~32 MB |

These inform budgets; ENVIRONMENT + BASELINE phases must re-measure on a fingerprinted host.

---

## Next phase (not this pass)

1. ENVIRONMENT — `fingerprint.json` via skill `env_fingerprint.sh` (Mac + remote agent host).
2. BASELINE — ≥20-run walls for A/B primary metrics; write BASELINE.md.
3. INSTRUMENT — env-gated spans on refresh / pollOnce / status_payload / host_metrics_payload.
)

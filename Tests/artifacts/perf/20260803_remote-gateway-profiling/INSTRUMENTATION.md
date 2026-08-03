# INSTRUMENTATION — remote-gateway profiling (phase 4)

**Scope:** measurement only. No caching redesigns, algorithm changes, or parallelization for speed.  
**Default:** OFF. Product behavior is unchanged unless an env flag is set.  
**Date / run dir:** `20260803_remote-gateway-profiling`

Prior phases in this run dir: `SCENARIO.md`, `BUDGETS.md`, `fingerprint.json`, `BASELINE.md`, `baseline_*.json`.

---

## Flags

| Variable | Values (truthy) | Effect |
|----------|-----------------|--------|
| `MSW_PERF_PROFILE` | `1`, `true`, `yes`, `on` (case-insensitive) | Enable span timing |
| `MSW_AGENT_PERF` | same | Alias for the same gate (agent + Mac app) |
| `MSW_PERF_JSONL` | absolute/relative path | **Agent only:** also append one JSON object per span to this file |

Unset / empty / other values → instrumentation is a no-op (no stderr, no JSONL, no extra work beyond a cheap env check).

---

## What is instrumented

### Remote agent (`RemoteAgent/model_switchboard_agent.py`)

| Span name | When | Stages (`stages_ms`) | Tags |
|-----------|------|----------------------|------|
| `status_payload` | `AgentService.status_payload()` (also HTTP `GET /api/status`) | `profiles_load`, `list_listening_tcp`, `profile_statuses`, `scan_port_claim_directories`, `discover_live_model_endpoints`, `merge_discovery` (full list only), `benchmark_status` | `n_profiles`, `n_statuses`, `n_listeners`, `n_claims`, `n_live`, `full_discovery` |
| `host_metrics_payload` | `host_metrics_payload()` / `GET /api/host/metrics` | `gpu`, `memory`, `cpu`, `assemble` | `gpu_source`, `n_gpus` |

Emit path:

1. **stderr** line (always when enabled):
   ```
   perf.profile.span_summary {"duration_ms":12.345,"span":"status_payload",...}
   ```
2. Optional **JSONL** when `MSW_PERF_JSONL` is set (same fields + `ts` unix time).

### Mac app (Swift, env via process environment)

| Span name | File | Notes |
|-----------|------|--------|
| `SwitchboardStore.refresh` | `SwitchboardStore+Refresh.swift` | Wall for one store refresh (fetch status + doctor + loopback probe path). Tag: `n_statuses`. |
| `RemoteHostMetricsMonitor.pollOnce` | `RemoteHostMetricsMonitor.swift` | Wall for one sequential poll of all enabled remotes. Tag: `n_remotes`. |

Swift emits the same `perf.profile.span_summary {json}` line on **stderr** when the flag is set. No JSONL helper on the app side (keep surface small).

`GatewayHub.refreshAll` multi-gateway fan-out is **not** wrapped separately; time per-store `SwitchboardStore.refresh` lines and compare to scenario A budgets. Deeper hub-level span can be added later if needed.

---

## How to enable

### Agent (local or remote host)

```bash
# One-shot CLI status with spans on stderr
MSW_PERF_PROFILE=1 python3 RemoteAgent/model_switchboard_agent.py status

# Serve with profiling (stderr of the agent process)
MSW_PERF_PROFILE=1 MSW_PERF_JSONL=/tmp/msw-agent-spans.jsonl \
  python3 RemoteAgent/model_switchboard_agent.py serve --port 8877

# Alias flag
MSW_AGENT_PERF=1 python3 -c "
from pathlib import Path
import model_switchboard_agent as a
# … construct AgentService and call status_payload / host_metrics_payload
"
```

Capture HTTP path:

```bash
MSW_PERF_PROFILE=1 python3 RemoteAgent/model_switchboard_agent.py serve --port 8877 2>/tmp/agent-perf.err &
curl -sS http://127.0.0.1:8877/api/status >/dev/null
curl -sS http://127.0.0.1:8877/api/host/metrics >/dev/null
grep 'perf.profile.span_summary' /tmp/agent-perf.err
```

### Mac app

Launch with the env var in the process environment (Xcode scheme → Environment Variables, or):

```bash
MSW_PERF_PROFILE=1 open -a "Model Switchboard Plus"   # if installed; or run from Xcode
# Read Console / Xcode debug console / redirected stderr for:
#   perf.profile.span_summary {"span":"SwitchboardStore.refresh",...}
#   perf.profile.span_summary {"span":"RemoteHostMetricsMonitor.pollOnce",...}
```

---

## Sample output

### Agent `status_payload` (full discovery)

```
perf.profile.span_summary {"duration_ms":18.421,"full_discovery":true,"n_claims":0,"n_listeners":8,"n_live":1,"n_profiles":5,"n_statuses":6,"span":"status_payload","stages_ms":{"benchmark_status":0.12,"discover_live_model_endpoints":1.05,"list_listening_tcp":9.8,"merge_discovery":0.4,"profile_statuses":4.1,"profiles_load":2.1,"scan_port_claim_directories":0.85}}
```

### Agent `host_metrics_payload`

```
perf.profile.span_summary {"duration_ms":6.203,"gpu_source":"unavailable","n_gpus":0,"span":"host_metrics_payload","stages_ms":{"assemble":0.05,"cpu":4.9,"gpu":0.8,"memory":0.4}}
```

### JSONL line (`MSW_PERF_JSONL`)

```json
{"duration_ms":6.203,"gpu_source":"unavailable","n_gpus":0,"span":"host_metrics_payload","stages_ms":{"assemble":0.05,"cpu":4.9,"gpu":0.8,"memory":0.4},"ts":1754236800.12}
```

### Swift

```
perf.profile.span_summary {"span":"SwitchboardStore.refresh","duration_ms":142.500,"n_statuses":5}
perf.profile.span_summary {"span":"RemoteHostMetricsMonitor.pollOnce","duration_ms":88.100,"n_remotes":2}
```

---

## Contract (profiling-only)

- **No optimizations** in this phase: no new caches, no parallel fan-out for speed, no algorithm rewrites.
- **Default off:** without the env flag, code paths are the prior logic plus a cheap boolean env read.
- **Stable product JSON:** response payloads for `/api/status` and `/api/host/metrics` are unchanged; spans go to stderr / JSONL only.
- **Do not leave flags on** in production LaunchAgents / installed apps.

---

## Mapping to scenarios

| Scenario | Span(s) |
|----------|---------|
| A multi-gateway refresh | `SwitchboardStore.refresh` (per store) + agent `status_payload` on each remote |
| B remote host metrics poll | `RemoteHostMetricsMonitor.pollOnce` + agent `host_metrics_payload` |
| C many profiles status | agent `status_payload` stages, especially `list_listening_tcp` / `profile_statuses` |

Use with existing baseline scripts (`bench_baseline.py`) by exporting `MSW_PERF_PROFILE=1` and grepping stderr, or set `MSW_PERF_JSONL` under this run dir for later OPTIMIZE analysis.

---

## Deferred / not instrumented

- Per-remote timing inside `pollOnce` (would need structured multi-span; pollOnce total + agent host_metrics is enough for now).
- `GatewayHub.refreshAll` dedicated span (derive from per-store refresh lines).
- Controller (local Swift `ModelSwitchboardController`) parity spans — local path already covered by prior run `20260801T164821Z_6cacd65` cProfile artifacts.
- cProfile / Instruments — optional follow-up; this phase is wall-clock spans only.

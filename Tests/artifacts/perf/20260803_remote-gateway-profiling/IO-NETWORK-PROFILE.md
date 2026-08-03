# IO-NETWORK-PROFILE — remote poll + agent inventory I/O

**Run id:** `20260803_remote-gateway-profiling`  
**Mode:** LOCAL-ONLY measurements + code-path attribution (no remote RTT capture)  
**Scope:** Attribute **wait vs busy** for agent inventory I/O and Mac remote poll sequencing. **No optimizations.**  
**Date:** 2026-08-03

---

## Executive summary

| Path | Dominant cost class | Evidence |
|------|---------------------|----------|
| Agent `GET /api/status` (full discovery) | **Wait-ish inventory** on cache miss: `list_listening_tcp` → `lsof`/`ss` subprocess + `select.poll` inside `communicate` (~45–65 ms cold on this Mac). Cache hit (~75 ms TTL) is **busy-light** shallow copy (~µs). | CPU-PROFILE stage p95; this run cold/warm JSON; cProfile |
| Agent `GET /api/host/metrics` | **Warm ~0** busy (cache). **Cold ~2 ms** busy-ish GPU probe path (`nvidia-smi` miss on macOS). HTTP loopback adds ~6 ms client overhead. | BASELINE + CPU-PROFILE |
| Mac `RemoteHostMetricsMonitor.pollOnce` | **Sequential** `fetchHostMetrics()` over enabled remotes; interval default **3 s**. Network RTT **not measured** (local-only). Sequential wall scales ~N × (RTT + server). | Swift source reading |
| Network RTT | **Not measured** this campaign. Impact of sequential N remotes estimated from local HTTP baselines only. | BASELINE HTTP |

---

## a) Agent inventory I/O

**Source:** `RemoteAgent/model_switchboard_agent.py`

### Cache TTL

```
LISTENING_TCP_CACHE_TTL_SECONDS = 0.075   # 75 ms
```

- Module lock `_listening_tcp_cache_lock`; miss fills **under lock** (coalesces concurrent misses; no stampede).
- Returns **caller-private shallow copy** of rows every call.
- Doc intent: concurrent / back-to-back status polls skip re-running `ss`/`lsof`; snapshot may lag ≤TTL.

### `list_listening_tcp` uncached order

1. **Linux `/proc` path** (`_linux_proc_listening_endpoints`): read `/proc/net/tcp` + `/proc/net/tcp6`, map socket inodes → pid via `/proc/*/fd` symlinks, resolve cmdline via `/proc/<pid>/cmdline` (no spawn). Returns `None` when `/proc/net/tcp` unreadable → fall through.
2. **`ss -lntupH`** via `subprocess.run(..., timeout=5)` when /proc path unavailable.
3. **`lsof -nP -iTCP -sTCP:LISTEN`** via `subprocess.run(..., timeout=8)` if still empty (macOS / sparse ss).

**This host (Mac loopback fixture):**  
`proc_net_tcp=false`, `ss=false`, `lsof=true` → always **lsof fallback** for uncached inventory.

### Related /proc vs subprocess helpers

| Helper | Linux | Non-Linux / miss |
|--------|-------|------------------|
| `process_command` | `/proc/<pid>/cmdline` | `ps -o command=` subprocess |
| `process_stat_state` / alive / zombie | `/proc/<pid>/stat` | `ps -o state=` then `kill(0)` |
| `process_rss_mb` | `/proc/<pid>/status` VmRSS | `ps -o rss=` |
| Host memory | `/proc/meminfo` | unavailable source |
| Host CPU % | `/proc/stat` deltas | `os.getloadavg` fallback |
| GPU | `nvidia-smi` subprocess (TTL 2.0 s cache) | `gpu_source=unavailable` |

### Hot call sites

- `status_payload`: **one** `list_listening_tcp()` shared for profile statuses + claim scan + live discovery (no N× inventory).
- `port_is_listening`: **not** lsof — loopback `socket.create_connection` timeout 0.25 s (doc: “lsof/ss are far too slow to poll”).
- Discovery probes: `urllib` to `/health`, `/v1/health`, `/v1/models` with `DISCOVERY_PROBE_TIMEOUT=0.6`, budget `DISCOVERY_PROBE_BUDGET=24` (wait-ish network local). On this fixture `n_live=0` so probe stage ≈ 0.

### Measured cold vs warm (this session)

File: [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json)

| Condition | n | mean | p50 | p95 | max |
|-----------|---|------|-----|-----|-----|
| Cold (clear cache each) | 5 | **56.9 ms** | 56.1 | 63.3 | 65.0 |
| Warm (within 75 ms TTL) | 20 | **0.001 ms** | 0.001 | 0.002 | 0.005 |
| Uncached forced | 5 | **56.0 ms** | 56.7 | 57.9 | 58.0 |

Listeners sample: **16**. Aligns with prior CPU-PROFILE: stage p95 ~**45–48 ms** on miss, p50 ~**0.003–0.005 ms** on hit.

### Prior status stage ranking (CPU-PROFILE, timed N=20)

| Stage | Share Σ | mean | p50 | p95 | Class |
|-------|---------|------|-----|-----|-------|
| **list_listening_tcp** | **~61%** | 4.6 | **0.003** | **~45** | wait-ish on miss |
| profile_statuses | ~22% | 1.6 | 1.6 | 1.8 | mixed (local probes) |
| scan_port_claim_directories | ~11% | 0.8 | — | — | busy FS walk |
| profiles_load | ~5% | 0.4 | — | — | busy |
| discover_live… | ~0.3% | 0.04 | — | — | wait-ish if probes |

HTTP `/api/status` loopback hyperfine: mean **35.6 ms**, p50 **9.8 ms**, p95 **~100 ms** (includes curl process + bimodal cache hit/miss).

---

## b) Mac client sequential host-metrics poll model

**Source:** `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift`

```
init(intervalSeconds: TimeInterval = 3)
// start(): while !cancelled { pollOnce(); sleep(intervalSeconds) }

func pollOnce() async {
    let runtimes = hub.enabledRemoteRuntimes
    // Sequential polls keep MainActor isolation simple; few remotes expected.
    for runtime in runtimes {
        let (id, entry) = await fetch(runtime: runtime)
        entries[id] = entry
    }
}

// fetch → client.fetchHostMetrics()  // GET /api/host/metrics
// SSH: skip network until tunnelState == .established
```

- **Default interval: 3 seconds** between full `pollOnce` sweeps.
- **Strictly sequential** over enabled remotes (not TaskGroup / parallel).
- Optional span: `RemoteHostMetricsMonitor.pollOnce` when `MSW_PERF_PROFILE=1` or `MSW_AGENT_PERF=1`.
- Client API: `ControllerClient.fetchHostMetrics()` → `GET /api/host/metrics` (`Sources/ModelSwitchboardCore/ControllerClient.swift`).

Agent side: `host_metrics_payload()` stages gpu → memory → cpu → assemble; GPU snapshot cached **2.0 s**.

| host_metrics | Value |
|--------------|-------|
| In-process warm p95 | **~0.008–0.06 ms** |
| In-process cold | **~2.1–2.3 ms** (gpu stage dominant even when unavailable) |
| HTTP loopback warm p95 | **~6.2 ms** (hyperfine curl) |

---

## c) Network RTT not measured — sequential N remotes vs 3 s interval

**Fact:** This campaign is **LOCAL-ONLY**. No WAN/LAN RTT samples to remote agents.

### Estimate using BASELINE local HTTP times

Treat local loopback HTTP as a **lower bound** on per-remote poll cost (real remotes add RTT + TLS/SSH tunnel + remote CPU).

| Component (local) | p50-ish | p95-ish |
|-------------------|---------|---------|
| HTTP `/api/host/metrics` | ~5.8 ms | ~6.2 ms |
| In-process host_metrics warm | ~0.01 ms | ~0.06 ms |
| ⇒ transport+client overhead on loopback | ~**5–6 ms** | |

**Sequential `pollOnce` wall (lower bound, no real RTT):**

| N remotes | Estimated sequential wall (local LB) | vs 3 s interval |
|-----------|--------------------------------------|-----------------|
| 1 | ~6 ms | 0.2% of interval |
| 3 | ~18 ms | 0.6% |
| 10 | ~60 ms | 2% |
| 50 | ~300 ms | 10% |

**If remote RTT ≈ R ms one-way effective HTTP RTT (request+response):**  
`pollOnce ≈ N × (R + server_work)`  
Server warm host_metrics ≪ 1 ms; cold first hit ~2 ms (+ possible nvidia-smi on GPU hosts).

| Hypothetical RTT (full HTTP) | N=3 sequential | N=10 | Fits in 3 s? |
|------------------------------|----------------|------|--------------|
| 5 ms (LAN-like, ≈ loopback scale) | 15 ms | 50 ms | yes |
| 50 ms | 150 ms | 500 ms | yes |
| 200 ms (remote/VPN-ish) | 600 ms | 2.0 s | N=10 tight |
| 500 ms | 1.5 s | 5.0 s | **N≥10 overruns 3 s** |

**Implication (profile only, no fix):** sequential polling is fine for “few remotes” as the code comment states; large N or high RTT makes `pollOnce` duration approach or exceed the 3 s interval (back-to-back sweeps, stale UI). Parallelism would change wait overlap — **out of scope**.

Status polling from Mac (if any) would face similar sequential/interval math; status cold inventory on remote (~50 ms lsof or /proc) is usually smaller than multi-hundred-ms RTT.

---

## d) Wait vs busy attribution

### Taxonomy used

| Class | Meaning | Examples in this stack |
|-------|---------|------------------------|
| **Wait-ish** | Thread blocked on kernel/IO/child completion; little Python/Swift CPU | `subprocess.communicate` → `select.poll`; socket connect timeout; HTTP client await; SSH tunnel wait |
| **Busy** | CPU parsing, FS walks of many small files, JSON assemble | claim-dir scan, profile load, row copy, /proc text parse |
| **Busy-light / noise** | Sub-ms bookkeeping | warm TTL cache hit, warm GPU metrics cache |

### Inventory path (macOS cold)

cProfile on status loop (prior CPU-PROFILE) — **subprocess wait dominates wall**:

| Symbol | cumulative (20× status) | Role |
|--------|-------------------------|------|
| `list_listening_tcp` / `_list_listening_tcp_uncached` | 0.191 s | inventory |
| `subprocess.run` | 0.188 s | spawn + wait |
| `subprocess.communicate` / `_communicate` | 0.108 s | pipe drain |
| **`{method poll of select.poll objects}`** | **0.102 s** | **wait-ish** |
| `fork_exec` | 0.025 s | spawn busy/sys |

**Conclusion:** cold `list_listening_tcp` on Mac is **mostly wait-ish** (poll for `lsof` pipes) plus spawn overhead; not pure Python CPU. Warm path is **busy-light** (lock + list/dict copy).

### Inventory path (Linux, code model)

Prefer **busy-ish FS**: read `/proc/net/tcp{,6}` + scan `/proc/*/fd` + cmdline — no subprocess if /proc works. Still I/O-bound but in-process reads (not select.poll). Fallback ss/lsof reintroduces wait-ish.

### host_metrics

| Stage | Warm | Cold (macOS no GPU) |
|-------|------|---------------------|
| gpu | 0 (cache) | ~2 ms wait-ish/busy probe (`nvidia-smi` miss path) |
| memory / cpu | ~0.004 ms | tiny /proc or loadavg |
| assemble | ~0.002 ms | busy-light |

### Mac remote poll

| Segment | Class |
|---------|-------|
| `await client.fetchHostMetrics()` | **Wait-ish** network (async) |
| Sequential for-loop | Accumulates wait; no overlap |
| Tunnel not established | Early return — no network |
| MainActor entry updates | Busy-light |

### Discovery (status full)

| Segment | Class |
|---------|-------|
| `list_listening_tcp` | wait-ish miss / busy-light hit |
| `discover_live_model_endpoints` probes | wait-ish HTTP local (budgeted) |
| claim directory scan | busy FS |

---

## Evidence index

| Artifact | Role |
|----------|------|
| [`list-listening-tcp-cold-warm.json`](./list-listening-tcp-cold-warm.json) | This phase: cold ~57 ms / warm ~0.001 ms |
| [`cpu-profile-summary.json`](./cpu-profile-summary.json) | Stage ranks; list_listening p95 |
| [`CPU-PROFILE.md`](./CPU-PROFILE.md) | Narrative; cProfile poll note |
| [`cprofile.txt`](./cprofile.txt) | select.poll / subprocess.communicate |
| [`baseline-derived-http-status.json`](./baseline-derived-http-status.json) | HTTP status p95 |
| [`baseline-derived-http-host-metrics.json`](./baseline-derived-http-host-metrics.json) | HTTP metrics ~6 ms |
| [`BASELINE.md`](./BASELINE.md) | N5/N20/N50 status scaling |
| Code | `RemoteAgent/model_switchboard_agent.py` (TTL 0.075; inventory; host_metrics) |
| Code | `Sources/ModelSwitchboardApp/Gateways/RemoteHostMetricsMonitor.swift` (sequential 3 s) |

---

## Non-goals (explicit)

- No code changes, no cache TTL changes, no parallel poll.
- No remote network measurement (would need multi-host harness).
- No commit.

---

## Status

**DONE** — I/O and network wait vs busy attributed for inventory + remote poll paths; sequential N vs 3 s interval estimated from local HTTP only; cold/warm inventory evidence captured.

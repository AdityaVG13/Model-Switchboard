# ENVIRONMENT — host fingerprint notes

**Run ID:** `20260803_remote-gateway-profiling`  
**Phase:** ENVIRONMENT only (no baseline, no profile, no optimization)  
**Captured:** see `fingerprint.json` → `captured_at_utc`  
**Git:** `a25d02e` on `feature/remote-gateways` (clean working tree at capture)

---

## Host summary

| Item | Value |
|------|-------|
| Machine | MacBook Pro (Mac17,6), Apple M5 Max |
| Cores | 18 (6 Super + 12 Performance) |
| RAM | 48 GB |
| OS | macOS 26.5 (25F71), Darwin 25.5.0 arm64 |
| Swift | 6.3.3 / Xcode 26.6 |
| Python | 3.14.6 (Homebrew) |
| Power | AC Power, battery ~80%, `powermode=0` (automatic) |
| Storage | Internal APFS SSD (~2 TB Apple Fabric) |

Full machine-readable record: [`fingerprint.json`](./fingerprint.json).

Same physical host family as prior run
`Tests/artifacts/perf/20260801T164821Z_6cacd65/` (also M5 Max / macOS 26.5).
Comparable for same-host variance envelopes; re-fingerprint if OS, Xcode, or chip
identity changes.

---

## Isolation notes

- **Not a dedicated bench host.** Developer laptop with interactive session, menu
  bar apps, and agent tooling (load averages ~5 / ~4 / ~4 at capture on 18 cores).
- **No** `taskset` / CPU affinity, **no** cgroup / rch isolation, **no** single-user
  boot, **no** closedown of unrelated daemons for this phase.
- Sleep was **prevented** at capture by `caffeinate` and other processes (see
  `fingerprint.json` → `power.sleep_prevented_by`). Display sleep AC = 180 min.
- Network: baselines for remote scenarios must record **direct (tailnet/loopback)
  vs SSH tunnel** separately (DEFINE ground rule). Host fingerprint does not
  freeze remote peer load or latency.
- Swap present (2 GB encrypted, ~0.4 GB used at capture). Prefer re-check if
  baseline RSS or page-fault noise is high.

**Implication for pass 3 baselines:** Prefer a quieter window (load 1m ≪ core count)
and AC power. If p95 drifts >10% vs a same-host re-run, treat load/thermal and
network path before code changes.

---

## What was NOT tuned

Per skill policy (**ASK before OS tuning**):

| Action | Done? |
|--------|-------|
| macOS Low Power / High Power force | **No** (`powermode` left at 0 automatic) |
| `sudo sysctl` / kernel param changes | **No** |
| Linux-style cpufreq governor / turbo / SMT | **N/A** on Apple Silicon; not attempted |
| `perf_event_paranoid` / kptr / nmi_watchdog / THP | **N/A** (Linux fields); not applied |
| Thermal/power governor experiments | **No** |
| Production code changes | **No** |
| App rebuild for a fixed release-perf binary | **No** (fingerprint only) |

`tuning_applied` in `fingerprint.json` records this explicitly. Do not invent a
"performance governor" baseline on this host without an explicit user ask and a
new fingerprint + `tuning.json`.

---

## Cold vs warm caveats (for later baselines)

DEFINE already requires **warm** agent (`serve` already up). Carry forward:

| Mode | Include in wall baselines? | Notes |
|------|----------------------------|-------|
| Warm agent + warm client path | **Yes** (default) | ≥20 runs; drop first 3–5 as warmup if using hyperfine |
| Cold agent start (process spawn → first ready) | **Out of band** | Separate card if ever measured; do not blend with warm p95 |
| Cold app launch (menu bar binary cold start) | **Out of scope** (DEFINE) | |
| First SSH tunnel establish | **Out of scope** | Measure only after tunnel `.established` |
| First status after long idle | Optional separate card | TCP keepalive / sleep may add one-shot latency |
| GPU `nvidia-smi` cache cold vs warm on **remote** | Remote-side | Agent TTL 2.0s; host metrics poll is sequential 3s default |

**Local measurement surface** is this Mac (menu bar + client HTTP). **Remote
agent CPU/GPU** lives on peer hosts and is **not** described by this fingerprint.
When baselining scenarios B/C (host metrics), fingerprint remotes separately or
record peer identity in the baseline card.

---

## Tooling readiness (evidence only)

| Tool | Version / path | Role later |
|------|----------------|------------|
| hyperfine | 1.20.0 | Wall baselines (≥20 runs) |
| uv | 0.11.32 | Python env consistency |
| zs | 1.3.0 | Repo CodeMode (not a perf timer) |
| sample / Instruments | system | macOS on-CPU if PROFILE phase needs it |

Skill script
`~/.cursor/skills/profiling-software-performance/scripts/env_fingerprint.sh`
is **Linux-oriented**; this run used macOS read-only probes instead. No OS
mutation was performed by either path.

---

## Next phase (not this pass)

1. BASELINE — scenarios A/B/C from `SCENARIO.md` / `BUDGETS.md` on this fingerprint  
2. Re-check AC power + load before each baseline card  
3. Still no OS tuning unless user explicitly asks  

**DONE criteria for this phase:** `fingerprint.json` + `ENVIRONMENT.md` present;
no production edits; no tuning applied.

# Pass 03 -- profile_statuses / health-probe cost when inventory is warm

**Decision: ZERO-CHANGE** (no production code edited this pass).

**Lever considered (one):** Reduce `status_payload` stage `profile_statuses` cost -- N× `AgentService.status()` / `_probe_health` -- when listening-TCP inventory is already paid for.

**Prior campaign score:** Impact 2 × Confidence 4 / Effort 3 = **2.67**  
(`Tests/artifacts/perf/20260803_remote-gateway-profiling/OPPORTUNITY-MATRIX.md`, H9).

**Rescore after reading current agent code:** **≤ 1.33** (below ready threshold 2.0).

---

## Code path (current)

| Stage | What runs |
|-------|-----------|
| `list_listening_tcp` | One inventory snapshot (warm after pass-01 TTL 2.0s) |
| `profile_statuses` | For each profile: `status(profile, listeners=listeners)` |

`status()` always starts with:

```text
ready, server_ids = self._probe_health(profile)   # HTTP urlopen; NO listeners param
```

Then, **only if** `listeners is not None` (status_payload always passes it):

| Concern | Inventory path | Live fallback (no listeners) |
|---------|----------------|------------------------------|
| pid from port | `listener_pid_from_inventory` | `listener_pid` → `port_is_listening` + lsof/ss |
| ready without pid | `port_listening_from_inventory` | `port_is_listening` |

`_probe_health` never calls `port_is_listening`. It only:

1. returns early if `HEALTHCHECK_MODE=disabled`
2. blocks non-loopback unless `ALLOW_REMOTE_HEALTHCHECK`
3. else `urllib.request.urlopen(healthcheck_url, timeout=HEALTH_TIMEOUT_SECONDS)` (default mode `openai-models`)

Default health URL is `base_url/models` on the profile loopback port.

---

## Why the "skip live port probes when inventory known" lever is already shipped

**Check 1 -- status_payload always shares inventory into status()**

`status_payload` loads `listeners = list_listening_tcp()` once, then:

```text
self.status(profile, allow_port_fallback=..., listeners=listeners)
```

There is no second per-profile inventory and no deliberate live path inside the warm status_payload loop for pid/listen attribution.

**Check 2 -- InventoryPortLookupTests already assert no live connect/lsof on that path**

`InventoryPortLookupTests` (historical Python suite — removed; contracts now in Swift `RemoteAgentConformanceTests`):

- `test_status_payload_skips_live_port_probes_when_inventory_known` patches `port_is_listening` / `listener_pid` with `AssertionError` and still gets pid/running from the inventory row.
- `test_status_without_listeners_still_uses_live_checks` proves stop/start/watchdog `status()` without inventory still hits live `listener_pid` / `port_is_listening` (correct non-payload path).

Preferential skip when inventory says listening is already the product behavior for **port/pid attribution**.

**Check 3 -- remaining profile_statuses cost is `_probe_health` fail-fast HTTP, not redundant port_is_listening**

Campaign HOTSPOTS/CPU-PROFILE: stage ~**1.6 ms** @ N=20 (~**22%** of stages on inventory hit); cProfile shows N× `status` + N× `socket.connect` from health `urlopen`, not N× inventory.

That connect is:

- **fail-fast connection refused** when nothing listens (steady "all down" path)
- **full HTTP /models (or http-200)** when something listens -- source of truth for `ready` and `server_ids`

---

## Candidate lever rejected (would change ready/running semantics)

**Idea:** If inventory says profile port is **not** listening, skip `_probe_health` and return `(False, [])`.

| Case | Today | With inventory short-circuit |
|------|-------|------------------------------|
| Port down, inventory agrees | ready=false (connect refuse) | ready=false -- isomorphic |
| Port up, inventory agrees | ready from HTTP body | still needs HTTP -- **no win** |
| Port **just** came up, inventory still stale (≤ `LISTENING_TCP_CACHE_TTL_SECONDS` = 2.0s) | live HTTP can set ready=true | inventory skip → ready=false -- **false negative ready** |
| Remote health URL (`ALLOW_REMOTE_HEALTHCHECK`) | live HTTP | local inventory cannot speak for remote host |

Mission constraint: *only implement if clear win **without** changing ready/running semantics.*  
Inventory-gated health skip couples ready lag to inventory TTL (pass-01 already accepted lag for **listen/pid attribution**, not for **health truth**). That is a semantic change, not a pure amortization.

Skipping or batching health when inventory says **listening** cannot replace HTTP: `ready`/`server_ids` require the model API response, not TCP LISTEN alone.

---

## Rescore (post code-read)

| Dimension | Was | Now | Why |
|-----------|----:|----:|-----|
| Impact | 2 | **2** | Absolute ~1.6 ms @ N=20; N=50 mean still green (~24 ms) |
| Confidence (safe isomorphic lever) | 4 | **2** | Preferred skip of live **port** probes is already done; remaining health connect is either required for ready or only skippable with ready lag |
| Effort | 3 | **3** | Still correctness-adjacent if anyone re-opens inventory-gated health |
| **Score** | **2.67** | **≤ 1.33** | Below ready threshold 2.0 |

Remaining cost = **fail-fast (or success-path) health connect that correctness requires for ready/server_ids**. Not a free redundant probe.

---

## Explicitly out of scope / not done this pass

- No agent code change
- No Mac app change
- No commit
- No parallelization of N× HTTP health (separate lever class; still correctness-adjacent wall-clock)
- No change to `discover_live_model_endpoints` (not `profile_statuses`; stage share ~0.3% in campaign)

Note (non-action): `discover_live_model_endpoints` still calls `port_is_listening` on ports already present in `listeners` before `probe_model_endpoint`. That is outside this stage's budget and was not the scored lever.

---

## Evidence anchors

- Agent: `RemoteAgent/model_switchboard_agent.py` -- `status_payload`, `status`, `_probe_health`, `port_listening_from_inventory`
- Tests: Swift `RemoteAgentConformanceTests` (Python `InventoryPortLookupTests` removed)
- Profile: `HOTSPOTS.md` finding 2, `CPU-PROFILE.md` stage rank #2, `OPPORTUNITY-MATRIX.md` row score 2.67, H9 in `HYPOTHESIS-LEDGER.md`
- Prior passes: pass-01 inventory TTL 0.075→2.0s; pass-02 parallel pollOnce (Mac)

---

## Status

**DONE** -- ZERO-CHANGE. Score re-evaluated **below 2.0**. Three specific checks above. No production edits. No commit.

# Pass 01 -- measure (inventory cache TTL)

**Host:** macOS (workspace machine), live `list_listening_tcp` → lsof path.  
**Policy:** `LISTENING_TCP_CACHE_TTL_SECONDS = 2.0` (was 0.075).  
**Date:** 2026-08-03.

## Microbench (this machine)

N=5 successive calls after policy change:

| Path | mean_ms | p50_ms | min_ms | max_ms |
|------|---------|--------|--------|--------|
| **Miss** (`clear_listening_tcp_cache` then inventory) | 109.1 | 100.2 | 53.5 | 202.4 |
| **Hit** (within 2.0s TTL, no clear) | 0.003 | 0.001 | 0.001 | 0.006 |

- Inventory rows observed: 16  
- Hit path avoids spawn/lsof entirely (shallow row copies only).  
- Approx mean speedup hit vs miss: ~10⁴× on wall time for the inventory call alone.

## Interpretation vs profile

Profiling hand-off (`20260803_remote-gateway-profiling`): cache miss → lsof dominated `status_payload` p95 (~45–57ms). That matches miss-path order of magnitude here (~50–200ms depending on system load).

With TTL=2.0s:

- Any second+ call within 2s of a fill pays ~µs (hit), not tens of ms (miss).
- Cross-request reuse covers rapid UI re-polls, multi-client bursts, and concurrent status/ports/scan in the same window.
- A lone poll every 10s still misses once per tick if spacing >2s; that is accepted lag policy, not a regression of per-request single inventory.

## Profile before (from hand-off context)

| Metric | Value |
|--------|--------|
| LISTENING_TCP_CACHE_TTL_SECONDS | 0.075 |
| list_listening_tcp on miss (macOS p95 contrib) | ~45–57ms |
| Hit rate for ~10s UI poll spacing | ~0 (cold miss almost every poll) |

## After (this pass)

| Metric | Value |
|--------|--------|
| LISTENING_TCP_CACHE_TTL_SECONDS | 2.0 |
| Hit path wall (local microbench mean) | ~0.003ms |
| Documented lag bound | ports/listen ≤ 2.0s |

## Tests

```text
python3 -m unittest discover -s RemoteAgent/tests -p 'test_agent.py' -k Listening -k Inventory -v
Ran 19 tests in 0.069s
OK
```

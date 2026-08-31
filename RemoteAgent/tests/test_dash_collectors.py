"""Failure-first tests for the sparkDash-derived host/LLM collectors.

Every parser is pure text-in/value-out; every collector degrades to None
fields instead of raising. These tests pin the exact field extraction that
the Mac UI depends on (uptime, storage, network, tailnet health, GPU process
names, llama.cpp/vLLM/sglang serving rates).
"""

from __future__ import annotations

import sys
import time
import unittest
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

from agent_core import (  # noqa: E402
    _llm_root_url,
    _sum_proc_net_dev,
    parse_llamacpp_slots_tokens,
    parse_macos_boottime_seconds,
    parse_proc_uptime_seconds,
    parse_prometheus_metric_sum,
    parse_sglang_server_info,
    parse_tailscale_status_health,
    storage_usage,
)


class UptimeTests(unittest.TestCase):
    def test_proc_uptime_first_field(self) -> None:
        self.assertEqual(parse_proc_uptime_seconds("12345.67 89012.34"), 12345.67)

    def test_proc_uptime_garbage_is_none(self) -> None:
        self.assertIsNone(parse_proc_uptime_seconds(""))
        self.assertIsNone(parse_proc_uptime_seconds("not-a-number"))

    def test_boottime_extraction(self) -> None:
        boot_epoch = 1725000000.0
        text = "{ sec = 1725000000, usec = 123456 } Sat Aug 30 12:00:00 2025"
        boot = parse_macos_boottime_seconds(text)
        self.assertIsNotNone(boot)
        self.assertAlmostEqual(boot, time.time() - boot_epoch, delta=5)


class StorageTests(unittest.TestCase):
    def test_storage_usage_shape(self) -> None:
        usage = storage_usage("/tmp")
        if usage is None:
            self.skipTest("statvfs unavailable")
        self.assertIn("used_mb", usage)
        self.assertIn("total_mb", usage)
        self.assertIn("percent", usage)
        self.assertGreater(usage["total_mb"], 0)
        self.assertGreaterEqual(usage["used_mb"], 0)

    def test_storage_missing_path_is_none(self) -> None:
        self.assertIsNone(storage_usage("/nonexistent/msw/path"))


class NetworkTests(unittest.TestCase):
    LOOPBACK_ONLY = (
        "Inter-|   Receive                                                |  Transmit\n"
        " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"
        "    lo: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n"
    )
    WITH_ETH = (
        "    lo: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n"
        "eth0: 104857600 90000 0 0 0 0 0 0 52428800 60000 0 0 0 0 0 0\n"
    )

    def test_loopback_excluded(self) -> None:
        self.assertIsNone(_sum_proc_net_dev(self.LOOPBACK_ONLY))

    def test_eth_counters_summed(self) -> None:
        rx, tx = _sum_proc_net_dev(self.WITH_ETH)
        self.assertEqual(rx, 104857600)
        self.assertEqual(tx, 52428800)


class TailnetHealthTests(unittest.TestCase):
    def test_online_self_parsed(self) -> None:
        payload = {
            "BackendState": "Running",
            "Health": [],
            "Self": {
                "Online": True,
                "TailscaleIPs": ["100.122.96.76", "fd7a:115c:a1e0::1"],
                "DNSName": "dgx-spark.tail01763b.ts.net.",
            },
        }
        health = parse_tailscale_status_health(payload)
        self.assertIsNotNone(health)
        self.assertTrue(health["online"])
        self.assertEqual(health["backend_state"], "Running")
        self.assertEqual(health["ipv4"], "100.122.96.76")
        self.assertEqual(health["dns_name"], "dgx-spark.tail01763b.ts.net")
        self.assertEqual(health["health"], [])

    def test_offline_with_warning(self) -> None:
        payload = {
            "BackendState": "NeedsLogin",
            "Health": ["login expired"],
            "Self": {"Online": False, "TailscaleIPs": []},
        }
        health = parse_tailscale_status_health(payload)
        self.assertFalse(health["online"])
        self.assertEqual(health["health"], ["login expired"])

    def test_garbage_is_none(self) -> None:
        self.assertIsNone(parse_tailscale_status_health(None))
        self.assertIsNone(parse_tailscale_status_health([]))
        self.assertIsNone(parse_tailscale_status_health({"Self": "junk"}))


class LlamaSlotsTests(unittest.TestCase):
    def test_standard_layout(self) -> None:
        body = '[{"id":0,"n_decoded":100,"n_prompt_tokens_processed":250},' \
               '{"id":1,"n_decoded":50,"n_prompt_tokens_processed":80}]'
        slots = parse_llamacpp_slots_tokens(body)
        self.assertEqual(slots, {"0": (100, 250), "1": (50, 80)})

    def test_nested_next_token_layout(self) -> None:
        body = '[{"id":0,"next_token":[{"n_decoded":42}],"n_prompt_tokens_processed":7}]'
        slots = parse_llamacpp_slots_tokens(body)
        self.assertEqual(slots, {"0": (42, 7)})

    def test_n_prompt_tokens_fallback(self) -> None:
        body = '[{"id":0,"n_decoded":5,"n_prompt_tokens":999}]'
        slots = parse_llamacpp_slots_tokens(body)
        self.assertEqual(slots, {"0": (5, 999)})

    def test_not_a_slots_array_is_none(self) -> None:
        self.assertIsNone(parse_llamacpp_slots_tokens('{"error":"no"}'))
        self.assertIsNone(parse_llamacpp_slots_tokens("not json"))


class PrometheusTests(unittest.TestCase):
    METRICS = (
        "# HELP vllm:generation_tokens_total number of generation tokens\n"
        "# TYPE vllm:generation_tokens_total counter\n"
        'vllm:generation_tokens_total{model_name="balesh-parent-A"} 1234.0\n'
        'vllm:generation_tokens_total{model_name="other"} 11.0\n'
        'vllm:prompt_tokens_total{model_name="balesh-parent-A"} 5e+03\n'
    )

    def test_sums_labeled_lines(self) -> None:
        self.assertEqual(parse_prometheus_metric_sum(self.METRICS, "vllm:generation_tokens_total"), 1245.0)

    def test_scientific_notation(self) -> None:
        self.assertEqual(parse_prometheus_metric_sum(self.METRICS, "vllm:prompt_tokens_total"), 5000.0)

    def test_missing_metric_is_none(self) -> None:
        self.assertIsNone(parse_prometheus_metric_sum(self.METRICS, "vllm:preemption_total"))

    def test_help_lines_never_counted(self) -> None:
        self.assertIsNone(parse_prometheus_metric_sum("# HELP x\n# TYPE x\n", "x"))


class SglangTests(unittest.TestCase):
    def test_counters_and_sticky_gauge(self) -> None:
        body = '{"total_input_tokens":1000,"total_output_tokens":2500,' \
               '"internal_states":[{"last_gen_throughput":41.5}]}'
        info = parse_sglang_server_info(body)
        self.assertEqual(info["input_tokens"], 1000)
        self.assertEqual(info["output_tokens"], 2500)
        self.assertEqual(info["last_gen_throughput"], 41.5)

    def test_garbage_is_none(self) -> None:
        self.assertIsNone(parse_sglang_server_info("nope"))
        self.assertIsNone(parse_sglang_server_info("[]"))


class RootUrlTests(unittest.TestCase):
    def test_strips_v1(self) -> None:
        self.assertEqual(_llm_root_url("http://127.0.0.1:8050/v1"), "http://127.0.0.1:8050")
        self.assertEqual(_llm_root_url("http://127.0.0.1:8050/v1/"), "http://127.0.0.1:8050")
        self.assertEqual(_llm_root_url("http://127.0.0.1:8050"), "http://127.0.0.1:8050")


if __name__ == "__main__":
    unittest.main()

"""GB10 / UMA: VRAM used is compute-apps memory, never /proc RAM used."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

import model_switchboard_agent as agent  # noqa: E402


class NvidiaSmiNumberTests(unittest.TestCase):
    def test_na_and_not_supported_are_missing(self) -> None:
        for raw in ("N/A", "[N/A]", "n/a", "Not Supported", "[Not Supported]", ""):
            self.assertIsNone(agent._nvidia_smi_number(raw))

    def test_numeric(self) -> None:
        self.assertEqual(agent._nvidia_smi_number(" 3 "), 3.0)
        self.assertEqual(agent._nvidia_smi_number("26009.6"), 26009.6)


class UnifiedMemoryVRAMTests(unittest.TestCase):
    def test_uma_used_is_compute_apps_not_host_ram(self) -> None:
        gpus = [
            {
                "index": 0,
                "name": "NVIDIA GB10",
                "util_percent": 3.0,
                "temp_c": 56.0,
                "vram_used_mb": None,
                "vram_total_mb": None,
            }
        ]
        # 25.4 GiB attributed; 34 GiB classic /proc used must not leak into VRAM.
        agent._apply_unified_memory_vram(
            gpus,
            vram_by_pid={100: 14000.0, 200: 12009.6},
            mem={"used_mb": 34816.0, "total_mb": 124620.8},
        )
        self.assertAlmostEqual(gpus[0]["vram_used_mb"], 26009.6)
        self.assertAlmostEqual(gpus[0]["vram_total_mb"], 124620.8)
        self.assertNotEqual(gpus[0]["vram_used_mb"], 34816.0)

    def test_uma_idle_is_zero_not_host_ram(self) -> None:
        gpus = [{"vram_used_mb": None, "vram_total_mb": None}]
        agent._apply_unified_memory_vram(
            gpus,
            vram_by_pid={},
            mem={"used_mb": 34816.0, "total_mb": 124620.8},
        )
        self.assertEqual(gpus[0]["vram_used_mb"], 0.0)
        self.assertAlmostEqual(gpus[0]["vram_total_mb"], 124620.8)

    def test_discrete_gpu_keeps_smi_used(self) -> None:
        gpus = [{"vram_used_mb": 55296.0, "vram_total_mb": 131072.0}]
        agent._apply_unified_memory_vram(
            gpus,
            vram_by_pid={1: 100.0},
            mem={"used_mb": 32000.0, "total_mb": 64000.0},
        )
        self.assertEqual(gpus[0]["vram_used_mb"], 55296.0)
        self.assertEqual(gpus[0]["vram_total_mb"], 131072.0)

    def test_host_metrics_payload_does_not_copy_ram_used(self) -> None:
        snap = {
            "gpus": [
                {
                    "index": 0,
                    "name": "NVIDIA GB10",
                    "util_percent": 3.0,
                    "temp_c": 56.0,
                    "vram_used_mb": None,
                    "vram_total_mb": None,
                }
            ],
            "vram_by_pid": {4242: 26009.6},
            "source": "nvidia-smi",
        }
        ram = {"used_mb": 34816.0, "total_mb": 124620.8, "percent": 27.9, "source": "proc"}
        with mock.patch.object(agent, "gpu_metrics_snapshot", return_value=snap):
            with mock.patch.object(agent, "_sample_memory", return_value=ram):
                with mock.patch.object(agent, "_sample_cpu_percent", return_value=1.0):
                    payload = agent.host_metrics_payload()
        self.assertAlmostEqual(payload["gpus"][0]["vram_used_mb"], 26009.6)
        self.assertAlmostEqual(payload["gpus"][0]["vram_total_mb"], 124620.8)
        self.assertEqual(payload["memory"]["used_mb"], 34816.0)

    def test_host_metrics_does_not_mutate_cached_gpu_dicts(self) -> None:
        gpu_entry = {
            "index": 0,
            "name": "NVIDIA GB10",
            "util_percent": 3.0,
            "temp_c": 56.0,
            "vram_used_mb": None,
            "vram_total_mb": None,
        }
        snap = {
            "gpus": [gpu_entry],
            "vram_by_pid": {4242: 26009.6},
            "source": "nvidia-smi",
        }
        ram = {"used_mb": 34816.0, "total_mb": 124620.8, "percent": 27.9, "source": "proc"}
        with mock.patch.object(agent, "gpu_metrics_snapshot", return_value=snap):
            with mock.patch.object(agent, "_sample_memory", return_value=ram):
                with mock.patch.object(agent, "_sample_cpu_percent", return_value=1.0):
                    payload = agent.host_metrics_payload()
        self.assertIsNone(gpu_entry["vram_used_mb"])
        self.assertIsNone(gpu_entry["vram_total_mb"])
        self.assertAlmostEqual(payload["gpus"][0]["vram_used_mb"], 26009.6)


if __name__ == "__main__":
    unittest.main()

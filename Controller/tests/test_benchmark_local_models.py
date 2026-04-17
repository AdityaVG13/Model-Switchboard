from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
MODULE_PATH = ROOT / "benchmark-local-models.py"
SPEC = importlib.util.spec_from_file_location("benchmark_local_models", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BenchmarkLocalModelsTests(unittest.TestCase):
    def test_local_suite_covers_primary_local_runtime_dimensions(self) -> None:
        categories = {item["category"] for item in MODULE.PROMPT_SUITES["local"]}
        self.assertEqual(categories, {"interactive", "decode", "prefill", "coding"})

    def test_build_long_context_prompt_reaches_target_budget(self) -> None:
        prompt = MODULE.build_long_context_prompt(
            2048,
            instruction="Summarize the operator tradeoffs in four bullets.",
            topic="local inference",
        )
        self.assertGreaterEqual(MODULE.estimated_tokens(prompt), 2048)

    def test_write_outputs_publishes_timestamped_and_latest_reports(self) -> None:
        report = {
            "generated_at": "2026-04-17T12:00:00+00:00",
            "suite": "local",
            "temperature": 0.2,
            "profiles": ["demo"],
            "isolate": True,
            "benchmarks": [
                {
                    "profile": "demo",
                    "display_name": "Demo Model",
                    "runtime": "llama.cpp",
                    "request_model": "demo-model",
                    "base_url": "http://127.0.0.1:9000/v1",
                    "pid": 123,
                    "rss_mb": 2048,
                    "warmup": {
                        "ttft_ms": 120.0,
                        "decode_tokens_per_sec": 50.0,
                    },
                    "results": [
                        {
                            "benchmark": "interactive-latency",
                            "category": "interactive",
                            "prompt_est_tokens": 32,
                            "max_tokens": 48,
                            "ttft_ms": 110.0,
                            "total_ms": 220.0,
                            "decode_tokens_per_sec": 48.0,
                            "e2e_tokens_per_sec": 30.0,
                            "usage_source": "server",
                            "output_preview": "TTFT dominates perceived latency.",
                        }
                    ],
                    "averages": {
                        "ttft_ms": 110.0,
                        "total_ms": 220.0,
                        "decode_tokens_per_sec": 48.0,
                        "e2e_tokens_per_sec": 30.0,
                    },
                    "category_averages": [
                        {
                            "category": "interactive",
                            "cases": ["interactive-latency"],
                            "ttft_ms": 110.0,
                            "total_ms": 220.0,
                            "decode_tokens_per_sec": 48.0,
                            "e2e_tokens_per_sec": 30.0,
                        }
                    ],
                }
            ],
        }

        with tempfile.TemporaryDirectory() as tmpdir:
            original_output_dir = MODULE.OUTPUT_DIR
            MODULE.OUTPUT_DIR = Path(tmpdir)
            try:
                json_path, md_path = MODULE.write_outputs(report)
            finally:
                MODULE.OUTPUT_DIR = original_output_dir

            self.assertTrue(json_path.exists())
            self.assertTrue(md_path.exists())
            self.assertTrue((Path(tmpdir) / "latest.json").exists())
            self.assertTrue((Path(tmpdir) / "latest.md").exists())
            markdown = md_path.read_text()
            self.assertIn("Controller/benchmark-results/", markdown)
            self.assertIn("interactive-latency", markdown)


if __name__ == "__main__":
    unittest.main()

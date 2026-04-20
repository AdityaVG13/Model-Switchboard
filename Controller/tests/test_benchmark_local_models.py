from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


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

    def test_finalize_stream_result_rejects_empty_response_without_usage(self) -> None:
        result = MODULE.finalize_stream_result(
            pieces=[],
            usage={},
            started=10.0,
            first_token_at=None,
            finished=10.001,
        )

        self.assertEqual(result["usage_source"], "error")
        self.assertEqual(result["decode_tokens_per_sec"], None)
        self.assertIn("empty streamed response", result["error"])

    def test_finalize_stream_result_uses_estimated_tokens_only_when_content_exists(self) -> None:
        result = MODULE.finalize_stream_result(
            pieces=["hello world"],
            usage={},
            started=10.0,
            first_token_at=10.1,
            finished=10.3,
        )

        self.assertEqual(result["usage_source"], "estimated")
        self.assertGreater(result["completion_tokens"], 0)
        self.assertGreater(result["decode_tokens_per_sec"], 0)

    def test_run_case_appends_non_stream_diagnostic_for_empty_stream(self) -> None:
        with mock.patch.object(
            MODULE,
            "stream_chat",
            return_value=MODULE.failed_result("empty streamed response without token usage"),
        ), mock.patch.object(
            MODULE,
            "non_stream_chat_diagnostic",
            return_value='non-stream HTTP 500: rope_dynamic: "Only one of base or freqs can have a value."',
        ):
            result = MODULE.run_case(
                "http://127.0.0.1:8080/v1",
                "gemma-4-31b-it-4bit-mlx",
                "Reply with READY only.",
                temperature=0.0,
                max_tokens=24,
                timeout=30.0,
                retries=0,
            )

        self.assertEqual(result["usage_source"], "error")
        self.assertIn("empty streamed response without token usage", result["error"])
        self.assertIn("rope_dynamic", result["error"])


if __name__ == "__main__":
    unittest.main()

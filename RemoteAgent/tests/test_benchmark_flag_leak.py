"""Regression: a benchmark start failure must not leak the running flag.

Before the try/except wrapper in AgentService.start_benchmark, any exception
between the flag being set and the worker thread starting (bad profiles dir,
unwritable log path, etc.) left _benchmark_running True forever - every later
benchmark request 500s with "benchmark already running" until agent restart.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

import model_switchboard_agent as agent  # noqa: E402


class BenchmarkFlagLeakTests(unittest.TestCase):
    def _service(self, root: Path) -> agent.AgentService:
        profiles = root / "profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        (profiles / "a.env").write_text("PORT=8001\nSTART_COMMAND=true\nREQUEST_MODEL=a\n", encoding="utf-8")
        return agent.AgentService(agent.AgentConfiguration(root=root, profiles_dir=profiles))

    def test_flag_resets_when_log_path_unwritable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            # Force the log-path write to fail after the flag is set.
            with mock.patch.object(
                Path, "write_text", side_effect=OSError("disk full")
            ):
                with self.assertRaises(OSError):
                    service.start_benchmark(profiles=["a"], suite="quick")
            self.assertFalse(service._benchmark_running, "flag leaked: benchmark permanently stuck")

    def test_flag_resets_when_pid_file_write_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            calls = {"n": 0}

            def fail_on_second_write(*args, **kwargs):
                # Call 1: log truncate. Call 2: the benchmark pid file write.
                calls["n"] += 1
                if calls["n"] == 2:
                    raise OSError("read-only run dir")
                return None

            with mock.patch.object(Path, "write_text", side_effect=fail_on_second_write):
                with self.assertRaises(OSError):
                    service.start_benchmark(profiles=["a"], suite="quick")
            self.assertFalse(service._benchmark_running, "flag leaked: benchmark permanently stuck")

    def test_flag_still_set_while_worker_runs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            started = None

            def slow_worker(*args, **kwargs):
                import time

                time.sleep(0.3)

            with mock.patch.object(service, "_run_benchmark_worker", side_effect=slow_worker):
                service.start_benchmark(profiles=["a"], suite="quick")
                started = service._benchmark_running
            self.assertTrue(started, "flag must stay set while the worker runs")
            # Wait out the worker.
            import time

            deadline = __import__("time").monotonic() + 2
            while service._benchmark_running and __import__("time").monotonic() < deadline:
                time.sleep(0.02)
            self.assertFalse(service._benchmark_running)


if __name__ == "__main__":
    unittest.main()

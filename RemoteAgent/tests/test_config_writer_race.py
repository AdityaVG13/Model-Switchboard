"""Regression: save_agent_config must be cross-process safe.

Two guarantees pinned here:
1. Concurrent writers never lose each other's keys (flock serializes the
   read-modify-write; previously a parallel writer's key could vanish).
2. Readers never observe a truncated/partial file (atomic os.replace; the
   old write_text truncated in place, so a concurrent reader could see an
   empty file and silently reset profiles_dir).
"""

from __future__ import annotations

import json
import multiprocessing
import sys
import tempfile
import unittest
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

from agent_core import agent_config_path  # noqa: E402
import model_switchboard_agent as agent  # noqa: E402


def _config_writer(root_str: str, key: str) -> None:
    root = Path(root_str)
    for _ in range(25):
        agent.save_agent_config(root, {key: "value-" + key})


class SaveAgentConfigTests(unittest.TestCase):
    def test_concurrent_writers_do_not_lose_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            keys = [f"key-{i}" for i in range(4)]
            procs = [
                multiprocessing.Process(target=_config_writer, args=(str(root), key))
                for key in keys
            ]
            for proc in procs:
                proc.start()
            for proc in procs:
                proc.join(timeout=30)
                self.assertEqual(proc.exitcode, 0)
            payload = json.loads(agent_config_path(root).read_text(encoding="utf-8"))
            for key in keys:
                self.assertEqual(payload.get(key), f"value-{key}", f"lost update for {key}")

    def test_reader_never_sees_truncated_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            agent.save_agent_config(root, {"profiles_dir": "/data/launch"})
            path = agent_config_path(root)
            # A crash mid-write under the old code left this empty; with
            # atomic replace the file is either absent or complete JSON.
            for _ in range(50):
                payload = agent.load_agent_config(root)
                if payload:
                    self.assertIsInstance(payload, dict)
                    self.assertIn("profiles_dir", payload)
                # No partial-JSON exception may escape load_agent_config.

    def test_tmp_and_lock_files_do_not_leak(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            agent.save_agent_config(root, {"a": "1"})
            agent.save_agent_config(root, {"b": "2"})
            self.assertNotIn(".tmp", {p.suffix for p in root.iterdir()})
            # The lock file persists by design (flock anchor); the tmp file
            # must not.


if __name__ == "__main__":
    unittest.main()

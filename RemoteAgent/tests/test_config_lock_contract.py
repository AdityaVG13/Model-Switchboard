"""Contract: agent and installer must lock/write the SAME file names.

The installer's config.json writer (RemoteAgent/install-remote-agent.sh)
uses config.json.lock and config.json.tmp. save_agent_config previously
built names with Path.with_suffix, which strips ".json" -> config.lock /
config.tmp, so the two writers flocked DIFFERENT files: no mutual
exclusion across the agent<->installer boundary, defeating the whole
protocol. These tests pin the shared names.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

from agent_core import agent_config_path  # noqa: E402
import model_switchboard_agent as agent  # noqa: E402

INSTALLER_LOCK_NAME = "config.json.lock"
INSTALLER_TMP_NAME = "config.json.tmp"


class LockPathContractTests(unittest.TestCase):
    def test_lock_file_matches_installer_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            agent.save_agent_config(root, {"profiles_dir": "/data/launch"})
            self.assertTrue(
                (root / INSTALLER_LOCK_NAME).is_file(),
                "agent must lock config.json.lock (the installer's anchor)",
            )

    def test_tmp_file_matches_installer_name_during_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            observed: list[str] = []
            real_replace = __import__("os").replace

            def spying_replace(src, dst):
                observed.append(Path(src).name)
                return real_replace(src, dst)

            import os

            with unittest.mock.patch.object(os, "replace", spying_replace):
                agent.save_agent_config(root, {"a": "1"})
            self.assertEqual(observed, [INSTALLER_TMP_NAME])

    def test_live_path_is_config_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            agent.save_agent_config(root, {"a": "1"})
            self.assertTrue((root / "config.json").is_file())
            self.assertEqual(
                agent.load_agent_config(root), {"a": "1"}
            )


import unittest.mock  # noqa: E402  (used above)

if __name__ == "__main__":
    unittest.main()

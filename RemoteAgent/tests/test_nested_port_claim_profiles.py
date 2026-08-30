"""Nested port-claim folders under profiles_dir load as port-N profiles."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

# RemoteAgent is not a package; load sibling modules via path.
import sys

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

import model_switchboard_agent as agent  # noqa: E402


class NestedPortClaimProfilesTests(unittest.TestCase):
    def test_profile_repository_loads_nested_flags_env_as_port_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            claim = root / "8027"
            claim.mkdir()
            (claim / "flags.env").write_text(
                "MODEL=${MODEL:-/models/demo.gguf}\n"
                "HOST=127.0.0.1\n"
                "PORT=8027\n",
                encoding="utf-8",
            )
            (claim / "launch.sh").write_text("#!/bin/sh\necho demo\n", encoding="utf-8")
            (claim / "launch.sh").chmod(0o755)

            profiles = agent.ProfileRepository(root).load()
            self.assertIn("port-8027", profiles)
            profile = profiles["port-8027"]
            self.assertEqual(profile.endpoint_port, "8027")
            self.assertIn("demo.gguf", profile.get("MODEL_PATH") or profile.get("REQUEST_MODEL") or "")

    def test_flat_file_preferred_over_nested_claim_same_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "port-8027.env").write_text(
                "REQUEST_MODEL=flat-model\nPORT=8027\nRUNTIME=command\nSTART_COMMAND=true\n",
                encoding="utf-8",
            )
            claim = root / "8027"
            claim.mkdir()
            (claim / "flags.env").write_text("MODEL=/models/nested.gguf\n", encoding="utf-8")
            (claim / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (claim / "launch.sh").chmod(0o755)

            profiles = agent.ProfileRepository(root).load()
            self.assertEqual(profiles["port-8027"].get("REQUEST_MODEL"), "flat-model")

    def test_resolve_profiles_directory_falls_back_to_scan_roots(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            agent_root = Path(tmp) / "agent"
            agent_root.mkdir()
            launch = Path(tmp) / "launch"
            claim = launch / "9011"
            claim.mkdir(parents=True)
            (claim / "flags.env").write_text("MODEL=/models/x.gguf\n", encoding="utf-8")
            (claim / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (claim / "launch.sh").chmod(0o755)

            empty_profiles = Path(tmp) / "model-profiles"
            empty_profiles.mkdir()
            (agent_root / "config.json").write_text(
                json.dumps(
                    {
                        "profiles_dir": str(empty_profiles),
                        "scan_roots": [str(launch)],
                    }
                ),
                encoding="utf-8",
            )

            # Keep preferred ~/model-profiles out of the way for this unit test.
            old_home = os.environ.get("HOME")
            try:
                os.environ["HOME"] = str(Path(tmp) / "home")
                Path(os.environ["HOME"]).mkdir(parents=True, exist_ok=True)
                resolved = agent.resolve_profiles_directory(agent_root)
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home

            self.assertEqual(resolved, launch.resolve())


if __name__ == "__main__":
    unittest.main()

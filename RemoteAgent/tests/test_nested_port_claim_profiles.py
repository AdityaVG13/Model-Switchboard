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


    def test_scan_skips_unreadable_port_claim_markers(self) -> None:
        from unittest.mock import patch

        import discovery

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            claim = root / "8126"
            claim.mkdir()
            (claim / "flags.env").write_text("MODEL=/models/x.gguf\n", encoding="utf-8")
            real_is_file = Path.is_file

            def flaky(self: Path) -> bool:
                if self.name in discovery.PORT_CLAIM_MARKERS and self.parent.name == "8126":
                    raise PermissionError("denied")
                return real_is_file(self)

            old_home = os.environ.get("HOME")
            try:
                os.environ["HOME"] = str(root / "home")
                Path(os.environ["HOME"]).mkdir()
                with patch.object(Path, "is_file", flaky):
                    claims = discovery.scan_port_claim_directories(
                        roots=[root],
                        agent_root=root,
                    )
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home
            self.assertEqual(claims, [])

    def test_profile_repository_load_skips_unreadable_directory(self) -> None:
        from unittest.mock import patch

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with patch.object(Path, "is_dir", side_effect=PermissionError("denied")):
                profiles = agent.ProfileRepository(root).load()
            self.assertEqual(profiles, {})

            with patch.object(Path, "iterdir", side_effect=PermissionError("denied")):
                profiles = agent.ProfileRepository(root).load()
            self.assertEqual(profiles, {})


    def test_hinted_roots_skip_os_runtime_and_permission_errors(self) -> None:
        from unittest.mock import patch

        import discovery

        self.assertTrue(discovery.is_os_runtime_path(Path("/run/user/126")))
        self.assertTrue(discovery.is_os_runtime_path(Path("/proc/1")))
        self.assertTrue(discovery.is_os_runtime_path(Path("/var/run/user/126")))
        self.assertFalse(discovery.is_os_runtime_path(Path("/tmp/models/8027")))

        with patch.object(Path, "is_dir", side_effect=PermissionError("denied")):
            roots = discovery.roots_hinted_by_commands(
                ["/run/user/126/bin/llama-server --model /models/x.gguf"]
            )
        self.assertEqual(roots, [])

        hinted = discovery.roots_hinted_by_commands(
            ["/run/user/126/flags.env", "/var/run/user/1000/bin/llama-server"]
        )
        self.assertEqual(hinted, [])

    def test_scan_skips_os_runtime_roots(self) -> None:
        import discovery

        with tempfile.TemporaryDirectory() as tmp:
            old_home = os.environ.get("HOME")
            try:
                os.environ["HOME"] = str(Path(tmp) / "home")
                Path(os.environ["HOME"]).mkdir()
                claims = discovery.scan_port_claim_directories(
                    roots=[Path("/run"), Path("/proc"), Path("/sys")],
                    agent_root=Path(tmp),
                )
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home
            for claim in claims:
                path = claim["path"]
                self.assertFalse(path.startswith("/run"), path)
                self.assertFalse(path.startswith("/proc"), path)
                self.assertFalse(path.startswith("/sys"), path)


if __name__ == "__main__":
    unittest.main()

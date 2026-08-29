"""Activate must not assemble the full status board to find stop targets."""

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


class SwitchProfileTests(unittest.TestCase):
    def test_switch_stops_other_managed_without_status_payload(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "profiles"
            profiles.mkdir()
            (profiles / "a.env").write_text(
                "PORT=8001\nSTART_COMMAND=true\nREQUEST_MODEL=a\n", encoding="utf-8"
            )
            (profiles / "b.env").write_text(
                "PORT=8002\nSTART_COMMAND=true\nREQUEST_MODEL=b\n", encoding="utf-8"
            )
            service = agent.AgentService(
                agent.AgentConfiguration(root=root, profiles_dir=profiles)
            )
            with mock.patch.object(service, "status_payload") as payload:
                with mock.patch.object(service, "stop") as stop:
                    with mock.patch.object(service, "start") as start:
                        service.switch_profile("b")
            payload.assert_not_called()
            stop.assert_called_once_with("a")
            start.assert_called_once_with("b")
            self.assertEqual(
                (root / "run" / "active-profile").read_text(encoding="utf-8").strip(),
                "b",
            )

    def test_switch_stops_supervised_claims_not_in_folder(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "profiles"
            profiles.mkdir()
            (profiles / "keep.env").write_text(
                "PORT=8001\nSTART_COMMAND=true\nREQUEST_MODEL=keep\n", encoding="utf-8"
            )
            service = agent.AgentService(
                agent.AgentConfiguration(root=root, profiles_dir=profiles)
            )
            service._supervised.add("port-9000")
            with mock.patch.object(service, "status_payload") as payload:
                with mock.patch.object(service, "stop") as stop:
                    with mock.patch.object(service, "start") as start:
                        service.switch_profile("keep")
            payload.assert_not_called()
            stop.assert_called_once_with("port-9000")
            start.assert_called_once_with("keep")

    def test_switch_starts_even_if_sibling_stop_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "profiles"
            profiles.mkdir()
            (profiles / "a.env").write_text(
                "PORT=8001\nSTART_COMMAND=true\nREQUEST_MODEL=a\n", encoding="utf-8"
            )
            (profiles / "b.env").write_text(
                "PORT=8002\nSTART_COMMAND=true\nREQUEST_MODEL=b\n", encoding="utf-8"
            )
            service = agent.AgentService(
                agent.AgentConfiguration(root=root, profiles_dir=profiles)
            )

            def boom(_name: str, force: bool = False) -> None:
                raise agent.OperationFailedError("STOP_COMMAND failed")

            with mock.patch.object(service, "status_payload") as payload:
                with mock.patch.object(service, "stop", side_effect=boom):
                    with mock.patch.object(service, "start") as start:
                        service.switch_profile("b")
            payload.assert_not_called()
            start.assert_called_once_with("b")

    def test_switch_starts_when_supervised_claim_is_gone(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "profiles"
            profiles.mkdir()
            (profiles / "keep.env").write_text(
                "PORT=8001\nSTART_COMMAND=true\nREQUEST_MODEL=keep\n", encoding="utf-8"
            )
            service = agent.AgentService(
                agent.AgentConfiguration(root=root, profiles_dir=profiles)
            )
            service._supervised.add("port-9000")
            with mock.patch.object(
                service, "stop", side_effect=agent.ProfileNotFoundError("port-9000")
            ):
                with mock.patch.object(service, "_reap_unresolved_pid") as reap:
                    with mock.patch.object(service, "start") as start:
                        service.switch_profile("keep")
            reap.assert_called_once_with("port-9000")
            start.assert_called_once_with("keep")

    def test_idle_stop_skips_stop_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "profiles"
            profiles.mkdir()
            (profiles / "idle.env").write_text(
                "PORT=8001\nSTART_COMMAND=true\nREQUEST_MODEL=idle\n"
                "STOP_COMMAND=false\n",
                encoding="utf-8",
            )
            service = agent.AgentService(
                agent.AgentConfiguration(root=root, profiles_dir=profiles)
            )
            service.stop("idle")


if __name__ == "__main__":
    unittest.main()

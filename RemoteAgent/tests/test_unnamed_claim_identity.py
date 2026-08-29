"""Claims with no model identity must not be gated on a port-N placeholder.

A port-claim folder that carries no MODEL*/REQUEST_MODEL/SERVER_MODEL_ID hint
has no operator-asserted identity. The synthetic "port-N" name is a placeholder,
not an identity — so the health probe must accept any served OpenAI id (the
endpoint proves itself), and status must adopt the live served id as the row's
name while the server is up. A claim WITH a hint keeps strict identity matching.
"""

from __future__ import annotations

import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

import discovery  # noqa: E402
import model_switchboard_agent as agent  # noqa: E402


def _write_executable(path: Path, text: str = "#!/bin/sh\n") -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


class UnnamedClaimTests(unittest.TestCase):
    def test_claim_without_any_model_hint_flags_any_id(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            claim_dir = Path(tmp) / "8050"
            claim_dir.mkdir()
            _write_executable(claim_dir / "ctrl.sh")
            claims = discovery.scan_port_claim_directories(roots=[Path(tmp)], listeners=[])
            self.assertEqual(len(claims), 1)
            profile = discovery.profile_from_claim(claims[0])
            self.assertEqual(profile.values.get("HEALTHCHECK_ANY_ID"), "1")
            self.assertEqual(profile.request_model, "port-8050")
            self.assertEqual(profile.display_name, "Port 8050")

    def test_claim_with_model_hint_keeps_strict_identity(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            claim_dir = Path(tmp) / "8040"
            claim_dir.mkdir()
            _write_executable(claim_dir / "launch.sh")
            (claim_dir / "flags.env").write_text(
                "MODEL_DIR=/data/models/internlm/Intern-S2-Mobius-FP8\n"
                "REQUEST_MODEL=Intern-S2-Mobius-FP8\n",
                encoding="utf-8",
            )
            claims = discovery.scan_port_claim_directories(roots=[Path(tmp)], listeners=[])
            self.assertEqual(len(claims), 1)
            profile = discovery.profile_from_claim(claims[0])
            self.assertNotIn("HEALTHCHECK_ANY_ID", profile.values)
            # The claim model_hint chain is path-first: REQUEST_MODEL becomes
            # the readable server id / display name, not request_model.
            self.assertEqual(profile.server_model_id, "Intern-S2-Mobius-FP8")
            self.assertEqual(profile.display_name, "Intern-S2-Mobius-FP8")

    def test_gguf_model_file_infers_llamacpp_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            claim_dir = Path(tmp) / "8038"
            claim_dir.mkdir()
            _write_executable(claim_dir / "launch.sh")
            (claim_dir / "flags.env").write_text(
                "MODEL_FILE=/data/models/jackrong/DeepSeek-Q8_0.gguf\n",
                encoding="utf-8",
            )
            claims = discovery.scan_port_claim_directories(roots=[Path(tmp)], listeners=[])
            self.assertEqual(len(claims), 1)
            self.assertEqual(claims[0]["runtime_hint"], "llama.cpp")

    def test_server_model_id_flag_is_carried(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            claim_dir = Path(tmp) / "8051"
            claim_dir.mkdir()
            _write_executable(claim_dir / "ctrl.sh")
            (claim_dir / "flags.env").write_text(
                "MODEL_DIR=/data/models/Qwen/Qwen3.8-27B\nSERVER_MODEL_ID=balesh-parent-A\n",
                encoding="utf-8",
            )
            claims = discovery.scan_port_claim_directories(roots=[Path(tmp)], listeners=[])
            self.assertEqual(len(claims), 1)
            profile = discovery.profile_from_claim(claims[0])
            self.assertNotIn("HEALTHCHECK_ANY_ID", profile.values)
            self.assertEqual(profile.server_model_id, "balesh-parent-A")


class AnyIdHealthTests(unittest.TestCase):
    MODELS_BODY = b'{"object":"list","data":[{"id":"balesh-parent-A"}]}'

    class _FakeResponse:
        def __init__(self, body: bytes) -> None:
            self._body = body

        def read(self) -> bytes:
            return self._body

        def __enter__(self) -> "AnyIdHealthTests._FakeResponse":
            return self

        def __exit__(self, *args: object) -> bool:
            return False

    def _service(self, root: Path) -> agent.AgentService:
        profiles = root / "profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        return agent.AgentService(
            agent.AgentConfiguration(root=root, profiles_dir=profiles)
        )

    def test_any_id_profile_ready_when_served_list_is_nonempty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            profile = agent.Profile(
                name="port-8050",
                values={"REQUEST_MODEL": "port-8050", "PORT": "8050", "HEALTHCHECK_ANY_ID": "1"},
            )
            with mock.patch.object(
                agent, "_urlopen_no_redirect", lambda request, timeout: self._FakeResponse(self.MODELS_BODY)
            ):
                ready, ids = service._probe_health(profile)
            self.assertTrue(ready)
            self.assertEqual(ids, ["balesh-parent-A"])

    def test_named_profile_still_requires_id_match(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            profile = agent.Profile(
                name="port-8050",
                values={
                    "REQUEST_MODEL": "port-8050",
                    "PORT": "8050",
                    "HEALTHCHECK_EXPECT_ID": "some-other-model",
                },
            )
            with mock.patch.object(
                agent, "_urlopen_no_redirect", lambda request, timeout: self._FakeResponse(self.MODELS_BODY)
            ):
                ready, ids = service._probe_health(profile)
            self.assertFalse(ready)
            self.assertEqual(ids, ["balesh-parent-A"])


class UnnamedStatusAdoptionTests(unittest.TestCase):
    def _service(self, root: Path) -> agent.AgentService:
        profiles = root / "profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        return agent.AgentService(
            agent.AgentConfiguration(root=root, profiles_dir=profiles)
        )

    def test_status_adopts_live_served_id_for_unnamed_claim(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            profile = agent.Profile(
                name="port-8050",
                values={"REQUEST_MODEL": "port-8050", "PORT": "8050", "HEALTHCHECK_ANY_ID": "1"},
            )
            with (
                mock.patch.object(service, "_probe_health", return_value=(True, ["balesh-parent-A"])),
                mock.patch.object(service, "_read_pid", return_value=None),
            ):
                payload = service.status(profile, allow_port_fallback=False, listeners=[])
            self.assertEqual(payload["request_model"], "balesh-parent-A")
            self.assertEqual(payload["server_model_id"], "balesh-parent-A")
            self.assertEqual(payload["display_name"], "balesh-parent-A")

    def test_status_keeps_asserted_identity_for_named_claim(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            profile = agent.Profile(
                name="port-8040",
                values={"REQUEST_MODEL": "Intern-S2-Mobius-FP8", "PORT": "8040"},
            )
            with (
                mock.patch.object(service, "_probe_health", return_value=(True, ["Intern-S2-Mobius-FP8"])),
                mock.patch.object(service, "_read_pid", return_value=None),
            ):
                payload = service.status(profile, allow_port_fallback=False, listeners=[])
            self.assertEqual(payload["request_model"], "Intern-S2-Mobius-FP8")
            self.assertEqual(payload["display_name"], "Intern-S2-Mobius-FP8")


if __name__ == "__main__":
    unittest.main()

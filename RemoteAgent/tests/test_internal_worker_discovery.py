"""Internal vLLM/engine worker ports must not enter live discovery probes."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

# Load agent first so discovery's deferred import cycle resolves (same as
# other RemoteAgent tests).
import model_switchboard_agent as agent  # noqa: E402,F401
import discovery  # noqa: E402


class InternalWorkerDiscoveryTests(unittest.TestCase):
    def test_enginecore_is_internal_worker_but_still_looks_like_model_server(self) -> None:
        cmd = "VLLM::EngineCore(pid=2645085)"
        self.assertTrue(discovery.command_looks_like_model_server(cmd))
        self.assertTrue(discovery.command_is_internal_model_worker(cmd))

    def test_public_vllm_serve_is_not_internal_worker(self) -> None:
        cmd = "python -m vllm.entrypoints.openai.api_server --port 8000"
        self.assertTrue(discovery.command_looks_like_model_server(cmd))
        self.assertFalse(discovery.command_is_internal_model_worker(cmd))

    def test_discover_skips_enginecore_without_probing(self) -> None:
        listeners = [
            {
                "port": 36539,
                "pid": 2645085,
                "command": "VLLM::EngineCore",
                "bind": "127.0.0.1",
            },
            {
                "port": 8000,
                "pid": 99,
                "command": "python -m vllm.entrypoints.openai.api_server --port 8000",
                "bind": "0.0.0.0",
            },
        ]
        with mock.patch.object(discovery, "probe_model_endpoint") as probe:
            probe.side_effect = lambda port, host="127.0.0.1": discovery.ProbeOutcome(
                port=port,
                host=host,
                health_ok=True,
                model_ids=[f"model-{port}"],
            )
            with mock.patch.object(discovery, "port_is_listening", return_value=True):
                found = discovery.discover_live_model_endpoints(listeners=listeners)

        ports = {int(item["port"]) for item in found}
        self.assertNotIn(36539, ports)
        self.assertIn(8000, ports)
        probed_ports = {call.args[0] for call in probe.call_args_list}
        self.assertNotIn(36539, probed_ports)
        self.assertIn(8000, probed_ports)


if __name__ == "__main__":
    unittest.main()

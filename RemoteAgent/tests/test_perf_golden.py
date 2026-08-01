"""Golden isomorphism checks for status/ports discovery shape.

Volatile fields (pid, rss, command, ready) are stripped so pure performance
refactors can be verified without live process noise.
"""
from __future__ import annotations

import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT_PATH = REPO_ROOT / "RemoteAgent" / "model_switchboard_agent.py"
_spec = importlib.util.spec_from_file_location("model_switchboard_agent", AGENT_PATH)
assert _spec and _spec.loader
agent = importlib.util.module_from_spec(_spec)
sys.modules["model_switchboard_agent"] = agent
_spec.loader.exec_module(agent)

GOLDEN_DIR = REPO_ROOT / "RemoteAgent" / "tests" / "golden"
GOLDEN_DIR.mkdir(parents=True, exist_ok=True)


def _normalize_status(payload: dict) -> dict:
    statuses = []
    for item in payload.get("statuses", []):
        statuses.append(
            {
                "profile": item.get("profile"),
                "port": str(item.get("port")),
                "runtime": item.get("runtime"),
                "request_model": item.get("request_model"),
                "discovery_source": item.get("discovery_source"),
                "launch_mode": item.get("launch_mode"),
                "log_path_is_str": isinstance(item.get("log_path"), str),
            }
        )
    statuses.sort(key=lambda s: (s["port"], s["profile"] or ""))
    claims = payload.get("discovery", {}).get("claims") or []
    claim_ports = sorted({int(c["port"]) for c in claims if "port" in c})
    return {
        "status_profiles": [s["profile"] for s in statuses],
        "status_ports": [s["port"] for s in statuses],
        "status_rows": statuses,
        "claim_ports": claim_ports,
        "log_paths_all_str": all(s["log_path_is_str"] for s in statuses),
    }


class PerfGoldenTests(unittest.TestCase):
    def test_claim_discovery_normalized_shape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "model-profiles"
            profiles.mkdir()
            claim = root / "stack" / "9555"
            claim.mkdir(parents=True)
            (claim / "flags.env").write_text(
                'MODEL="${MODEL:-/models/x.gguf}"\nPORT="${PORT:-9555}"\nLLAMA_BIN=llama-server\n',
                encoding="utf-8",
            )
            launch = claim / "launch.sh"
            launch.write_text("#!/bin/sh\n", encoding="utf-8")
            launch.chmod(0o755)
            cfg = agent.AgentConfiguration(
                root=root, host="127.0.0.1", port=18879, profiles_dir=profiles
            )
            svc = agent.AgentService(cfg)
            old = os.environ.get(agent.SCAN_ROOTS_ENV)
            os.environ[agent.SCAN_ROOTS_ENV] = str(root / "stack")
            try:
                payload = svc.status_payload()
            finally:
                if old is None:
                    os.environ.pop(agent.SCAN_ROOTS_ENV, None)
                else:
                    os.environ[agent.SCAN_ROOTS_ENV] = old
            norm = _normalize_status(payload)
            self.assertIn("port-9555", norm["status_profiles"])
            self.assertTrue(norm["log_paths_all_str"])
            self.assertIn(9555, norm["claim_ports"])
            # Stable subset golden
            golden = {
                "must_include_profile": "port-9555",
                "must_include_port": "9555",
                "log_paths_all_str": True,
            }
            path = GOLDEN_DIR / "claim_discovery_shape.json"
            if not path.exists() or os.environ.get("UPDATE_PERF_GOLDEN") == "1":
                path.write_text(json.dumps(golden, indent=2) + "\n", encoding="utf-8")
            expected = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(norm["log_paths_all_str"], expected["log_paths_all_str"])
            self.assertIn(expected["must_include_profile"], norm["status_profiles"])
            self.assertIn(expected["must_include_port"], norm["status_ports"])


if __name__ == "__main__":
    unittest.main()

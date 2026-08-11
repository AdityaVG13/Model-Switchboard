"""HF directory checkpoints must not be reported as missing model files."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))

import model_switchboard_agent as agent  # noqa: E402
import discovery  # noqa: E402


class HFDirectoryClaimTests(unittest.TestCase):
    def test_missing_artifacts_accepts_model_file_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            model_dir = Path(tmp) / "hf-model"
            model_dir.mkdir()
            (model_dir / "config.json").write_text("{}", encoding="utf-8")
            missing = agent.missing_local_model_artifacts(
                {
                    "MODEL_PATH": str(model_dir),
                    "MODEL_FILE": str(model_dir),
                }
            )
            self.assertEqual(missing, [])

    def test_profile_from_claim_maps_hf_dir_to_model_dir_not_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            claim_path = Path(tmp) / "8040"
            claim_path.mkdir()
            model_dir = Path(tmp) / "Intern-S2-Mobius"
            model_dir.mkdir()
            (model_dir / "config.json").write_text("{}", encoding="utf-8")
            (claim_path / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (claim_path / "launch.sh").chmod(0o755)
            (claim_path / "flags.env").write_text(
                f"MODEL={model_dir}\nHOST=127.0.0.1\nPORT=8040\n",
                encoding="utf-8",
            )
            claims = discovery.scan_port_claim_directories(roots=[Path(tmp)])
            claim = next(c for c in claims if int(c["port"]) == 8040)
            profile = discovery.profile_from_claim(claim)
            self.assertEqual(profile.get("MODEL_PATH"), str(model_dir))
            self.assertEqual(profile.get("MODEL_DIR"), str(model_dir))
            self.assertEqual(profile.get("MODEL_FILE") or "", "")
            self.assertEqual(agent.missing_local_model_artifacts(profile.values), [])


if __name__ == "__main__":
    unittest.main()

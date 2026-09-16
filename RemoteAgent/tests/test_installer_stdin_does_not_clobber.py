"""Mac Update runs the installer via `bash -s`; leftover $PWD files must not win."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]


class InstallerStdinTests(unittest.TestCase):
    def test_stdin_install_keeps_pushed_modules_over_home_leftovers(self) -> None:
        installer = (AGENT_DIR / "install-remote-agent.sh").read_text(encoding="utf-8")
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            home.mkdir()
            install_root = home / ".local/share/model-switchboard-agent"
            install_root.mkdir(parents=True)
            (home / ".local/bin").mkdir(parents=True)
            for name in ("agent_core.py", "discovery.py", "model_switchboard_agent.py"):
                shutil.copy(AGENT_DIR / name, install_root / name)
            (home / "agent_core.py").write_text("# LEFTOVER_CLOBBER\n", encoding="utf-8")

            fake_bin = Path(tmp) / "bin"
            fake_bin.mkdir()
            systemctl = fake_bin / "systemctl"
            systemctl.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
            systemctl.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            env["PATH"] = f"{fake_bin}{os.pathsep}{env.get('PATH', '')}"
            env.pop("XDG_RUNTIME_DIR", None)

            result = subprocess.run(
                ["bash", "-s", "--", "--port", "8877"],
                input=installer,
                cwd=str(home),
                env=env,
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(
                result.returncode,
                0,
                msg=result.stderr + result.stdout,
            )
            core = (install_root / "agent_core.py").read_text(encoding="utf-8")
            self.assertNotIn("LEFTOVER_CLOBBER", core)
            self.assertIn("def path_is_regular_file", core)


if __name__ == "__main__":
    unittest.main()

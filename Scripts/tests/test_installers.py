import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def write_executable(path: Path, content: str) -> None:
    path.write_text(textwrap.dedent(content))
    path.chmod(0o755)


class InstallerScriptTests(unittest.TestCase):
    def test_app_installer_installs_app_cli_and_completions_quietly(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            repo = tmp_path / "repo"
            scripts = repo / "Scripts"
            scripts.mkdir(parents=True)
            shutil.copy2(ROOT / "Scripts" / "install.sh", scripts / "install.sh")
            shutil.copy2(ROOT / "Scripts" / "model-switchboardctl", scripts / "model-switchboardctl")
            (repo / "VERSION").write_text("9.9.9\n")

            write_executable(
                scripts / "build-app.sh",
                """\
                #!/usr/bin/env bash
                set -euo pipefail
                root="$(cd "$(dirname "$0")/.." && pwd)"
                case "${APP_VARIANT:-base}" in
                  base) app_name="Model Switchboard.app" ;;
                  plus) app_name="Model Switchboard Plus.app" ;;
                  *) exit 2 ;;
                esac
                app="$root/dist/$app_name"
                mkdir -p "$app/Contents"
                cat > "$app/Contents/Info.plist" <<'PLIST'
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0"><dict><key>CFBundleName</key><string>Model Switchboard</string></dict></plist>
                PLIST
                """,
            )
            write_executable(
                scripts / "verify-privacy.sh",
                """\
                #!/usr/bin/env bash
                set -euo pipefail
                exit 0
                """,
            )

            fake_bin = tmp_path / "fake-bin"
            fake_bin.mkdir()
            for name in ("pkill", "sleep", "xattr", "codesign", "osascript", "SetFile", "mdimport", "open"):
                write_executable(fake_bin / name, "#!/bin/sh\nexit 0\n")
            write_executable(
                fake_bin / "ditto",
                """\
                #!/bin/sh
                set -eu
                src="$1"
                dst="$2"
                rm -rf "$dst"
                mkdir -p "$(dirname "$dst")"
                cp -R "$src" "$dst"
                """,
            )
            write_executable(
                fake_bin / "uname",
                """\
                #!/bin/sh
                case "$1" in
                  -s) printf 'Darwin\\n' ;;
                  -m) printf 'arm64\\n' ;;
                  *) /usr/bin/uname "$@" ;;
                esac
                """,
            )

            home = tmp_path / "home"
            app_dir = home / "Applications"
            bin_dir = home / ".local" / "bin"
            env = os.environ.copy()
            env.update(
                {
                    "HOME": str(home),
                    "PATH": f"{fake_bin}:{env['PATH']}",
                    "TMPDIR": str(tmp_path),
                    "SYSTEM_APPLICATIONS_DIR": str(tmp_path / "SystemApplications"),
                }
            )

            install = scripts / "install.sh"
            result = subprocess.run(
                [
                    "bash",
                    str(install),
                    "--variant",
                    "plus",
                    "--install-dir",
                    str(app_dir),
                    "--bin-dir",
                    str(bin_dir),
                    "--skip-open",
                    "--quiet",
                    "--no-gum",
                    "--force",
                ],
                cwd=repo,
                env=env,
                text=True,
                capture_output=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            self.assertEqual(result.stdout, "")
            self.assertEqual(result.stderr, "")
            self.assertTrue((app_dir / "Model Switchboard Plus.app" / "Contents" / "Info.plist").exists())
            self.assertTrue((bin_dir / "model-switchboardctl").exists())
            self.assertTrue((home / ".local/share/bash-completion/completions/model-switchboardctl").exists())
            self.assertTrue((home / ".local/share/zsh/site-functions/_model-switchboardctl").exists())
            self.assertTrue((home / ".config/fish/completions/model-switchboardctl.fish").exists())

            verify = subprocess.run(
                [
                    "bash",
                    str(install),
                    "--variant",
                    "plus",
                    "--install-dir",
                    str(app_dir),
                    "--bin-dir",
                    str(bin_dir),
                    "--verify",
                    "--quiet",
                    "--no-gum",
                ],
                cwd=repo,
                env=env,
                text=True,
                capture_output=True,
            )
            self.assertEqual(verify.returncode, 0, verify.stderr or verify.stdout)
            self.assertEqual(verify.stdout, "")
            self.assertEqual(verify.stderr, "")

    def test_model_switchboardctl_prints_completions_without_controller(self) -> None:
        ctl = ROOT / "Scripts" / "model-switchboardctl"
        result = subprocess.run(
            ["bash", str(ctl), "completions", "bash"],
            text=True,
            capture_output=True,
            check=True,
        )
        self.assertIn("complete -F _model_switchboardctl_completion", result.stdout)
        self.assertEqual(result.stderr, "")

    def test_model_switchboardctl_exposes_agent_capabilities_without_controller(self) -> None:
        ctl = ROOT / "Scripts" / "model-switchboardctl"
        result = subprocess.run(
            ["bash", str(ctl), "capabilities"],
            text=True,
            capture_output=True,
            check=True,
        )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["tool"], "model-switchboardctl")
        self.assertEqual(payload["default_probe"], "model-switchboardctl triage")
        self.assertIn("commands", payload)
        self.assertEqual(result.stderr, "")

    def test_model_switchboardctl_unknown_command_teaches_correction(self) -> None:
        ctl = ROOT / "Scripts" / "model-switchboardctl"
        result = subprocess.run(
            ["bash", str(ctl), "stats"],
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 64)
        self.assertIn("did you mean: model-switchboardctl status", result.stderr)
        self.assertIn("model-switchboardctl capabilities", result.stderr)

    def test_model_switchboardctl_robot_docs_rejects_unknown_topic(self) -> None:
        ctl = ROOT / "Scripts" / "model-switchboardctl"
        result = subprocess.run(
            ["bash", str(ctl), "robot-docs", "reference"],
            text=True,
            capture_output=True,
            check=False,
        )

        self.assertEqual(result.returncode, 64)
        self.assertIn("did you mean: model-switchboardctl robot-docs guide", result.stderr)

    def test_model_switchboardctl_dry_run_plan_does_not_require_controller(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            ctl = Path(tmpdir) / "model-switchboardctl"
            shutil.copy2(ROOT / "Scripts" / "model-switchboardctl", ctl)
            result = subprocess.run(
                ["bash", str(ctl), "start", "qwen35-a3b", "--dry-run", "--json"],
                text=True,
                capture_output=True,
                check=True,
            )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["tool"], "model-switchboardctl")
        self.assertTrue(payload["dry_run"])
        self.assertEqual(payload["plan"][0]["endpoint"], "/api/start")
        self.assertEqual(payload["plan"][0]["payload"], {"profile": "qwen35-a3b"})
        self.assertEqual(result.stderr, "")


if __name__ == "__main__":
    unittest.main()

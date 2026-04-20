from __future__ import annotations

import importlib.util
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
MODULE_PATH = ROOT / "modelctl.py"
SPEC = importlib.util.spec_from_file_location("modelctl", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ModelCtlTests(unittest.TestCase):
    def test_model_path_for_profile_requires_explicit_model_root_for_model_file(self) -> None:
        env_without_root = {"MODEL_FILE": "demo.gguf"}
        env_with_root = {"MODEL_FILE": "demo.gguf", "MODEL_ROOT": "/models"}

        self.assertIsNone(MODULE.model_path_for_profile(env_without_root))
        self.assertEqual(MODULE.model_path_for_profile(env_with_root), Path("/models/demo.gguf"))

    def test_resolve_llama_server_bin_prefers_profile_config_before_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            server_bin = Path(tmpdir) / "llama-server"
            server_bin.write_text("#!/bin/sh\nexit 0\n")
            server_bin.chmod(0o755)

            env = {"SERVER_BIN": str(server_bin)}

            self.assertEqual(MODULE.resolve_llama_server_bin(env), str(server_bin))

    def test_resolve_mlx_server_bin_prefers_profile_config_before_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            server_bin = Path(tmpdir) / "mlx_lm.server"
            server_bin.write_text("#!/bin/sh\nexit 0\n")
            server_bin.chmod(0o755)

            env = {"SERVER_BIN": str(server_bin)}

            self.assertEqual(MODULE.resolve_mlx_server_bin(env), str(server_bin))

    def test_status_for_profile_ignores_unmatched_shared_port_listener(self) -> None:
        env = {
            "PROFILE_NAME": "qwen35-a3b",
            "DISPLAY_NAME": "Qwen 3.5 35B",
            "REQUEST_MODEL": "qwen35-local",
            "SERVER_MODEL_ID": "qwen35-local",
            "PORT": "8080",
        }

        with (
            mock.patch.object(MODULE, "probe_health", return_value=(False, ["supergemma-local"])),
            mock.patch.object(MODULE, "read_pid", return_value=None),
            mock.patch.object(MODULE, "port_listener_pid", return_value=4242),
            mock.patch.object(MODULE, "process_alive", return_value=True),
            mock.patch.object(MODULE, "pid_command", return_value="/tmp/supergemma31b/server --model-dir /models/supergemma"),
            mock.patch.object(MODULE, "pid_rss_mb", return_value=None),
            mock.patch.object(MODULE, "log_path", return_value="/tmp/qwen35.log"),
        ):
            status = MODULE.status_for_profile("qwen35-a3b", env)

        self.assertIsNone(status["pid"])
        self.assertFalse(status["running"])
        self.assertFalse(status["ready"])
        self.assertEqual(status["server_ids"], ["supergemma-local"])

    def test_status_for_profile_accepts_ready_listener_without_pid_file(self) -> None:
        env = {
            "PROFILE_NAME": "supergemma31b-rvllm-mlx",
            "DISPLAY_NAME": "SuperGemma 31B",
            "REQUEST_MODEL": "supergemma-local",
            "SERVER_MODEL_ID": "supergemma-local",
            "PORT": "8080",
        }

        with (
            mock.patch.object(MODULE, "probe_health", return_value=(True, ["supergemma-local"])),
            mock.patch.object(MODULE, "read_pid", return_value=None),
            mock.patch.object(MODULE, "port_listener_pid", return_value=5151),
            mock.patch.object(MODULE, "process_alive", return_value=True),
            mock.patch.object(MODULE, "pid_command", return_value="/tmp/supergemma31b/server --model-dir /models/supergemma"),
            mock.patch.object(MODULE, "pid_rss_mb", return_value=2048.0),
            mock.patch.object(MODULE, "log_path", return_value="/tmp/supergemma.log"),
        ):
            status = MODULE.status_for_profile("supergemma31b-rvllm-mlx", env)

        self.assertEqual(status["pid"], 5151)
        self.assertTrue(status["running"])
        self.assertTrue(status["ready"])
        self.assertEqual(status["server_ids"], ["supergemma-local"])

    def test_diagnose_profile_accepts_valid_rvllm_mlx_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            server_bin = tmp_path / "rvllm-mlx-server"
            server_bin.write_text("#!/bin/sh\nexit 0\n")
            server_bin.chmod(0o755)
            model_dir = tmp_path / "model"
            model_dir.mkdir()

            env = {
                "PROFILE_NAME": "supergemma31b-rvllm-mlx",
                "DISPLAY_NAME": "SuperGemma 31B",
                "RUNTIME": "rvllm-mlx",
                "SERVER_BIN": str(server_bin),
                "MODEL_DIR": str(model_dir),
                "PORT": "8080",
                "REQUEST_MODEL": "supergemma-local",
                "SERVER_MODEL_ID": "supergemma-local",
            }

            with mock.patch.object(
                MODULE,
                "status_for_profile",
                return_value={
                    "running": False,
                    "ready": False,
                    "pid": None,
                    "base_url": "http://127.0.0.1:8080/v1",
                },
            ):
                report = MODULE.diagnose_profile("supergemma31b-rvllm-mlx", env)

        self.assertEqual(report["errors"], [])
        self.assertEqual(report["warnings"], [])

    def test_start_model_script_requires_profile_selection(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            script_path = Path(tmpdir) / "start-model-mac.sh"
            shutil.copy2(ROOT / "start-model-mac.sh", script_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmpdir,
                text=True,
                capture_output=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set MODEL_PROFILE or MODEL_PROFILE_PATH", result.stderr or result.stdout)

    def test_start_model_script_supports_rvllm_mlx_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script_path = tmp_path / "start-model-mac.sh"
            shutil.copy2(ROOT / "start-model-mac.sh", script_path)

            model_dir = tmp_path / "model"
            model_dir.mkdir()
            profile_path = tmp_path / "supergemma31b-rvllm-mlx.json"
            log_alias = "supergemma31b-rvllm-mlx-test"

            server_bin = tmp_path / "fake-rvllm-mlx-server"
            server_bin.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import argparse
                    import json
                    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

                    parser = argparse.ArgumentParser()
                    parser.add_argument("--model-dir")
                    parser.add_argument("--host", default="127.0.0.1")
                    parser.add_argument("--port", type=int, required=True)
                    args = parser.parse_args()

                    class Handler(BaseHTTPRequestHandler):
                        def do_GET(self):
                            if self.path != "/v1/models":
                                self.send_response(404)
                                self.end_headers()
                                return
                            payload = json.dumps({"data": [{"id": "supergemma-local"}]}).encode()
                            self.send_response(200)
                            self.send_header("Content-Type", "application/json")
                            self.send_header("Content-Length", str(len(payload)))
                            self.end_headers()
                            self.wfile.write(payload)

                        def log_message(self, format, *args):
                            return

                    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
                    """
                )
            )
            server_bin.chmod(0o755)

            agl_python = tmp_path / ".venv-agentlightning" / "bin" / "python"
            agl_python.parent.mkdir(parents=True)
            agl_python.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/sh
                    exit 0
                    """
                )
            )
            agl_python.chmod(0o755)

            profile_path.write_text(
                textwrap.dedent(
                    f"""\
                    {{
                      "DISPLAY_NAME": "SuperGemma 31B",
                      "RUNTIME": "rvllm-mlx",
                      "SERVER_BIN": "{server_bin}",
                      "MODEL_DIR": "{model_dir}",
                      "HOST": "127.0.0.1",
                      "PORT": "18080",
                      "REQUEST_MODEL": "supergemma-local",
                      "SERVER_MODEL_ID": "supergemma-local",
                      "MODEL_ALIAS": "{log_alias}"
                    }}
                    """
                )
            )

            env = os.environ.copy()
            env["MODEL_PROFILE"] = "supergemma31b-rvllm-mlx"
            env["MODEL_PROFILE_PATH"] = str(profile_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmp_path,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )

            pid_path = tmp_path / "run" / "supergemma31b-rvllm-mlx.pid"
            self.assertIn("runtime=rvllm-mlx", result.stdout)
            self.assertTrue(pid_path.exists())

            pid = int(pid_path.read_text().strip())
            os.kill(pid, signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()

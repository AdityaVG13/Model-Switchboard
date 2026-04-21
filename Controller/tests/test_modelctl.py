from __future__ import annotations

import importlib.util
import os
import shutil
import signal
import socket
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


def reserve_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


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

    def test_profile_endpoint_conflicts_normalize_loopback_hosts(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
            "supergemma31b-rvllm-mlx": {
                "PROFILE_NAME": "supergemma31b-rvllm-mlx",
                "DISPLAY_NAME": "SuperGemma 31B",
                "REQUEST_MODEL": "supergemma-local",
                "HOST": "localhost",
                "PORT": "8080",
            },
            "gemma3-mlx": {
                "PROFILE_NAME": "gemma3-mlx",
                "DISPLAY_NAME": "Gemma 3 MLX",
                "REQUEST_MODEL": "gemma3-local",
                "HOST": "127.0.0.1",
                "PORT": "8081",
            },
        }

        conflicts = MODULE.profile_endpoint_conflicts(profiles)

        self.assertEqual(
            conflicts["qwen35-a3b"],
            ("localhost:8080", ["supergemma31b-rvllm-mlx"]),
        )
        self.assertEqual(
            conflicts["supergemma31b-rvllm-mlx"],
            ("localhost:8080", ["qwen35-a3b"]),
        )
        self.assertNotIn("gemma3-mlx", conflicts)

    def test_status_snapshot_disables_port_fallback_for_conflicted_profiles(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
            "supergemma31b-rvllm-mlx": {
                "PROFILE_NAME": "supergemma31b-rvllm-mlx",
                "DISPLAY_NAME": "SuperGemma 31B",
                "REQUEST_MODEL": "supergemma-local",
                "HOST": "localhost",
                "PORT": "8080",
            },
            "gemma3-mlx": {
                "PROFILE_NAME": "gemma3-mlx",
                "DISPLAY_NAME": "Gemma 3 MLX",
                "REQUEST_MODEL": "gemma3-local",
                "HOST": "127.0.0.1",
                "PORT": "8081",
            },
        }
        captured: dict[str, bool] = {}

        def fake_status_for_profile(name: str, env: dict[str, str], *, allow_port_fallback: bool = True) -> dict[str, object]:
            captured[name] = allow_port_fallback
            return {
                "profile": name,
                "display_name": env["DISPLAY_NAME"],
                "runtime": env.get("RUNTIME", "llama.cpp"),
                "host": env.get("HOST", "127.0.0.1"),
                "port": env.get("PORT", ""),
                "base_url": MODULE.base_url(env),
                "request_model": env["REQUEST_MODEL"],
                "server_model_id": env.get("SERVER_MODEL_ID", env["REQUEST_MODEL"]),
                "pid": None,
                "running": False,
                "ready": False,
                "server_ids": [],
                "rss_mb": None,
                "command": None,
                "log_path": "/tmp/test.log",
            }

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "status_for_profile", side_effect=fake_status_for_profile),
        ):
            statuses = MODULE.status_snapshot()

        self.assertEqual([item["profile"] for item in statuses], ["gemma3-mlx", "qwen35-a3b", "supergemma31b-rvllm-mlx"])
        self.assertTrue(captured["gemma3-mlx"])
        self.assertFalse(captured["qwen35-a3b"])
        self.assertFalse(captured["supergemma31b-rvllm-mlx"])

    def test_doctor_report_flags_duplicate_endpoint_profiles(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
            "supergemma31b-rvllm-mlx": {
                "PROFILE_NAME": "supergemma31b-rvllm-mlx",
                "DISPLAY_NAME": "SuperGemma 31B",
                "REQUEST_MODEL": "supergemma-local",
                "HOST": "localhost",
                "PORT": "8080",
            },
        }
        live_status = {
            "running": False,
            "ready": False,
            "pid": None,
            "base_url": "http://127.0.0.1:8080/v1",
        }

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "controller_status", return_value={"url": "http://127.0.0.1:8877/api/status", "reachable": True, "profiles": 2, "integrations": 0}),
            mock.patch.object(MODULE, "launch_agent_status", return_value={"plist_path": "/tmp/io.modelswitchboard.controller.plist", "installed": True, "running": True}),
            mock.patch.object(MODULE, "integration_status", return_value=[]),
            mock.patch.object(MODULE, "status_for_profile", return_value=live_status),
        ):
            report = MODULE.doctor_report()

        diagnostics = {item["profile"]: item for item in report["profiles"]}
        self.assertIn(
            "duplicate endpoint localhost:8080 is also configured for profile supergemma31b-rvllm-mlx",
            diagnostics["qwen35-a3b"]["errors"],
        )
        self.assertIn(
            "duplicate endpoint localhost:8080 is also configured for profile qwen35-a3b",
            diagnostics["supergemma31b-rvllm-mlx"]["errors"],
        )

    def test_switch_profile_rejects_duplicate_endpoint_assignment(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
            "supergemma31b-rvllm-mlx": {
                "PROFILE_NAME": "supergemma31b-rvllm-mlx",
                "DISPLAY_NAME": "SuperGemma 31B",
                "REQUEST_MODEL": "supergemma-local",
                "HOST": "localhost",
                "PORT": "8080",
            },
        }

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "status_snapshot", return_value=[]),
            mock.patch.object(MODULE, "stop_profile") as stop_profile,
            mock.patch.object(MODULE, "start_profile") as start_profile,
        ):
            with self.assertRaises(MODULE.ProfileConflictError) as ctx:
                MODULE.switch_profile("supergemma31b-rvllm-mlx")

        self.assertEqual(
            str(ctx.exception),
            "Cannot activate supergemma31b-rvllm-mlx: endpoint localhost:8080 is also configured for profile qwen35-a3b. Each profile must use a unique HOST:PORT or BASE_URL.",
        )
        stop_profile.assert_not_called()
        start_profile.assert_not_called()

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
            port = reserve_local_port()

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
                      "PORT": "{port}",
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

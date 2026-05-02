from __future__ import annotations

import importlib.util
import json
import os
import plistlib
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
    def test_model_path_for_profile_supports_model_root_hint(self) -> None:
        env = {"MODEL_FILE": "demo.gguf", "MODEL_ROOT_HINT": "/hinted-models"}

        self.assertEqual(MODULE.model_path_for_profile(env), Path("/hinted-models/demo.gguf"))

    def test_model_path_for_profile_prefers_explicit_model_path(self) -> None:
        env = {
            "MODEL_PATH": "/direct/model.gguf",
            "MODEL_FILE": "demo.gguf",
            "MODEL_ROOT": "/models",
            "MODEL_ROOT_HINT": "/hinted-models",
        }

        self.assertEqual(MODULE.model_path_for_profile(env), Path("/direct/model.gguf"))

    def test_adapter_model_source_prefers_local_sources_before_remote_ids(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            model_dir = Path(tmpdir) / "mlx-model"
            model_dir.mkdir()
            env = {
                "MODEL_DIR": str(model_dir),
                "MODEL_FILE": "fallback.gguf",
                "MODEL_ROOT": tmpdir,
                "MODEL_ID": "remote/id",
                "MODEL_REPO": "remote/repo",
            }

            self.assertEqual(MODULE.adapter_model_source(env), str(model_dir))

            env.pop("MODEL_DIR")
            env["MODEL_PATH"] = str(Path(tmpdir) / "direct.gguf")
            self.assertEqual(MODULE.adapter_model_source(env), env["MODEL_PATH"])

            env.pop("MODEL_PATH")
            self.assertEqual(MODULE.adapter_model_source(env), str(Path(tmpdir) / "fallback.gguf"))

    def test_log_path_sanitizes_model_alias_paths(self) -> None:
        env = {
            "PROFILE_NAME": "supergemma31b-rvllm-mlx",
            "MODEL_ALIAS": "/opt/models/gemma",
        }

        self.assertEqual(MODULE.log_path(env), "/tmp/_opt_models_gemma.log")

    def test_diagnose_profile_reports_model_root_hint_fallbacks_when_model_path_is_missing(self) -> None:
        env = {
            "PROFILE_NAME": "broken-llama",
            "DISPLAY_NAME": "Broken Llama",
            "RUNTIME": "llama.cpp",
            "MODEL_FILE": "missing.gguf",
            "REQUEST_MODEL": "broken-llama",
        }

        with (
            mock.patch.object(MODULE, "resolve_llama_server_bin", return_value="/usr/local/bin/llama-server"),
            mock.patch.object(MODULE, "model_path_for_profile", return_value=None),
            mock.patch.object(
                MODULE,
                "status_for_profile",
                return_value={
                    "running": False,
                    "ready": False,
                    "pid": None,
                    "base_url": "http://127.0.0.1:8080/v1",
                },
            ),
        ):
            report = MODULE.diagnose_profile("broken-llama", env)

        self.assertIn(
            "missing MODEL_PATH or MODEL_FILE with a model root (MODEL_ROOT, MODEL_ROOT_HINT, ~/AI/models, or ../models)",
            report["errors"],
        )

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

    def test_resolve_vllm_mlx_server_bin_prefers_profile_config_before_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            server_bin = Path(tmpdir) / "vllm-mlx"
            server_bin.write_text("#!/bin/sh\nexit 0\n")
            server_bin.chmod(0o755)

            env = {"SERVER_BIN": str(server_bin)}

            self.assertEqual(MODULE.resolve_vllm_mlx_server_bin(env), str(server_bin))

    def test_runtime_metadata_canonicalizes_aliases_and_adds_profile_tags(self) -> None:
        env = {
            "RUNTIME": "mlx_lm",
            "RUNTIME_TAGS": "fast, coding agent",
        }

        self.assertEqual(MODULE.canonical_runtime(env["RUNTIME"]), "mlx")
        self.assertEqual(MODULE.runtime_spec(env)["label"], "MLX")
        self.assertEqual(
            MODULE.runtime_tags(env),
            ["mlx", "managed", "openai-compatible", "apple-silicon", "fast", "coding", "agent"],
        )

    def test_runtime_metadata_canonicalizes_vllm_mlx(self) -> None:
        env = {"RUNTIME": "vllm_mlx"}

        self.assertEqual(MODULE.canonical_runtime(env["RUNTIME"]), "vllm-mlx")
        self.assertEqual(MODULE.runtime_spec(env)["label"], "vLLM-MLX")
        self.assertEqual(
            MODULE.runtime_tags(env),
            ["vllm-mlx", "managed", "openai-compatible", "mlx", "server", "apple-silicon"],
        )

    def test_runtime_metadata_keeps_named_command_runtime_label(self) -> None:
        env = {
            "RUNTIME": "ddtree_mlx",
            "START_COMMAND": "/opt/ddtree/start",
        }

        self.assertEqual(MODULE.canonical_runtime(env["RUNTIME"]), "ddtree-mlx")
        self.assertEqual(MODULE.runtime_spec(env)["label"], "DDTree MLX")
        self.assertEqual(MODULE.runtime_spec(env)["launch_mode"], "command")
        self.assertIn("speculative-decoding", MODULE.runtime_tags(env))

    def test_runtime_metadata_covers_named_launcher_ecosystem(self) -> None:
        cases = {
            "mistral-rs": ("mistral.rs", "mistral.rs", "rust"),
            "mlx-omni": ("mlx-omni-server", "MLX Omni Server", "anthropic-compatible"),
            "mlc": ("mlc-llm", "MLC-LLM", "metal"),
            "litellm-proxy": ("litellm", "LiteLLM", "proxy"),
            "nexa-sdk": ("nexa", "Nexa SDK", "multimodal"),
        }

        for raw, (canonical, label, tag) in cases.items():
            with self.subTest(runtime=raw):
                env = {"RUNTIME": raw}
                self.assertEqual(MODULE.canonical_runtime(raw), canonical)
                self.assertEqual(MODULE.runtime_spec(env)["label"], label)
                self.assertIn(tag, MODULE.runtime_tags(env))

    def test_runtime_spec_treats_start_command_as_command_launch_mode(self) -> None:
        env = {
            "RUNTIME": "lmstudio",
            "START_COMMAND": "/usr/local/bin/lms server start",
        }

        self.assertEqual(MODULE.canonical_runtime(env["RUNTIME"]), "lm-studio")
        self.assertEqual(MODULE.runtime_spec(env)["launch_mode"], "command")

    def test_diagnose_honors_external_launch_mode_for_native_runtime(self) -> None:
        env = {
            "PROFILE_NAME": "external-vllm",
            "DISPLAY_NAME": "External vLLM",
            "RUNTIME": "vllm",
            "LAUNCH_MODE": "external",
            "REQUEST_MODEL": "qwen",
            "SERVER_MODEL_ID": "qwen",
            "BASE_URL": "http://127.0.0.1:8000/v1",
        }

        with mock.patch.object(
            MODULE,
            "status_for_profile",
            return_value={
                "running": False,
                "ready": False,
                "pid": None,
                "base_url": "http://127.0.0.1:8000/v1",
            },
        ):
            report = MODULE.diagnose_profile("external-vllm", env)

        self.assertNotIn("missing MODEL_REPO, MODEL_ID, MODEL_DIR, MODEL_PATH, or MODEL_FILE for vllm", report["errors"])
        self.assertEqual(report["launch_mode"], "external")

    def test_terminate_pid_signals_process_group_before_process(self) -> None:
        with (
            mock.patch.object(MODULE.os, "killpg") as killpg,
            mock.patch.object(MODULE.os, "kill") as kill_pid,
            mock.patch.object(MODULE, "process_alive", return_value=False),
        ):
            MODULE.terminate_pid(4242)

        killpg.assert_called_once_with(4242, signal.SIGTERM)
        kill_pid.assert_not_called()

    def test_stop_profile_runs_stop_command_without_pid(self) -> None:
        env = {
            "PROFILE_NAME": "external",
            "DISPLAY_NAME": "External",
            "REQUEST_MODEL": "external",
            "STOP_COMMAND": "echo stop",
        }
        with (
            mock.patch.object(MODULE, "require_profile", return_value=env),
            mock.patch.object(MODULE, "status_for_profile", return_value={"pid": None}),
            mock.patch.object(MODULE, "run_profile_shell") as run_profile_shell,
            mock.patch.object(MODULE, "pid_path") as pid_path,
        ):
            pid_path.return_value.unlink.return_value = None
            MODULE.stop_profile("external")

        run_profile_shell.assert_called_once_with("echo stop", env)

    def test_stop_profile_runs_stop_command_then_terminates_pid(self) -> None:
        env = {
            "PROFILE_NAME": "managed",
            "DISPLAY_NAME": "Managed",
            "REQUEST_MODEL": "managed",
            "STOP_COMMAND": "echo stop",
        }
        with (
            mock.patch.object(MODULE, "require_profile", return_value=env),
            mock.patch.object(MODULE, "status_for_profile", return_value={"pid": 5151}),
            mock.patch.object(MODULE, "run_profile_shell") as run_profile_shell,
            mock.patch.object(MODULE, "terminate_pid") as terminate_pid,
            mock.patch.object(MODULE, "pid_path") as pid_path,
        ):
            pid_path.return_value.unlink.return_value = None
            MODULE.stop_profile("managed")

        run_profile_shell.assert_called_once_with("echo stop", env)
        terminate_pid.assert_called_once_with(5151)

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

    def test_switch_profile_marks_active_profile_after_start(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
        }

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "status_snapshot", return_value=[]),
            mock.patch.object(MODULE, "start_profile") as start_profile,
            mock.patch.object(MODULE, "write_active_profile") as write_active_profile,
        ):
            MODULE.switch_profile("qwen35-a3b")

        start_profile.assert_called_once_with("qwen35-a3b")
        write_active_profile.assert_called_once_with("qwen35-a3b")

    def test_active_profile_watchdog_restarts_dead_active_profile(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
        }

        with (
            mock.patch.object(MODULE, "read_active_profile", return_value="qwen35-a3b"),
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(
                MODULE,
                "status_for_profile",
                return_value={
                    "running": False,
                    "ready": False,
                    "pid": None,
                },
            ),
            mock.patch.object(MODULE, "start_profile") as start_profile,
        ):
            MODULE.active_profile_watchdog_once()

        start_profile.assert_called_once_with("qwen35-a3b")

    def test_active_profile_watchdog_leaves_live_active_profile_alone(self) -> None:
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen 3.5 35B",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
        }

        with (
            mock.patch.object(MODULE, "read_active_profile", return_value="qwen35-a3b"),
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(
                MODULE,
                "status_for_profile",
                return_value={
                    "running": True,
                    "ready": False,
                    "pid": 123,
                },
            ),
            mock.patch.object(MODULE, "start_profile") as start_profile,
        ):
            MODULE.active_profile_watchdog_once()

        start_profile.assert_not_called()

    def test_stop_profile_clears_active_profile_when_already_stopped(self) -> None:
        env = {
            "PROFILE_NAME": "qwen35-a3b",
            "DISPLAY_NAME": "Qwen 3.5 35B",
            "REQUEST_MODEL": "qwen35-local",
            "HOST": "127.0.0.1",
            "PORT": "8080",
        }

        with (
            mock.patch.object(MODULE, "require_profile", return_value=env),
            mock.patch.object(MODULE, "status_for_profile", return_value={"pid": None}),
            mock.patch.object(MODULE, "clear_active_profile") as clear_active_profile,
        ):
            MODULE.stop_profile("qwen35-a3b")

        clear_active_profile.assert_called_once_with("qwen35-a3b")

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

    def test_diagnose_profile_accepts_valid_vllm_mlx_profile(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            server_bin = tmp_path / "vllm-mlx"
            server_bin.write_text("#!/bin/sh\nexit 0\n")
            server_bin.chmod(0o755)
            model_dir = tmp_path / "model"
            model_dir.mkdir()

            env = {
                "PROFILE_NAME": "qwen-vllm-mlx",
                "DISPLAY_NAME": "Qwen vLLM-MLX",
                "RUNTIME": "vllm-mlx",
                "SERVER_BIN": str(server_bin),
                "MODEL_DIR": str(model_dir),
                "PORT": "8102",
                "REQUEST_MODEL": "qwen-local",
                "SERVER_MODEL_ID": "qwen-local",
            }

            with mock.patch.object(
                MODULE,
                "status_for_profile",
                return_value={
                    "running": False,
                    "ready": False,
                    "pid": None,
                    "base_url": "http://127.0.0.1:8102/v1",
                },
            ):
                report = MODULE.diagnose_profile("qwen-vllm-mlx", env)

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
                    parser.add_argument("--ctx-len")
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
                      "MODEL_ALIAS": "{log_alias}",
                      "SERVER_ARGS_JSON": ["--ctx-len", "32768"]
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

    def test_start_model_script_supports_vllm_mlx_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script_path = tmp_path / "start-model-mac.sh"
            shutil.copy2(ROOT / "start-model-mac.sh", script_path)
            port = reserve_local_port()

            model_dir = tmp_path / "model"
            model_dir.mkdir()
            profile_path = tmp_path / "qwen-vllm-mlx.json"
            log_alias = "qwen-vllm-mlx-test"

            server_bin = tmp_path / "fake-vllm-mlx"
            server_bin.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import argparse
                    import json
                    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

                    parser = argparse.ArgumentParser()
                    parser.add_argument("command")
                    parser.add_argument("model")
                    parser.add_argument("--host", default="127.0.0.1")
                    parser.add_argument("--port", type=int, required=True)
                    parser.add_argument("--served-model-name", required=True)
                    parser.add_argument("--max-tokens")
                    parser.add_argument("--max-request-tokens")
                    parser.add_argument("--gpu-memory-utilization")
                    parser.add_argument("--prefill-step-size")
                    parser.add_argument("--cache-memory-percent")
                    parser.add_argument("--default-chat-template-kwargs")
                    parser.add_argument("--enable-auto-tool-choice", action="store_true")
                    parser.add_argument("--tool-call-parser")
                    args = parser.parse_args()

                    class Handler(BaseHTTPRequestHandler):
                        def do_GET(self):
                            if self.path != "/v1/models":
                                self.send_response(404)
                                self.end_headers()
                                return
                            payload = json.dumps({"data": [{"id": args.served_model_name}]}).encode()
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
            agl_python.write_text("#!/bin/sh\nexit 0\n")
            agl_python.chmod(0o755)

            profile_path.write_text(
                json.dumps(
                    {
                        "DISPLAY_NAME": "Qwen vLLM-MLX",
                        "RUNTIME": "vllm-mlx",
                        "SERVER_BIN": str(server_bin),
                        "MODEL_DIR": str(model_dir),
                        "HOST": "127.0.0.1",
                        "PORT": str(port),
                        "REQUEST_MODEL": "qwen-local",
                        "SERVER_MODEL_ID": "qwen-local",
                        "MODEL_ALIAS": log_alias,
                        "MAX_TOKENS": "32768",
                        "MAX_REQUEST_TOKENS": "32768",
                        "CACHE_MEMORY_PERCENT": "0.15",
                        "CHAT_TEMPLATE_KWARGS": "{\"enable_thinking\":false}",
                        "ENABLE_TOOL_CALLS": "1",
                        "TOOL_CALL_PARSER": "qwen",
                    }
                )
            )

            env = os.environ.copy()
            env["MODEL_PROFILE"] = "qwen-vllm-mlx"
            env["MODEL_PROFILE_PATH"] = str(profile_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmp_path,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )

            pid_path = tmp_path / "run" / "qwen-vllm-mlx.pid"
            self.assertIn("runtime=vllm-mlx", result.stdout)
            self.assertTrue(pid_path.exists())

            pid = int(pid_path.read_text().strip())
            os.kill(pid, signal.SIGTERM)

    def test_start_model_script_supports_generic_server_bin_with_json_args(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script_path = tmp_path / "start-model-mac.sh"
            shutil.copy2(ROOT / "start-model-mac.sh", script_path)
            port = reserve_local_port()
            server_bin = tmp_path / "fake-tabbyapi-server"
            server_bin.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import argparse
                    import json
                    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

                    parser = argparse.ArgumentParser()
                    parser.add_argument("--host", default="127.0.0.1")
                    parser.add_argument("--port", type=int, required=True)
                    parser.add_argument("--model-id", required=True)
                    args = parser.parse_args()

                    class Handler(BaseHTTPRequestHandler):
                        def do_GET(self):
                            if self.path != "/v1/models":
                                self.send_response(404)
                                self.end_headers()
                                return
                            payload = json.dumps({"data": [{"id": args.model_id}]}).encode()
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
            agl_python.write_text("exit 0\n")
            agl_python.chmod(0o755)
            profile_path = tmp_path / "tabbyapi.json"
            profile_path.write_text(
                json.dumps(
                    {
                        "DISPLAY_NAME": "TabbyAPI Test",
                        "RUNTIME": "tabbyapi",
                        "SERVER_BIN": str(server_bin),
                        "SERVER_ARGS_JSON": ["--host", "127.0.0.1", "--port", str(port), "--model-id", "tabby-local"],
                        "HOST": "127.0.0.1",
                        "PORT": str(port),
                        "REQUEST_MODEL": "tabby-local",
                        "SERVER_MODEL_ID": "tabby-local",
                    }
                )
            )
            env = os.environ.copy()
            env["MODEL_PROFILE"] = "tabbyapi"
            env["MODEL_PROFILE_PATH"] = str(profile_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmp_path,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )

            pid_path = tmp_path / "run" / "tabbyapi.pid"
            self.assertIn("runtime=tabbyapi", result.stdout)
            self.assertTrue(pid_path.exists())
            pid = int(pid_path.read_text().strip())
            os.kill(pid, signal.SIGTERM)

    def test_start_model_script_resolves_model_root_hint_and_passes_llama_args(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script_path = tmp_path / "start-model-mac.sh"
            shutil.copy2(ROOT / "start-model-mac.sh", script_path)
            port = reserve_local_port()

            model_root = tmp_path / "hinted-models"
            model_root.mkdir()
            model_path = model_root / "qwen.gguf"
            model_path.write_bytes(b"GGUF")

            capture_path = tmp_path / "llama-args.json"
            server_bin = tmp_path / "fake-llama-server"
            server_bin.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import argparse
                    import json
                    import os
                    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

                    parser = argparse.ArgumentParser(allow_abbrev=False)
                    parser.add_argument("--model", required=True)
                    parser.add_argument("--alias", required=True)
                    parser.add_argument("--host", default="127.0.0.1")
                    parser.add_argument("--port", type=int, required=True)
                    parser.add_argument("--ctx-size")
                    parser.add_argument("--parallel")
                    parser.add_argument("--threads")
                    parser.add_argument("--threads-batch")
                    parser.add_argument("--n-gpu-layers")
                    parser.add_argument("--batch-size")
                    parser.add_argument("--ubatch-size")
                    parser.add_argument("--cache-type-k")
                    parser.add_argument("--cache-type-v")
                    parser.add_argument("--flash-attn")
                    parser.add_argument("--reasoning")
                    parser.add_argument("--fit")
                    parser.add_argument("--fit-target")
                    parser.add_argument("--fit-ctx")
                    parser.add_argument("--reasoning-format")
                    parser.add_argument("--reasoning-budget")
                    parser.add_argument("--chat-template-kwargs")
                    parser.add_argument("--cache-ram")
                    parser.add_argument("--metrics", action="store_true")
                    parser.add_argument("--cont-batching", action="store_true")
                    parser.add_argument("--mmap", action="store_true")
                    parser.add_argument("--no-mmap", action="store_true")
                    parser.add_argument("--mlock", action="store_true")
                    args = parser.parse_args()

                    capture_path = os.environ["ARG_CAPTURE_PATH"]
                    with open(capture_path, "w", encoding="utf-8") as fp:
                        json.dump(vars(args), fp)

                    class Handler(BaseHTTPRequestHandler):
                        def do_GET(self):
                            if self.path != "/v1/models":
                                self.send_response(404)
                                self.end_headers()
                                return
                            payload = json.dumps({"data": [{"id": args.alias}]}).encode()
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

            profile_path = tmp_path / "qwen-llama.env"
            profile_path.write_text(
                textwrap.dedent(
                    f"""\
                    DISPLAY_NAME='Qwen GGUF'
                    RUNTIME=llama.cpp
                    SERVER_BIN={server_bin}
                    MODEL_FILE=qwen.gguf
                    MODEL_ROOT_HINT={model_root}
                    HOST=127.0.0.1
                    PORT={port}
                    REQUEST_MODEL=qwen-local
                    SERVER_MODEL_ID=qwen-local
                    MODEL_ALIAS=qwen-local
                    CONTEXT_SIZE=4096
                    N_PARALLEL=1
                    GPU_LAYERS=99
                    BATCH_SIZE=128
                    UBATCH_SIZE=64
                    CACHE_TYPE_K=f16
                    CACHE_TYPE_V=f16
                    FLASH_ATTN=1
                    REASONING=off
                    FIT=0
                    FIT_TARGET=0
                    FIT_CTX=0
                    REASONING_FORMAT=deepseek
                    REASONING_BUDGET=0
                    CHAT_TEMPLATE_KWARGS='{{"enable_thinking":false}}'
                    CACHE_RAM=4096
                    export ARG_CAPTURE_PATH={capture_path}
                    """
                )
            )

            env = os.environ.copy()
            env["MODEL_PROFILE"] = "qwen-llama"
            env["MODEL_PROFILE_PATH"] = str(profile_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmp_path,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )

            pid_path = tmp_path / "run" / "qwen-llama.pid"
            self.assertIn("runtime=llama.cpp", result.stdout)
            self.assertTrue(pid_path.exists())

            captured_args = json.loads(capture_path.read_text())
            self.assertEqual(captured_args["model"], str(model_path))
            self.assertEqual(captured_args["chat_template_kwargs"], '{"enable_thinking":false}')
            self.assertEqual(captured_args["cache_ram"], "4096")

            pid = int(pid_path.read_text().strip())
            os.kill(pid, signal.SIGTERM)

    def test_start_model_script_reports_clear_error_when_model_root_cannot_be_resolved(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            controller_dir = tmp_path / "Controller"
            controller_dir.mkdir()
            script_path = controller_dir / "start-model-mac.sh"
            shutil.copy2(ROOT / "start-model-mac.sh", script_path)

            profile_path = controller_dir / "broken.env"
            profile_path.write_text(
                textwrap.dedent(
                    """\
                    DISPLAY_NAME='Broken GGUF'
                    RUNTIME=llama.cpp
                    MODEL_FILE=missing.gguf
                    """
                )
            )

            env = os.environ.copy()
            env["HOME"] = str(tmp_path / "home")
            env["MODEL_PROFILE"] = "broken"
            env["MODEL_PROFILE_PATH"] = str(profile_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=controller_dir,
                env=env,
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn(
                "MODEL_FILE requires MODEL_ROOT, MODEL_ROOT_HINT, ~/AI/models, or ../models",
                result.stderr or result.stdout,
            )

    def test_install_controller_script_supports_root_override(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            install_dir = tmp_path / "installer"
            install_dir.mkdir()
            script_path = install_dir / "install-model-switchboard-controller.sh"
            shutil.copy2(ROOT / "install-model-switchboard-controller.sh", script_path)

            selected_root = tmp_path / "selected-root"
            selected_root.mkdir()
            (selected_root / "ModelSwitchboardController.swift").write_text("print(\"ok\")\n")

            fake_bin = tmp_path / "fake-bin"
            fake_bin.mkdir()

            swiftc = fake_bin / "swiftc"
            swiftc.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/sh
                    while [ "$#" -gt 0 ]; do
                      if [ "$1" = "-o" ]; then
                        shift
                        out="$1"
                        shift
                        src="$1"
                        mkdir -p "$(dirname "$out")"
                        printf '#!/bin/sh\nexit 0\n' > "$out"
                        chmod +x "$out"
                        printf '%s\n' "$src" > "${out}.src"
                        exit 0
                      fi
                      shift
                    done
                    exit 1
                    """
                )
            )
            swiftc.chmod(0o755)

            launchctl = fake_bin / "launchctl"
            launchctl.write_text(
                textwrap.dedent(
                    """\
                    #!/bin/sh
                    exit 0
                    """
                )
            )
            launchctl.chmod(0o755)

            home_dir = tmp_path / "home"
            home_dir.mkdir()

            env = os.environ.copy()
            env["HOME"] = str(home_dir)
            env["PATH"] = f"{fake_bin}:{env['PATH']}"

            result = subprocess.run(
                ["bash", str(script_path), "--root", str(selected_root)],
                cwd=install_dir,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )

            plist_path = home_dir / "Library" / "LaunchAgents" / "io.modelswitchboard.controller.plist"
            self.assertIn(f"installed={plist_path}", result.stdout)
            self.assertTrue(plist_path.exists())
            self.assertTrue((selected_root / "bin" / "ModelSwitchboardController").exists())

            with plist_path.open("rb") as fp:
                plist = plistlib.load(fp)

            self.assertEqual(
                plist["ProgramArguments"],
                [
                    str(selected_root / "bin" / "ModelSwitchboardController"),
                    "--root",
                    str(selected_root),
                    "--host",
                    "127.0.0.1",
                    "--port",
                    "8877",
                ],
            )
            self.assertEqual(plist["WorkingDirectory"], str(selected_root))


if __name__ == "__main__":
    unittest.main()

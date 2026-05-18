from __future__ import annotations

import importlib.util
import http.client
import io
import json
import os
import plistlib
import shutil
import signal
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import textwrap
import urllib.error
import urllib.request
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


def copy_start_model_launcher(target_dir: Path) -> Path:
    script_path = target_dir / "start-model-mac.sh"
    shutil.copy2(ROOT / "start-model-mac.sh", script_path)
    shutil.copy2(ROOT / "profile_env.py", target_dir / "profile_env.py")
    return script_path


class ModelCtlTests(unittest.TestCase):
    def test_load_env_profile_is_declarative_and_does_not_execute_shell(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            marker = Path(tmpdir) / "profile-loader-ran"
            profile = Path(tmpdir) / "safe.env"
            profile.write_text(
                textwrap.dedent(
                    f"""\
                    DISPLAY_NAME=$(touch {marker})
                    START_COMMAND='cd /tmp && ./serve --port 8123'
                    STOP_COMMAND='curl -fsS http://127.0.0.1:8123/shutdown || true'
                    SERVER_ARGS_JSON='["--n_ctx", "32768"]'
                    export SYNC_TO_DROID=0
                    INLINE_COMMENT=value # local note
                    """
                )
            )

            env = MODULE.load_env_profile(profile)

            self.assertFalse(marker.exists())
            self.assertEqual(env["DISPLAY_NAME"], f"$(touch {marker})")
            self.assertEqual(env["START_COMMAND"], "cd /tmp && ./serve --port 8123")
            self.assertEqual(env["STOP_COMMAND"], "curl -fsS http://127.0.0.1:8123/shutdown || true")
            self.assertEqual(env["SERVER_ARGS_JSON"], '["--n_ctx", "32768"]')
            self.assertEqual(env["SYNC_TO_DROID"], "0")
            self.assertEqual(env["INLINE_COMMENT"], "value")
            self.assertEqual(env["PROFILE_NAME"], "safe")

    def test_load_env_profile_rejects_shell_statements(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            profile = Path(tmpdir) / "unsafe.env"
            profile.write_text("source ~/.zshrc\n")

            with self.assertRaisesRegex(MODULE.ProfileFormatError, "profile files are not shell scripts"):
                MODULE.load_env_profile(profile)

    def test_load_json_profile_rejects_invalid_export_keys(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            profile = Path(tmpdir) / "unsafe.json"
            profile.write_text(json.dumps({"BAD-KEY": "value"}))

            with self.assertRaisesRegex(MODULE.ProfileFormatError, "invalid profile key"):
                MODULE.load_json_profile(profile)

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

    def test_profile_urls_reject_non_http_schemes(self) -> None:
        with self.assertRaisesRegex(ValueError, "BASE_URL must use http or https"):
            MODULE.base_url({"BASE_URL": "file:///etc/passwd"})
        with self.assertRaisesRegex(ValueError, "MODEL_LIST_URL must use http or https"):
            MODULE.models_url({"MODEL_LIST_URL": "ftp://127.0.0.1/models"})
        with self.assertRaisesRegex(ValueError, "HEALTHCHECK_URL must use http or https"):
            MODULE.healthcheck_url({"HEALTHCHECK_URL": "file:///tmp/health"})

    def test_fetch_openai_models_does_not_open_non_http_urls(self) -> None:
        with mock.patch.object(MODULE.urllib.request, "urlopen") as urlopen:
            self.assertEqual(MODULE.fetch_openai_models("file:///etc/passwd"), [])
        urlopen.assert_not_called()

    def test_default_healthcheck_urls_use_loopback_for_wildcard_binds(self) -> None:
        env = {
            "HOST": "0.0.0.0",
            "PORT": "8080",
        }

        self.assertEqual(MODULE.base_url(env), "http://127.0.0.1:8080/v1")
        self.assertEqual(MODULE.healthcheck_url(env), "http://127.0.0.1:8080/v1/models")

    def test_diagnose_profile_reports_invalid_profile_urls(self) -> None:
        env = {
            "PROFILE_NAME": "external",
            "DISPLAY_NAME": "External",
            "RUNTIME": "external",
            "REQUEST_MODEL": "external",
            "BASE_URL": "file:///etc/passwd",
        }

        report = MODULE.diagnose_profile("external", env)

        self.assertIn("BASE_URL must use http or https", report["errors"])
        self.assertFalse(report["ready"])

    def test_terminate_pid_signals_process_group_before_process(self) -> None:
        with (
            mock.patch.object(MODULE.os, "getpgid", return_value=4242),
            mock.patch.object(MODULE.os, "getpgrp", return_value=9999),
            mock.patch.object(MODULE.os, "killpg") as killpg,
            mock.patch.object(MODULE.os, "kill") as kill_pid,
            mock.patch.object(MODULE, "process_alive", return_value=False),
            mock.patch.object(MODULE, "process_tree_pids", return_value=[]),
        ):
            MODULE.terminate_pid(4242)

        killpg.assert_called_once_with(4242, signal.SIGTERM)
        kill_pid.assert_not_called()

    def test_signal_process_tree_signals_descendants_when_process_is_not_group_leader(self) -> None:
        with (
            mock.patch.object(MODULE.os, "getpgid", return_value=9000),
            mock.patch.object(MODULE.os, "getpgrp", return_value=9999),
            mock.patch.object(MODULE.os, "killpg", side_effect=OSError),
            mock.patch.object(MODULE, "process_tree_pids", return_value=[4242, 5151, 6161]),
            mock.patch.object(MODULE, "signal_pid") as signal_pid,
        ):
            MODULE.signal_process_tree(4242, signal.SIGTERM)

        self.assertEqual(
            signal_pid.mock_calls,
            [
                mock.call(6161, signal.SIGTERM),
                mock.call(5151, signal.SIGTERM),
                mock.call(4242, signal.SIGTERM),
            ],
        )

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
            mock.patch.object(MODULE, "terminate_profile_processes", return_value=False) as terminate_profile_processes,
            mock.patch.object(MODULE, "pid_path") as pid_path,
        ):
            pid_path.return_value.unlink.return_value = None
            MODULE.stop_profile("external")

        run_profile_shell.assert_called_once_with("echo stop", env)
        terminate_profile_processes.assert_called_once_with("external", env, None)

    def test_stop_profile_terminates_stale_listener_without_pid(self) -> None:
        env = {
            "PROFILE_NAME": "managed",
            "DISPLAY_NAME": "Managed",
            "REQUEST_MODEL": "managed",
        }
        with (
            mock.patch.object(MODULE, "require_profile", return_value=env),
            mock.patch.object(MODULE, "status_for_profile", return_value={"pid": None}),
            mock.patch.object(MODULE, "terminate_profile_processes", return_value=True) as terminate_profile_processes,
            mock.patch.object(MODULE, "wait_for_profile_stopped", return_value=True) as wait_for_profile_stopped,
            mock.patch.object(MODULE, "pid_path") as pid_path,
        ):
            pid_path.return_value.unlink.return_value = None
            MODULE.stop_profile("managed")

        terminate_profile_processes.assert_called_once_with("managed", env, None)
        wait_for_profile_stopped.assert_called_once_with("managed", env, None)

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
            mock.patch.object(MODULE, "terminate_profile_processes") as terminate_profile_processes,
            mock.patch.object(MODULE, "wait_for_profile_stopped", return_value=True),
            mock.patch.object(MODULE, "pid_path") as pid_path,
        ):
            pid_path.return_value.unlink.return_value = None
            MODULE.stop_profile("managed")

        run_profile_shell.assert_called_once_with("echo stop", env)
        terminate_profile_processes.assert_called_once_with("managed", env, 5151)

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

    def test_controller_bind_rejects_non_loopback_without_unsafe_bind(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires --unsafe-bind"):
            MODULE.validate_controller_bind("0.0.0.0")

    def test_controller_bind_rejects_unsafe_non_loopback_without_token(self) -> None:
        with self.assertRaisesRegex(ValueError, "requires a bearer auth token"):
            MODULE.validate_controller_bind("0.0.0.0", unsafe_bind=True)

    def test_controller_bind_accepts_unsafe_non_loopback_with_token(self) -> None:
        MODULE.validate_controller_bind("0.0.0.0", unsafe_bind=True, auth_token="x" * 32)

    def test_dashboard_api_requires_bearer_token_when_configured(self) -> None:
        token = "x" * 32
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        server.auth_token = token
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}/api/stop-all"
        status_payload = {
            "statuses": [],
            "benchmark": {"running": False, "pid": None, "log_path": "", "latest": None},
            "integrations": [],
            "profiles_dir": str(ROOT / "model-profiles"),
            "controller_root": str(ROOT),
        }
        try:
            request = urllib.request.Request(url, data=b"{}", method="POST", headers={"Content-Type": "application/json"})
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(request)
            self.assertEqual(ctx.exception.code, 401)

            request = urllib.request.Request(
                url,
                data=b"{}",
                method="POST",
                headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
            )
            with (
                mock.patch.object(MODULE, "stop_all") as stop_all,
                mock.patch.object(MODULE, "status_payload", return_value=status_payload),
                mock.patch.object(MODULE, "write_status_cache"),
                urllib.request.urlopen(request) as response,
            ):
                body = json.loads(response.read().decode())
            stop_all.assert_called_once_with()
            self.assertTrue(body["ok"])
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_dashboard_rejects_oversized_json_content_length(self) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        try:
            connection.putrequest("POST", "/api/stop-all")
            connection.putheader("Content-Type", "application/json")
            connection.putheader("Content-Length", str(MODULE.MAX_JSON_BODY_BYTES + 1))
            connection.endheaders()
            response = connection.getresponse()
            body = json.loads(response.read().decode())

            self.assertEqual(response.status, 413)
            self.assertEqual(body["error"], "payload_too_large")
        finally:
            connection.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_dashboard_rejects_invalid_content_length(self) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
        try:
            connection.putrequest("POST", "/api/stop-all")
            connection.putheader("Content-Type", "application/json")
            connection.putheader("Content-Length", "not-a-number")
            connection.endheaders()
            response = connection.getresponse()
            body = json.loads(response.read().decode())

            self.assertEqual(response.status, 400)
            self.assertEqual(body["error"], "invalid_content_length")
        finally:
            connection.close()
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_dashboard_rejects_missing_required_fields_as_bad_request(self) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}/api/start"
        try:
            request = urllib.request.Request(url, data=b"{}", method="POST", headers={"Content-Type": "application/json"})
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(request)
            body = json.loads(ctx.exception.read().decode())

            self.assertEqual(ctx.exception.code, 400)
            self.assertEqual(body["error"], "invalid_request")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_dashboard_maps_unknown_profiles_to_not_found(self) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}/api/start"
        try:
            request = urllib.request.Request(
                url,
                data=json.dumps({"profile": "missing-profile"}).encode(),
                method="POST",
                headers={"Content-Type": "application/json"},
            )
            with self.assertRaises(urllib.error.HTTPError) as ctx:
                urllib.request.urlopen(request)
            body = json.loads(ctx.exception.read().decode())

            self.assertEqual(ctx.exception.code, 404)
            self.assertEqual(body["error"], "profile_not_found")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_dashboard_maps_profile_conflicts_to_conflict(self) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}/api/switch"
        try:
            request = urllib.request.Request(
                url,
                data=json.dumps({"profile": "qwen"}).encode(),
                method="POST",
                headers={"Content-Type": "application/json"},
            )
            with (
                mock.patch.object(MODULE, "switch_profile", side_effect=MODULE.ProfileConflictError("raw conflict detail")),
                self.assertRaises(urllib.error.HTTPError) as ctx,
            ):
                urllib.request.urlopen(request)
            body = json.loads(ctx.exception.read().decode())

            self.assertEqual(ctx.exception.code, 409)
            self.assertEqual(body["error"], "profile_conflict")
            self.assertNotIn("raw conflict detail", json.dumps(body))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_dashboard_sanitizes_unexpected_action_errors(self) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f"http://127.0.0.1:{server.server_port}/api/stop-all"
        try:
            request = urllib.request.Request(url, data=b"{}", method="POST", headers={"Content-Type": "application/json"})
            with (
                mock.patch.object(MODULE, "stop_all", side_effect=RuntimeError("secret path /tmp/private")),
                mock.patch.object(MODULE.sys, "stderr", io.StringIO()),
                self.assertRaises(urllib.error.HTTPError) as ctx,
            ):
                urllib.request.urlopen(request)
            body = json.loads(ctx.exception.read().decode())

            self.assertEqual(ctx.exception.code, 500)
            self.assertEqual(body, {"ok": False, "error": "internal_error", "message": "internal server error"})
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_start_benchmark_creates_unique_private_run_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir) / "run"
            fake_proc = mock.Mock(pid=4242)
            with (
                mock.patch.object(MODULE, "RUN_DIR", run_dir),
                mock.patch.object(MODULE.subprocess, "Popen", return_value=fake_proc),
                mock.patch.object(MODULE, "process_alive", return_value=True),
            ):
                status = MODULE.start_benchmark(["qwen35-a3b"])

            log_path = Path(status["log_path"])
            self.assertEqual(log_path.parent, run_dir / "logs")
            self.assertRegex(log_path.name, r"^benchmark-\d{8}T\d{6}Z-[0-9a-f]{16}\.log$")
            self.assertTrue(log_path.exists())
            self.assertEqual(stat.S_IMODE(log_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(log_path.parent.stat().st_mode), 0o700)
            self.assertEqual((run_dir / "benchmark.log.path").read_text().strip(), str(log_path))

    def test_benchmark_log_creation_does_not_follow_symlinks(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            run_dir = Path(tmpdir) / "run"
            with mock.patch.object(MODULE, "RUN_DIR", run_dir):
                log_dir = MODULE.secure_benchmark_log_dir()
                link_path = log_dir / "blocked.log"
                link_path.symlink_to(Path(tmpdir) / "target.log")

                with self.assertRaises(FileExistsError):
                    MODULE.open_benchmark_log_file(link_path)

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

    def test_doctor_capabilities_advertise_agent_contract(self) -> None:
        capabilities = MODULE.doctor_capabilities()

        self.assertEqual(capabilities["tool"], "modelctl.py")
        self.assertIn("capabilities", capabilities["subcommands"])
        self.assertIn("robot-docs", capabilities["subcommands"])
        self.assertIn("0", capabilities["exit_codes"])
        self.assertIn("1", capabilities["exit_codes"])
        self.assertTrue(capabilities["offline_default"])
        self.assertTrue(any(fixer["id"] == "create-profiles-dir" for fixer in capabilities["fixers"]))

    def test_modelctl_capabilities_advertise_root_agent_contract(self) -> None:
        capabilities = MODULE.modelctl_capabilities()

        self.assertEqual(capabilities["tool"], "modelctl.py")
        self.assertEqual(capabilities["default_probe"], "./Controller/modelctl.py triage --json")
        commands = {command["name"]: command for command in capabilities["commands"]}
        self.assertIn("triage", commands)
        self.assertIn("robot-docs", commands)
        self.assertIn("doctor", commands)
        self.assertEqual(capabilities["aliases"]["--robot-triage"], ["triage", "--json"])
        self.assertIn("64", capabilities["exit_codes"])

    def test_modelctl_triage_payload_is_single_call_agent_summary(self) -> None:
        with (
            mock.patch.object(MODULE, "load_profiles", return_value={"qwen35-a3b": {}, "gemma3-mlx": {}}),
            mock.patch.object(
                MODULE,
                "doctor_health_payload",
                return_value={"healthy": True, "finding_count": 0, "auto_fixable_count": 0},
            ),
        ):
            payload = MODULE.modelctl_triage_payload()

        self.assertTrue(payload["health"]["healthy"])
        self.assertEqual(payload["profiles"]["names"], ["gemma3-mlx", "qwen35-a3b"])
        self.assertTrue(any(item["command"] == "./Controller/modelctl.py capabilities --json" for item in payload["recommendations"]))
        self.assertIn("./Controller/modelctl.py doctor --json", payload["commands"])

    def test_modelctl_accepts_agent_intent_aliases(self) -> None:
        parser = MODULE.build_parser()

        diagnose = parser.parse_args(MODULE.normalize_cli_argv(["diagnose", "--json"]))
        health = parser.parse_args(MODULE.normalize_cli_argv(["health", "--json"]))
        triage = parser.parse_args(MODULE.normalize_cli_argv(["--robot-triage"]))

        self.assertEqual(diagnose.command, "doctor")
        self.assertTrue(diagnose.json)
        self.assertEqual(health.command, "doctor")
        self.assertEqual(health.doctor_command, "health")
        self.assertEqual(triage.command, "triage")
        self.assertTrue(triage.json)

    def test_modelctl_usage_error_suggests_correct_command_and_flag(self) -> None:
        parser = MODULE.build_parser()
        stderr = io.StringIO()
        with mock.patch.object(MODULE.sys, "stderr", stderr):
            with self.assertRaises(SystemExit) as command_error:
                parser.parse_args(["stats"])
        self.assertEqual(command_error.exception.code, 64)
        self.assertIn("did you mean: `", stderr.getvalue())
        self.assertIn("status", stderr.getvalue())

        stderr = io.StringIO()
        with mock.patch.object(MODULE.sys, "stderr", stderr):
            with self.assertRaises(SystemExit) as flag_error:
                parser.parse_args(["doctor", "--jsno"])
        self.assertEqual(flag_error.exception.code, 64)
        self.assertIn("did you mean:", stderr.getvalue())
        self.assertIn("--json", stderr.getvalue())

    def test_modelctl_robot_docs_are_available_in_tool(self) -> None:
        docs = MODULE.modelctl_robot_docs()

        self.assertIn("./Controller/modelctl.py triage --json", docs)
        self.assertIn("./Controller/modelctl.py capabilities --json", docs)
        self.assertIn("Usage errors and hints print to stderr and exit 64", docs)

    def test_start_dry_run_json_plans_without_starting_profile(self) -> None:
        parser = MODULE.build_parser()
        args = parser.parse_args(["start", "qwen35-a3b", "--dry-run", "--json"])
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            }
        }
        stdout = io.StringIO()

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "start_profile") as start_profile,
            mock.patch.object(MODULE.sys, "stdout", stdout),
        ):
            code = MODULE.handle_mutating_command(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        self.assertTrue(payload["dry_run"])
        self.assertEqual(payload["status"], "planned")
        self.assertEqual(payload["plan"][0]["action"], "start-profile")
        self.assertEqual(payload["plan"][0]["profile"], "qwen35-a3b")
        start_profile.assert_not_called()

    def test_start_all_dry_run_json_allows_empty_profile_set(self) -> None:
        parser = MODULE.build_parser()
        args = parser.parse_args(["start", "all", "--dry-run", "--json"])
        stdout = io.StringIO()

        with (
            mock.patch.object(MODULE, "load_profiles", return_value={}),
            mock.patch.object(MODULE, "start_profile") as start_profile,
            mock.patch.object(MODULE.sys, "stdout", stdout),
        ):
            code = MODULE.handle_mutating_command(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["status"], "planned")
        self.assertEqual(payload["plan"][0]["action"], "start-all")
        self.assertEqual(payload["plan"][0]["details"]["profiles"], [])
        start_profile.assert_not_called()

    def test_switch_dry_run_json_plans_exclusive_activation_without_mutating(self) -> None:
        parser = MODULE.build_parser()
        args = parser.parse_args(["switch", "qwen35-a3b", "--plan", "--json"])
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            },
            "gemma3-mlx": {
                "PROFILE_NAME": "gemma3-mlx",
                "DISPLAY_NAME": "Gemma",
                "REQUEST_MODEL": "gemma-local",
                "HOST": "127.0.0.1",
                "PORT": "8081",
            },
        }
        stdout = io.StringIO()

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "status_snapshot", return_value=[{"profile": "gemma3-mlx", "running": True}]),
            mock.patch.object(MODULE, "start_profile") as start_profile,
            mock.patch.object(MODULE, "stop_profile") as stop_profile,
            mock.patch.object(MODULE, "write_active_profile") as write_active_profile,
            mock.patch.object(MODULE.sys, "stdout", stdout),
        ):
            code = MODULE.handle_mutating_command(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        self.assertEqual(payload["plan"][0]["action"], "switch-profile")
        self.assertEqual(payload["plan"][0]["details"]["stop_first"], ["gemma3-mlx"])
        steps = payload["plan"][0]["details"]["steps"]
        self.assertEqual([step["action"] for step in steps], ["stop-running-profile", "start-profile", "write-active-profile"])
        start_profile.assert_not_called()
        stop_profile.assert_not_called()
        write_active_profile.assert_not_called()

    def test_start_json_result_envelope_captures_stdout_and_status(self) -> None:
        parser = MODULE.build_parser()
        args = parser.parse_args(["start", "qwen35-a3b", "--json"])
        profiles = {
            "qwen35-a3b": {
                "PROFILE_NAME": "qwen35-a3b",
                "DISPLAY_NAME": "Qwen",
                "REQUEST_MODEL": "qwen35-local",
                "HOST": "127.0.0.1",
                "PORT": "8080",
            }
        }
        status_after = {
            "statuses": [],
            "benchmark": {"running": False, "log_path": "", "latest": None},
            "integrations": [],
            "profiles_dir": "/tmp/profiles",
            "controller_root": "/tmp/controller",
        }
        stdout = io.StringIO()

        with (
            mock.patch.object(MODULE, "load_profiles", return_value=profiles),
            mock.patch.object(MODULE, "start_profile", side_effect=lambda name: print(f"started {name}")) as start_profile,
            mock.patch.object(MODULE, "status_payload", return_value=status_after),
            mock.patch.object(MODULE.sys, "stdout", stdout),
        ):
            code = MODULE.handle_mutating_command(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        self.assertFalse(payload["dry_run"])
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["results"][0]["stdout"], ["started qwen35-a3b"])
        self.assertEqual(payload["status_after"], status_after)
        start_profile.assert_called_once_with("qwen35-a3b")

    def test_stop_all_dry_run_json_plans_benchmark_profiles_and_script(self) -> None:
        parser = MODULE.build_parser()
        args = parser.parse_args(["stop-all", "--dry-run", "--json"])
        stdout = io.StringIO()

        with (
            mock.patch.object(MODULE, "load_profiles", return_value={"qwen35-a3b": {}, "gemma3-mlx": {}}),
            mock.patch.object(MODULE, "read_pid", return_value=4242),
            mock.patch.object(MODULE, "stop_all") as stop_all,
            mock.patch.object(MODULE.sys, "stdout", stdout),
        ):
            code = MODULE.handle_mutating_command(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 0)
        steps = payload["plan"][0]["details"]["steps"]
        self.assertEqual(steps[0]["action"], "stop-benchmark")
        self.assertEqual(steps[-1]["action"], "run-stop-all-script")
        self.assertEqual(payload["plan"][0]["details"]["profiles"], ["gemma3-mlx", "qwen35-a3b"])
        stop_all.assert_not_called()

    def test_mutating_json_error_envelope_for_unknown_profile(self) -> None:
        parser = MODULE.build_parser()
        args = parser.parse_args(["start", "missing-profile", "--json"])
        stdout = io.StringIO()

        with (
            mock.patch.object(MODULE, "load_profiles", return_value={}),
            mock.patch.object(MODULE.sys, "stdout", stdout),
        ):
            code = MODULE.handle_mutating_command(args)

        payload = json.loads(stdout.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"]["code"], "user_input_error")
        self.assertIn("Unknown profile: missing-profile", payload["error"]["message"])

    def test_doctor_report_includes_structured_findings_and_next_steps(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            original_profile_dir = MODULE.PROFILE_DIR
            MODULE.PROFILE_DIR = Path(tmpdir) / "missing-profiles"
            try:
                with (
                    mock.patch.object(MODULE, "controller_status", return_value={"url": "http://127.0.0.1:8877/api/status", "reachable": True, "profiles": 0, "integrations": 0}),
                    mock.patch.object(MODULE, "launch_agent_status", return_value={"plist_path": "/tmp/io.modelswitchboard.controller.plist", "installed": True, "running": True}),
                    mock.patch.object(MODULE, "integration_status", return_value=[]),
                ):
                    report = MODULE.doctor_report()
            finally:
                MODULE.PROFILE_DIR = original_profile_dir

        self.assertFalse(report["healthy"])
        findings = {finding["id"]: finding for finding in report["findings"]}
        self.assertTrue(findings["fm-profiles-dir-missing"]["auto_fixable"])
        self.assertIn("./Controller/modelctl.py doctor --fix", findings["fm-profiles-dir-missing"]["remediation"])
        self.assertTrue(report["next_steps"])

    def test_doctor_fix_creates_missing_profiles_dir_and_undo_quarantines_it(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            original_profile_dir = MODULE.PROFILE_DIR
            original_artifact_dir = MODULE.DOCTOR_ARTIFACT_DIR
            original_runs_dir = MODULE.DOCTOR_RUNS_DIR
            original_latest_path = MODULE.DOCTOR_LATEST_PATH
            MODULE.PROFILE_DIR = Path(tmpdir) / "model-profiles"
            MODULE.DOCTOR_ARTIFACT_DIR = Path(tmpdir) / ".doctor"
            MODULE.DOCTOR_RUNS_DIR = MODULE.DOCTOR_ARTIFACT_DIR / "runs"
            MODULE.DOCTOR_LATEST_PATH = MODULE.DOCTOR_ARTIFACT_DIR / "latest"
            try:
                patches = (
                    mock.patch.object(MODULE, "controller_status", return_value={"url": "http://127.0.0.1:8877/api/status", "reachable": True, "profiles": 0, "integrations": 0}),
                    mock.patch.object(MODULE, "launch_agent_status", return_value={"plist_path": "/tmp/io.modelswitchboard.controller.plist", "installed": True, "running": True}),
                    mock.patch.object(MODULE, "integration_status", return_value=[]),
                )
                with patches[0], patches[1], patches[2]:
                    dry_run, dry_code = MODULE.doctor_fix(dry_run=True, run_id="dry-run")
                    applied, code = MODULE.doctor_fix(run_id="create-dir")
                    second, second_code = MODULE.doctor_fix(run_id="idempotent")
                    undo, undo_code = MODULE.doctor_undo("create-dir")
            finally:
                MODULE.PROFILE_DIR = original_profile_dir
                MODULE.DOCTOR_ARTIFACT_DIR = original_artifact_dir
                MODULE.DOCTOR_RUNS_DIR = original_runs_dir
                MODULE.DOCTOR_LATEST_PATH = original_latest_path

            self.assertEqual(dry_code, 1)
            self.assertEqual(dry_run["actions"][0]["status"], "planned")
            self.assertEqual(code, 0)
            self.assertEqual(applied["actions_taken"], 1)
            self.assertEqual(second_code, 0)
            self.assertEqual(second["actions_taken"], 0)
            self.assertEqual(undo_code, 0)
            self.assertTrue(undo["ok"])
            self.assertFalse((Path(tmpdir) / "model-profiles").exists())
            self.assertTrue(any(item["status"] == "quarantined" for item in undo["undone"]))

    def test_doctor_explain_returns_current_finding_details(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            original_profile_dir = MODULE.PROFILE_DIR
            MODULE.PROFILE_DIR = Path(tmpdir) / "missing-profiles"
            try:
                with (
                    mock.patch.object(MODULE, "controller_status", return_value={"url": "http://127.0.0.1:8877/api/status", "reachable": True, "profiles": 0, "integrations": 0}),
                    mock.patch.object(MODULE, "launch_agent_status", return_value={"plist_path": "/tmp/io.modelswitchboard.controller.plist", "installed": True, "running": True}),
                    mock.patch.object(MODULE, "integration_status", return_value=[]),
                ):
                    payload, code = MODULE.explain_doctor_finding("fm-profiles-dir-missing")
            finally:
                MODULE.PROFILE_DIR = original_profile_dir

        self.assertEqual(code, 0)
        self.assertEqual(payload["finding"]["id"], "fm-profiles-dir-missing")
        self.assertIn("next_steps", payload)

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
            script_path = copy_start_model_launcher(Path(tmpdir))

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmpdir,
                text=True,
                capture_output=True,
            )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Set MODEL_PROFILE or MODEL_PROFILE_PATH", result.stderr or result.stdout)

    def test_start_model_script_preserves_non_empty_chat_template_args(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script_path = copy_start_model_launcher(tmp_path)
            port = reserve_local_port()

            model_dir = tmp_path / "model"
            model_dir.mkdir()
            capture_path = tmp_path / "mlx-args.json"
            server_bin = tmp_path / "fake-mlx-server"
            server_bin.write_text(
                textwrap.dedent(
                    """\
                    #!/usr/bin/env python3
                    import argparse
                    import json
                    import os
                    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

                    parser = argparse.ArgumentParser()
                    parser.add_argument("--model", required=True)
                    parser.add_argument("--host", default="127.0.0.1")
                    parser.add_argument("--port", type=int, required=True)
                    parser.add_argument("--temp")
                    parser.add_argument("--top-p")
                    parser.add_argument("--max-tokens")
                    parser.add_argument("--prompt-cache-size")
                    parser.add_argument("--prompt-cache-bytes")
                    parser.add_argument("--prompt-concurrency")
                    parser.add_argument("--decode-concurrency")
                    parser.add_argument("--prefill-step-size")
                    parser.add_argument("--chat-template-args")
                    args = parser.parse_args()

                    with open(os.environ["ARG_CAPTURE_PATH"], "w", encoding="utf-8") as fp:
                        json.dump(vars(args), fp)

                    class Handler(BaseHTTPRequestHandler):
                        def do_GET(self):
                            if self.path != "/v1/models":
                                self.send_response(404)
                                self.end_headers()
                                return
                            payload = json.dumps({"data": [{"id": "qwen-mlx"}]}).encode()
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

            profile_path = tmp_path / "qwen-mlx.json"
            profile_path.write_text(
                json.dumps(
                    {
                        "DISPLAY_NAME": "Qwen MLX",
                        "RUNTIME": "mlx",
                        "SERVER_BIN": str(server_bin),
                        "MODEL_DIR": str(model_dir),
                        "HOST": "127.0.0.1",
                        "PORT": str(port),
                        "REQUEST_MODEL": "qwen-mlx",
                        "SERVER_MODEL_ID": "qwen-mlx",
                        "CHAT_TEMPLATE_ARGS": '{"enable_thinking":false}',
                    }
                )
            )

            env = os.environ.copy()
            env["MODEL_PROFILE"] = "qwen-mlx"
            env["MODEL_PROFILE_PATH"] = str(profile_path)
            env["ARG_CAPTURE_PATH"] = str(capture_path)

            result = subprocess.run(
                ["bash", str(script_path)],
                cwd=tmp_path,
                env=env,
                text=True,
                capture_output=True,
                check=True,
            )

            self.assertIn("runtime=mlx", result.stdout)
            captured_args = json.loads(capture_path.read_text())
            self.assertEqual(captured_args["chat_template_args"], '{"enable_thinking":false}')

            pid = int((tmp_path / "run" / "qwen-mlx.pid").read_text().strip())
            os.kill(pid, signal.SIGTERM)

    def test_start_model_script_honors_start_timeout_for_command_and_ollama_runtimes(self) -> None:
        for runtime, profile_extra, expected_checks in [
            ("command", "START_COMMAND=true\n", 4),
            ("ollama", "", 3),
        ]:
            with self.subTest(runtime=runtime), tempfile.TemporaryDirectory() as tmpdir:
                tmp_path = Path(tmpdir)
                script_path = copy_start_model_launcher(tmp_path)
                port = reserve_local_port()

                fake_bin = tmp_path / "bin"
                fake_bin.mkdir()
                curl_count_path = tmp_path / "curl-count"
                curl_bin = fake_bin / "curl"
                curl_bin.write_text(
                    textwrap.dedent(
                        """\
                        #!/bin/sh
                        printf '1\\n' >> "$CURL_COUNT_PATH"
                        exit 22
                        """
                    )
                )
                curl_bin.chmod(0o755)
                sleep_bin = fake_bin / "sleep"
                sleep_bin.write_text("#!/bin/sh\nexit 0\n")
                sleep_bin.chmod(0o755)
                server_bin = fake_bin / "ollama"
                server_bin.write_text("#!/bin/sh\nexit 0\n")
                server_bin.chmod(0o755)

                timeout_seconds = 3 if runtime == "command" else 2
                profile_path = tmp_path / f"{runtime}-timeout.env"
                profile_path.write_text(
                    textwrap.dedent(
                        f"""\
                        DISPLAY_NAME='{runtime} timeout'
                        RUNTIME={runtime}
                        SERVER_BIN={server_bin}
                        HOST=127.0.0.1
                        PORT={port}
                        REQUEST_MODEL={runtime}-timeout
                        SERVER_MODEL_ID={runtime}-timeout
                        START_TIMEOUT_SECONDS={timeout_seconds}
                        {profile_extra}"""
                    )
                )

                env = os.environ.copy()
                env["MODEL_PROFILE"] = f"{runtime}-timeout"
                env["MODEL_PROFILE_PATH"] = str(profile_path)
                env["CURL_COUNT_PATH"] = str(curl_count_path)
                env["PATH"] = f"{fake_bin}{os.pathsep}{env['PATH']}"

                result = subprocess.run(
                    ["bash", str(script_path)],
                    cwd=tmp_path,
                    env=env,
                    text=True,
                    capture_output=True,
                    timeout=10,
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(curl_count_path.read_text().splitlines()), expected_checks)

    def test_start_model_script_supports_rvllm_mlx_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            script_path = copy_start_model_launcher(tmp_path)
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
            script_path = copy_start_model_launcher(tmp_path)
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
                    parser.add_argument("--cache-memory-mb")
                    parser.add_argument("--cache-memory-percent")
                    parser.add_argument("--use-paged-cache", action="store_true")
                    parser.add_argument("--no-memory-aware-cache", action="store_true")
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
                        "CACHE_MEMORY_MB": "4096",
                        "CACHE_MEMORY_PERCENT": "0.15",
                        "USE_PAGED_CACHE": "1",
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
            script_path = copy_start_model_launcher(tmp_path)
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
            script_path = copy_start_model_launcher(tmp_path)
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
            script_path = copy_start_model_launcher(controller_dir)

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

    def test_install_controller_script_rejects_non_loopback_host_without_unsafe_bind(self) -> None:
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
            for executable in ("swiftc", "launchctl"):
                path = fake_bin / executable
                path.write_text("#!/bin/sh\nexit 0\n")
                path.chmod(0o755)

            home_dir = tmp_path / "home"
            home_dir.mkdir()

            env = os.environ.copy()
            env["HOME"] = str(home_dir)
            env["PATH"] = f"{fake_bin}:{env['PATH']}"

            result = subprocess.run(
                ["bash", str(script_path), "--root", str(selected_root), "--host", "0.0.0.0", "--no-start"],
                cwd=install_dir,
                env=env,
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("non-loopback controller host requires --unsafe-bind", result.stderr)

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

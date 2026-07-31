"""Tests for the Model Switchboard remote agent.

Stdlib-only (unittest), mirroring Scripts/tests style. Includes:
- profile parsing parity cases against ProfileRepository.swift semantics,
- HTTP conformance driven by Controller/tests/conformance/fixtures,
- a real start -> ready -> stop lifecycle against a stub OpenAI server.
"""

import http.client
import importlib.util
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENT_PATH = REPO_ROOT / "RemoteAgent" / "model_switchboard_agent.py"
FIXTURES_PATH = REPO_ROOT / "Controller" / "tests" / "conformance" / "fixtures" / "controller_api_cases.json"

_spec = importlib.util.spec_from_file_location("model_switchboard_agent", AGENT_PATH)
assert _spec is not None and _spec.loader is not None
agent = importlib.util.module_from_spec(_spec)
sys.modules["model_switchboard_agent"] = agent
_spec.loader.exec_module(agent)

CONFORMANCE_TOKEN = "conformance-token-0000000000000001"

STUB_SERVER_SOURCE = textwrap.dedent(
    """\
    import http.server
    import json
    import sys

    port = int(sys.argv[1])
    model = sys.argv[2]

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps({"data": [{"id": model}]}).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
    """
)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def write_profile(root: Path, name: str, values: dict[str, str]) -> None:
    profiles = root / "model-profiles"
    profiles.mkdir(parents=True, exist_ok=True)
    lines = [f'{key}="{value}"' for key, value in values.items()]
    (profiles / f"{name}.env").write_text("\n".join(lines) + "\n", encoding="utf-8")


class AgentHarness:
    """Runs the agent HTTP server in-process on an ephemeral port."""

    def __init__(self, root: Path, auth_token: str | None = None):
        self.configuration = agent.AgentConfiguration(
            root=root, host="127.0.0.1", port=0, auth_token=auth_token
        )
        self.configuration.profiles_directory.mkdir(parents=True, exist_ok=True)
        self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
        self.service = agent.AgentService(self.configuration)
        self.server = agent.make_server(self.service)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def close(self) -> None:
        try:
            self.service.stop_all()
        except agent.AgentError:
            pass
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def request(
        self,
        method: str,
        path: str,
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
        content_length: object = None,
    ) -> tuple[int, dict]:
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
        try:
            connection.putrequest(method, path)
            sent_headers = dict(headers or {})
            if body is not None and "Content-Type" not in sent_headers:
                sent_headers["Content-Type"] = "application/json"
            if content_length is not None:
                sent_headers["Content-Length"] = str(content_length)
            elif body is not None:
                sent_headers["Content-Length"] = str(len(body))
            for key, value in sent_headers.items():
                connection.putheader(key, value)
            connection.endheaders()
            if body is not None and content_length is None:
                connection.send(body)
            response = connection.getresponse()
            payload = json.loads(response.read() or b"{}")
            return response.status, payload
        finally:
            connection.close()

    def json_request(
        self, method: str, path: str, payload: dict | None = None, token: str | None = None
    ) -> tuple[int, dict]:
        headers = {}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        body = json.dumps(payload).encode("utf-8") if payload is not None else (b"{}" if method == "POST" else None)
        return self.request(method, path, body=body, headers=headers)


class ProfileParsingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="msw-agent-parse-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

    def parse_env(self, content: str) -> dict[str, str]:
        file = self.tmp / "profile.env"
        file.write_text(textwrap.dedent(content), encoding="utf-8")
        return agent.parse_env_profile(file)

    def test_env_parsing_matches_swift_semantics(self) -> None:
        values = self.parse_env(
            """\
            # comment line
            export REQUEST_MODEL=qwen
            PORT=8080 # inline comment
            HASH_VALUE=va#lue
            QUOTED="kept # not a comment"
            ESCAPES="a\\nb\\tc\\\\d"
            LITERAL='raw\\n'
            EMPTY=
            """
        )
        self.assertEqual(values["REQUEST_MODEL"], "qwen")
        self.assertEqual(values["PORT"], "8080")
        self.assertEqual(values["HASH_VALUE"], "va")
        self.assertEqual(values["QUOTED"], "kept # not a comment")
        self.assertEqual(values["ESCAPES"], "a\nb\tc\\d")
        self.assertEqual(values["LITERAL"], "raw\\n")
        self.assertEqual(values["EMPTY"], "")

    def test_env_parsing_rejects_invalid_keys_and_quotes(self) -> None:
        with self.assertRaises(agent.InvalidProfileError):
            self.parse_env("1BAD=value\n")
        with self.assertRaises(agent.InvalidProfileError):
            self.parse_env('KEY="unterminated\n')
        with self.assertRaises(agent.InvalidProfileError):
            self.parse_env("NOEQUALS\n")

    def test_json_parsing_matches_nsnumber_semantics(self) -> None:
        file = self.tmp / "profile.json"
        file.write_text(
            json.dumps(
                {
                    "REQUEST_MODEL": "qwen",
                    "PORT": 8080,
                    "FLAG": True,
                    "OFF": False,
                    "NOTHING": None,
                    "LIST": ["a", 1],
                    "MAP": {"k": "v"},
                }
            ),
            encoding="utf-8",
        )
        values = agent.parse_json_profile(file)
        self.assertEqual(values["PORT"], "8080")
        self.assertEqual(values["FLAG"], "1")
        self.assertEqual(values["OFF"], "0")
        self.assertEqual(values["NOTHING"], "")
        self.assertEqual(values["LIST"], '["a",1]')
        self.assertEqual(values["MAP"], '{"k":"v"}')

    def test_profile_requires_request_model_and_endpoint(self) -> None:
        with self.assertRaises(agent.InvalidProfileError):
            agent.Profile(name="x", values={"PORT": "8080"})
        with self.assertRaises(agent.InvalidProfileError):
            agent.Profile(name="x", values={"REQUEST_MODEL": "m"})
        profile = agent.Profile(name="x", values={"REQUEST_MODEL": "m", "PORT": "8080"})
        self.assertEqual(profile.base_url, "http://127.0.0.1:8080/v1")
        self.assertEqual(profile.healthcheck_url, "http://127.0.0.1:8080/v1/models")
        self.assertEqual(profile.endpoint_identity, "localhost:8080")

    def test_non_loopback_host_falls_back_for_base_url(self) -> None:
        profile = agent.Profile(
            name="x", values={"REQUEST_MODEL": "m", "PORT": "8080", "HOST": "0.0.0.0"}
        )
        self.assertEqual(profile.base_url, "http://127.0.0.1:8080/v1")
        self.assertEqual(profile.endpoint_host, "0.0.0.0")

    def test_conflicts_detects_shared_endpoints(self) -> None:
        repository = agent.ProfileRepository(self.tmp)
        profiles = {
            "a": agent.Profile(name="a", values={"REQUEST_MODEL": "m", "PORT": "8080"}),
            "b": agent.Profile(name="b", values={"REQUEST_MODEL": "m", "PORT": "8080"}),
            "c": agent.Profile(name="c", values={"REQUEST_MODEL": "m", "PORT": "8081"}),
        }
        conflicts = repository.conflicts(profiles)
        self.assertIn("a", conflicts)
        self.assertIn("b", conflicts)
        self.assertNotIn("c", conflicts)
        with self.assertRaises(agent.ProfileConflictError):
            repository.ensure_unique("a", "start", profiles)


class BuildStartCommandTests(unittest.TestCase):
    def test_start_command_takes_precedence(self) -> None:
        profile = agent.Profile(
            name="x",
            values={"REQUEST_MODEL": "m", "PORT": "1", "START_COMMAND": "run-my-server --flag"},
        )
        self.assertEqual(agent.build_start_command(profile), "run-my-server --flag")

    def test_vllm_template(self) -> None:
        profile = agent.Profile(
            name="x",
            values={
                "REQUEST_MODEL": "meta-llama/Llama-3-8B",
                "RUNTIME": "vllm",
                "PORT": "8001",
                "EXTRA_ARGS": "--max-model-len 8192",
            },
        )
        command = agent.build_start_command(profile)
        self.assertIn("vllm serve meta-llama/Llama-3-8B", command)
        self.assertIn("--port 8001", command)
        self.assertIn("--served-model-name meta-llama/Llama-3-8B", command)
        self.assertTrue(command.endswith("--max-model-len 8192"))

    def test_llamacpp_template_requires_model_file(self) -> None:
        profile = agent.Profile(
            name="x", values={"REQUEST_MODEL": "m", "RUNTIME": "llama.cpp", "PORT": "8001"}
        )
        with self.assertRaises(agent.InvalidProfileError):
            agent.build_start_command(profile)

    def test_external_runtime_is_rejected(self) -> None:
        profile = agent.Profile(
            name="x", values={"REQUEST_MODEL": "m", "RUNTIME": "ollama", "PORT": "11434"}
        )
        with self.assertRaises(agent.UnsupportedError):
            agent.build_start_command(profile)


class AgentHTTPContractTests(unittest.TestCase):
    """Fixture-driven conformance plus direct route/limit checks."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="msw-agent-http-"))
        write_profile(
            cls.tmp,
            "qwen35-a3b",
            {
                "REQUEST_MODEL": "qwen35-a3b",
                "PORT": str(free_port()),
                "START_COMMAND": "sleep 30",
                "HEALTHCHECK_MODE": "disabled",
            },
        )
        cls.plain = AgentHarness(cls.tmp)
        cls.authed = AgentHarness(cls.tmp, auth_token=CONFORMANCE_TOKEN)

    @classmethod
    def tearDownClass(cls) -> None:
        cls.plain.close()
        cls.authed.close()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_conformance_fixture_cases(self) -> None:
        cases = json.loads(FIXTURES_PATH.read_text(encoding="utf-8"))
        # macOS-controller-specific arrangements the agent intentionally does
        # not implement: Factory Droid integration sync and benchmark runs.
        skipped_arranges = {"integration_run", "benchmark_start"}
        executed = 0
        for case in cases:
            if case.get("arrange") in skipped_arranges:
                continue
            if case.get("arrange") == "profile_conflict":
                continue  # covered with a dedicated root in test_profile_conflict_maps_to_409
            with self.subTest(case["id"]):
                harness = self.authed if case.get("server_auth_token") else self.plain
                request = case["request"]
                body = None
                if "json" in request:
                    body = json.dumps(request["json"]).encode("utf-8")
                elif "raw_body" in request:
                    body = request["raw_body"].encode("utf-8")
                status, payload = harness.request(
                    request["method"],
                    request["path"],
                    body=body,
                    headers=request.get("headers"),
                    content_length=request.get("content_length"),
                )
                expected = case["expected"]
                self.assertEqual(status, expected["status"], payload)
                for key, expected_value in expected.get("json_path_equals", {}).items():
                    self.assertEqual(payload.get(key), expected_value, payload)
                type_names = {"list": list, "dict": dict, "str": str}
                for key, type_name in expected.get("json_path_types", {}).items():
                    self.assertIsInstance(payload.get(key), type_names[type_name], payload)
                executed += 1
        self.assertGreaterEqual(executed, 8)
        # Leave nothing running behind fixture-driven /api/start calls.
        self.plain.service.stop_all()

    def test_profile_conflict_maps_to_409(self) -> None:
        with tempfile.TemporaryDirectory(prefix="msw-agent-conflict-") as tmp:
            root = Path(tmp)
            port = str(free_port())
            write_profile(root, "qwen35-a3b", {"REQUEST_MODEL": "m", "PORT": port})
            write_profile(root, "other", {"REQUEST_MODEL": "m", "PORT": port})
            harness = AgentHarness(root)
            try:
                status, payload = harness.json_request(
                    "POST", "/api/switch", {"profile": "qwen35-a3b"}
                )
                self.assertEqual(status, 409)
                self.assertEqual(payload["error"], "profile_conflict")
            finally:
                harness.close()

    def test_benchmark_start_is_unsupported(self) -> None:
        status, payload = self.plain.json_request(
            "POST", "/api/benchmark/start", {"suite": "quick"}
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "unsupported_action")

    def test_integration_run_is_unsupported(self) -> None:
        status, payload = self.plain.json_request(
            "POST", "/api/integrations/run", {"integration": "droid"}
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"], "unsupported_action")

    def test_doctor_report_shape(self) -> None:
        status, payload = self.plain.json_request("GET", "/api/doctor")
        self.assertEqual(status, 200)
        self.assertTrue(payload["controller"]["reachable"])
        self.assertIsInstance(payload["launch_agent"]["plist_path"], str)
        self.assertIsInstance(payload["profiles"], list)
        self.assertEqual(payload["integrations"], [])

    def test_wrong_token_is_rejected(self) -> None:
        status, payload = self.authed.json_request(
            "POST", "/api/stop-all", {}, token="wrong-token-wrong-token"
        )
        self.assertEqual(status, 401)
        self.assertEqual(payload["error"], "unauthorized")


class AgentLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="msw-agent-lifecycle-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.stub_script = self.tmp / "stub_openai_server.py"
        self.stub_script.write_text(STUB_SERVER_SOURCE, encoding="utf-8")
        self.harness: AgentHarness | None = None

    def tearDown(self) -> None:
        if self.harness is not None:
            self.harness.close()

    def make_stub_profile(self, name: str, model: str) -> int:
        port = free_port()
        write_profile(
            self.tmp,
            name,
            {
                "REQUEST_MODEL": model,
                "SERVER_MODEL_ID": model,
                "PORT": str(port),
                "START_COMMAND": f"exec {sys.executable} {self.stub_script} {port} {model}",
            },
        )
        return port

    def wait_for(self, predicate, timeout: float = 15.0, message: str = "condition") -> dict:
        deadline = time.monotonic() + timeout
        last: dict = {}
        while time.monotonic() < deadline:
            status, payload = self.harness.json_request("GET", "/api/status")
            self.assertEqual(status, 200)
            last = payload
            if predicate(payload):
                return payload
            time.sleep(0.3)
        self.fail(f"timed out waiting for {message}; last payload: {json.dumps(last)[:2000]}")

    @staticmethod
    def profile_status(payload: dict, name: str) -> dict:
        return next(s for s in payload["statuses"] if s["profile"] == name)

    def test_start_becomes_ready_then_stop(self) -> None:
        self.make_stub_profile("stub-a", "stub-model-a")
        self.harness = AgentHarness(self.tmp)

        status, payload = self.harness.json_request("POST", "/api/start", {"profile": "stub-a"})
        self.assertEqual(status, 200, payload)
        self.assertTrue(payload["ok"])

        ready = self.wait_for(
            lambda p: self.profile_status(p, "stub-a")["ready"], message="stub-a ready"
        )
        stub = self.profile_status(ready, "stub-a")
        self.assertTrue(stub["running"])
        self.assertEqual(stub["server_ids"], ["stub-model-a"])
        self.assertIsNotNone(stub["pid"])

        status, payload = self.harness.json_request("POST", "/api/stop", {"profile": "stub-a"})
        self.assertEqual(status, 200, payload)
        stopped = self.profile_status(payload, "stub-a")
        self.assertFalse(stopped["running"])
        self.assertFalse(stopped["ready"])

    def test_switch_stops_other_profiles(self) -> None:
        self.make_stub_profile("stub-a", "stub-model-a")
        self.make_stub_profile("stub-b", "stub-model-b")
        self.harness = AgentHarness(self.tmp)

        status, _ = self.harness.json_request("POST", "/api/start", {"profile": "stub-a"})
        self.assertEqual(status, 200)
        self.wait_for(lambda p: self.profile_status(p, "stub-a")["ready"], message="stub-a ready")

        status, payload = self.harness.json_request("POST", "/api/switch", {"profile": "stub-b"})
        self.assertEqual(status, 200, payload)
        self.wait_for(lambda p: self.profile_status(p, "stub-b")["ready"], message="stub-b ready")

        final_status, payload = self.harness.json_request("GET", "/api/status")
        self.assertEqual(final_status, 200)
        self.assertFalse(self.profile_status(payload, "stub-a")["running"])
        active = (self.tmp / "run" / "active-profile").read_text(encoding="utf-8").strip()
        self.assertEqual(active, "stub-b")

    def test_stop_all_clears_everything(self) -> None:
        self.make_stub_profile("stub-a", "stub-model-a")
        self.make_stub_profile("stub-b", "stub-model-b")
        self.harness = AgentHarness(self.tmp)

        for name in ("stub-a", "stub-b"):
            status, _ = self.harness.json_request("POST", "/api/start", {"profile": name})
            self.assertEqual(status, 200)
        self.wait_for(
            lambda p: all(s["ready"] for s in p["statuses"]), message="both stubs ready"
        )

        status, payload = self.harness.json_request("POST", "/api/stop-all", {})
        self.assertEqual(status, 200, payload)
        self.assertTrue(all(not s["running"] for s in payload["statuses"]))


class InstallerSourceResolutionTests(unittest.TestCase):
    """The installer must work from a checkout AND from a pre-pushed agent
    (the Mac app deploys over SSH with no checkout on the remote host)."""

    def run_installer(self, script_dir: Path, home: Path) -> subprocess.CompletedProcess:
        installer = REPO_ROOT / "RemoteAgent" / "install-remote-agent.sh"
        staged = script_dir / "install-remote-agent.sh"
        staged.write_text(installer.read_text(encoding="utf-8"), encoding="utf-8")
        staged.chmod(0o755)
        env = {
            "HOME": str(home),
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        }
        return subprocess.run(
            ["bash", str(staged), "--port", "8899"],
            capture_output=True, text=True, timeout=60, env=env, check=False,
        )

    def test_installs_from_adjacent_agent_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            script_dir = Path(tmp) / "checkout"
            script_dir.mkdir(parents=True)
            home.mkdir(parents=True)
            shutil.copy2(AGENT_PATH, script_dir / "model_switchboard_agent.py")

            result = self.run_installer(script_dir, home)

            self.assertEqual(result.returncode, 0, result.stderr)
            launcher = home / ".local/bin/model-switchboard-agent"
            self.assertTrue(launcher.is_file())
            self.assertIn("modelswitchboard-gateway://", result.stdout)
            installed = home / ".local/share/model-switchboard-agent/model_switchboard_agent.py"
            self.assertEqual(
                installed.read_text(encoding="utf-8"),
                AGENT_PATH.read_text(encoding="utf-8"),
            )

    def test_installs_from_prepushed_agent(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp) / "home"
            script_dir = Path(tmp) / "empty"
            script_dir.mkdir(parents=True)
            install_root = home / ".local/share/model-switchboard-agent"
            install_root.mkdir(parents=True)
            shutil.copy2(AGENT_PATH, install_root / "model_switchboard_agent.py")

            result = self.run_installer(script_dir, home)

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("already present", result.stdout)
            self.assertIn("modelswitchboard-gateway://", result.stdout)
            self.assertTrue((home / ".local/bin/model-switchboard-agent").is_file())


class ConfigurationTests(unittest.TestCase):
    def test_non_loopback_bind_requires_unsafe_flag_and_token(self) -> None:
        with self.assertRaises(agent.InvalidConfigurationError):
            agent.AgentConfiguration(root=Path("/tmp/x"), host="0.0.0.0")
        with self.assertRaises(agent.InvalidConfigurationError):
            agent.AgentConfiguration(root=Path("/tmp/x"), host="0.0.0.0", unsafe_bind=True)
        configuration = agent.AgentConfiguration(
            root=Path("/tmp/x"),
            host="0.0.0.0",
            unsafe_bind=True,
            auth_token=CONFORMANCE_TOKEN,
        )
        self.assertEqual(configuration.auth_token, CONFORMANCE_TOKEN)

    def test_short_tokens_are_rejected(self) -> None:
        with self.assertRaises(agent.InvalidConfigurationError):
            agent.AgentConfiguration(root=Path("/tmp/x"), auth_token="short")

    def test_cli_version_smoke(self) -> None:
        result = subprocess.run(
            [sys.executable, str(AGENT_PATH), "--version"],
            capture_output=True, text=True, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("model-switchboard-agent", result.stdout)

    def test_link_code_encodes_pairing_details(self) -> None:
        info = agent.build_link_code(9001)
        self.assertTrue(info["link"].startswith("modelswitchboard-gateway://"))
        self.assertIn("agent_port=9001", info["link"])
        self.assertIn(f"@{info['host']}", info["link"])
        self.assertTrue(info["user"])
        self.assertTrue(info["name"])

    def test_cli_link_json_smoke(self) -> None:
        result = subprocess.run(
            [sys.executable, str(AGENT_PATH), "--json", "--port", "9001", "link"],
            capture_output=True, text=True, timeout=30, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["agent_port"], "9001")
        self.assertTrue(payload["link"].startswith("modelswitchboard-gateway://"))


if __name__ == "__main__":
    unittest.main()

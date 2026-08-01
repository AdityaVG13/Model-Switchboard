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
import unittest.mock
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


def write_profile(root: Path, name: str, values: dict[str, str], profiles_dir: Path | None = None) -> None:
    profiles = profiles_dir or (root / "model-profiles")
    profiles.mkdir(parents=True, exist_ok=True)
    lines = [f'{key}="{value}"' for key, value in values.items()]
    (profiles / f"{name}.env").write_text("\n".join(lines) + "\n", encoding="utf-8")


class AgentHarness:
    """Runs the agent HTTP server in-process on an ephemeral port."""

    def __init__(self, root: Path, auth_token: str | None = None, profiles_dir: Path | None = None):
        profiles = profiles_dir or (root / "model-profiles")
        profiles.mkdir(parents=True, exist_ok=True)
        self.configuration = agent.AgentConfiguration(
            root=root,
            host="127.0.0.1",
            port=0,
            auth_token=auth_token,
            profiles_dir=profiles,
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
            self.service.stop_all(force=True)
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
            self.assertIn("Profiles folder:", result.stdout)
            profiles = home / "model-profiles"
            self.assertTrue(profiles.is_dir())
            config = json.loads(
                (home / ".local/share/model-switchboard-agent/config.json").read_text(encoding="utf-8")
            )
            self.assertEqual(config["profiles_dir"], str(profiles))
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


class TailscaleTests(unittest.TestCase):
    def test_cgnat_range_detection(self) -> None:
        self.assertTrue(agent.is_tailscale_ip("100.64.0.1"))
        self.assertTrue(agent.is_tailscale_ip("100.101.102.103"))
        self.assertTrue(agent.is_tailscale_ip("100.127.255.254"))
        self.assertFalse(agent.is_tailscale_ip("100.128.0.1"))
        self.assertFalse(agent.is_tailscale_ip("100.63.0.1"))
        self.assertFalse(agent.is_tailscale_ip("10.0.0.1"))
        self.assertFalse(agent.is_tailscale_ip("not-an-ip"))

    def test_tailscale_bind_requires_token_by_default(self) -> None:
        with self.assertRaises(agent.InvalidConfigurationError):
            agent.AgentConfiguration(
                root=Path("/tmp/x"), host="100.101.102.103", tailscale_bind=True
            )

    def test_tailscale_bind_allows_cgnat_with_token(self) -> None:
        configuration = agent.AgentConfiguration(
            root=Path("/tmp/x"),
            host="100.101.102.103",
            tailscale_bind=True,
            auth_token=CONFORMANCE_TOKEN,
        )
        self.assertEqual(configuration.host, "100.101.102.103")
        self.assertEqual(configuration.auth_token, CONFORMANCE_TOKEN)

    def test_tailscale_bind_allows_unauthenticated_opt_out(self) -> None:
        configuration = agent.AgentConfiguration(
            root=Path("/tmp/x"),
            host="100.101.102.103",
            tailscale_bind=True,
            allow_unauthenticated=True,
        )
        self.assertIsNone(configuration.auth_token)

    def test_tailscale_bind_rejects_non_cgnat_host(self) -> None:
        with self.assertRaises(agent.InvalidConfigurationError):
            agent.AgentConfiguration(root=Path("/tmp/x"), host="0.0.0.0", tailscale_bind=True)

    def test_status_prefers_cli_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "tailscale"
            fake.write_text(
                "#!/bin/bash\n"
                "if [ \"$1\" = \"status\" ]; then\n"
                "  echo '{\"Self\": {\"TailscaleIPs\": [\"100.101.102.103\"], "
                "\"DNSName\": \"spark.tail1234.ts.net.\"}}'\n"
                "fi\n",
                encoding="utf-8",
            )
            fake.chmod(0o755)
            original = os.environ.get("PATH", "")
            os.environ["PATH"] = f"{tmp}:{original}"
            try:
                ipv4, dns_name = agent.tailscale_status()
            finally:
                os.environ["PATH"] = original
            self.assertEqual(ipv4, "100.101.102.103")
            self.assertEqual(dns_name, "spark.tail1234.ts.net")

    def test_direct_link_code_uses_direct_mode(self) -> None:
        info = agent.build_link_code(8877, direct_host="spark.tail1234.ts.net")
        self.assertEqual(info["mode"], "direct")
        self.assertIn("mode=direct", info["link"])
        self.assertIn("spark.tail1234.ts.net", info["link"])
        self.assertNotIn("@", info["link"].split("://", 1)[1].split("?")[0])



class ProcessLifecycleTests(unittest.TestCase):
    def test_zombie_pid_is_not_running(self) -> None:
        """Defunct children must not count as running (spark handoff regression)."""
        child = subprocess.Popen(["/bin/bash", "-c", "exit 0"])
        deadline = time.time() + 2.0
        while time.time() < deadline and child.poll() is None:
            time.sleep(0.05)
        self.assertIsNotNone(child.poll())
        # Unreaped exited child is a zombie of this process; still not "alive".
        self.assertFalse(agent.process_is_alive(child.pid))
        state = agent.process_lifecycle_state(child.pid)
        self.assertIn(state, ("dead", "zombie"))
        try:
            child.wait(timeout=1)
        except Exception:
            pass

    def test_force_stop_and_status_state(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            port = free_port()
            write_profile(
                root,
                "stub",
                {
                    "REQUEST_MODEL": "stub-model",
                    "SERVER_MODEL_ID": "stub-model",
                    "PORT": str(port),
                    "START_COMMAND": (
                        f"exec {sys.executable} -c "
                        f"\"import http.server,socketserver; "
                        f"socketserver.TCPServer(('127.0.0.1',{port}),"
                        f"http.server.BaseHTTPRequestHandler).serve_forever()\""
                    ),
                    "HEALTHCHECK_MODE": "disabled",
                },
            )
            harness = AgentHarness(root)
            try:
                harness.service.start("stub")
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    st = harness.service.status(harness.service.profiles.profile("stub"))
                    if st["running"]:
                        break
                    time.sleep(0.1)
                self.assertTrue(st["running"])
                self.assertEqual(st["state"], "running")

                status, payload = harness.json_request(
                    "POST", "/api/stop", {"profile": "stub", "force": True}
                )
                self.assertEqual(status, 200, payload)
                stopped = next(s for s in payload["statuses"] if s["profile"] == "stub")
                self.assertFalse(stopped["running"])
                self.assertEqual(stopped["state"], "dead")
            finally:
                try:
                    harness.service.stop_all(force=True)
                except agent.AgentError:
                    pass
                harness.close()

    def test_watchdog_does_not_restore_from_disk_alone(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "model-profiles"
            profiles.mkdir()
            (root / "run").mkdir()
            (root / "run" / "active-profile").write_text("ghost\n", encoding="utf-8")
            write_profile(
                root,
                "ghost",
                {
                    "REQUEST_MODEL": "g",
                    "PORT": "19999",
                    "RUNTIME": "command",
                    "START_COMMAND": "true",
                    "HEALTHCHECK_MODE": "disabled",
                },
            )
            service = agent.AgentService(
                agent.AgentConfiguration(root=root, profiles_dir=profiles)
            )
            service.watchdog_tick()
            self.assertEqual(service._supervised, set())
            status = service.status(service.profiles.profile("ghost"))
            self.assertFalse(status["running"])


class ProcessAliveZombieTests(unittest.TestCase):
    """process_is_alive / process_is_zombie: /proc state first, then ps/kill."""

    def test_rejects_missing_pid(self) -> None:
        self.assertFalse(agent.process_is_alive(None))
        self.assertFalse(agent.process_is_alive(0))
        self.assertFalse(agent.process_is_alive(-1))
        self.assertFalse(agent.process_is_zombie(None))
        self.assertFalse(agent.process_is_zombie(0))

    def test_self_is_alive_not_zombie(self) -> None:
        pid = os.getpid()
        self.assertTrue(agent.process_is_alive(pid))
        self.assertFalse(agent.process_is_zombie(pid))

    def test_proc_state_live_skips_ps_and_kill(self) -> None:
        """Linux path: non-Z /proc state is authoritative; no ps or kill."""
        fake_stat = "4242 (python) S 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 0 0 0\n"
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            # /proc/<pid>/stat content for process_stat_state
            mock_path.return_value.read_text.return_value = fake_stat
            with unittest.mock.patch.object(agent, "reap_child", return_value=False):
                with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                    with unittest.mock.patch.object(agent.os, "kill") as kill_mock:
                        alive = agent.process_is_alive(4242)
                        zombie = agent.process_is_zombie(4242)
        self.assertTrue(alive)
        self.assertFalse(zombie)
        run_mock.assert_not_called()
        kill_mock.assert_not_called()

    def test_proc_state_zombie_skips_ps_and_kill(self) -> None:
        fake_stat = "99 (defunct) Z 1 1 1 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 0 0 0\n"
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.return_value = fake_stat
            with unittest.mock.patch.object(agent, "reap_child", return_value=False):
                with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                    with unittest.mock.patch.object(agent.os, "kill") as kill_mock:
                        alive = agent.process_is_alive(99)
                        zombie = agent.process_is_zombie(99)
        self.assertFalse(alive)
        self.assertTrue(zombie)
        run_mock.assert_not_called()
        kill_mock.assert_not_called()

    def test_proc_table_missing_pid_is_dead_without_ps(self) -> None:
        """When /proc is the process table and pid has no stat, skip ps/kill."""
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            # process_stat_state → OSError; _proc_stat_table_available → True
            def path_side_effect(arg):  # type: ignore[no-untyped-def]
                m = unittest.mock.MagicMock()
                path_str = str(arg)
                if path_str == "/proc/self/stat":
                    m.is_file.return_value = True
                else:
                    m.read_text.side_effect = OSError("no such process")
                return m

            mock_path.side_effect = path_side_effect
            with unittest.mock.patch.object(agent, "reap_child", return_value=False):
                with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                    with unittest.mock.patch.object(agent.os, "kill") as kill_mock:
                        self.assertFalse(agent.process_is_alive(404))
                        self.assertFalse(agent.process_is_zombie(404))
        run_mock.assert_not_called()
        kill_mock.assert_not_called()

    def test_no_proc_falls_back_to_ps_state(self) -> None:
        """macOS-style: no /proc table → ps state decides alive/zombie."""
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.side_effect = OSError("no /proc")
            mock_path.return_value.is_file.return_value = False
            with unittest.mock.patch.object(agent, "reap_child", return_value=False):
                with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                    run_mock.return_value = unittest.mock.Mock(stdout="S\n")
                    with unittest.mock.patch.object(agent.os, "kill") as kill_mock:
                        self.assertTrue(agent.process_is_alive(77))
                        self.assertFalse(agent.process_is_zombie(77))
        run_mock.assert_called()
        args = run_mock.call_args[0][0]
        self.assertEqual(args[:3], ["ps", "-o", "state="])
        kill_mock.assert_not_called()

    def test_no_proc_ps_zombie(self) -> None:
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.side_effect = OSError("no /proc")
            mock_path.return_value.is_file.return_value = False
            with unittest.mock.patch.object(agent, "reap_child", return_value=False):
                with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                    run_mock.return_value = unittest.mock.Mock(stdout="Z\n")
                    with unittest.mock.patch.object(agent.os, "kill") as kill_mock:
                        self.assertFalse(agent.process_is_alive(77))
                        self.assertTrue(agent.process_is_zombie(77))
        kill_mock.assert_not_called()


class ProcessCommandTests(unittest.TestCase):
    """process_command: Linux /proc cmdline first, ps fallback elsewhere."""

    def test_process_command_rejects_missing_pid(self) -> None:
        self.assertIsNone(agent.process_command(None))
        self.assertIsNone(agent.process_command(0))

    def test_process_command_self_nonempty(self) -> None:
        cmd = agent.process_command(os.getpid())
        self.assertIsNotNone(cmd)
        assert cmd is not None
        self.assertTrue(cmd.strip())
        # Content varies (ps vs /proc); only require a usable command string.
        lowered = cmd.lower()
        self.assertTrue(
            "python" in lowered
            or "unittest" in lowered
            or Path(sys.executable).name.lower() in lowered
            or sys.executable in cmd,
            msg=f"unexpected self cmdline: {cmd!r}",
        )

    def test_process_command_prefers_proc_cmdline_without_ps(self) -> None:
        """On Linux path, NUL-separated /proc cmdline is authoritative; no ps."""
        fake = b"python\x00-m\x00uvicorn\x00app:main\x00"
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_bytes.return_value = fake
            with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                cmd = agent.process_command(4242)
        mock_path.assert_called_with("/proc/4242/cmdline")
        self.assertEqual(cmd, "python -m uvicorn app:main")
        run_mock.assert_not_called()

    def test_process_command_falls_back_to_ps_when_proc_missing(self) -> None:
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_bytes.side_effect = OSError("no /proc")
            with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                run_mock.return_value = unittest.mock.Mock(
                    stdout="  /usr/bin/python3 -c pass\n"
                )
                cmd = agent.process_command(99)
        self.assertEqual(cmd, "/usr/bin/python3 -c pass")
        run_mock.assert_called_once()
        args = run_mock.call_args[0][0]
        self.assertEqual(args[:3], ["ps", "-o", "command="])


class ProcessRssMbTests(unittest.TestCase):
    """process_rss_mb: Linux /proc status VmRSS first, ps fallback elsewhere."""

    def test_process_rss_mb_rejects_missing_pid(self) -> None:
        self.assertIsNone(agent.process_rss_mb(None))
        self.assertIsNone(agent.process_rss_mb(0))

    def test_process_rss_mb_self_nonnegative(self) -> None:
        rss = agent.process_rss_mb(os.getpid())
        self.assertIsNotNone(rss)
        assert rss is not None
        self.assertIsInstance(rss, float)
        self.assertGreaterEqual(rss, 0.0)

    def test_process_rss_mb_prefers_proc_status_without_ps(self) -> None:
        """On Linux path, VmRSS from /proc is authoritative; no ps."""
        fake = "Name:\tpython\nVmRSS:\t  2048 kB\nVmSize:\t  4096 kB\n"
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.return_value = fake
            with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                rss = agent.process_rss_mb(4242)
        mock_path.assert_called_with("/proc/4242/status")
        # 2048 kB / 1024 = 2.0 MB; same one-decimal rounding as ps path.
        self.assertEqual(rss, 2.0)
        run_mock.assert_not_called()

    def test_process_rss_mb_rounds_like_ps_path(self) -> None:
        # 1536 kB -> 1.5 MB; 100 kB -> 0.1 MB after one-decimal rounding.
        fake = "VmRSS:\t1536 kB\n"
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.return_value = fake
            self.assertEqual(agent.process_rss_mb(7), 1.5)
        fake = "VmRSS:\t100 kB\n"
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.return_value = fake
            self.assertEqual(agent.process_rss_mb(7), 0.1)

    def test_process_rss_mb_falls_back_to_ps_when_proc_missing(self) -> None:
        with unittest.mock.patch.object(agent, "Path") as mock_path:
            mock_path.return_value.read_text.side_effect = OSError("no /proc")
            with unittest.mock.patch.object(agent.subprocess, "run") as run_mock:
                run_mock.return_value = unittest.mock.Mock(stdout="  3072\n")
                rss = agent.process_rss_mb(99)
        self.assertEqual(rss, 3.0)
        run_mock.assert_called_once()
        args = run_mock.call_args[0][0]
        self.assertEqual(args[:3], ["ps", "-o", "rss="])


class ListListeningTcpTests(unittest.TestCase):
    """list_listening_tcp: one ss/lsof parse; process_command once per unique pid."""

    def setUp(self) -> None:
        agent.clear_listening_tcp_cache()

    def tearDown(self) -> None:
        agent.clear_listening_tcp_cache()

    def test_ss_path_resolves_cmdline_once_per_unique_pid(self) -> None:
        # Same PID on two ports (and a third line without pid): one process_command.
        ss_out = "\n".join(
            [
                "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:((\"py\",pid=4242,fd=3))",
                "LISTEN 0 128 127.0.0.1:8081 0.0.0.0:* users:((\"py\",pid=4242,fd=4))",
                "LISTEN 0 128 0.0.0.0:22 0.0.0.0:*",
                "",
            ]
        )

        def run_side_effect(cmd, *args, **kwargs):  # type: ignore[no-untyped-def]
            if cmd and cmd[0] == "ss":
                return unittest.mock.Mock(stdout=ss_out, returncode=0)
            return unittest.mock.Mock(stdout="", returncode=1)

        with unittest.mock.patch.object(
            agent.subprocess, "run", side_effect=run_side_effect
        ) as run_mock:
            with unittest.mock.patch.object(
                agent, "process_command", return_value="python -m server"
            ) as cmd_mock:
                rows = agent.list_listening_tcp()

        # ss once; lsof must not run when ss yields listeners.
        ss_calls = [c for c in run_mock.call_args_list if c[0][0][0] == "ss"]
        lsof_calls = [c for c in run_mock.call_args_list if c[0][0][0] == "lsof"]
        self.assertEqual(len(ss_calls), 1)
        self.assertEqual(lsof_calls, [])
        cmd_mock.assert_called_once_with(4242)

        by_port = {row["port"]: row for row in rows}
        self.assertEqual(set(by_port), {8080, 8081, 22})
        self.assertEqual(by_port[8080]["pid"], 4242)
        self.assertEqual(by_port[8080]["command"], "python -m server")
        self.assertEqual(by_port[8081]["pid"], 4242)
        self.assertEqual(by_port[8081]["command"], "python -m server")
        self.assertIsNone(by_port[22]["pid"])
        self.assertIsNone(by_port[22]["command"])
        # Schema keys unchanged.
        for row in rows:
            self.assertEqual(set(row), {"port", "pid", "command", "bind"})

    def test_lsof_fallback_when_ss_empty_dedupes_pid(self) -> None:
        lsof_out = "\n".join(
            [
                "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME",
                "python  99 me 3u IPv4 1 0t0 TCP 127.0.0.1:9000 (LISTEN)",
                "python  99 me 4u IPv6 2 0t0 TCP [::1]:9001 (LISTEN)",
                "",
            ]
        )

        def run_side_effect(cmd, *args, **kwargs):  # type: ignore[no-untyped-def]
            if cmd and cmd[0] == "ss":
                return unittest.mock.Mock(stdout="", returncode=0)
            if cmd and cmd[0] == "lsof":
                return unittest.mock.Mock(stdout=lsof_out, returncode=0)
            return unittest.mock.Mock(stdout="", returncode=1)

        with unittest.mock.patch.object(
            agent.subprocess, "run", side_effect=run_side_effect
        ):
            with unittest.mock.patch.object(
                agent, "process_command", return_value="/usr/bin/python3 app"
            ) as cmd_mock:
                rows = agent.list_listening_tcp()

        cmd_mock.assert_called_once_with(99)
        by_port = {row["port"]: row for row in rows}
        self.assertEqual(set(by_port), {9000, 9001})
        self.assertEqual(by_port[9000]["command"], "/usr/bin/python3 app")
        self.assertEqual(by_port[9001]["command"], "/usr/bin/python3 app")

    def test_skips_process_command_for_skip_listen_ports(self) -> None:
        # ssh (22) is in SKIP_LISTEN_PORTS: still record pid/port/bind, no cmdline.
        ss_out = "\n".join(
            [
                "LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:((\"sshd\",pid=1,fd=3))",
                "LISTEN 0 128 127.0.0.1:53 0.0.0.0:* users:((\"dns\",pid=2,fd=4))",
                "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* users:((\"vllm\",pid=4242,fd=5))",
                "",
            ]
        )

        def run_side_effect(cmd, *args, **kwargs):  # type: ignore[no-untyped-def]
            if cmd and cmd[0] == "ss":
                return unittest.mock.Mock(stdout=ss_out, returncode=0)
            return unittest.mock.Mock(stdout="", returncode=1)

        with unittest.mock.patch.object(
            agent.subprocess, "run", side_effect=run_side_effect
        ):
            with unittest.mock.patch.object(
                agent, "process_command", return_value="python -m vllm.entrypoints"
            ) as cmd_mock:
                rows = agent.list_listening_tcp()

        cmd_mock.assert_called_once_with(4242)
        by_port = {row["port"]: row for row in rows}
        self.assertEqual(set(by_port), {22, 53, 8080})
        self.assertEqual(by_port[22]["pid"], 1)
        self.assertIsNone(by_port[22]["command"])
        self.assertEqual(by_port[53]["pid"], 2)
        self.assertIsNone(by_port[53]["command"])
        self.assertEqual(by_port[8080]["pid"], 4242)
        self.assertEqual(by_port[8080]["command"], "python -m vllm.entrypoints")

    def test_skips_process_command_for_agent_self_port(self) -> None:
        self_pid = os.getpid()
        other_pid = self_pid + 99999
        ss_out = "\n".join(
            [
                (
                    f"LISTEN 0 128 127.0.0.1:{agent.DEFAULT_PORT} 0.0.0.0:* "
                    f"users:((\"agent\",pid={self_pid},fd=3))"
                ),
                (
                    f"LISTEN 0 128 127.0.0.1:9000 0.0.0.0:* "
                    f"users:((\"srv\",pid={other_pid},fd=4))"
                ),
                "",
            ]
        )

        def run_side_effect(cmd, *args, **kwargs):  # type: ignore[no-untyped-def]
            if cmd and cmd[0] == "ss":
                return unittest.mock.Mock(stdout=ss_out, returncode=0)
            return unittest.mock.Mock(stdout="", returncode=1)

        with unittest.mock.patch.object(
            agent.subprocess, "run", side_effect=run_side_effect
        ):
            with unittest.mock.patch.object(
                agent, "process_command", return_value="python -m server"
            ) as cmd_mock:
                rows = agent.list_listening_tcp()

        cmd_mock.assert_called_once_with(other_pid)
        by_port = {row["port"]: row for row in rows}
        self.assertEqual(by_port[agent.DEFAULT_PORT]["pid"], self_pid)
        self.assertIsNone(by_port[agent.DEFAULT_PORT]["command"])
        self.assertEqual(by_port[9000]["command"], "python -m server")

    def test_discover_live_skips_agent_self_by_pid_without_command(self) -> None:
        self_pid = os.getpid()
        listeners = [
            {
                "port": agent.DEFAULT_PORT,
                "pid": self_pid,
                "command": None,
                "bind": "127.0.0.1",
            },
            {
                "port": 9000,
                "pid": 99,
                "command": "python -m vllm.entrypoints.openai.api_server",
                "bind": "127.0.0.1",
            },
        ]
        with unittest.mock.patch.object(
            agent, "port_is_listening", return_value=False
        ):
            found = agent.discover_live_model_endpoints(listeners=listeners)
        ports = {item["port"] for item in found}
        self.assertNotIn(agent.DEFAULT_PORT, ports)
        self.assertIn(9000, ports)

    def test_second_call_within_ttl_skips_ss(self) -> None:
        """Back-to-back polls reuse the short-TTL inventory (no second ss)."""
        ss_out = (
            "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* "
            'users:(("py",pid=4242,fd=3))\n'
        )
        clock = {"t": 1000.0}

        def run_side_effect(cmd, *args, **kwargs):  # type: ignore[no-untyped-def]
            if cmd and cmd[0] == "ss":
                return unittest.mock.Mock(stdout=ss_out, returncode=0)
            return unittest.mock.Mock(stdout="", returncode=1)

        with unittest.mock.patch.object(
            agent.time, "monotonic", side_effect=lambda: clock["t"]
        ):
            with unittest.mock.patch.object(
                agent.subprocess, "run", side_effect=run_side_effect
            ) as run_mock:
                with unittest.mock.patch.object(
                    agent, "process_command", return_value="python -m server"
                ):
                    first = agent.list_listening_tcp()
                    # Still well inside LISTENING_TCP_CACHE_TTL_SECONDS (75ms).
                    clock["t"] = 1000.0 + 0.05
                    second = agent.list_listening_tcp()

        ss_calls = [c for c in run_mock.call_args_list if c[0][0][0] == "ss"]
        self.assertEqual(len(ss_calls), 1)
        self.assertEqual(first, second)
        self.assertIs(first, second)
        self.assertEqual(first[0]["port"], 8080)

    def test_call_after_ttl_reinvokes_ss(self) -> None:
        """Past TTL the inventory is refreshed (ss runs again)."""
        ss_out = (
            "LISTEN 0 128 127.0.0.1:8080 0.0.0.0:* "
            'users:(("py",pid=4242,fd=3))\n'
        )
        clock = {"t": 1000.0}

        def run_side_effect(cmd, *args, **kwargs):  # type: ignore[no-untyped-def]
            if cmd and cmd[0] == "ss":
                return unittest.mock.Mock(stdout=ss_out, returncode=0)
            return unittest.mock.Mock(stdout="", returncode=1)

        with unittest.mock.patch.object(
            agent.time, "monotonic", side_effect=lambda: clock["t"]
        ):
            with unittest.mock.patch.object(
                agent.subprocess, "run", side_effect=run_side_effect
            ) as run_mock:
                with unittest.mock.patch.object(
                    agent, "process_command", return_value="python -m server"
                ):
                    agent.list_listening_tcp()
                    clock["t"] = 1000.0 + agent.LISTENING_TCP_CACHE_TTL_SECONDS + 0.001
                    agent.list_listening_tcp()

        ss_calls = [c for c in run_mock.call_args_list if c[0][0][0] == "ss"]
        self.assertEqual(len(ss_calls), 2)


class ListeningInventoryOnceTests(unittest.TestCase):
    """status/ports/scan share one list_listening_tcp per request path."""

    def _service(self, root: Path) -> agent.AgentService:
        profiles = root / "model-profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        configuration = agent.AgentConfiguration(
            root=root,
            host="127.0.0.1",
            port=18880,
            profiles_dir=profiles,
        )
        return agent.AgentService(configuration)

    def test_scan_with_listeners_does_not_reinventory(self) -> None:
        fake = [{"port": 8080, "pid": 1, "command": "/tmp/x", "bind": "127.0.0.1"}]
        with unittest.mock.patch.object(
            agent, "list_listening_tcp", side_effect=AssertionError("should not inventory")
        ) as inv:
            found = agent.scan_port_claim_directories(
                roots=[],
                listeners=fake,
                max_depth=1,
            )
        inv.assert_not_called()
        self.assertIsInstance(found, list)

    def test_status_payload_inventories_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            fake = [
                {
                    "port": 8080,
                    "pid": 42,
                    "command": "python -m vllm.entrypoints.openai.api_server",
                    "bind": "127.0.0.1",
                }
            ]
            with unittest.mock.patch.object(
                agent, "list_listening_tcp", return_value=fake
            ) as inv:
                with unittest.mock.patch.object(
                    agent, "discover_live_model_endpoints", return_value=[]
                ) as disc:
                    with unittest.mock.patch.object(
                        agent, "scan_port_claim_directories", return_value=[]
                    ) as scan:
                        service.status_payload()
            inv.assert_called_once_with()
            # Downstream helpers must receive the shared snapshot.
            self.assertEqual(scan.call_args.kwargs.get("listeners"), fake)
            self.assertEqual(disc.call_args.kwargs.get("listeners"), fake)

    def test_ports_payload_inventories_once(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            fake = [
                {
                    "port": 9000,
                    "pid": 7,
                    "command": "llama-server --port 9000",
                    "bind": "127.0.0.1",
                }
            ]
            with unittest.mock.patch.object(
                agent, "list_listening_tcp", return_value=fake
            ) as inv:
                with unittest.mock.patch.object(
                    agent, "discover_live_model_endpoints", return_value=[]
                ) as disc:
                    with unittest.mock.patch.object(
                        agent, "scan_port_claim_directories", return_value=[]
                    ) as scan:
                        service.ports_payload()
            inv.assert_called_once_with()
            self.assertEqual(scan.call_args.kwargs.get("listeners"), fake)
            self.assertEqual(disc.call_args.kwargs.get("listeners"), fake)

    def test_resolve_profile_shares_listeners_across_scan_and_discover(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            fake = [
                {
                    "port": 9666,
                    "pid": 3,
                    "command": "python -m vllm.entrypoints.openai.api_server --port 9666",
                    "bind": "127.0.0.1",
                }
            ]
            live_row = {
                "port": 9666,
                "pid": 3,
                "command": fake[0]["command"],
                "ready": True,
                "request_model": "demo",
                "display_name": "demo",
                "runtime": "vllm",
            }
            with unittest.mock.patch.object(
                agent, "list_listening_tcp", return_value=fake
            ) as inv:
                with unittest.mock.patch.object(
                    agent, "scan_port_claim_directories", return_value=[]
                ) as scan:
                    with unittest.mock.patch.object(
                        agent,
                        "discover_live_model_endpoints",
                        return_value=[live_row],
                    ) as disc:
                        profile = service.resolve_profile("discovered-9666")
            inv.assert_called_once_with()
            self.assertEqual(scan.call_args.kwargs.get("listeners"), fake)
            self.assertEqual(disc.call_args.kwargs.get("listeners"), fake)
            self.assertEqual(profile.endpoint_port, "9666")



class InventoryPortLookupTests(unittest.TestCase):
    """status_payload uses shared inventory instead of N× port_is_listening/lsof."""

    def test_port_listening_from_inventory(self) -> None:
        rows = [
            {"port": 8080, "pid": 11, "command": "x", "bind": "127.0.0.1"},
            {"port": 9000, "pid": None, "command": None, "bind": "*"},
        ]
        self.assertTrue(agent.port_listening_from_inventory(8080, rows))
        self.assertTrue(agent.port_listening_from_inventory("9000", rows))
        self.assertFalse(agent.port_listening_from_inventory(1, rows))
        self.assertFalse(agent.port_listening_from_inventory("bad", rows))

    def test_listener_pid_from_inventory(self) -> None:
        rows = [
            {"port": 8080, "pid": 42, "command": "x", "bind": "127.0.0.1"},
            {"port": 9000, "pid": None, "command": None, "bind": "*"},
        ]
        self.assertEqual(agent.listener_pid_from_inventory("8080", rows), 42)
        self.assertIsNone(agent.listener_pid_from_inventory(9000, rows))
        self.assertIsNone(agent.listener_pid_from_inventory(1, rows))

    def _service(self, root: Path) -> agent.AgentService:
        profiles = root / "model-profiles"
        profiles.mkdir(parents=True, exist_ok=True)
        (profiles / "demo.env").write_text(
            "REQUEST_MODEL=demo\nPORT=8080\nHOST=127.0.0.1\n"
            "HEALTHCHECK_MODE=disabled\n",
            encoding="utf-8",
        )
        configuration = agent.AgentConfiguration(
            root=root,
            host="127.0.0.1",
            port=18880,
            profiles_dir=profiles,
        )
        return agent.AgentService(configuration)

    def test_status_payload_skips_live_port_probes_when_inventory_known(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            fake = [
                {
                    "port": 8080,
                    "pid": 4242,
                    "command": "python -m vllm.entrypoints.openai.api_server --port 8080",
                    "bind": "127.0.0.1",
                }
            ]
            with unittest.mock.patch.object(
                agent, "list_listening_tcp", return_value=fake
            ):
                with unittest.mock.patch.object(
                    agent, "discover_live_model_endpoints", return_value=[]
                ):
                    with unittest.mock.patch.object(
                        agent, "scan_port_claim_directories", return_value=[]
                    ):
                        with unittest.mock.patch.object(
                            agent,
                            "port_is_listening",
                            side_effect=AssertionError("no live connect"),
                        ):
                            with unittest.mock.patch.object(
                                agent,
                                "listener_pid",
                                side_effect=AssertionError("no per-port lsof"),
                            ):
                                with unittest.mock.patch.object(
                                    agent, "process_is_alive", return_value=True
                                ):
                                    with unittest.mock.patch.object(
                                        agent,
                                        "process_command",
                                        return_value=fake[0]["command"],
                                    ):
                                        with unittest.mock.patch.object(
                                            agent, "process_rss_mb", return_value=None
                                        ):
                                            payload = service.status_payload()
            demo = next(s for s in payload["statuses"] if s["profile"] == "demo")
            self.assertEqual(demo["pid"], 4242)
            self.assertTrue(demo["running"])

    def test_status_without_listeners_still_uses_live_checks(self) -> None:
        """stop/start/watchdog call status() without inventory -- live path."""
        with tempfile.TemporaryDirectory() as tmp:
            service = self._service(Path(tmp))
            profile = service.profiles.load()["demo"]
            with unittest.mock.patch.object(
                agent, "listener_pid", return_value=99
            ) as live_pid:
                with unittest.mock.patch.object(
                    agent, "port_is_listening", return_value=True
                ) as live_port:
                    with unittest.mock.patch.object(
                        agent, "process_is_alive", return_value=True
                    ):
                        with unittest.mock.patch.object(
                            agent, "process_command", return_value="llama-server --port 8080"
                        ):
                            with unittest.mock.patch.object(
                                agent, "process_rss_mb", return_value=None
                            ):
                                # Force ready so port_is_listening path is exercised when needed.
                                with unittest.mock.patch.object(
                                    service,
                                    "_probe_health",
                                    return_value=(True, ["demo"]),
                                ):
                                    with unittest.mock.patch.object(
                                        service, "_read_pid", return_value=None
                                    ):
                                        with unittest.mock.patch.object(
                                            service, "_process_matches", return_value=True
                                        ):
                                            row = service.status(profile)
            live_pid.assert_called()
            self.assertEqual(row["pid"], 99)
            self.assertTrue(row["running"])
            # live_port mock is installed so accidental inventory-only path would
            # still resolve; the assertion above is that listener_pid was used.
            self.assertGreaterEqual(live_port.call_count, 0)


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
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "agent-root"
            profiles = Path(tmp) / "my-models"
            profiles.mkdir(parents=True)
            (profiles / "model.env").write_text(
                'REQUEST_MODEL="m"\nPORT=8080\n', encoding="utf-8"
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(AGENT_PATH),
                    "--json",
                    "--yes",
                    "--root",
                    str(root),
                    "--profiles-dir",
                    str(profiles),
                    "--port",
                    "9001",
                    "link",
                ],
                capture_output=True,
                text=True,
                timeout=30,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["agent_port"], "9001")
            self.assertTrue(payload["link"].startswith("modelswitchboard-gateway://"))
            self.assertEqual(payload["profiles_dir"], str(profiles.resolve()))
            config = json.loads((root / "config.json").read_text(encoding="utf-8"))
            self.assertEqual(config["profiles_dir"], str(profiles.resolve()))


class ProfileDirectoryTests(unittest.TestCase):
    def test_looks_like_profile_file_detects_ai_style_model_env(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "model.env"
            path.write_text(
                'DISPLAY_NAME="Qwen"\nREQUEST_MODEL="qwen"\nPORT=8081\n',
                encoding="utf-8",
            )
            self.assertTrue(agent.looks_like_profile_file(path))
            example = Path(tmp) / "example-vllm.env.example"
            example.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
            self.assertFalse(agent.looks_like_profile_file(example))

    def test_scan_groups_by_parent_directory(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            folder = home / "spark-models"
            folder.mkdir()
            (folder / "model.env").write_text(
                'REQUEST_MODEL="a"\nPORT=1\n', encoding="utf-8"
            )
            (folder / "qwen.env").write_text(
                'REQUEST_MODEL="b"\nSTART_COMMAND="run"\n', encoding="utf-8"
            )
            (home / "notes.txt").write_text("not a profile\n", encoding="utf-8")
            candidates = agent.scan_profile_directories(home, max_depth=3)
            self.assertTrue(candidates)
            self.assertEqual(candidates[0]["path"], str(folder.resolve()))
            self.assertEqual(candidates[0]["profile_count"], 2)

    def test_resolve_prefers_config_then_legacy_then_home(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "agent"
            legacy = root / "model-profiles"
            legacy.mkdir(parents=True)
            (legacy / "old.env").write_text('REQUEST_MODEL="m"\nPORT=1\n', encoding="utf-8")
            self.assertEqual(
                agent.resolve_profiles_directory(root),
                legacy.resolve(),
            )
            custom = Path(tmp) / "custom-profiles"
            custom.mkdir()
            agent.save_profiles_directory(root, custom)
            self.assertEqual(
                agent.resolve_profiles_directory(root),
                custom.resolve(),
            )

    def test_prompt_accepts_pasted_path(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "agent"
            root.mkdir()
            chosen = Path(tmp) / "pasted"
            answers = iter([str(chosen)])
            result = agent.prompt_profiles_directory(
                root,
                current=Path(tmp) / "current",
                input_func=lambda _: next(answers),
                home=Path(tmp),
            )
            self.assertEqual(result, chosen.resolve())
            self.assertTrue(chosen.is_dir())




class DiscoveryTests(unittest.TestCase):
    def test_parse_loose_env_bash_defaults(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "flags.env"
            path.write_text(
                'PORT="${PORT:-9099}"\n'
                'MODEL="${MODEL:-/models/demo.gguf}"\n'
                'HOST="${HOST:-127.0.0.1}"\n'
                'BACKEND="${BACKEND:-vllm}"\n',
                encoding="utf-8",
            )
            values = agent.parse_loose_env_assignments(path)
            self.assertEqual(values["PORT"], "9099")
            self.assertEqual(values["MODEL"], "/models/demo.gguf")
            self.assertEqual(values["BACKEND"], "vllm")

    def test_infer_runtime_and_model_from_command(self) -> None:
        cmd = "/opt/bin/llama-server -m /models/foo-Q8_0.gguf --port 8027 --host 127.0.0.1"
        self.assertEqual(agent.infer_runtime_from_command(cmd), "llama.cpp")
        self.assertEqual(agent.infer_model_from_command(cmd), "/models/foo-Q8_0.gguf")
        vllm = "python -m vllm.entrypoints.openai.api_server --model org/model-7b --port 8081"
        self.assertEqual(agent.infer_runtime_from_command(vllm), "vllm")
        # Never invent a model when argv has none.
        self.assertIsNone(agent.infer_model_from_command("some-random-daemon --port 99"))

    def test_scan_port_claim_directories_is_path_agnostic(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # Arbitrary parent name — not /data/launch.
            claim = root / "my-servers" / "9123"
            claim.mkdir(parents=True)
            (claim / "flags.env").write_text(
                'PORT="${PORT:-9123}"\n'
                'MODEL="${MODEL:-/w/custom.gguf}"\n'
                'LLAMA_BIN="${LLAMA_BIN:-/usr/bin/llama-server}"\n',
                encoding="utf-8",
            )
            (claim / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (claim / "launch.sh").chmod(0o755)
            found = agent.scan_port_claim_directories(roots=[root], max_depth=3)
            ports = {item["port"] for item in found}
            self.assertIn(9123, ports)
            item = next(item for item in found if item["port"] == 9123)
            self.assertEqual(item["runtime_hint"], "llama.cpp")
            self.assertIn("custom.gguf", item["model_hint"])
            self.assertEqual(item["path"], str(claim.resolve()))

    def test_scan_overlapping_roots_still_discovers_claim(self) -> None:
        """Parent + nested roots must not drop claims when visit map dedupes."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            claim = root / "a" / "b" / "9222"
            claim.mkdir(parents=True)
            (claim / "flags.env").write_text(
                'PORT="${PORT:-9222}"\nMODEL="${MODEL:-/w/overlap.gguf}"\n',
                encoding="utf-8",
            )
            (claim / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (claim / "launch.sh").chmod(0o755)
            found = agent.scan_port_claim_directories(
                roots=[root, root / "a", root / "a" / "b"],
                max_depth=3,
                listeners=[],
            )
            ports = {item["port"] for item in found}
            self.assertIn(9222, ports)

    def test_scan_skips_home_when_primary_yields_claims(self) -> None:
        """$HOME is a costly fallback -- skip when configured roots already hit."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            primary = root / "configured"
            claim = primary / "9333"
            claim.mkdir(parents=True)
            (claim / "flags.env").write_text(
                'PORT="${PORT:-9333}"\n',
                encoding="utf-8",
            )
            (claim / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (claim / "launch.sh").chmod(0o755)
            home = root / "fake-home"
            home_claim = home / "9444"
            home_claim.mkdir(parents=True)
            (home_claim / "flags.env").write_text(
                'PORT="${PORT:-9444}"\n',
                encoding="utf-8",
            )
            (home_claim / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (home_claim / "launch.sh").chmod(0o755)
            with unittest.mock.patch.object(Path, "home", return_value=home):
                found = agent.scan_port_claim_directories(
                    roots=[primary],
                    max_depth=2,
                    home_depth=2,
                    listeners=[],
                )
            ports = {item["port"] for item in found}
            self.assertIn(9333, ports)
            self.assertNotIn(9444, ports)

    def test_status_merges_claims_without_inventing_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "model-profiles"
            profiles.mkdir()
            claims_root = root / "wherever"
            port_dir = claims_root / "9555"
            port_dir.mkdir(parents=True)
            (port_dir / "flags.env").write_text(
                'MODEL="${MODEL:-/models/real.gguf}"\nPORT="${PORT:-9555}"\n',
                encoding="utf-8",
            )
            (port_dir / "launch.sh").write_text("#!/bin/sh\n", encoding="utf-8")
            (port_dir / "launch.sh").chmod(0o755)
            configuration = agent.AgentConfiguration(
                root=root,
                host="127.0.0.1",
                port=18877,
                profiles_dir=profiles,
            )
            service = agent.AgentService(configuration)
            # Point scan at our temp tree via env.
            old = os.environ.get(agent.SCAN_ROOTS_ENV)
            os.environ[agent.SCAN_ROOTS_ENV] = str(claims_root)
            try:
                payload = service.status_payload()
            finally:
                if old is None:
                    os.environ.pop(agent.SCAN_ROOTS_ENV, None)
                else:
                    os.environ[agent.SCAN_ROOTS_ENV] = old
            names = {item["profile"] for item in payload["statuses"]}
            self.assertIn("port-9555", names)
            claim_status = next(item for item in payload["statuses"] if item["profile"] == "port-9555")
            self.assertEqual(claim_status["port"], "9555")
            self.assertIn("real.gguf", claim_status["request_model"])
            # Down + unprobed: not ready, not a fake vLLM.
            self.assertFalse(claim_status["ready"])
            self.assertNotEqual(claim_status["runtime"], "vllm")
            self.assertEqual(claim_status["discovery_source"], "claim")
            self.assertIsInstance(claim_status["log_path"], str)


    def test_resolve_profile_uses_claim_start_command(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            profiles = root / "model-profiles"
            profiles.mkdir()
            claim = root / "my-stack" / "9777"
            claim.mkdir(parents=True)
            (claim / "flags.env").write_text(
                'MODEL="${MODEL:-/models/x.gguf}"\nPORT="${PORT:-9777}"\n',
                encoding="utf-8",
            )
            launch = claim / "launch.sh"
            launch.write_text("#!/bin/sh\necho hi\n", encoding="utf-8")
            launch.chmod(0o755)
            configuration = agent.AgentConfiguration(
                root=root, host="127.0.0.1", port=18878, profiles_dir=profiles
            )
            service = agent.AgentService(configuration)
            old = os.environ.get(agent.SCAN_ROOTS_ENV)
            os.environ[agent.SCAN_ROOTS_ENV] = str(root / "my-stack")
            try:
                profile = service.resolve_profile("port-9777")
            finally:
                if old is None:
                    os.environ.pop(agent.SCAN_ROOTS_ENV, None)
                else:
                    os.environ[agent.SCAN_ROOTS_ENV] = old
            self.assertEqual(profile.endpoint_port, "9777")
            cmd = agent.build_start_command(profile)
            self.assertIn("launch.sh", cmd)

    def test_discovered_status_log_path_is_string(self) -> None:
        """Mac Codable requires log_path: String — null breaks the gateway UI."""
        status = agent.status_dict_from_discovery(
            {
                "port": 9555,
                "display_name": "demo",
                "runtime": "llama.cpp",
                "request_model": "/models/demo.gguf",
                "ready": False,
            },
            source="claim",
            profile_name="port-9555",
        )
        self.assertIsInstance(status["log_path"], str)
        self.assertTrue(status["log_path"])


if __name__ == "__main__":
    unittest.main()

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import unittest
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
MODELCTL = ROOT / "modelctl.py"
SAFE_TEST_HOSTS = {"127.0.0.1", "localhost", "::1"}


def reserve_local_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class E2ELogger:
    def __init__(self, suite: str, test_name: str) -> None:
        self.suite = suite
        self.test_name = test_name
        self.started = time.monotonic()

    def event(self, phase: str, event: str, **data: object) -> None:
        payload: dict[str, object] = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "suite": self.suite,
            "test": self.test_name,
            "phase": phase,
            "event": event,
        }
        if data:
            payload["data"] = data
        print(json.dumps(payload, sort_keys=True), file=sys.stderr)

    def finish(self, result: str) -> None:
        self.event("teardown", "test_end", result=result, duration_ms=int((time.monotonic() - self.started) * 1000))


def assert_safe_test_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "http" or parsed.hostname not in SAFE_TEST_HOSTS:
        raise AssertionError(f"refusing to run real-service E2E against non-local URL: {url}")


def read_json(url: str, *, token: str | None = None) -> tuple[int, dict[str, Any]]:
    assert_safe_test_url(url)
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=2) as response:
            return response.status, json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode())


def wait_for_status(base_url: str, *, token: str, timeout: float = 8.0) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last_error: BaseException | None = None
    while time.monotonic() < deadline:
        try:
            status, payload = read_json(f"{base_url}/api/status", token=token)
            if status == 200:
                return payload
        except (OSError, urllib.error.URLError) as exc:
            last_error = exc
        time.sleep(0.1)
    raise AssertionError(f"controller did not become ready: {last_error}")


class ControllerRealServiceE2ETests(unittest.TestCase):
    def start_controller(self, *, home: Path, token_file: Path, port: int) -> subprocess.Popen[bytes]:
        env = os.environ.copy()
        env["HOME"] = str(home)
        env["PYTHONUNBUFFERED"] = "1"
        return subprocess.Popen(
            [
                sys.executable,
                str(MODELCTL),
                "serve-web",
                "--host",
                "127.0.0.1",
                "--port",
                str(port),
                "--auth-token-file",
                str(token_file),
            ],
            cwd=ROOT,
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        )

    def stop_controller(self, proc: subprocess.Popen[bytes]) -> tuple[str, str]:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                stdout, stderr = proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                stdout, stderr = proc.communicate(timeout=3)
        else:
            stdout, stderr = proc.communicate(timeout=3)
        return stdout.decode(errors="replace"), stderr.decode(errors="replace")

    def test_serve_web_real_process_status_cache_and_bearer_auth(self) -> None:
        log = E2ELogger("controller-real-service-e2e", "serve-web-status-cache-auth")
        token = "real-service-e2e-token-0000000000000001"
        port = reserve_local_port()
        base_url = f"http://127.0.0.1:{port}"
        proc: subprocess.Popen[bytes] | None = None
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp_path = Path(tmpdir)
            home = tmp_path / "home"
            home.mkdir()
            token_file = tmp_path / "controller.token"
            token_file.write_text(token)
            log.event("setup", "service_start", port=port, home=str(home))
            proc = self.start_controller(home=home, token_file=token_file, port=port)
            try:
                payload = wait_for_status(base_url, token=token)
                log.event("act", "status_ready", profiles=len(payload["statuses"]))

                unauthorized_status, unauthorized_payload = read_json(f"{base_url}/api/status")
                self.assertEqual(unauthorized_status, 401)
                self.assertEqual(unauthorized_payload["error"], "unauthorized")
                log.event("assert", "auth_rejected", status=unauthorized_status)

                self.assertIsInstance(payload["statuses"], list)
                self.assertIsInstance(payload["benchmark"], dict)
                self.assertEqual(payload["profiles_dir"], str(ROOT / "model-profiles"))
                cache_path = home / "Library" / "Caches" / "io.modelswitchboard" / "controller-status.json"
                self.assertTrue(cache_path.exists())
                cached = json.loads(cache_path.read_text())
                self.assertEqual(cached["profiles_dir"], payload["profiles_dir"])
                log.event("assert", "status_cache_written", cache_path=str(cache_path))
                log.finish("pass")
            except Exception:
                log.finish("fail")
                raise
            finally:
                if proc is not None:
                    stdout, stderr = self.stop_controller(proc)
                    log.event("teardown", "service_stopped", returncode=proc.returncode, stdout=stdout.strip(), stderr=stderr.strip())

    def test_real_service_harness_blocks_non_local_urls(self) -> None:
        log = E2ELogger("controller-real-service-e2e", "production-url-blocklist")
        log.event("setup", "guard_check")
        with self.assertRaisesRegex(AssertionError, "non-local URL"):
            assert_safe_test_url("https://example.com/api/status")
        log.event("assert", "guard_rejected_production_url")
        log.finish("pass")


if __name__ == "__main__":
    unittest.main()

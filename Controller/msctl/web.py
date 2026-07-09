from __future__ import annotations

import hmac
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from msctl.benchmarks import benchmark_status, start_benchmark
from msctl.doctor import doctor_report
from msctl.paths import BASE, MAX_JSON_BODY_BYTES, PROFILE_DIR
from msctl.profiles import (
    action_response_from_status,
    integration_status,
    restart_profile,
    run_active_profile_watchdog,
    run_integration_action,
    start_profile,
    status_payload,
    stop_all,
    stop_profile,
    switch_profile,
    write_status_cache,
)
from msctl.security import (
    ControllerAPIError,
    ControllerRequest,
    ProfileConflictError,
    request_path,
    validate_controller_bind,
)

def load_dashboard_html() -> str:
    html_path = BASE / "web" / "dashboard.html"
    try:
        return html_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise RuntimeError(f"dashboard HTML missing: {html_path}") from exc


HTML_PAGE = load_dashboard_html()


class DashboardHandler(BaseHTTPRequestHandler):
    def _auth_token(self) -> str | None:
        token = getattr(self.server, "auth_token", None)
        return token if isinstance(token, str) and token else None

    def _check_auth(self) -> bool:
        token = self._auth_token()
        if not token:
            return True
        expected = f"Bearer {token}"
        if hmac.compare_digest(self.headers.get("Authorization", ""), expected):
            return True
        self._send_json({"ok": False, "error": "unauthorized", "message": "unauthorized"}, status=401)
        return False

    def _send_api_error(self, exc: ControllerAPIError) -> None:
        self._send_json({"ok": False, "error": exc.code, "message": exc.message}, status=exc.status)

    def _send_internal_error(self, exc: BaseException) -> None:
        print(f"[ERROR] controller request failed: {type(exc).__name__}", file=sys.stderr)
        self._send_api_error(ControllerAPIError(500, "internal_error", "internal server error"))

    @staticmethod
    def _system_exit_error(exc: SystemExit) -> ControllerAPIError:
        message = str(exc)
        if message.startswith("Unknown profile:"):
            return ControllerAPIError(404, "profile_not_found", "profile not found")
        return ControllerAPIError(400, "request_failed", "request could not be completed")

    @staticmethod
    def _required_string(payload: ControllerRequest, key: str) -> str:
        value = payload.get(key)
        if not isinstance(value, str) or not value:
            raise ControllerAPIError(400, "invalid_request", f"missing required string field: {key}")
        return value

    @staticmethod
    def _optional_profiles(payload: ControllerRequest) -> list[str] | None:
        profiles = payload.get("profiles")
        if profiles is None:
            return None
        if not isinstance(profiles, list):
            raise ControllerAPIError(400, "invalid_request", "profiles must be a list of strings")
        if not all(isinstance(item, str) for item in profiles):
            raise ControllerAPIError(400, "invalid_request", "profiles must be a list of strings")
        return profiles

    def _send_json(self, payload: dict[str, object], status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body: str, status: int = 200) -> None:
        raw = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _read_json(self) -> ControllerRequest:
        raw_length = self.headers.get("Content-Length", "0") or "0"
        try:
            length = int(raw_length)
        except ValueError as exc:
            raise ControllerAPIError(400, "invalid_content_length", "invalid Content-Length") from exc
        if length < 0:
            raise ControllerAPIError(400, "invalid_content_length", "invalid Content-Length")
        if length > MAX_JSON_BODY_BYTES:
            raise ControllerAPIError(413, "payload_too_large", "JSON payload too large")
        if length <= 0:
            return {}
        try:
            payload = self.rfile.read(length).decode()
        except UnicodeDecodeError as exc:
            raise ControllerAPIError(400, "invalid_json", "request body must be UTF-8 JSON") from exc
        try:
            raw_payload = json.loads(payload) if payload else {}
        except json.JSONDecodeError as exc:
            raise ControllerAPIError(400, "invalid_json", "invalid JSON") from exc
        if not isinstance(raw_payload, dict):
            raise ControllerAPIError(400, "invalid_json", "request body must be a JSON object")
        request: ControllerRequest = {}
        for key in ("profile", "integration", "action", "suite"):
            value = raw_payload.get(key)
            if isinstance(value, str):
                request[key] = value
        profiles = raw_payload.get("profiles")
        if profiles is not None:
            if not isinstance(profiles, list) or not all(isinstance(item, str) for item in profiles):
                raise ControllerAPIError(400, "invalid_request", "profiles must be a list of strings")
            if profiles:
                request["profiles"] = profiles
        for key in ("allow_concurrent", "keep_running"):
            value = raw_payload.get(key)
            if isinstance(value, bool):
                request[key] = value
        return request

    def do_GET(self) -> None:
        try:
            path = request_path(self.path)
            if path.startswith("/api/") and not self._check_auth():
                return
            if path in {"/", "/index.html"}:
                self._send_html(HTML_PAGE)
                return
            if path == "/api/status":
                payload = status_payload()
                write_status_cache(payload)
                self._send_json(payload)
                return
            if path == "/api/doctor":
                self._send_json(doctor_report())
                return
            if path == "/api/benchmark/status":
                self._send_json(benchmark_status())
                return
            if path == "/api/integrations":
                self._send_json(
                    {
                        "integrations": integration_status(),
                        "profiles_dir": str(PROFILE_DIR),
                        "controller_root": str(BASE),
                    }
                )
                return
            raise ControllerAPIError(404, "not_found", "not found")
        except ControllerAPIError as exc:
            self._send_api_error(exc)
        except SystemExit as exc:
            self._send_api_error(self._system_exit_error(exc))
        except Exception as exc:  # noqa: BLE001
            self._send_internal_error(exc)

    def do_POST(self) -> None:
        if not self._check_auth():
            return
        try:
            path = request_path(self.path)
            payload = self._read_json()
            if path == "/api/start":
                start_profile(self._required_string(payload, "profile"))
            elif path == "/api/stop":
                stop_profile(self._required_string(payload, "profile"))
            elif path == "/api/restart":
                restart_profile(self._required_string(payload, "profile"))
            elif path == "/api/switch":
                switch_profile(self._required_string(payload, "profile"))
            elif path == "/api/stop-all":
                stop_all()
            elif path == "/api/integrations/run":
                run_integration_action(
                    self._required_string(payload, "integration"),
                    payload.get("action", "sync"),
                )
            elif path == "/api/benchmark/start":
                status = start_benchmark(
                    self._optional_profiles(payload),
                    suite=payload.get("suite", "quick"),
                    allow_concurrent=bool(payload.get("allow_concurrent", False)),
                    keep_running=bool(payload.get("keep_running", False)),
                )
                controller_payload = status_payload()
                controller_payload["benchmark"] = status
                response_payload = action_response_from_status(controller_payload)
                write_status_cache(controller_payload)
                self._send_json(response_payload)
                return
            else:
                self._send_api_error(ControllerAPIError(404, "not_found", "not found"))
                return
        except ControllerAPIError as exc:
            self._send_api_error(exc)
            return
        except ProfileConflictError:
            self._send_api_error(ControllerAPIError(409, "profile_conflict", "profile endpoint conflict"))
            return
        except SystemExit as exc:
            self._send_api_error(self._system_exit_error(exc))
            return
        except ValueError:
            self._send_api_error(ControllerAPIError(400, "invalid_request", "invalid request"))
            return
        except Exception as exc:  # noqa: BLE001
            self._send_internal_error(exc)
            return
        controller_payload = status_payload()
        response_payload = action_response_from_status(controller_payload)
        write_status_cache(controller_payload)
        self._send_json(response_payload)

    def log_message(self, fmt: str, *args: object) -> None:
        return


def serve_web(host: str, port: int, *, unsafe_bind: bool = False, auth_token: str | None = None) -> None:
    validate_controller_bind(host, unsafe_bind=unsafe_bind, auth_token=auth_token)
    threading.Thread(target=run_active_profile_watchdog, daemon=True).start()
    server = ThreadingHTTPServer((host, port), DashboardHandler)
    server.auth_token = auth_token
    print(f"dashboard=http://{host}:{port}")
    server.serve_forever()



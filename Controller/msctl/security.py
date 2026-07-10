from __future__ import annotations

import ipaddress
import os
import pathlib
import time
import urllib.parse
from typing import TypedDict

from msctl.paths import (
    ALLOW_REMOTE_HEALTHCHECK_ENV,
    DOCTOR_RUN_ID_PATTERN,
    MIN_AUTH_TOKEN_BYTES,
    MUTATION_LOCK,
)
import msctl.paths as _paths

class ProfileConflictError(RuntimeError):
    """Raised when two or more profiles resolve to the same endpoint."""


class ControllerAPIError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        Exception.__init__(self, message)
        self.status = status
        self.code = code
        self.message = message


def _host_for_ip_parse(host: str) -> str:
    value = host.strip().lower()
    if value.startswith("[") and value.endswith("]"):
        return value[1:-1]
    return value


def is_loopback_host(host: str) -> bool:
    value = _host_for_ip_parse(host)
    if value == "localhost":
        return True
    try:
        return ipaddress.ip_address(value).is_loopback
    except ValueError:
        return False


def read_auth_token_file(path: str | None) -> str | None:
    if not path:
        return None
    token = pathlib.Path(path).expanduser().read_text(encoding="utf-8").strip()
    return token or None


def resolve_auth_token(token: str | None = None, token_file: str | None = None) -> str | None:
    resolved = token or read_auth_token_file(token_file)
    if resolved and len(resolved.encode("utf-8")) < MIN_AUTH_TOKEN_BYTES:
        raise ValueError(f"auth token must be at least {MIN_AUTH_TOKEN_BYTES} bytes")
    return resolved


def validate_controller_bind(host: str, *, unsafe_bind: bool = False, auth_token: str | None = None) -> None:
    if is_loopback_host(host):
        return
    if not unsafe_bind:
        raise ValueError(f"non-loopback controller bind requires --unsafe-bind: {host}")
    if not auth_token:
        raise ValueError("non-loopback controller bind requires a bearer auth token")


def suppress_active_profile_watchdog(seconds: float = 45.0) -> None:
    """Prevent the crash-recovery watchdog from fighting intentional stops."""
    _paths._WATCHDOG_SUPPRESS_UNTIL = max(_paths._WATCHDOG_SUPPRESS_UNTIL, time.time() + seconds)


def is_active_profile_watchdog_suppressed() -> bool:
    return time.time() < _paths._WATCHDOG_SUPPRESS_UNTIL


def request_path(raw_path: str) -> str:
    """Return the URL path without query/fragment for exact route matching."""
    return urllib.parse.urlsplit(raw_path).path or "/"


def is_safe_healthcheck_url(url: str) -> bool:
    """Default-deny non-loopback health probes unless explicitly opted in."""
    if os.environ.get(ALLOW_REMOTE_HEALTHCHECK_ENV, "").strip() in {"1", "true", "TRUE", "yes", "YES"}:
        return True
    try:
        parsed = urllib.parse.urlparse(url)
    except ValueError:
        return False
    host = parsed.hostname or ""
    return is_loopback_host(host)


def sanitize_doctor_run_id(run_id: str) -> str:
    value = (run_id or "").strip()
    if not DOCTOR_RUN_ID_PATTERN.fullmatch(value):
        raise ValueError("invalid doctor run id")
    return value


def with_mutation_lock(fn):
    """Serialize profile/benchmark mutations across HTTP worker threads."""
    import functools

    @functools.wraps(fn)
    def wrapped(*args, **kwargs):
        with MUTATION_LOCK:
            return fn(*args, **kwargs)

    return wrapped


class ControllerRequest(TypedDict, total=False):
    profile: str
    profiles: list[str]
    integration: str
    action: str
    suite: str
    allow_concurrent: bool
    keep_running: bool

#!/usr/bin/env python3
"""Model Switchboard remote agent.

A single-file, stdlib-only implementation of the Model Switchboard controller
HTTP contract (see SETUP.md "Controller API contract") for remote hosts:
Linux boxes, DGX-class machines, or anything with Python 3.10+.

The macOS menu bar app adds this host as a remote gateway (directly or through
an SSH tunnel) and can then launch, monitor, and stop model servers here.

Design constraints:
- No dependencies outside the standard library, ever.
- Same profile formats as the reference controller (model-profiles/*.env|*.json).
- Same HTTP routes, status codes, auth rules, and JSON field names.
- Loopback bind by default; non-loopback binds require --unsafe-bind and a
  bearer token of at least 16 bytes, mirroring the Swift controller.
"""

from __future__ import annotations

import argparse
import getpass
import hmac
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable

AGENT_VERSION = "1.1.2"
DEFAULT_PORT = 8877
MINIMUM_TOKEN_BYTES = 16
MAXIMUM_BODY_BYTES = 64 * 1024
WATCHDOG_INTERVAL_SECONDS = 30.0
WATCHDOG_SUPPRESSION_SECONDS = 45.0
# Large model servers (vLLM, etc.) can take a long time to unload GPU memory.
STOP_WAIT_SECONDS = 90.0
TERMINATE_TIMEOUT_SECONDS = 20.0
FORCE_TERMINATE_TIMEOUT_SECONDS = 3.0
HEALTH_TIMEOUT_SECONDS = 1.5
PROFILES_DIR_ENV = "MODEL_SWITCHBOARD_PROFILES_DIR"
# Keys that make a .env/.json look like a Switchboard (or AI-authored) launch profile.
PROFILE_SIGNAL_KEYS = frozenset({
    "REQUEST_MODEL",
    "PORT",
    "BASE_URL",
    "START_COMMAND",
    "MODEL_FILE",
    "MODEL_PATH",
    "MODEL_REPO",
    "SERVER_MODEL_ID",
    "RUNTIME",
    "DISPLAY_NAME",
})
PROFILE_SCAN_SKIP_DIRS = frozenset({
    ".git",
    ".hg",
    ".svn",
    ".cache",
    ".local",
    ".Trash",
    ".cursor",
    ".vscode",
    ".npm",
    ".cargo",
    ".rustup",
    "node_modules",
    "Library",
    "Applications",
    "__pycache__",
    "venv",
    ".venv",
    "dist",
    "build",
    ".build",
    "target",
})
PROFILE_SCAN_MAX_DEPTH = 5
PROFILE_SCAN_MAX_CANDIDATES = 8
# Optional colon-separated roots for "claimed port" folder scans (never assumed).
# Example: MODEL_SWITCHBOARD_SCAN_ROOTS=/opt/models:/srv/launch
SCAN_ROOTS_ENV = "MODEL_SWITCHBOARD_SCAN_ROOTS"
# Numeric dir name = claimed TCP port (2–5 digits). Parent path is not fixed.
PORT_CLAIM_DIR_RE = re.compile(r"^\d{2,5}$")
PORT_CLAIM_MARKERS = ("flags.env", "launch.sh", "start.sh", "run.sh", "serve.sh", "ctrl.sh")
# Cmdline tokens that suggest a local model / OpenAI-compatible server.
MODEL_SERVER_COMMAND_MARKERS = (
    "llama-server",
    "llama.cpp",
    "llamacpp",
    "vllm",
    "sglang",
    "text-generation-launcher",
    "text-generation-server",
    "ollama",
    "tabbyapi",
    "aphrodite",
    "tgi-",
    "openai",
    "mlc_llm",
    "koboldcpp",
    "kobold",
    "exllamav2",
    "exllama",
    "lmdeploy",
    "tensorrt_llm",
    "trtllm",
    "localai",
    "llama-cpp",
    "gguf",
)
# System / clearly non-model listeners we never probe.
SKIP_LISTEN_PORTS = frozenset({
    22, 25, 53, 67, 68, 69, 80, 110, 123, 135, 139, 143, 161, 389, 443,
    445, 465, 587, 631, 636, 993, 995, 2375, 2376, 3306, 3389, 5432, 5900,
    6379, 6443, 8088, 8443, 9100, 10250, 27017,
})
DISCOVERY_PROBE_BUDGET = 24
DISCOVERY_PROBE_TIMEOUT = 0.6
# Inventory cache TTL for list_listening_tcp (ss/lsof/proc).
# Default 2.0s is tuned to UI status poll cadence (~10s active refresh) and
# cross-request reuse: rapid re-polls, multi-client bursts, and concurrent
# status/ports/scan callers share one snapshot for a few seconds instead of
# cold-missing every request (old 75ms TTL was shorter than any real poll).
# Ports/listen state may lag ≤TTL -- intentional; stop/start still use live
# listener_pid / clear_listening_tcp_cache when accuracy matters.
LISTENING_TCP_CACHE_TTL_SECONDS = 2.0

PROFILE_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SHELL_DEFAULT_RE = re.compile(
    r"^\$\{[A-Za-z_][A-Za-z0-9_]*:-((?:\\.|[^\\}])*)\}$"
)

LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}

# --------------------------------------------------------------------------
# Perf profiling (measurement only; default OFF)
# Enable with MSW_PERF_PROFILE=1 or MSW_AGENT_PERF=1.
# Optional JSONL append path: MSW_PERF_JSONL=/path/to/spans.jsonl
# Emits stderr lines: perf.profile.span_summary {json}
# --------------------------------------------------------------------------
_PERF_PROFILE_TRUE = frozenset({"1", "true", "yes", "on"})


def _perf_profile_enabled() -> bool:
    """True when env-gated agent timing is requested (default off)."""
    for key in ("MSW_PERF_PROFILE", "MSW_AGENT_PERF"):
        raw = os.environ.get(key, "").strip().lower()
        if raw in _PERF_PROFILE_TRUE:
            return True
    return False


def _emit_perf_span_summary(payload: dict[str, Any]) -> None:
    """Write one structured span line to stderr; optionally append JSONL."""
    try:
        body = json.dumps(payload, separators=(",", ":"), sort_keys=True, default=str)
    except (TypeError, ValueError):
        body = json.dumps(
            {"span": str(payload.get("span")), "duration_ms": payload.get("duration_ms")},
            separators=(",", ":"),
        )
    print(f"perf.profile.span_summary {body}", file=sys.stderr, flush=True)
    path = os.environ.get("MSW_PERF_JSONL", "").strip()
    if not path:
        return
    try:
        record = dict(payload)
        record.setdefault("ts", time.time())
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, separators=(",", ":"), default=str) + "\n")
    except OSError:
        pass


class _PerfSpan:
    """Env-gated wall-clock span. No-op when profiling is off (zero side effects)."""

    __slots__ = ("name", "tags", "enabled", "_t0", "stages", "_stage_name", "_stage_t0")

    def __init__(self, name: str, **tags: Any) -> None:
        self.name = name
        self.tags: dict[str, Any] = dict(tags)
        self.enabled = _perf_profile_enabled()
        self._t0 = 0.0
        self.stages: dict[str, float] = {}
        self._stage_name: str | None = None
        self._stage_t0: float | None = None

    def stage(self, name: str) -> None:
        """Close the previous stage (if any) and open *name*."""
        if not self.enabled:
            return
        now = time.perf_counter()
        if self._stage_name is not None and self._stage_t0 is not None:
            self.stages[self._stage_name] = round((now - self._stage_t0) * 1000.0, 3)
        self._stage_name = name
        self._stage_t0 = now

    def __enter__(self) -> "_PerfSpan":
        if self.enabled:
            self._t0 = time.perf_counter()
        return self

    def __exit__(self, *_exc: object) -> bool:
        if not self.enabled:
            return False
        now = time.perf_counter()
        if self._stage_name is not None and self._stage_t0 is not None:
            self.stages[self._stage_name] = round((now - self._stage_t0) * 1000.0, 3)
        duration_ms = round((now - self._t0) * 1000.0, 3)
        payload: dict[str, Any] = {
            "span": self.name,
            "duration_ms": duration_ms,
            **self.tags,
        }
        if self.stages:
            payload["stages_ms"] = self.stages
        _emit_perf_span_summary(payload)
        return False


def is_loopback(host: str) -> bool:
    return host.strip().strip("[]").lower() in LOOPBACK_HOSTS


def is_tailscale_ip(address: str) -> bool:
    """Tailscale assigns IPv4 from the CGNAT range 100.64.0.0/10."""
    parts = address.split(".")
    if len(parts) != 4:
        return False
    try:
        first, second = int(parts[0]), int(parts[1])
    except ValueError:
        return False
    return first == 100 and 64 <= second <= 127


def tailscale_status() -> tuple[str | None, str | None]:
    """Return (ipv4, magic_dns_name) for this host's tailnet presence.

    Prefers the tailscale CLI; falls back to scanning interfaces for a CGNAT
    address so it works even when the CLI is not on PATH.
    """
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if result.returncode == 0:
            parsed = json.loads(result.stdout)
            self_info = parsed.get("Self") or {}
            ips = [ip for ip in self_info.get("TailscaleIPs") or [] if is_tailscale_ip(ip)]
            dns_name = (self_info.get("DNSName") or "").rstrip(".") or None
            if ips:
                return ips[0], dns_name
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if result.returncode == 0:
            for line in result.stdout.split():
                if is_tailscale_ip(line.strip()):
                    return line.strip(), None
    except (OSError, subprocess.TimeoutExpired):
        pass
    for command in (["ip", "-4", "addr"], ["ifconfig"]):
        try:
            result = subprocess.run(
                command, capture_output=True, text=True, timeout=5, check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode != 0:
            continue
        for match in re.finditer(r"inet (\d+\.\d+\.\d+\.\d+)", result.stdout):
            if is_tailscale_ip(match.group(1)):
                return match.group(1), None
    return None, None


# --------------------------------------------------------------------------
# Errors (mirrors ControllerError -> ControllerRouter HTTP mapping)
# --------------------------------------------------------------------------


class AgentError(Exception):
    """Base error with the same categories as the Swift ControllerError."""

    http_status = 500
    code = "internal_error"
    public_message = "internal server error"

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class UsageError(AgentError):
    http_status = 400
    code = "invalid_request"
    public_message = "invalid request"


class InvalidConfigurationError(AgentError):
    http_status = 400
    code = "invalid_request"
    public_message = "invalid request"


class InvalidProfileError(AgentError):
    http_status = 400
    code = "invalid_request"
    public_message = "invalid request"


class ProfileNotFoundError(AgentError):
    http_status = 404
    code = "profile_not_found"
    public_message = "profile not found"

    def __init__(self, name: str):
        super().__init__(f"Unknown profile: {name}")


class ProfileConflictError(AgentError):
    http_status = 409
    code = "profile_conflict"
    public_message = "profile endpoint conflict"


class OperationFailedError(AgentError):
    http_status = 500
    code = "internal_error"
    public_message = "internal server error"

    def __init__(self, message: str):
        super().__init__(message)
        # Surface the concrete failure to clients (benchmark already running, etc.).
        self.public_message = message


class UnsupportedError(AgentError):
    http_status = 400
    code = "unsupported_action"

    def __init__(self, message: str):
        super().__init__(message)
        self.public_message = message


class InvalidJSONError(AgentError):
    http_status = 400
    code = "invalid_json"
    public_message = "invalid JSON"


# --------------------------------------------------------------------------
# Runtime catalog (subset parity with RuntimeCatalog.swift)
# --------------------------------------------------------------------------

RUNTIME_ALIASES: dict[str, str] = {
    "llamacpp": "llama.cpp", "llama-cpp": "llama.cpp", "mlx-lm": "mlx", "mlx_lm": "mlx",
    "rvllm": "rvllm-mlx", "rvllm_mlx": "rvllm-mlx", "vllm_mlx": "vllm-mlx",
    "ddtree": "ddtree-mlx", "ddtree_mlx": "ddtree-mlx", "mlx_vlm": "mlx-vlm",
    "mlx-omni": "mlx-omni-server", "mlx-openai": "mlx-openai-server", "mlx-engine": "mlxengine",
    "openai": "external", "openai-compatible": "external", "endpoint": "external",
    "custom": "command", "lmstudio": "lm-studio", "local-ai": "localai",
    "text-generation-inference": "tgi", "huggingface-tgi": "tgi",
    "oobabooga": "text-generation-webui",
    "kobold-cpp": "koboldcpp", "exllama": "exllamav2", "exllama-v2": "exllamav2",
    "aphrodite-engine": "aphrodite", "mistralrs": "mistral.rs", "mlc": "mlc-llm",
    "fast-chat": "fastchat", "bentoml-openllm": "openllm", "nexa-sdk": "nexa",
    "nexaai": "nexa", "litellm-proxy": "litellm", "llamaswap": "llama-swap",
    "hf-transformers": "transformers", "huggingface-transformers": "transformers",
    "nvidia-triton": "triton", "tensorrtllm": "tensorrt-llm", "ort-genai": "onnxruntime-genai",
}

# runtime -> (label, tags, launch_mode)
RUNTIME_SPECS: dict[str, tuple[str, list[str], str]] = {
    "llama.cpp": ("llama.cpp", ["managed", "openai-compatible", "gguf"], "adapter"),
    "vllm": ("vLLM", ["managed", "openai-compatible", "server", "cuda"], "adapter"),
    "sglang": ("SGLang", ["managed", "openai-compatible", "server", "radix-cache"], "adapter"),
    "tgi": ("Text Generation Inference", ["managed", "openai-compatible", "server", "hugging-face"], "adapter"),
    "ollama": ("Ollama", ["daemon", "openai-compatible", "model-registry"], "external"),
    "llama-cpp-python": ("llama-cpp-python", ["managed", "openai-compatible", "gguf", "python"], "adapter"),
    "llamafile": ("llamafile", ["managed", "openai-compatible", "gguf", "single-binary"], "adapter"),
    "koboldcpp": ("KoboldCpp", ["managed", "openai-compatible", "gguf"], "adapter"),
    "tabbyapi": ("TabbyAPI", ["managed", "openai-compatible", "exllamav2"], "adapter"),
    "exllamav2": ("ExLlamaV2", ["managed", "openai-compatible", "exllamav2", "gptq"], "adapter"),
    "aphrodite": ("Aphrodite Engine", ["managed", "openai-compatible", "server"], "adapter"),
    "lmdeploy": ("LMDeploy", ["managed", "openai-compatible", "server", "turbomind"], "adapter"),
    "mistral.rs": ("mistral.rs", ["managed", "openai-compatible", "rust", "gguf"], "adapter"),
    "lightllm": ("LightLLM", ["managed", "openai-compatible", "server"], "adapter"),
    "fastchat": ("FastChat", ["managed", "openai-compatible", "server"], "adapter"),
    "openllm": ("OpenLLM", ["managed", "openai-compatible", "server", "bentoml"], "adapter"),
    "litellm": ("LiteLLM", ["external", "openai-compatible", "proxy"], "external"),
    "llama-swap": ("llama-swap", ["external", "openai-compatible", "proxy", "on-demand-swap"], "external"),
    "transformers": ("Transformers", ["managed", "openai-compatible", "python", "hugging-face"], "adapter"),
    "triton": ("Triton Inference Server", ["external", "openai-compatible", "server"], "external"),
    "tensorrt-llm": ("TensorRT-LLM", ["managed", "openai-compatible", "server"], "adapter"),
    "onnxruntime-genai": ("ONNX Runtime GenAI", ["managed", "openai-compatible", "onnx"], "adapter"),
    "text-generation-webui": ("text-generation-webui", ["managed", "openai-compatible", "launcher"], "adapter"),
    "localai": ("LocalAI", ["external", "openai-compatible", "multi-backend"], "external"),
    "external": ("OpenAI-compatible endpoint", ["external", "openai-compatible"], "external"),
    "command": ("Custom command", ["managed", "custom", "openai-compatible"], "command"),
}


def canonical_runtime(value: str | None) -> str:
    normalized = (value or "llama.cpp").strip().lower().replace("_", "-")
    return RUNTIME_ALIASES.get(normalized, normalized)


# --------------------------------------------------------------------------
# Profiles (parity with ProfileRepository.swift)
# --------------------------------------------------------------------------


def _parse_env_value(raw: str, file: Path, line: int) -> str:
    first = raw[:1]
    if first not in ("'", '"'):
        return raw.split("#", 1)[0].strip()
    if len(raw) < 2 or raw[-1] != first:
        raise InvalidProfileError(f"{file}:{line}: invalid quoted value")
    inner = raw[1:-1]
    if first == "'":
        return inner
    value: list[str] = []
    escaped = False
    for character in inner:
        if escaped:
            if character == "n":
                value.append("\n")
            elif character == "t":
                value.append("\t")
            else:
                value.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        else:
            value.append(character)
    if escaped:
        value.append("\\")
    return "".join(value)


def parse_env_profile(file: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    content = file.read_text(encoding="utf-8")
    for offset, raw_line in enumerate(content.splitlines()):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        equals = line.find("=")
        if equals < 0:
            raise InvalidProfileError(f"{file}:{offset + 1}: expected KEY=value")
        key = line[:equals].strip()
        if not PROFILE_KEY_RE.match(key):
            raise InvalidProfileError(f"{file}:{offset + 1}: invalid profile key {key}")
        values[key] = _parse_env_value(line[equals + 1:].strip(), file, offset + 1)
    return values


def parse_json_profile(file: Path) -> dict[str, str]:
    try:
        parsed = json.loads(file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise InvalidProfileError(f"Profile JSON is invalid: {file}: {error}") from error
    if not isinstance(parsed, dict):
        raise InvalidProfileError(f"Profile JSON must be an object: {file}")
    values: dict[str, str] = {}
    for key, value in parsed.items():
        if not PROFILE_KEY_RE.match(key):
            raise InvalidProfileError(f"{file}: invalid profile key {key}")
        if isinstance(value, str):
            values[key] = value
        elif isinstance(value, bool):
            # NSNumber.stringValue renders booleans as 1/0.
            values[key] = "1" if value else "0"
        elif isinstance(value, (int, float)):
            values[key] = str(value)
        elif value is None:
            values[key] = ""
        elif isinstance(value, (list, dict)):
            values[key] = json.dumps(value, separators=(",", ":"))
        else:
            values[key] = str(value)
    return values


@dataclass
class Profile:
    name: str
    values: dict[str, str]

    def __post_init__(self) -> None:
        normalized = dict(self.values)
        normalized.setdefault("PROFILE_NAME", self.name)
        normalized.setdefault("DISPLAY_NAME", self.name)
        request_model = normalized.get("REQUEST_MODEL", "")
        if not request_model:
            raise InvalidProfileError(f"{self.name}: missing REQUEST_MODEL")
        if not normalized.get("PORT") and not normalized.get("BASE_URL"):
            raise InvalidProfileError(f"{self.name}: missing PORT or BASE_URL")
        self.values = normalized

    def get(self, key: str) -> str | None:
        return self.values.get(key)

    @property
    def display_name(self) -> str:
        return self.values.get("DISPLAY_NAME", self.name)

    @property
    def runtime(self) -> str:
        return canonical_runtime(self.values.get("RUNTIME"))

    @property
    def runtime_spec(self) -> tuple[str, list[str], str]:
        label, tags, launch_mode = RUNTIME_SPECS.get(
            self.runtime, (self.runtime, ["managed", "custom"], "adapter")
        )
        if self.values.get("START_COMMAND"):
            launch_mode = "command"
        elif self.values.get("LAUNCH_MODE"):
            launch_mode = self.values["LAUNCH_MODE"].lower()
        return label, tags, launch_mode

    @property
    def runtime_tags(self) -> list[str]:
        configured = (
            (self.values.get("RUNTIME_TAGS") or self.values.get("TAGS") or "")
            .replace(",", " ")
            .split()
        )
        _, spec_tags, _ = self.runtime_spec
        result: list[str] = []
        for tag in [self.runtime] + spec_tags + [tag.lower() for tag in configured]:
            if tag not in result:
                result.append(tag)
        return result

    @property
    def request_model(self) -> str:
        return self.values.get("REQUEST_MODEL", self.name)

    @property
    def server_model_id(self) -> str:
        return self.values.get("SERVER_MODEL_ID") or self.request_model

    @property
    def healthcheck_mode(self) -> str:
        return (self.values.get("HEALTHCHECK_MODE") or "openai-models").lower()

    @property
    def endpoint_host(self) -> str:
        host = self.values.get("HOST", "")
        if host:
            return host
        parsed = urllib.parse.urlparse(self.base_url)
        return parsed.hostname or "127.0.0.1"

    @property
    def endpoint_port(self) -> str:
        port = self.values.get("PORT", "")
        if port:
            return port
        parsed = urllib.parse.urlparse(self.base_url)
        return str(parsed.port) if parsed.port else ""

    @property
    def base_url(self) -> str:
        configured = (self.values.get("BASE_URL") or "").strip()
        if configured:
            return configured.rstrip("/") if configured.endswith("/") else configured
        port = self.values.get("PORT", "")
        if not port:
            return ""
        configured_host = (self.values.get("HOST") or "127.0.0.1").strip()
        host = configured_host if is_loopback(configured_host) else "127.0.0.1"
        literal = f"[{host}]" if ":" in host and not host.startswith("[") else host
        return f"http://{literal}:{port}/v1"

    @property
    def healthcheck_url(self) -> str:
        configured = self.values.get("HEALTHCHECK_URL", "")
        if configured:
            return configured
        if self.healthcheck_mode == "openai-models":
            model_list = self.values.get("MODEL_LIST_URL", "")
            if model_list:
                return model_list
            return f"{self.base_url}/models" if self.base_url else ""
        return self.base_url

    @property
    def log_path(self) -> str:
        raw = self.values.get("LOG_ALIAS") or self.values.get("MODEL_ALIAS") or self.name
        safe = "".join(c if c.isalnum() or c in "_.-" else "_" for c in raw)
        return f"/tmp/{safe}.log"

    @property
    def endpoint_identity(self) -> str | None:
        if not self.endpoint_port:
            return None
        host = self.endpoint_host
        host = "localhost" if is_loopback(host) else host.strip("[]").lower()
        return f"{host}:{self.endpoint_port}"

    @property
    def working_directory(self) -> Path | None:
        raw = self.values.get("WORKING_DIRECTORY") or self.values.get("WORKDIR")
        if not raw:
            return None
        return Path(raw).expanduser()


class ProfileRepository:
    def __init__(self, directory: Path):
        self.directory = directory

    def load(self) -> dict[str, Profile]:
        if not self.directory.is_dir():
            return {}
        profiles: dict[str, Profile] = {}
        files = sorted(
            (
                path
                for path in self.directory.iterdir()
                if path.suffix.lower() in (".env", ".json") and not path.name.startswith(".")
            ),
            key=lambda path: path.name.lower(),
        )
        for file in files:
            name = file.stem
            values = (
                parse_json_profile(file)
                if file.suffix.lower() == ".json"
                else parse_env_profile(file)
            )
            profiles[name] = Profile(name=name, values=values)
        return profiles

    def profile(self, name: str) -> Profile:
        profile = self.load().get(name)
        if profile is None:
            raise ProfileNotFoundError(name)
        return profile

    def conflicts(self, profiles: dict[str, Profile]) -> dict[str, tuple[str, list[str]]]:
        groups: dict[str, list[str]] = {}
        for profile in profiles.values():
            identity = profile.endpoint_identity
            if identity:
                groups.setdefault(identity, []).append(profile.name)
        result: dict[str, tuple[str, list[str]]] = {}
        for endpoint, names in groups.items():
            if len(names) > 1:
                for name in sorted(names):
                    result[name] = (endpoint, sorted(n for n in names if n != name))
        return result

    def ensure_unique(self, name: str, action: str, profiles: dict[str, Profile]) -> None:
        conflict = self.conflicts(profiles).get(name)
        if conflict:
            endpoint, others = conflict
            raise ProfileConflictError(
                f"Cannot {action} {name}: endpoint {endpoint} is also configured for {', '.join(others)}."
            )


# --------------------------------------------------------------------------
# Launch command templates
# --------------------------------------------------------------------------


def build_start_command(profile: Profile) -> str:
    """Return the shell command that launches this profile's model server."""
    explicit = (profile.get("START_COMMAND") or "").strip()
    if explicit:
        return explicit
    if (profile.get("LAUNCH_MODE") or "").lower() == "external":
        raise UnsupportedError(
            f"{profile.name}: externally managed endpoint; set START_COMMAND or a launch claim to start"
        )

    runtime = profile.runtime
    host = profile.get("HOST") or "127.0.0.1"
    port = profile.endpoint_port
    extra = (profile.get("EXTRA_ARGS") or "").strip()
    model = profile.get("MODEL_PATH") or profile.get("MODEL_REPO") or profile.request_model
    model_file = profile.get("MODEL_FILE") or profile.get("MODEL_PATH") or ""

    if runtime == "vllm":
        command = (
            f"vllm serve {shlex.quote(model)} --host {shlex.quote(host)} --port {shlex.quote(port)}"
            f" --served-model-name {shlex.quote(profile.server_model_id)}"
        )
    elif runtime == "llama.cpp":
        if not model_file:
            raise InvalidProfileError(
                f"{profile.name}: llama.cpp launches need MODEL_FILE (or MODEL_PATH) or an explicit START_COMMAND"
            )
        command = (
            f"llama-server -m {shlex.quote(model_file)} --host {shlex.quote(host)}"
            f" --port {shlex.quote(port)} -a {shlex.quote(profile.server_model_id)}"
        )
    elif runtime == "sglang":
        command = (
            f"python3 -m sglang.launch_server --model-path {shlex.quote(model)}"
            f" --host {shlex.quote(host)} --port {shlex.quote(port)}"
        )
    elif runtime == "tgi":
        command = (
            f"text-generation-launcher --model-id {shlex.quote(model)}"
            f" --hostname {shlex.quote(host)} --port {shlex.quote(port)}"
        )
    else:
        _, _, launch_mode = profile.runtime_spec
        if launch_mode == "external":
            raise UnsupportedError(
                f"{profile.name}: runtime {runtime} is externally managed; the agent only reports its health"
            )
        raise InvalidProfileError(
            f"{profile.name}: no launch template for runtime {runtime}; set START_COMMAND"
        )

    if extra:
        command = f"{command} {extra}"
    venv = (profile.get("VENV") or "").strip()
    if venv:
        activate = Path(venv).expanduser() / "bin" / "activate"
        command = f"source {shlex.quote(str(activate))} && {command}"
    return command


# --------------------------------------------------------------------------
# Process helpers
# --------------------------------------------------------------------------


def process_stat_state(pid: int) -> str | None:
    """Return the single-letter process state from /proc, or None if missing.

    Linux: R/S/D/T/Z/...  Z means zombie (defunct). macOS has no /proc; callers
    fall back to `ps` via process_ps_state.
    """
    try:
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    except OSError:
        return None
    # comm may contain spaces/parens; state is the field after the closing ')'.
    close = raw.rfind(")")
    if close < 0:
        return None
    parts = raw[close + 1 :].split()
    return parts[0] if parts else None


def process_ps_state(pid: int) -> str | None:
    """Single-letter state via `ps` (non-Linux /proc miss fallback only)."""
    try:
        result = subprocess.run(
            ["ps", "-o", "state=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    state = result.stdout.strip()
    return state[:1] if state else None


def _proc_stat_table_available() -> bool:
    """True when Linux-style /proc/<pid>/stat is the process table.

    When True, a missing /proc/<pid>/stat means the pid is gone — no need for
    `ps` or kill(0). When False (macOS, restricted mounts), fall back.
    """
    try:
        return Path("/proc/self/stat").is_file()
    except OSError:
        return False


def process_is_zombie(pid: int | None) -> bool:
    """True if *pid* is a defunct/zombie process.

    Linux: one /proc/<pid>/stat read. Missing entry with /proc present ⇒ not a
    zombie (gone). Otherwise `ps -o state=` fallback.
    """
    if not pid or pid <= 0:
        return False
    state = process_stat_state(pid)
    if state is not None:
        return state.upper().startswith("Z")
    if _proc_stat_table_available():
        return False
    state = process_ps_state(pid)
    if state is None:
        return False
    return state.upper().startswith("Z")


def reap_child(pid: int) -> bool:
    """Reap *pid* if it is our zombie/exited child. True if reaped or gone."""
    try:
        reaped, _ = os.waitpid(pid, os.WNOHANG)
        return reaped == pid
    except ChildProcessError:
        return False
    except OSError:
        return False


def process_is_alive(pid: int | None) -> bool:
    """True only for a live (non-zombie) process.

    Defunct/zombie PIDs are treated as dead: they hold no GPU/CPU work and
    must not keep status.running true or block stop.

    Linux: one /proc/<pid>/stat read decides existence + zombie without kill/ps.
    Other platforms (or no /proc): ps state, then kill(0) existence probe.
    """
    if not pid or pid <= 0:
        return False
    # Reap our own children first so unreaped zombies do not linger.
    if reap_child(pid):
        return False
    state = process_stat_state(pid)
    if state is not None:
        # Authoritative on Linux: Z is not "running"; any other letter is live.
        return not state.upper().startswith("Z")
    if _proc_stat_table_available():
        # /proc is the process table and this pid has no entry ⇒ dead.
        return False
    # No /proc (macOS, etc.): ps state, then kill(0).
    state = process_ps_state(pid)
    if state is not None:
        return not state.upper().startswith("Z")
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Exists but we cannot signal it; state probes already failed.
        return True
    return True


def process_lifecycle_state(pid: int | None, *, ready: bool = False) -> str:
    """Coarse lifecycle for status payloads: ready|running|zombie|dead."""
    if ready:
        return "ready"
    if not pid or pid <= 0:
        return "dead"
    if reap_child(pid):
        return "dead"
    if process_is_zombie(pid):
        return "zombie"
    if process_is_alive(pid):
        return "running"
    return "dead"


def _signal_process_tree(pid: int, signal_number: int) -> None:
    try:
        pgid = os.getpgid(pid)
        if pgid > 0 and pgid != os.getpgrp():
            os.killpg(pgid, signal_number)
            return
    except ProcessLookupError:
        return
    except PermissionError:
        pass
    try:
        os.kill(pid, signal_number)
    except (ProcessLookupError, PermissionError):
        pass


def terminate_process_tree(
    pid: int,
    timeout: float = TERMINATE_TIMEOUT_SECONDS,
    *,
    force: bool = False,
) -> None:
    """SIGTERM process group, wait, then SIGKILL. Always attempt to reap."""
    if force:
        _signal_process_tree(pid, signal.SIGKILL)
        deadline = time.monotonic() + min(timeout, FORCE_TERMINATE_TIMEOUT_SECONDS)
        while time.monotonic() < deadline and process_is_alive(pid):
            reap_child(pid)
            time.sleep(0.1)
        reap_child(pid)
        return

    _signal_process_tree(pid, signal.SIGTERM)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and process_is_alive(pid):
        reap_child(pid)
        time.sleep(0.2)
    if process_is_alive(pid):
        _signal_process_tree(pid, signal.SIGKILL)
        kill_deadline = time.monotonic() + FORCE_TERMINATE_TIMEOUT_SECONDS
        while time.monotonic() < kill_deadline and process_is_alive(pid):
            reap_child(pid)
            time.sleep(0.1)
    reap_child(pid)


def process_command(pid: int | None) -> str | None:
    """Return the process command line for *pid*, or None.

    Linux: read /proc/<pid>/cmdline (NUL-separated → spaces) without spawning.
    Other platforms, or empty/missing /proc entry: fall back to `ps -o command=`.
    """
    if not pid:
        return None
    # Prefer /proc on Linux -- avoids one `ps` subprocess per listener PID.
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        raw = b""
    if raw:
        command = raw.replace(b"\x00", b" ").decode("utf-8", errors="replace").strip()
        if command:
            return command
    try:
        result = subprocess.run(
            ["ps", "-o", "command=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    command = result.stdout.strip()
    return command or None


def process_rss_mb(pid: int | None) -> float | None:
    """Return resident set size in MB for *pid*, or None.

    Linux: parse VmRSS from /proc/<pid>/status (kB) without spawning.
    Other platforms, or missing /proc entry: fall back to `ps -o rss=`.
    Rounding matches the historical `ps` path: one decimal place.
    """
    if not pid:
        return None
    # Prefer /proc on Linux -- avoids one `ps` subprocess per listener PID.
    try:
        status = Path(f"/proc/{pid}/status").read_text(encoding="utf-8")
    except OSError:
        status = ""
    if status:
        for line in status.splitlines():
            if line.startswith("VmRSS:"):
                parts = line.split()
                if len(parts) >= 2:
                    try:
                        rss_kb = float(parts[1])
                    except ValueError:
                        break
                    return round(rss_kb / 1024 * 10) / 10
                break
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5, check=False,
        )
        rss_kb = float(result.stdout.strip())
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return round(rss_kb / 1024 * 10) / 10



# -- host / GPU metrics ----------------------------------------------------

_GPU_METRICS_CACHE: dict[str, Any] = {"at": 0.0, "payload": None}
_GPU_METRICS_TTL_SECONDS = 2.0
_CPU_SAMPLE_LOCK = threading.Lock()
_CPU_PREV: tuple[float, float] | None = None  # (total, idle)


def _read_proc_meminfo() -> dict[str, int]:
    """Return /proc/meminfo keys in kB (Linux). Empty on non-Linux."""
    out: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            if ":" not in line:
                continue
            key, rest = line.split(":", 1)
            parts = rest.split()
            if parts:
                try:
                    out[key] = int(parts[0])
                except ValueError:
                    pass
    except OSError:
        return {}
    return out


def _sample_cpu_percent() -> float | None:
    """Busy CPU % from /proc/stat deltas, or loadavg fallback."""
    global _CPU_PREV
    try:
        first = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0]
    except OSError:
        first = ""
    if first.startswith("cpu "):
        parts = first.split()
        try:
            # user nice system idle iowait irq softirq steal ...
            nums = [float(x) for x in parts[1:8]]
        except ValueError:
            nums = []
        if len(nums) >= 4:
            idle = nums[3] + (nums[4] if len(nums) > 4 else 0.0)
            total = sum(nums)
            with _CPU_SAMPLE_LOCK:
                prev = _CPU_PREV
                _CPU_PREV = (total, idle)
            if prev is not None:
                d_total = total - prev[0]
                d_idle = idle - prev[1]
                if d_total > 0:
                    busy = max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100.0))
                    return round(busy * 10) / 10
            return None
    try:
        load1, _, _ = os.getloadavg()
        cpus = os.cpu_count() or 1
        return round(min(100.0, (load1 / cpus) * 100.0) * 10) / 10
    except OSError:
        return None


def _sample_memory() -> dict[str, Any]:
    info = _read_proc_meminfo()
    if info.get("MemTotal"):
        total_kb = info["MemTotal"]
        # Match common "used" definition: total - free - buffers - cached
        free_kb = info.get("MemFree", 0)
        buffers_kb = info.get("Buffers", 0)
        cached_kb = info.get("Cached", 0) + info.get("SReclaimable", 0)
        used_kb = max(0, total_kb - free_kb - buffers_kb - cached_kb)
        total_mb = total_kb / 1024
        used_mb = used_kb / 1024
        percent = (used_kb / total_kb) * 100.0 if total_kb else None
        return {
            "used_mb": round(used_mb * 10) / 10,
            "total_mb": round(total_mb * 10) / 10,
            "percent": round(percent * 10) / 10 if percent is not None else None,
            "source": "proc",
        }
    # Fallback: no absolute numbers without platform APIs.
    return {
        "used_mb": None,
        "total_mb": None,
        "percent": None,
        "source": "unavailable",
    }


def _run_nvidia_smi_query() -> dict[str, Any] | None:
    """Query nvidia-smi once. Returns None when the binary/driver is absent."""
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                "--query-gpu=index,name,utilization.gpu,temperature.gpu,memory.used,memory.total",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    gpus: list[dict[str, Any]] = []
    for line in result.stdout.splitlines():
        parts = [p.strip() for p in line.split(",")]
        if len(parts) < 6:
            continue
        try:
            index = int(parts[0])
            util = float(parts[2]) if parts[2] not in ("", "[N/A]", "N/A") else None
            temp = float(parts[3]) if parts[3] not in ("", "[N/A]", "N/A") else None
            used = float(parts[4]) if parts[4] not in ("", "[N/A]", "N/A") else None
            total = float(parts[5]) if parts[5] not in ("", "[N/A]", "N/A") else None
        except ValueError:
            continue
        gpus.append(
            {
                "index": index,
                "name": parts[1],
                "util_percent": util,
                "temp_c": temp,
                "vram_used_mb": used,
                "vram_total_mb": total,
            }
        )
    # Per-process VRAM (compute apps).
    by_pid: dict[int, float] = {}
    try:
        proc_result = subprocess.run(
            [
                "nvidia-smi",
                "--query-compute-apps=pid,used_gpu_memory",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if proc_result.returncode == 0:
            for line in proc_result.stdout.splitlines():
                parts = [p.strip() for p in line.split(",")]
                if len(parts) < 2:
                    continue
                try:
                    pid = int(parts[0])
                    mem = float(parts[1]) if parts[1] not in ("", "[N/A]", "N/A") else None
                except ValueError:
                    continue
                if mem is not None:
                    by_pid[pid] = by_pid.get(pid, 0.0) + mem
    except (OSError, subprocess.TimeoutExpired):
        pass
    return {"gpus": gpus, "vram_by_pid": by_pid, "source": "nvidia-smi"}


def gpu_metrics_snapshot() -> dict[str, Any]:
    """Cached GPU snapshot for status rows + /api/host/metrics."""
    now = time.time()
    cached = _GPU_METRICS_CACHE.get("payload")
    if cached is not None and now - float(_GPU_METRICS_CACHE.get("at") or 0) < _GPU_METRICS_TTL_SECONDS:
        return cached
    nvidia = _run_nvidia_smi_query()
    if nvidia is None:
        payload = {"gpus": [], "vram_by_pid": {}, "source": "unavailable"}
    else:
        payload = nvidia
    _GPU_METRICS_CACHE["at"] = now
    _GPU_METRICS_CACHE["payload"] = payload
    return payload


def process_vram_mb(pid: int | None) -> float | None:
    """GPU memory (MiB) attributed to *pid* via nvidia-smi, if available."""
    if not pid:
        return None
    snap = gpu_metrics_snapshot()
    by_pid = snap.get("vram_by_pid") or {}
    value = by_pid.get(int(pid))
    if value is None:
        return None
    return round(float(value) * 10) / 10


def host_metrics_payload() -> dict[str, Any]:
    """SparkDash-like host snapshot for the Mac Remote Hosts panel.

    Units:
    - CPU/GPU util: percent 0-100
    - temp: Celsius
    - memory/VRAM: megabytes (MiB from nvidia-smi; MB from /proc)
    Graceful when nvidia-smi or /proc are absent (old agent / non-GPU host).

    When MSW_PERF_PROFILE=1 or MSW_AGENT_PERF=1, emits perf.profile.span_summary
    on stderr (measurement only; no behavior change when flags are off).
    """
    with _PerfSpan("host_metrics_payload") as span:
        span.stage("gpu")
        gpu = gpu_metrics_snapshot()
        span.stage("memory")
        mem = _sample_memory()
        span.stage("cpu")
        cpu_percent = _sample_cpu_percent()
        span.stage("assemble")
        hostname = socket.gethostname()
        gpus = gpu.get("gpus") or []
        gpu_source = gpu.get("source") or "unavailable"
        span.tags["gpu_source"] = gpu_source
        span.tags["n_gpus"] = len(gpus)
        return {
            "host": hostname,
            "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "cpu_percent": cpu_percent,
            "memory": mem,
            "gpus": gpus,
            "gpu_source": gpu_source,
            "processes": [
                {"pid": pid, "vram_mb": round(float(mb) * 10) / 10}
                for pid, mb in sorted((gpu.get("vram_by_pid") or {}).items())
            ],
            "agent_version": AGENT_VERSION,
        }


def port_is_listening(port: str) -> bool:
    """Fast loopback connect check; lsof/ss are far too slow to poll."""
    if not port:
        return False
    try:
        with socket.create_connection(("127.0.0.1", int(port)), timeout=0.25):
            return True
    except (OSError, ValueError):
        return False


def listener_pid(port: str) -> int | None:
    if not port or not port_is_listening(port):
        return None
    try:
        result = subprocess.run(
            ["lsof", f"-tiTCP:{port}", "-sTCP:LISTEN"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        pids = [int(line) for line in result.stdout.split() if line.strip().isdigit()]
        if pids:
            return pids[0]
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        result = subprocess.run(
            ["ss", "-tlnpH", f"sport = :{port}"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        match = re.search(r"pid=(\d+)", result.stdout)
        if match:
            return int(match.group(1))
    except (OSError, subprocess.TimeoutExpired):
        pass
    return None


def port_listening_from_inventory(
    port: str | int,
    listeners: list[dict[str, Any]],
) -> bool:
    """True when *port* appears in an existing list_listening_tcp snapshot.

    Prefer this on status_payload hot paths that already paid for one inventory
    (ss/lsof). Avoids N× loopback connect checks. Incomplete only if the
    snapshot is stale (same lag as LISTENING_TCP_CACHE_TTL_SECONDS).
    """
    try:
        want = int(port)
    except (TypeError, ValueError):
        return False
    for row in listeners:
        try:
            if int(row.get("port", -1)) == want:
                return True
        except (TypeError, ValueError):
            continue
    return False


def listener_pid_from_inventory(
    port: str | int,
    listeners: list[dict[str, Any]],
) -> int | None:
    """Owning LISTEN pid from inventory, or None if absent / unknown.

    No socket connect and no per-port lsof/ss. Used when status already holds
    a shared listeners snapshot. stop/start keep calling listener_pid() for
    live accuracy.
    """
    try:
        want = int(port)
    except (TypeError, ValueError):
        return None
    for row in listeners:
        try:
            if int(row.get("port", -1)) != want:
                continue
        except (TypeError, ValueError):
            continue
        pid = row.get("pid")
        if pid is None:
            return None
        try:
            return int(pid)
        except (TypeError, ValueError):
            return None
    return None


# --------------------------------------------------------------------------
# Host discovery (Ports-style listening + portable port claims)
# --------------------------------------------------------------------------
# Never hardcode a host's layout (no /data/launch, no fixed product ports).
# Sources of truth, in order of trust for identity:
#   1) user-authored Switchboard profiles (.env/.json)
#   2) live process cmdline + /v1/models|/health probes
#   3) portable "claimed port" folders: any dir named <port> that contains
#      launch/flags markers, wherever the user put them
# --------------------------------------------------------------------------


def _configured_scan_roots(agent_root: Path | None = None) -> list[Path]:
    """Env + optional config.json scan_roots — never product-specific defaults."""
    roots: list[Path] = []
    raw = (os.environ.get(SCAN_ROOTS_ENV) or "").strip()
    if raw:
        for part in raw.split(":"):
            part = part.strip()
            if part:
                roots.append(Path(part).expanduser())
    if agent_root is not None:
        configured = load_agent_config(agent_root).get("scan_roots")
        if isinstance(configured, str) and configured.strip():
            roots.append(Path(configured).expanduser())
        elif isinstance(configured, list):
            for item in configured:
                if isinstance(item, str) and item.strip():
                    roots.append(Path(item).expanduser())
    return roots


def parse_loose_env_assignments(file: Path) -> dict[str, str]:
    """Parse KEY=value including bash ${VAR:-default} defaults — no shell exec."""
    try:
        content = file.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return {}
    values: dict[str, str] = {}
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        equals = line.find("=")
        if equals <= 0:
            continue
        key = line[:equals].strip()
        if not PROFILE_KEY_RE.match(key):
            continue
        rest = line[equals + 1 :].strip()
        if " #" in rest and not (rest[:1] in "'\"" and rest.endswith(rest[:1])):
            rest = rest.split(" #", 1)[0].rstrip()
        if rest.startswith("#"):
            continue
        if len(rest) >= 2 and rest[0] == rest[-1] and rest[0] in "'\"":
            rest = rest[1:-1]
        match = SHELL_DEFAULT_RE.fullmatch(rest)
        if match:
            rest = match.group(1)
            # Unescape common shell sequences inside the default.
            rest = rest.replace("\\$", "$").replace("\\\"", '"').replace("\\'", "'")
        elif rest.startswith("$"):
            # Unresolved reference with no default — skip.
            continue
        values[key] = rest
    return values


# Inventory cache: (monotonic_ts, rows). Thread-safe for ThreadingHTTPServer;
# concurrent callers may share a snapshot that lags ≤LISTENING_TCP_CACHE_TTL_SECONDS.
# list_listening_tcp always returns a caller-private shallow copy so handlers
# cannot mutate cached rows. Misses fill under the lock (no stampede / DCL race
# with clear_listening_tcp_cache mid-inventory).
_listening_tcp_cache_lock = threading.Lock()
_listening_tcp_cache: tuple[float, list[dict[str, Any]]] | None = None


def clear_listening_tcp_cache() -> None:
    """Drop the short-TTL list_listening_tcp cache (tests / forced refresh)."""
    global _listening_tcp_cache
    with _listening_tcp_cache_lock:
        _listening_tcp_cache = None


def _copy_listening_tcp_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Caller-private copy of inventory rows (list + per-row dict)."""
    return [dict(row) for row in rows]


def list_listening_tcp() -> list[dict[str, Any]]:
    """Inventory local TCP listeners with pid/command when available.

    Mirrors the Ports.app idea: port + owning process + command line.

    Order per uncached call:
      1. Linux `/proc/net/tcp` + `/proc/net/tcp6` (no spawn; inode→pid via
         `/proc/*/fd`) when `/proc/net/tcp` is readable.
      2. `ss -lntupH` (Linux) when /proc path is unavailable.
      3. `lsof` when still empty (macOS / sparse ss).

    Command lines are resolved once per unique PID via process_command within
    that inventory -- no longer-lived process_command cache. Ports in
    SKIP_LISTEN_PORTS and the agent self listener (DEFAULT_PORT + own pid) skip
    cmdline resolution; command may be None for those rows. Same pid on a
    non-skip port still resolves when that row is seen.

    Module-level cache (LISTENING_TCP_CACHE_TTL_SECONDS, default 2.0s) so
    concurrent or back-to-back status/ports polls in the same process skip
    re-running inventory. Results may lag ≤TTL -- intentional for poll
    coalescing (UI active refresh is ~10s; 2s covers rapid re-polls and
    multi-caller bursts). Each call returns a fresh list of dicts (safe under
    ThreadingHTTPServer if a handler mutates its result).
    """
    global _listening_tcp_cache
    now = time.monotonic()
    with _listening_tcp_cache_lock:
        cached = _listening_tcp_cache
        if cached is not None and (now - cached[0]) < LISTENING_TCP_CACHE_TTL_SECONDS:
            return _copy_listening_tcp_rows(cached[1])
        # Hold the lock across inventory so concurrent misses coalesce into one
        # fill and clear_listening_tcp_cache cannot interleave mid-write.
        result = _list_listening_tcp_uncached()
        _listening_tcp_cache = (now, result)
        return _copy_listening_tcp_rows(result)


# /proc/net/tcp{,6} connection state: TCP_LISTEN
_PROC_TCP_LISTEN_STATE = "0A"


def _decode_proc_net_ip(addr_hex: str, *, ipv6: bool) -> str:
    """Decode a /proc/net/tcp{,6} local address field to a presentation string."""
    if not ipv6:
        try:
            value = int(addr_hex, 16)
        except ValueError:
            return addr_hex
        # Little-endian 32-bit host word → dotted IPv4.
        return (
            f"{value & 0xFF}."
            f"{(value >> 8) & 0xFF}."
            f"{(value >> 16) & 0xFF}."
            f"{(value >> 24) & 0xFF}"
        )
    # IPv6: eight-hex-digit words, each little-endian on the host.
    cleaned = addr_hex.strip()
    if len(cleaned) != 32:
        return cleaned
    try:
        words: list[str] = []
        for index in range(0, 32, 8):
            word = cleaned[index : index + 8]
            # Reverse byte pairs within the 32-bit word.
            words.append("".join(word[j : j + 2] for j in range(6, -1, -2)))
        packed = bytes.fromhex("".join(words))
        return socket.inet_ntop(socket.AF_INET6, packed)
    except (ValueError, OSError):
        return cleaned


def _parse_proc_net_tcp_table(
    text: str, *, ipv6: bool = False
) -> list[tuple[int, str, int]]:
    """Parse /proc/net/tcp or tcp6 into (port, bind, inode) LISTEN rows."""
    rows: list[tuple[int, str, int]] = []
    lines = text.splitlines()
    if len(lines) < 2:
        return rows
    for line in lines[1:]:
        parts = line.split()
        # sl local_address rem_address st ... inode (index 9)
        if len(parts) < 10:
            continue
        if parts[3] != _PROC_TCP_LISTEN_STATE:
            continue
        local = parts[1]
        if ":" not in local:
            continue
        ip_hex, port_hex = local.rsplit(":", 1)
        try:
            port = int(port_hex, 16)
            inode = int(parts[9])
        except ValueError:
            continue
        if port <= 0 or port > 65535:
            continue
        bind = _decode_proc_net_ip(ip_hex, ipv6=ipv6)
        rows.append((port, bind, inode))
    return rows


def _socket_inodes_to_pids(
    proc_root: Path, needed: set[int] | None = None
) -> dict[int, int]:
    """Map socket inode → owning pid by reading ``proc_root/*/fd`` symlinks.

    When *needed* is provided, stop once every requested inode is resolved
    (typical: only the LISTEN sockets from /proc/net/tcp — far fewer than all
    open sockets on the box).
    """
    mapping: dict[int, int] = {}
    remaining: set[int] | None = set(needed) if needed is not None else None
    try:
        entries = os.listdir(proc_root)
    except OSError:
        return mapping
    for name in entries:
        if remaining is not None and not remaining:
            break
        if not name.isdigit():
            continue
        pid = int(name)
        fd_dir = proc_root / name / "fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd_name in fds:
            try:
                target = os.readlink(fd_dir / fd_name)
            except OSError:
                continue
            if not (target.startswith("socket:[") and target.endswith("]")):
                continue
            try:
                inode = int(target[8:-1])
            except ValueError:
                continue
            if remaining is not None and inode not in remaining:
                continue
            # First owner wins (matches typical ss "one pid" presentation).
            if inode not in mapping:
                mapping[inode] = pid
                if remaining is not None:
                    remaining.discard(inode)
                    if not remaining:
                        break
    return mapping


def _linux_proc_listening_endpoints(
    proc_root: Path | None = None,
) -> list[tuple[int, int | None, str]] | None:
    """Linux /proc inventory of TCP listeners as (port, pid, bind).

    Returns None when ``/proc/net/tcp`` is not readable so callers fall back to
    ss/lsof (macOS, restricted containers). An empty list means the table was
    readable and there are simply no LISTEN sockets.
    """
    root = proc_root if proc_root is not None else Path("/proc")
    tcp_path = root / "net" / "tcp"
    try:
        tcp_text = tcp_path.read_text(encoding="utf-8")
    except OSError:
        return None

    table = _parse_proc_net_tcp_table(tcp_text, ipv6=False)
    tcp6_path = root / "net" / "tcp6"
    try:
        table.extend(
            _parse_proc_net_tcp_table(
                tcp6_path.read_text(encoding="utf-8"), ipv6=True
            )
        )
    except OSError:
        pass

    need_inodes = {inode for _, _, inode in table if inode > 0}
    inode_to_pid = (
        _socket_inodes_to_pids(root, needed=need_inodes) if need_inodes else {}
    )

    endpoints: list[tuple[int, int | None, str]] = []
    for port, bind, inode in table:
        pid: int | None = None
        if inode > 0:
            pid = inode_to_pid.get(inode)
        endpoints.append((port, pid, bind))
    return endpoints


def _list_listening_tcp_uncached() -> list[dict[str, Any]]:
    by_port: dict[int, dict[str, Any]] = {}
    # Same PID often owns several binds (IPv4+IPv6, multi-port). Resolve once.
    cmd_by_pid: dict[int, str | None] = {}
    self_pid = os.getpid()

    def cmdline(pid: int | None, *, port: int) -> str | None:
        if not pid:
            return None
        # System / clearly non-model ports and this agent: no /proc|ps.
        # Do not cache a miss for skip ports -- same pid may need resolve later.
        if port in SKIP_LISTEN_PORTS or (port == DEFAULT_PORT and pid == self_pid):
            return cmd_by_pid.get(pid)
        if pid not in cmd_by_pid:
            cmd_by_pid[pid] = process_command(pid)
        return cmd_by_pid[pid]

    def note(port: int, pid: int | None, command: str | None, bind: str) -> None:
        if port <= 0 or port > 65535:
            return
        existing = by_port.get(port)
        if existing is None:
            by_port[port] = {
                "port": port,
                "pid": pid,
                "command": command,
                "bind": bind,
            }
            return
        if existing.get("pid") is None and pid is not None:
            existing["pid"] = pid
        if not existing.get("command") and command:
            existing["command"] = command
        if bind and bind not in (existing.get("bind") or ""):
            existing["bind"] = bind

    # Prefer pure /proc on Linux -- avoids ss spawn (rank-1 after ps→/proc).
    proc_endpoints = _linux_proc_listening_endpoints()
    if proc_endpoints is not None:
        for port, pid, bind in proc_endpoints:
            note(port, pid, cmdline(pid, port=port), bind)
        return [by_port[key] for key in sorted(by_port)]

    # Linux ss: State Recv-Q Send-Q Local Address:Port Peer Address:Port Process
    try:
        result = subprocess.run(
            ["ss", "-lntupH"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        for line in result.stdout.splitlines():
            # Local address is usually field 4.
            parts = line.split()
            if len(parts) < 4:
                continue
            local = parts[3]
            if local.startswith("%"):
                continue
            # Formats: 127.0.0.1:8080, *:8080, [::1]:8080, [::]:8080
            port = _parse_local_port(local)
            if port is None:
                continue
            bind = local.rsplit(":", 1)[0].strip("[]") if ":" in local else local
            pid = None
            pid_match = re.search(r"pid=(\d+)", line)
            if pid_match:
                pid = int(pid_match.group(1))
            note(port, pid, cmdline(pid, port=port), bind)
    except (OSError, subprocess.TimeoutExpired):
        pass

    if not by_port:
        try:
            result = subprocess.run(
                ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"],
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            for line in result.stdout.splitlines()[1:]:
                parts = line.split()
                if len(parts) < 9:
                    continue
                try:
                    pid = int(parts[1])
                except ValueError:
                    pid = None
                name = parts[8]
                port = _parse_local_port(name)
                if port is None:
                    continue
                bind = name.rsplit(":", 1)[0].strip("[]") if ":" in name else name
                note(port, pid, cmdline(pid, port=port), bind)
        except (OSError, subprocess.TimeoutExpired):
            pass

    return [by_port[key] for key in sorted(by_port)]


def _parse_local_port(local: str) -> int | None:
    local = local.strip()
    if not local:
        return None
    # [ipv6]:port
    if local.startswith("["):
        close = local.find("]")
        if close > 0 and close + 1 < len(local) and local[close + 1] == ":":
            try:
                return int(local[close + 2 :])
            except ValueError:
                return None
    if local.count(":") == 1:
        try:
            return int(local.rsplit(":", 1)[1])
        except ValueError:
            return None
    # bare :port
    if local.startswith(":") and local[1:].isdigit():
        return int(local[1:])
    return None


def command_looks_like_model_server(command: str | None) -> bool:
    if not command:
        return False
    lowered = command.lower()
    return any(marker in lowered for marker in MODEL_SERVER_COMMAND_MARKERS)


def infer_runtime_from_command(command: str | None) -> str:
    """Best-effort runtime label from a live process — never invent a stack."""
    if not command:
        return "unknown"
    lowered = command.lower()
    if "vllm" in lowered:
        return "vllm"
    if "sglang" in lowered:
        return "sglang"
    if "text-generation" in lowered or "tgi" in lowered:
        return "tgi"
    if "ollama" in lowered:
        return "ollama"
    if any(
        token in lowered
        for token in ("llama-server", "llama.cpp", "llamacpp", "llama-cpp", "kobold")
    ):
        return "llama.cpp"
    if "tabby" in lowered:
        return "tabbyapi"
    return "unknown"


def infer_model_from_command(command: str | None) -> str | None:
    """Pull a model path/id out of argv when present. None if not visible."""
    if not command:
        return None
    try:
        tokens = shlex.split(command)
    except ValueError:
        tokens = command.split()
    for index, token in enumerate(tokens):
        if token in ("-m", "--model", "--model-path", "--model-id", "--served-model-name"):
            if index + 1 < len(tokens):
                return tokens[index + 1]
        if token.startswith("--model="):
            return token.split("=", 1)[1]
        if token.startswith("--model-path="):
            return token.split("=", 1)[1]
        if token.startswith("--model-id="):
            return token.split("=", 1)[1]
    # vllm serve <model>
    for index, token in enumerate(tokens):
        if token == "serve" and index + 1 < len(tokens):
            candidate = tokens[index + 1]
            if not candidate.startswith("-"):
                return candidate
    # Last path-like arg ending in .gguf / looking like HF repo
    for token in reversed(tokens):
        if token.startswith("-"):
            continue
        if token.endswith(".gguf") or "/" in token:
            return token
    return None


def probe_model_endpoint(port: int, host: str = "127.0.0.1") -> dict[str, Any]:
    """Probe common local model HTTP surfaces. Does not invent identity."""
    result: dict[str, Any] = {
        "port": port,
        "host": host,
        "ready": False,
        "health_ok": False,
        "openai_models": False,
        "model_ids": [],
        "base_url": f"http://{host}:{port}/v1",
    }
    health_urls = (
        f"http://{host}:{port}/health",
        f"http://{host}:{port}/v1/health",
    )
    for url in health_urls:
        try:
            request = urllib.request.Request(url, headers={"Accept": "application/json"})
            with urllib.request.urlopen(request, timeout=DISCOVERY_PROBE_TIMEOUT) as response:
                if 200 <= response.status < 300:
                    result["health_ok"] = True
                    break
        except (urllib.error.URLError, OSError, ValueError):
            continue

    models_url = f"http://{host}:{port}/v1/models"
    try:
        request = urllib.request.Request(models_url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(request, timeout=DISCOVERY_PROBE_TIMEOUT) as response:
            body = response.read()
        parsed = json.loads(body)
        entries = parsed.get("data", []) if isinstance(parsed, dict) else []
        ids = [
            entry["id"]
            for entry in entries
            if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"]
        ]
        if ids:
            result["openai_models"] = True
            result["model_ids"] = ids
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError, AttributeError):
        pass

    result["ready"] = bool(result["health_ok"] or result["openai_models"])
    return result


def _roots_hinted_by_path_token(token: str) -> list[Path]:
    """If a cmdline/profile path sits inside a numeric port folder, return its parent."""
    try:
        path = Path(token).expanduser()
    except (TypeError, ValueError):
        return []
    candidates: list[Path] = []
    # Walk up a few levels: …/launch/8080/launch.sh → …/launch
    current = path if path.suffix else path
    for _ in range(4):
        if PORT_CLAIM_DIR_RE.fullmatch(current.name):
            parent = current.parent
            if parent != current:
                candidates.append(parent)
        current = current.parent
        if current == current.parent:
            break
    return candidates


def roots_hinted_by_commands(commands: list[str | None]) -> list[Path]:
    """Derive scan roots from live argv / START_COMMAND paths (host-agnostic)."""
    found: list[Path] = []
    seen: set[Path] = set()
    for command in commands:
        if not command:
            continue
        try:
            tokens = shlex.split(command)
        except ValueError:
            tokens = command.split()
        for token in tokens:
            if "/" not in token and not token.startswith("~"):
                continue
            for root in _roots_hinted_by_path_token(token):
                try:
                    resolved = root.resolve()
                except OSError:
                    continue
                if resolved not in seen and resolved.is_dir():
                    seen.add(resolved)
                    found.append(resolved)
    return found


def _normalize_scan_root(root: Path) -> Path:
    """Expand ~ and resolve once for stable identity (symlink prefixes, '..').

    Root count is tiny vs dirent work; resolve is kept so macOS /var vs
    /private/var and overlapping roots share one path key.
    """
    return root.expanduser().resolve()


def scan_port_claim_directories(
    roots: list[Path] | None = None,
    *,
    agent_root: Path | None = None,
    listeners: list[dict[str, Any]] | None = None,
    max_depth: int = 3,
    home_depth: int = 2,
    limit: int = 64,
) -> list[dict[str, Any]]:
    """Find claimed-port folders under configured / hinted roots.

    Convention only: a directory whose name is a TCP port (2–5 digits) and that
    contains a launch/flags marker. Parent path is whatever the user chose —
    no product-specific roots are assumed. Roots come from:
      • explicit `roots` argument
      • MODEL_SWITCHBOARD_SCAN_ROOTS / config.json scan_roots
      • paths embedded in live process commands / profile START_COMMANDs
      • $HOME shallow fallback only when primary roots yield no claims
        (developer homes are huge -- avoid re-walking when primary already hit)

    Dirent work is bounded within one call: remaining-depth visit map skips
    re-iterdir when roots overlap; is_dir is memoized for the scan.
    """
    hinted: list[Path] = []
    try:
        live = listeners if listeners is not None else list_listening_tcp()
        hinted.extend(
            roots_hinted_by_commands([item.get("command") for item in live])
        )
    except Exception:
        pass

    # Per-scan is_dir memo (root admission + walk); paths reappear under overlap.
    is_dir_memo: dict[Path, bool] = {}

    def path_is_dir(path: Path) -> bool:
        cached = is_dir_memo.get(path)
        if cached is not None:
            return cached
        try:
            ok = path.is_dir()
        except OSError:
            ok = False
        is_dir_memo[path] = ok
        return ok

    primary: list[Path] = []
    primary_set: set[Path] = set()
    for root in (roots or []) + _configured_scan_roots(agent_root) + hinted:
        try:
            resolved = _normalize_scan_root(root)
        except OSError:
            continue
        if resolved in primary_set:
            continue
        if path_is_dir(resolved):
            primary_set.add(resolved)
            primary.append(resolved)

    # Parents first so a higher remaining budget covers nested sibling roots.
    primary.sort(key=lambda p: (len(p.parts), str(p)))

    home_roots: list[Path] = []
    try:
        home = _normalize_scan_root(Path.home())
        if path_is_dir(home) and home not in primary_set:
            home_roots.append(home)
    except OSError:
        pass

    claims: dict[int, dict[str, Any]] = {}
    # directory -> best remaining depth already walked (skip re-iterdir on overlap)
    walked_remaining: dict[Path, int] = {}

    def consider_claim(directory: Path) -> None:
        if len(claims) >= limit:
            return
        name = directory.name
        if not PORT_CLAIM_DIR_RE.fullmatch(name):
            return
        markers = [m for m in PORT_CLAIM_MARKERS if (directory / m).is_file()]
        if not markers:
            return
        port = int(name)
        flags: dict[str, str] = {}
        flags_path = directory / "flags.env"
        if flags_path.is_file():
            flags = parse_loose_env_assignments(flags_path)
        configured_port = flags.get("PORT") or str(port)
        try:
            port = int(str(configured_port).strip())
        except ValueError:
            port = int(name)
        model_hint = (
            flags.get("MODEL")
            or flags.get("MODEL_FILE")
            or flags.get("MODEL_PATH")
            or flags.get("MODEL_DIR")
            or flags.get("MODEL_REPO")
            or flags.get("REQUEST_MODEL")
            or ""
        )
        runtime_hint = ""
        if flags.get("RUNTIME"):
            runtime_hint = canonical_runtime(flags.get("RUNTIME"))
        elif flags.get("BACKEND"):
            runtime_hint = infer_runtime_from_command(flags.get("BACKEND"))
        elif flags.get("LLAMA_BIN") or flags.get("LLAMA_SERVER"):
            runtime_hint = "llama.cpp"
        elif flags.get("VLLM_BIN") or "vllm" in (flags.get("BACKEND") or "").lower():
            runtime_hint = "vllm"
        display = flags.get("DISPLAY_NAME") or ""
        if not display and model_hint:
            display = Path(model_hint).name
        if not display:
            display = f"Port {port}"
        start_command = ""
        for candidate in ("ctrl.sh", "launch.sh", "start.sh", "run.sh", "serve.sh"):
            script = directory / candidate
            if script.is_file() and os.access(script, os.X_OK):
                if candidate == "ctrl.sh":
                    start_command = f"{shlex.quote(str(script))} start"
                else:
                    start_command = shlex.quote(str(script))
                break
        claims[port] = {
            "port": port,
            "path": str(directory),
            "markers": markers,
            "display_name": display,
            "model_hint": model_hint,
            "runtime_hint": runtime_hint or "unknown",
            "host": flags.get("HOST") or "127.0.0.1",
            "start_command": start_command,
            "flags": {
                key: flags[key]
                for key in (
                    "MODEL",
                    "MODEL_FILE",
                    "MODEL_PATH",
                    "MODEL_DIR",
                    "MODEL_REPO",
                    "LLAMA_BIN",
                    "BACKEND",
                    "VLLM_BIN",
                    "REQUEST_MODEL",
                    "DISPLAY_NAME",
                    "PORT",
                    "HOST",
                )
                if key in flags
            },
        }

    def walk(directory: Path, depth: int, depth_limit: int) -> None:
        if depth > depth_limit or len(claims) >= limit:
            return
        remaining = depth_limit - depth
        prior = walked_remaining.get(directory)
        if prior is not None and prior >= remaining:
            return
        walked_remaining[directory] = remaining
        consider_claim(directory)
        if remaining == 0:
            return
        try:
            entries = list(directory.iterdir())
        except OSError:
            return
        for entry in entries:
            if entry.name in PROFILE_SCAN_SKIP_DIRS or entry.name.startswith("."):
                continue
            if path_is_dir(entry):
                walk(entry, depth + 1, depth_limit)

    for root in primary:
        walk(root, 0, max_depth)
        if len(claims) >= limit:
            break
    # $HOME is a costly shallow fallback -- only when primary found nothing.
    if not claims:
        for root in home_roots:
            walk(root, 0, home_depth)
            if len(claims) >= limit:
                break

    return [claims[key] for key in sorted(claims)]


def discover_live_model_endpoints(
    *,
    profile_ports: set[int] | None = None,
    claim_ports: set[int] | None = None,
    listeners: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Ports-style live discovery of model-looking listeners.

    Probes only when the owning command looks like a model server, or the port
    is already claimed by a profile / port-folder. Caps probe budget.
    """
    profile_ports = profile_ports or set()
    claim_ports = claim_ports or set()
    discovered: list[dict[str, Any]] = []
    probes_left = DISCOVERY_PROBE_BUDGET

    self_pid = os.getpid()
    for listener in (listeners if listeners is not None else list_listening_tcp()):
        port = int(listener["port"])
        if port in SKIP_LISTEN_PORTS:
            continue
        # Skip the agent itself: prefer pid (works without cmdline resolution).
        listener_pid = listener.get("pid")
        if (
            port == DEFAULT_PORT
            and listener_pid is not None
            and int(listener_pid) == self_pid
        ):
            continue
        # Fallback when pid missing: cmdline name (if list_listening resolved it).
        if port == DEFAULT_PORT and command_looks_like_model_server(
            listener.get("command") or ""
        ) is False:
            command = (listener.get("command") or "").lower()
            if "model_switchboard_agent" in command or "model-switchboard-agent" in command:
                continue

        command = listener.get("command")
        looks_model = command_looks_like_model_server(command)
        claimed = port in profile_ports or port in claim_ports
        if not looks_model and not claimed:
            continue

        probe: dict[str, Any] = {
            "port": port,
            "host": "127.0.0.1",
            "ready": False,
            "health_ok": False,
            "openai_models": False,
            "model_ids": [],
            "base_url": f"http://127.0.0.1:{port}/v1",
        }
        if probes_left > 0 and port_is_listening(str(port)):
            probes_left -= 1
            probe = probe_model_endpoint(port)

        # Drop pure system listeners that didn't respond as a model API unless
        # the cmdline clearly says model server / the port is claimed.
        if not probe["ready"] and not looks_model and not claimed:
            continue

        runtime = infer_runtime_from_command(command)
        model_from_cmd = infer_model_from_command(command)
        model_ids = list(probe.get("model_ids") or [])
        request_model = (
            (model_ids[0] if model_ids else None)
            or model_from_cmd
            or f"port-{port}"
        )
        display = request_model
        if isinstance(display, str) and ("/" in display or display.endswith(".gguf")):
            display = Path(display).name

        discovered.append(
            {
                "port": port,
                "pid": listener.get("pid"),
                "command": command,
                "bind": listener.get("bind"),
                "runtime": runtime,
                "request_model": request_model,
                "server_ids": model_ids,
                "display_name": display,
                "ready": bool(probe.get("ready")),
                "health_ok": bool(probe.get("health_ok")),
                "base_url": probe.get("base_url") or f"http://127.0.0.1:{port}/v1",
                "source": "listening",
            }
        )
    return discovered


def status_dict_from_discovery(
    item: dict[str, Any],
    *,
    source: str,
    profile_name: str | None = None,
    listeners: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Shape a discovery/claim record like a controller status entry."""
    port = str(item.get("port", ""))
    runtime = item.get("runtime") or item.get("runtime_hint") or "unknown"
    if runtime == "unknown" and item.get("runtime_hint"):
        runtime = item["runtime_hint"]
    label, tags, launch_mode = RUNTIME_SPECS.get(
        runtime, (runtime, ["discovered", "external"], "external")
    )
    if source == "claim":
        launch_mode = "command" if item.get("start_command") else "external"
        tags = list(dict.fromkeys(["claimed", "launch-folder"] + list(tags)))
    else:
        tags = list(dict.fromkeys(["discovered", "listening"] + list(tags)))
        launch_mode = "external"

    ready = bool(item.get("ready"))
    pid = item.get("pid")
    if pid is None and listeners is not None:
        pid = listener_pid_from_inventory(port, listeners)
    if pid:
        alive = process_is_alive(pid)
    elif ready:
        if listeners is not None:
            alive = port_listening_from_inventory(port, listeners)
        else:
            alive = port_is_listening(port)
    else:
        alive = False
    if ready and not pid:
        if listeners is None:
            # Live path only when no shared inventory (avoid N× lsof on status).
            pid = listener_pid(port)
            alive = process_is_alive(pid) if pid else ready
        # With inventory: port known listening without pid still counts ready below.

    request_model = item.get("request_model") or item.get("model_hint") or f"port-{port}"
    if isinstance(request_model, str) and request_model and not item.get("request_model"):
        # Prefer basename for display-ish model paths from flags.
        pass
    display = item.get("display_name") or Path(str(request_model)).name or f"Port {port}"
    name = profile_name or f"discovered-{port}"
    state = process_lifecycle_state(pid if alive else None, ready=ready and alive)
    if ready and not alive:
        # Health answered; treat as ready even if we could not attribute a pid.
        state = "ready"
        alive = True

    return {
        "profile": name,
        "display_name": display,
        "runtime": runtime,
        "runtime_label": label if runtime != "unknown" else "Discovered",
        "runtime_tags": tags,
        "launch_mode": launch_mode,
        "host": item.get("host") or "127.0.0.1",
        "port": port,
        "base_url": item.get("base_url") or f"http://127.0.0.1:{port}/v1",
        "request_model": str(request_model),
        "server_model_id": str(
            (item.get("server_ids") or [None])[0] or request_model
        ),
        "pid": pid if alive else None,
        "running": alive,
        "state": state,
        "ready": ready,
        "server_ids": item.get("server_ids") or item.get("model_ids") or [],
        "rss_mb": process_rss_mb(pid) if alive and pid else None,
        "vram_mb": process_vram_mb(pid) if alive and pid else None,
        "command": item.get("command") if alive else None,
        # Mac app ModelProfileStatus.logPath is a non-optional String — never null.
        "log_path": item.get("log_path")
        or (
            f"/tmp/launch-{port}.log"
            if port
            else f"/tmp/{name}.log"
        ),
        "discovery_source": source,
        "claim_path": item.get("path"),
    }


def profile_from_claim(claim: dict[str, Any]) -> Profile:
    """Build a manage-able Profile from a claimed port folder (no invented flags)."""
    port = str(claim.get("port") or "")
    if not port:
        raise InvalidProfileError("claim missing port")
    name = f"port-{port}"
    claim_path = claim.get("path") or ""
    request = claim.get("model_hint") or f"port-{port}"
    request_s = str(request)
    flags = claim.get("flags") if isinstance(claim.get("flags"), dict) else {}
    start = (claim.get("start_command") or "").strip()
    stop = ""
    if claim_path:
        directory = Path(claim_path)
        ctrl = directory / "ctrl.sh"
        launch = directory / "launch.sh"
        if ctrl.is_file() and os.access(ctrl, os.X_OK):
            start = start or f"{shlex.quote(str(ctrl))} start"
            stop = f"{shlex.quote(str(ctrl))} stop"
        elif launch.is_file() and os.access(launch, os.X_OK):
            start = start or shlex.quote(str(launch))
    display = claim.get("display_name") or Path(request_s).name or name
    values: dict[str, str] = {
        "DISPLAY_NAME": str(display),
        "RUNTIME": "command",
        "REQUEST_MODEL": request_s,
        "SERVER_MODEL_ID": Path(request_s).name if ("/" in request_s or request_s.endswith(".gguf")) else request_s,
        "PORT": port,
        "HOST": str(claim.get("host") or "127.0.0.1"),
        "START_COMMAND": start,
        "WORKING_DIRECTORY": claim_path,
        "LOG_ALIAS": f"launch-{port}",
        "MODEL_PATH": str(flags.get("MODEL") or flags.get("MODEL_PATH") or request_s),
        "MODEL_FILE": str(
            flags.get("MODEL_FILE")
            or flags.get("MODEL")
            or (request_s if request_s.endswith(".gguf") else "")
        ),
        "MODEL_REPO": str(flags.get("MODEL_REPO") or flags.get("MODEL_DIR") or ""),
        "RUNTIME_TAGS": "claimed,launch-folder",
    }
    if stop:
        values["STOP_COMMAND"] = stop
    if not start:
        # Still construct for status/stop-by-port; start() will raise clearly.
        values["LAUNCH_MODE"] = "external"
    return Profile(name=name, values=values)



# --------------------------------------------------------------------------
# Profiles directory resolution + home scan
# --------------------------------------------------------------------------


def _default_root() -> Path:
    return Path.home() / ".local/share/model-switchboard-agent"


def preferred_profiles_directory() -> Path:
    """Visible default: ~/model-profiles (not buried under the agent install root)."""
    return Path.home() / "model-profiles"


def agent_config_path(root: Path) -> Path:
    return root.expanduser() / "config.json"


def load_agent_config(root: Path) -> dict[str, Any]:
    path = agent_config_path(root)
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


def save_agent_config(root: Path, updates: dict[str, Any]) -> Path:
    root = root.expanduser()
    root.mkdir(parents=True, exist_ok=True)
    path = agent_config_path(root)
    payload = load_agent_config(root)
    payload.update(updates)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return path


def save_profiles_directory(root: Path, profiles_dir: Path) -> Path:
    resolved = profiles_dir.expanduser().resolve()
    save_agent_config(root, {"profiles_dir": str(resolved)})
    return resolved


def _directory_has_profile_files(directory: Path) -> bool:
    if not directory.is_dir():
        return False
    try:
        for path in directory.iterdir():
            if path.suffix.lower() in (".env", ".json") and not path.name.startswith("."):
                if path.name.endswith(".example"):
                    continue
                return True
    except OSError:
        return False
    return False


def resolve_profiles_directory(
    root: Path,
    explicit: Path | str | None = None,
) -> Path:
    """Pick the profiles folder without inventing profile contents.

    Order: CLI/explicit → env → config.json → existing <root>/model-profiles
    (legacy installs with real profiles) → ~/model-profiles.
    """
    if explicit is not None:
        return Path(explicit).expanduser().resolve()
    env = (os.environ.get(PROFILES_DIR_ENV) or "").strip()
    if env:
        return Path(env).expanduser().resolve()
    configured = load_agent_config(root).get("profiles_dir")
    if isinstance(configured, str) and configured.strip():
        return Path(configured).expanduser().resolve()
    legacy = root.expanduser() / "model-profiles"
    if _directory_has_profile_files(legacy):
        return legacy.resolve()
    return preferred_profiles_directory().resolve()


def _peek_profile_keys(path: Path) -> set[str]:
    """Best-effort key set for scan scoring — never executes file contents."""
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return set()
    if path.suffix.lower() == ".json":
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return set()
        if not isinstance(parsed, dict):
            return set()
        return {str(key) for key in parsed.keys()}
    keys: set[str] = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        equals = line.find("=")
        if equals <= 0:
            continue
        key = line[:equals].strip()
        if PROFILE_KEY_RE.match(key):
            keys.add(key)
    return keys


def looks_like_profile_file(path: Path) -> bool:
    if path.suffix.lower() not in (".env", ".json") or path.name.startswith("."):
        return False
    # Skip installer samples that are not live profiles yet.
    if ".example" in path.name:
        return False
    keys = _peek_profile_keys(path)
    if not keys:
        return False
    signals = keys & PROFILE_SIGNAL_KEYS
    if "REQUEST_MODEL" in signals:
        return True
    if "START_COMMAND" in signals:
        return True
    if "PORT" in signals or "BASE_URL" in signals:
        return bool(signals & {"RUNTIME", "MODEL_FILE", "MODEL_PATH", "MODEL_REPO", "DISPLAY_NAME"})
    return False


def scan_profile_directories(
    home: Path | None = None,
    *,
    max_depth: int = PROFILE_SCAN_MAX_DEPTH,
    limit: int = PROFILE_SCAN_MAX_CANDIDATES,
) -> list[dict[str, Any]]:
    """Find directories that already hold Switchboard-shaped launch .env/.json files.

    Does not invent flags — only groups files an AI or user already wrote
    (often `model.env`, `qwen.env`, …) by parent folder.
    """
    home = (home or Path.home()).expanduser()
    tallies: dict[Path, list[str]] = {}

    def walk(directory: Path, depth: int) -> None:
        if depth > max_depth:
            return
        try:
            entries = list(directory.iterdir())
        except OSError:
            return
        for entry in entries:
            name = entry.name
            if name in PROFILE_SCAN_SKIP_DIRS:
                continue
            # Skip hidden directories; still consider visible files.
            try:
                is_dir = entry.is_dir()
            except OSError:
                continue
            if is_dir:
                if name.startswith("."):
                    continue
                walk(entry, depth + 1)
                continue
            if not looks_like_profile_file(entry):
                continue
            parent = entry.parent.resolve()
            tallies.setdefault(parent, []).append(entry.name)

    walk(home, 0)
    # Always consider the preferred default and common legacy path.
    for extra in (preferred_profiles_directory(), _default_root() / "model-profiles"):
        try:
            resolved = extra.expanduser().resolve()
        except OSError:
            continue
        if resolved in tallies:
            continue
        if not resolved.is_dir():
            continue
        try:
            children = list(resolved.iterdir())
        except OSError:
            continue
        for path in children:
            if looks_like_profile_file(path):
                tallies.setdefault(resolved, []).append(path.name)

    ranked = sorted(
        tallies.items(),
        key=lambda item: (-len(item[1]), str(item[0])),
    )
    results: list[dict[str, Any]] = []
    for directory, files in ranked[:limit]:
        unique_files = sorted(set(files))
        results.append({
            "path": str(directory),
            "profile_count": len(unique_files),
            "files": unique_files[:12],
        })
    return results


def prompt_profiles_directory(
    root: Path,
    *,
    current: Path,
    input_func: Callable[[str], str] | None = None,
    home: Path | None = None,
) -> Path:
    """Interactive: confirm a scanned folder or paste another path."""
    reader = input_func or input
    candidates = scan_profile_directories(home)
    print("Model profiles are plain .env/.json launch files (ports, START_COMMAND, …).")
    print("Switchboard only needs the folder that already holds them — it will not")
    print("author flags for every runtime fork.")
    print()
    print(f"Current profiles folder: {current}")
    if candidates:
        print("Found folders that look like they already have model launch profiles:")
        for index, candidate in enumerate(candidates, start=1):
            preview = ", ".join(candidate["files"][:4])
            extra = "" if len(candidate["files"]) <= 4 else ", …"
            print(
                f"  [{index}] {candidate['path']} "
                f"({candidate['profile_count']} file(s): {preview}{extra})"
            )
        print("  [Enter] keep current")
        print("  [0]     use ~/model-profiles (create if needed)")
        print("  or paste another folder path")
    else:
        print("No launch-looking .env/.json folders found under your home directory.")
        print("  [Enter] keep current / use ~/model-profiles")
        print("  or paste the folder path where your model .env files live")
    print()
    try:
        answer = reader("Profiles folder? ").strip()
    except EOFError:
        answer = ""
    if not answer:
        if current.exists() or _directory_has_profile_files(current):
            chosen = current
        elif candidates:
            chosen = Path(candidates[0]["path"])
        else:
            chosen = preferred_profiles_directory()
    elif answer == "0":
        chosen = preferred_profiles_directory()
    elif answer.isdigit() and candidates:
        index = int(answer)
        if 1 <= index <= len(candidates):
            chosen = Path(candidates[index - 1]["path"])
        else:
            raise UsageError(f"No candidate numbered {index}")
    else:
        chosen = Path(answer)
    chosen = chosen.expanduser().resolve()
    chosen.mkdir(parents=True, exist_ok=True)
    save_profiles_directory(root, chosen)
    print(f"Using profiles folder: {chosen}")
    return chosen


@dataclass
class AgentConfiguration:
    root: Path
    host: str = "127.0.0.1"
    port: int = DEFAULT_PORT
    auth_token: str | None = None
    unsafe_bind: bool = False
    tailscale_bind: bool = False
    # Tailscale binds require a token unless this is set (personal tailnet opt-out).
    allow_unauthenticated: bool = False
    profiles_dir: Path | None = None

    def __post_init__(self) -> None:
        token = (self.auth_token or "").strip()
        if token and len(token.encode("utf-8")) < MINIMUM_TOKEN_BYTES:
            raise InvalidConfigurationError(
                f"auth token must be at least {MINIMUM_TOKEN_BYTES} bytes"
            )
        if self.tailscale_bind and not is_tailscale_ip(self.host):
            raise InvalidConfigurationError(
                f"--tailscale bind resolved a non-Tailscale address: {self.host}"
            )
        if self.tailscale_bind and not token and not self.allow_unauthenticated:
            raise InvalidConfigurationError(
                "--tailscale requires a bearer auth token "
                "(--auth-token / --auth-token-file), or pass "
                "--allow-unauthenticated for a personal tailnet"
            )
        if not is_loopback(self.host) and not self.tailscale_bind:
            # Plain LAN / non-loopback: unsafe-bind + token always required.
            if not self.unsafe_bind:
                raise InvalidConfigurationError(
                    f"non-loopback agent bind requires --unsafe-bind: {self.host}"
                )
            if not token:
                raise InvalidConfigurationError(
                    "non-loopback agent bind requires a bearer auth token"
                )
        self.auth_token = token or None
        self.root = self.root.expanduser()
        self.profiles_dir = resolve_profiles_directory(self.root, self.profiles_dir)

    @property
    def profiles_directory(self) -> Path:
        assert self.profiles_dir is not None
        return self.profiles_dir

    @property
    def run_directory(self) -> Path:
        return self.root / "run"

    @property
    def active_profile_file(self) -> Path:
        return self.run_directory / "active-profile"

    @property
    def systemd_unit_path(self) -> Path:
        return Path.home() / ".config/systemd/user/model-switchboard-agent.service"


class AgentService:
    def __init__(self, configuration: AgentConfiguration):
        self.configuration = configuration
        self.profiles = ProfileRepository(configuration.profiles_directory)
        self._mutation_lock = threading.RLock()
        self._watchdog_suppressed_until = 0.0
        self._watchdog_timer: threading.Timer | None = None
        # Profiles started by *this* agent process. Crash-recovery restarts only
        # these — an agent reboot / login never spontaneously loads a model.
        self._supervised: set[str] = set()
        self._benchmark_lock = threading.Lock()
        self._benchmark_running = False

    def resolve_profile(self, name: str) -> Profile:
        """Profiles folder first; then claimed port folders (port-N); never invent."""
        loaded = self.profiles.load()
        if name in loaded:
            return loaded[name]
        port: int | None = None
        if name.startswith("port-"):
            try:
                port = int(name.removeprefix("port-"))
            except ValueError:
                port = None
        elif name.startswith("discovered-"):
            try:
                port = int(name.removeprefix("discovered-"))
            except ValueError:
                port = None
        if port is not None:
            # One inventory for claim scan + live discovery (no second ss/lsof).
            listeners = list_listening_tcp()
            claims = scan_port_claim_directories(
                agent_root=self.configuration.root,
                listeners=listeners,
            )
            for claim in claims:
                try:
                    if int(claim["port"]) == port:
                        return profile_from_claim(claim)
                except (KeyError, TypeError, ValueError):
                    continue
            live = discover_live_model_endpoints(
                profile_ports=set(),
                claim_ports={port},
                listeners=listeners,
            )
            for item in live:
                try:
                    if int(item["port"]) != port:
                        continue
                except (KeyError, TypeError, ValueError):
                    continue
                request = str(item.get("request_model") or f"port-{port}")
                return Profile(
                    name=name,
                    values={
                        "DISPLAY_NAME": str(item.get("display_name") or request),
                        "RUNTIME": str(item.get("runtime") or "unknown"),
                        "REQUEST_MODEL": request,
                        "SERVER_MODEL_ID": request,
                        "PORT": str(port),
                        "HOST": "127.0.0.1",
                        "LAUNCH_MODE": "external",
                        "START_COMMAND": "",
                        "LOG_ALIAS": f"discovered-{port}",
                    },
                )
        raise ProfileNotFoundError(name)

    # -- status ------------------------------------------------------------

    def status_payload(self, selected: list[str] | None = None) -> dict[str, Any]:
        """Assemble controller status JSON (profiles + optional full discovery).

        When MSW_PERF_PROFILE=1 or MSW_AGENT_PERF=1, emits perf.profile.span_summary
        on stderr with stage timings (measurement only).
        """
        with _PerfSpan("status_payload") as span:
            span.stage("profiles_load")
            loaded = self.profiles.load()
            conflicts = self.profiles.conflicts(loaded)
            names = selected if selected is not None else sorted(loaded.keys())
            # One inventory for profile port attribution (no N× socket/lsof) and,
            # when listing everything, claim scan + live discovery.
            span.stage("list_listening_tcp")
            listeners = list_listening_tcp()
            span.stage("profile_statuses")
            statuses = []
            profile_ports: set[int] = set()
            for name in names:
                profile = loaded.get(name)
                if profile is None:
                    raise ProfileNotFoundError(name)
                statuses.append(
                    self.status(
                        profile,
                        allow_port_fallback=name not in conflicts,
                        listeners=listeners,
                    )
                )
                try:
                    profile_ports.add(int(profile.endpoint_port))
                except (TypeError, ValueError):
                    pass

            claims: list[dict[str, Any]] = []
            listening: list[dict[str, Any]] = []
            # Full discovery only when listing everything — targeted stays profile-only.
            if selected is None:
                # Reuse the same listeners snapshot (no second inventory).
                start_cmds = [
                    profile.get("START_COMMAND")
                    for profile in loaded.values()
                ]
                # START_COMMAND path hints only; scan re-hints from listeners=.
                claim_roots = roots_hinted_by_commands(start_cmds)
                span.stage("scan_port_claim_directories")
                claims = scan_port_claim_directories(
                    roots=claim_roots or None,
                    agent_root=self.configuration.root,
                    listeners=listeners,
                )
                claim_ports = {int(item["port"]) for item in claims}
                span.stage("discover_live_model_endpoints")
                listening = discover_live_model_endpoints(
                    profile_ports=profile_ports,
                    claim_ports=claim_ports,
                    listeners=listeners,
                )
                span.stage("merge_discovery")
                covered_ports = {
                    int(item["port"])
                    for item in statuses
                    if str(item.get("port") or "").isdigit()
                }

                # Claimed port folders not already represented by a profile.
                for claim in claims:
                    port = int(claim["port"])
                    if port in covered_ports:
                        continue
                    live = next((item for item in listening if int(item["port"]) == port), None)
                    merged = dict(claim)
                    if live:
                        merged.update(
                            {
                                "pid": live.get("pid"),
                                "command": live.get("command"),
                                "ready": live.get("ready"),
                                "server_ids": live.get("server_ids"),
                                "base_url": live.get("base_url"),
                                "runtime": live.get("runtime")
                                if live.get("runtime") != "unknown"
                                else claim.get("runtime_hint") or "unknown",
                                "request_model": live.get("request_model")
                                if live.get("request_model")
                                and not str(live.get("request_model")).startswith("port-")
                                else (claim.get("model_hint") or live.get("request_model")),
                                "display_name": claim.get("display_name")
                                or live.get("display_name"),
                            }
                        )
                    else:
                        merged["ready"] = False
                        merged["request_model"] = claim.get("model_hint") or f"port-{port}"
                        merged["runtime"] = claim.get("runtime_hint") or "unknown"
                    statuses.append(
                        status_dict_from_discovery(
                            merged,
                            source="claim",
                            profile_name=f"port-{port}",
                            listeners=listeners,
                        )
                    )
                    covered_ports.add(port)

                # Pure listeners not claimed and not profiled.
                for live in listening:
                    port = int(live["port"])
                    if port in covered_ports:
                        continue
                    statuses.append(
                        status_dict_from_discovery(
                            live,
                            source="listening",
                            profile_name=f"discovered-{port}",
                            listeners=listeners,
                        )
                    )
                    covered_ports.add(port)

            span.stage("benchmark_status")
            benchmark = self.benchmark_status()
            span.tags["n_profiles"] = len(names)
            span.tags["n_statuses"] = len(statuses)
            span.tags["n_listeners"] = len(listeners)
            span.tags["n_claims"] = len(claims)
            span.tags["n_live"] = len(listening)
            span.tags["full_discovery"] = selected is None
            return {
                "statuses": statuses,
                "benchmark": benchmark,
                "integrations": [],
                "profiles_dir": str(self.configuration.profiles_directory),
                "controller_root": str(self.configuration.root),
                "discovery": {
                    "listening": listening if selected is None else [],
                    "claims": [
                        {
                            "port": item["port"],
                            "path": item["path"],
                            "display_name": item.get("display_name"),
                            "model_hint": item.get("model_hint"),
                            "runtime_hint": item.get("runtime_hint"),
                        }
                        for item in (claims if selected is None else [])
                    ],
                    "scan_roots_env": SCAN_ROOTS_ENV,
                },
            }

    def ports_payload(self) -> dict[str, Any]:
        """Ports-style inventory: every listener + model probe outcome."""
        loaded = self.profiles.load()
        profile_ports: set[int] = set()
        for profile in loaded.values():
            try:
                profile_ports.add(int(profile.endpoint_port))
            except (TypeError, ValueError):
                pass
        # One inventory shared with claim scan + live discovery.
        listeners = list_listening_tcp()
        claims = scan_port_claim_directories(
            agent_root=self.configuration.root,
            listeners=listeners,
        )
        claim_ports = {int(item["port"]) for item in claims}
        live = discover_live_model_endpoints(
            profile_ports=profile_ports,
            claim_ports=claim_ports,
            listeners=listeners,
        )
        live_by_port = {int(item["port"]): item for item in live}
        ports: list[dict[str, Any]] = []
        for listener in listeners:
            port = int(listener["port"])
            entry = {
                "port": port,
                "pid": listener.get("pid"),
                "command": listener.get("command"),
                "bind": listener.get("bind"),
                "looks_like_model": command_looks_like_model_server(listener.get("command")),
                "model": live_by_port.get(port),
                "claimed": next(
                    (claim for claim in claims if int(claim["port"]) == port),
                    None,
                ),
            }
            ports.append(entry)
        # Claims with nothing listening yet still appear.
        listening_ports = {int(item["port"]) for item in listeners}
        for claim in claims:
            if int(claim["port"]) not in listening_ports:
                ports.append(
                    {
                        "port": int(claim["port"]),
                        "pid": None,
                        "command": None,
                        "bind": None,
                        "looks_like_model": False,
                        "model": None,
                        "claimed": claim,
                    }
                )
        ports.sort(key=lambda item: int(item["port"]))
        return {
            "ports": ports,
            "profiles_dir": str(self.configuration.profiles_directory),
            "controller_root": str(self.configuration.root),
            "scan_roots_env": SCAN_ROOTS_ENV,
        }

    def action_response(self) -> dict[str, Any]:
        payload = self.status_payload()
        return {
            "ok": True,
            "statuses": payload["statuses"],
            "benchmark": payload["benchmark"],
            "integrations": payload["integrations"],
            "profiles_dir": payload["profiles_dir"],
            "controller_root": payload["controller_root"],
            "error": None,
        }

    def _benchmark_dir(self) -> Path:
        path = self.configuration.run_directory / "benchmarks"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _benchmark_pid_file(self) -> Path:
        return self.configuration.run_directory / "benchmark.pid"

    def _benchmark_log_path(self) -> Path:
        return self.configuration.run_directory / "logs" / "benchmark.log"

    def _benchmark_latest_json(self) -> Path:
        return self._benchmark_dir() / "latest.json"

    def _benchmark_latest_md(self) -> Path:
        return self._benchmark_dir() / "latest.md"

    def _read_benchmark_pid(self) -> int | None:
        path = self._benchmark_pid_file()
        try:
            raw = path.read_text(encoding="utf-8").strip()
            pid = int(raw)
        except (OSError, ValueError):
            return None
        if not process_is_alive(pid):
            path.unlink(missing_ok=True)
            return None
        return pid

    def _latest_benchmark_report(self) -> dict[str, Any] | None:
        path = self._benchmark_latest_json()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if not isinstance(payload, dict):
            return None
        reports = payload.get("benchmarks") or []
        rows: list[dict[str, Any]] = []
        for report in reports:
            if not isinstance(report, dict):
                continue
            averages = report.get("averages") or {}
            rows.append(
                {
                    "profile": report.get("profile"),
                    "runtime": report.get("runtime"),
                    "ttft_ms": averages.get("ttft_ms"),
                    "decode_tokens_per_sec": averages.get("decode_tokens_per_sec"),
                    "e2e_tokens_per_sec": averages.get("e2e_tokens_per_sec"),
                    "rss_mb": report.get("rss_mb"),
                    "vram_mb": report.get("vram_mb"),
                }
            )
        return {
            "generated_at": payload.get("generated_at"),
            "suite": payload.get("suite"),
            "profiles": payload.get("profiles") or [],
            "rows": rows,
            "json_path": str(path),
            "markdown_path": str(self._benchmark_latest_md()),
        }

    def benchmark_status(self) -> dict[str, Any]:
        pid = self._read_benchmark_pid() if self._benchmark_running else None
        # Clear stale pid files left after process crash.
        if not self._benchmark_running and self._benchmark_pid_file().exists():
            self._benchmark_pid_file().unlink(missing_ok=True)
            pid = None
        log_path = self._benchmark_log_path()
        return {
            "running": self._benchmark_running,
            "pid": pid if self._benchmark_running else None,
            "log_path": str(log_path) if log_path.exists() or self._benchmark_running else None,
            "latest": self._latest_benchmark_report(),
        }

    def start_benchmark(
        self,
        profiles: list[str] | None = None,
        suite: str = "quick",
        allow_concurrent: bool = False,
        keep_running: bool = False,
    ) -> dict[str, Any]:
        """Run a quick local-endpoint benchmark in a background thread.

        Hits the model on the agent host (always loopback-reachable here). The
        Mac app must only start a remote bench when the profile is ready; the
        agent will also try switch/start if needed.
        """
        with self._benchmark_lock:
            if self._benchmark_running:
                raise OperationFailedError("benchmark already running")
            self._benchmark_running = True
        loaded = self.profiles.load()
        if profiles:
            names = [n for n in profiles if n in loaded]
            missing = [n for n in profiles if n not in loaded]
            if missing and not names:
                with self._benchmark_lock:
                    self._benchmark_running = False
                raise ProfileNotFoundError(missing[0])
        else:
            names = sorted(loaded.keys())
        if not names:
            with self._benchmark_lock:
                self._benchmark_running = False
            raise UsageError("no profiles available to benchmark")

        log_path = self._benchmark_log_path()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("", encoding="utf-8")
        # Marker pid = this agent process while the worker thread runs.
        self._benchmark_pid_file().write_text(f"{os.getpid()}\n", encoding="utf-8")

        def worker() -> None:
            try:
                self._run_benchmark_worker(
                    names,
                    suite=suite,
                    allow_concurrent=allow_concurrent,
                    keep_running=keep_running,
                    log_path=log_path,
                )
            finally:
                self._benchmark_pid_file().unlink(missing_ok=True)
                with self._benchmark_lock:
                    self._benchmark_running = False

        thread = threading.Thread(target=worker, name="msw-benchmark", daemon=True)
        thread.start()
        return self.benchmark_status()

    def _run_benchmark_worker(
        self,
        names: list[str],
        *,
        suite: str,
        allow_concurrent: bool,
        keep_running: bool,
        log_path: Path,
    ) -> None:
        prompts = self._benchmark_prompts(suite)
        reports: list[dict[str, Any]] = []

        def log(line: str) -> None:
            try:
                with log_path.open("a", encoding="utf-8") as handle:
                    handle.write(line + "\n")
            except OSError:
                pass

        for name in names:
            try:
                profile = self.resolve_profile(name)
            except AgentError as error:
                log(f"{name}: resolve failed: {error}")
                continue
            before = self.status(profile)
            was_running = bool(before.get("running"))
            try:
                if not before.get("ready"):
                    if allow_concurrent:
                        self.start(name)
                    else:
                        self.switch_profile(name)
                    # Quick suite should not block the agent for minutes if the
                    # model never becomes ready (disabled healthcheck, OOM, …).
                    deadline = time.time() + (15 if suite == "quick" else 90)
                    while time.time() < deadline:
                        before = self.status(self.resolve_profile(name))
                        if before.get("ready"):
                            break
                        time.sleep(0.5)
                results: list[dict[str, Any]] = []
                if not before.get("ready"):
                    results.append(
                        {
                            "benchmark": "ready-wait",
                            "category": "setup",
                            "error": "profile not ready for benchmark",
                        }
                    )
                else:
                    for prompt in prompts:
                        results.append(self._benchmark_one(profile, prompt))
                successful = [r for r in results if not r.get("error")]
                def avg(key: str) -> float | None:
                    vals = [float(r[key]) for r in successful if r.get(key) is not None]
                    if not vals:
                        return None
                    return round(sum(vals) / len(vals) * 10) / 10
                current = self.status(self.resolve_profile(name))
                reports.append(
                    {
                        "profile": name,
                        "runtime": profile.runtime,
                        "rss_mb": current.get("rss_mb"),
                        "vram_mb": current.get("vram_mb"),
                        "averages": {
                            "ttft_ms": avg("ttft_ms"),
                            "decode_tokens_per_sec": avg("decode_tokens_per_sec"),
                            "e2e_tokens_per_sec": avg("e2e_tokens_per_sec"),
                        },
                        "results": results,
                    }
                )
                log(f"{name}: ok rows={len(successful)}/{len(results)}")
            except AgentError as error:
                log(f"{name}: {error}")
                reports.append(
                    {
                        "profile": name,
                        "runtime": profile.runtime,
                        "rss_mb": None,
                        "vram_mb": None,
                        "averages": {
                            "ttft_ms": None,
                            "decode_tokens_per_sec": None,
                            "e2e_tokens_per_sec": None,
                        },
                        "results": [{"error": str(error)}],
                    }
                )
            finally:
                # Prefer leaving the host as we found it for quick suite.
                if not keep_running and not was_running:
                    try:
                        self.stop(name, force=True)
                    except TypeError:
                        try:
                            self.stop(name)
                        except AgentError:
                            pass
                    except AgentError:
                        pass

        generated_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        payload = {
            "generated_at": generated_at,
            "suite": suite,
            "profiles": names,
            "benchmarks": reports,
        }
        latest = self._benchmark_latest_json()
        latest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        lines = [
            "# Model Switchboard Benchmark",
            "",
            f"Generated: {generated_at}",
            "",
            "| Profile | Runtime | TTFT ms | Decode tok/s |",
            "|---|---|---:|---:|",
        ]
        for report in reports:
            averages = report.get("averages") or {}
            lines.append(
                f"| {report.get('profile')} | {report.get('runtime')} | "
                f"{averages.get('ttft_ms') or '-'} | {averages.get('decode_tokens_per_sec') or '-'} |"
            )
        self._benchmark_latest_md().write_text("\n".join(lines) + "\n", encoding="utf-8")
        log(f"wrote {latest}")

    @staticmethod
    def _benchmark_prompts(suite: str) -> list[dict[str, Any]]:
        # Keep quick suite short: remote agents may hold large models.
        if suite == "context":
            return [
                {"benchmark": "prefill-1k", "category": "prefill", "prompt": "Hello " * 200, "max_tokens": 16},
                {"benchmark": "prefill-4k", "category": "prefill", "prompt": "Hello " * 800, "max_tokens": 16},
            ]
        return [
            {
                "benchmark": "quick-short",
                "category": "decode",
                "prompt": "Write a one-sentence greeting.",
                "max_tokens": 32,
            },
            {
                "benchmark": "quick-medium",
                "category": "decode",
                "prompt": "Explain what a token is in large language models in two sentences.",
                "max_tokens": 64,
            },
        ]

    def _benchmark_one(self, profile: Profile, prompt: dict[str, Any]) -> dict[str, Any]:
        """POST /v1/chat/completions on the local endpoint and time TTFT/decode."""
        url = profile.base_url.rstrip("/") + "/chat/completions"
        body = json.dumps(
            {
                "model": profile.request_model,
                "messages": [{"role": "user", "content": prompt["prompt"]}],
                "max_tokens": int(prompt.get("max_tokens") or 32),
                "temperature": 0,
                "stream": False,
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                raw = response.read()
            elapsed_s = max(time.perf_counter() - started, 1e-6)
            payload = json.loads(raw.decode("utf-8"))
            choice = (payload.get("choices") or [{}])[0]
            message = choice.get("message") or {}
            content = message.get("content") or choice.get("text") or ""
            usage = payload.get("usage") or {}
            completion_tokens = usage.get("completion_tokens")
            if not isinstance(completion_tokens, int):
                completion_tokens = max(1, len(str(content).split()))
            prompt_tokens = usage.get("prompt_tokens")
            if not isinstance(prompt_tokens, int):
                prompt_tokens = max(1, len(str(prompt["prompt"]).split()))
            ttft_ms = elapsed_s * 1000.0  # non-stream: whole response latency as TTFT proxy
            return {
                "benchmark": prompt.get("benchmark"),
                "category": prompt.get("category"),
                "ttft_ms": round(ttft_ms * 10) / 10,
                "decode_tokens_per_sec": round((completion_tokens / elapsed_s) * 10) / 10,
                "e2e_tokens_per_sec": round(((prompt_tokens + completion_tokens) / elapsed_s) * 10) / 10,
                "completion_tokens": completion_tokens,
                "prompt_est_tokens": prompt_tokens,
            }
        except Exception as error:  # noqa: BLE001 - surface as row error
            return {
                "benchmark": prompt.get("benchmark"),
                "category": prompt.get("category"),
                "error": str(error),
            }

    def host_metrics(self) -> dict[str, Any]:
        return host_metrics_payload()

    def status(
        self,
        profile: Profile,
        allow_port_fallback: bool = True,
        *,
        listeners: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        ready, server_ids = self._probe_health(profile)
        pid = self._read_pid(profile.name)
        zombie = bool(pid and process_is_zombie(pid))
        if pid is not None and not process_is_alive(pid):
            # Clear pid file for dead *and* zombie children once reaped/known.
            if not zombie:
                self._pid_file(profile.name).unlink(missing_ok=True)
                pid = None
            else:
                # Still show the defunct pid once so operators can see it, but
                # running stays false; next successful stop clears the file.
                pass
        if pid is None and allow_port_fallback:
            if listeners is not None:
                listener = listener_pid_from_inventory(profile.endpoint_port, listeners)
            else:
                listener = listener_pid(profile.endpoint_port)
            if listener is not None:
                # Prefer cmdline match, but if health already succeeded on this
                # port trust the listener — external launch scripts rarely share
                # profile name tokens with the model process argv.
                if self._process_matches(listener, profile) or ready:
                    pid = listener
                    zombie = process_is_zombie(pid)
        label, _, launch_mode = profile.runtime_spec
        alive = process_is_alive(pid)
        # Healthy OpenAI/loopback endpoint on the claimed port counts as live
        # even when we could not attribute a pid (permission / pid namespace).
        if ready and not alive:
            if listeners is not None:
                listening = port_listening_from_inventory(
                    profile.endpoint_port, listeners
                )
            else:
                listening = port_is_listening(profile.endpoint_port)
            if listening:
                alive = True
                if pid is None:
                    if listeners is not None:
                        pid = listener_pid_from_inventory(
                            profile.endpoint_port, listeners
                        )
                    else:
                        pid = listener_pid(profile.endpoint_port)
                    zombie = bool(pid and process_is_zombie(pid))
                    alive = process_is_alive(pid) or ready
        state = process_lifecycle_state(pid, ready=ready and alive)
        if ready and alive:
            state = "ready"
        if zombie and not process_is_alive(pid):
            state = "zombie"
            if not ready:
                alive = False
        return {
            "profile": profile.name,
            "display_name": profile.display_name,
            "runtime": profile.runtime,
            "runtime_label": label,
            "runtime_tags": profile.runtime_tags,
            "launch_mode": launch_mode,
            "host": profile.endpoint_host,
            "port": profile.endpoint_port,
            "base_url": profile.base_url,
            "request_model": profile.request_model,
            "server_model_id": profile.server_model_id,
            "pid": pid if (alive or zombie) else None,
            "running": alive,
            "state": state,
            "ready": bool(ready and alive),
            "server_ids": server_ids if alive else [],
            "rss_mb": process_rss_mb(pid) if alive and pid else None,
            # GPU VRAM when nvidia-smi can attribute memory to this pid (not RSS).
            "vram_mb": process_vram_mb(pid) if alive and pid else None,
            "command": process_command(pid) if ((alive or zombie) and pid) else None,
            "log_path": profile.log_path,
            "discovery_source": "profile",
        }

    # -- lifecycle ---------------------------------------------------------

    def start(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            if not (profile.get("START_COMMAND") or "").strip() and profile.runtime_spec[2] == "external":
                raise UnsupportedError(
                    f"{name}: discovered endpoint has no launch claim; cannot start from Switchboard"
                )
            loaded = self.profiles.load()
            # Include synthetic claim profile for conflict checks on the port.
            loaded = dict(loaded)
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "start", loaded)
            command = build_start_command(profile)

            environment = dict(os.environ)
            environment.update(profile.values)
            environment["MODEL_PROFILE"] = name
            environment["MODEL_SWITCHBOARD_PROFILE_LOADED"] = "1"
            environment["MODEL_SWITCHBOARD_AGENT"] = "1"

            self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
            log_path = Path(profile.log_path)
            try:
                log_handle = log_path.open("ab")
            except OSError as error:
                raise OperationFailedError(f"cannot open log {log_path}: {error}") from error
            try:
                process = subprocess.Popen(
                    ["/bin/bash", "-lc", command],
                    stdout=log_handle,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                    cwd=profile.working_directory or self.configuration.root,
                    env=environment,
                    start_new_session=True,
                )
            except OSError as error:
                raise OperationFailedError(f"failed to launch {name}: {error}") from error
            finally:
                log_handle.close()
            self._pid_file(name).write_text(f"{process.pid}\n", encoding="utf-8")
            self._supervised.add(name)

    def stop(self, name: str, force: bool = False) -> None:
        with self._mutation_lock:
            self._suppress_watchdog()
            self._supervised.discard(name)
            self._clear_active_profile(if_matching=name)
            profile = self.resolve_profile(name)
            current = self.status(profile)
            primary_pid = current.get("pid")
            stop_error: Exception | None = None

            stop_command = (profile.get("STOP_COMMAND") or "").strip()
            if stop_command and not force:
                environment = dict(os.environ)
                environment.update(profile.values)
                try:
                    subprocess.run(
                        ["/bin/bash", "-lc", stop_command],
                        cwd=profile.working_directory,
                        env=environment,
                        capture_output=True,
                        check=True,
                        timeout=60,
                    )
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as error:
                    stop_error = error

            if profile.get("STOP_COMMAND_ONLY") != "1" or force:
                self._terminate_profile_processes(
                    profile, primary_pid, force=force
                )
                wait_ok = self._wait_until_stopped(
                    profile,
                    primary_pid,
                    timeout=FORCE_TERMINATE_TIMEOUT_SECONDS * 3 if force else STOP_WAIT_SECONDS,
                )
                if not wait_ok:
                    # Last-chance SIGKILL of anything still matching the port.
                    self._terminate_profile_processes(profile, primary_pid, force=True)
                    wait_ok = self._wait_until_stopped(
                        profile,
                        primary_pid,
                        timeout=FORCE_TERMINATE_TIMEOUT_SECONDS * 2,
                    )
                if not wait_ok:
                    raise OperationFailedError(
                        f"failed to stop {name}: endpoint or process is still alive"
                    )
            self._pid_file(name).unlink(missing_ok=True)
            if stop_error is not None and not force:
                raise OperationFailedError(f"STOP_COMMAND failed for {name}: {stop_error}")

    def restart(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            loaded = dict(self.profiles.load())
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "restart", loaded)
            self.stop(name)
            self.start(name)

    def switch_profile(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            loaded = dict(self.profiles.load())
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "activate", loaded)
            for item in self.status_payload()["statuses"]:
                if item["profile"] != name and item["running"]:
                    self.stop(item["profile"])
            self.start(name)
            self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
            self.configuration.active_profile_file.write_text(f"{name}\n", encoding="utf-8")

    def stop_all(self, force: bool = False) -> None:
        with self._mutation_lock:
            failures: list[str] = []
            for name in sorted(self.profiles.load().keys()):
                try:
                    # Nested stop also takes the mutation lock (RLock).
                    self.stop(name, force=force)
                except AgentError as error:
                    failures.append(f"{name}: {error.message}")
            # Clear any leftover active marker so a later watchdog cannot revive.
            self.configuration.active_profile_file.unlink(missing_ok=True)
            self._supervised.clear()
            if failures:
                raise OperationFailedError("Failed to stop profiles: " + "; ".join(failures))

    def run_integration(self, integration: str, action: str) -> None:
        raise UnsupportedError(f"Unsupported integration action: {integration}:{action}")

    # -- doctor ------------------------------------------------------------

    def doctor_report(self) -> dict[str, Any]:
        payload = self.status_payload()
        unit = self.configuration.systemd_unit_path
        return {
            "controller": {
                "url": f"http://{self.configuration.host}:{self.configuration.port}",
                "reachable": True,
                "profiles": len(payload["statuses"]),
                "integrations": 0,
            },
            "launch_agent": {
                "plist_path": str(unit),
                "installed": unit.is_file(),
                "running": True,
            },
            "integrations": [],
            "profiles_dir": payload["profiles_dir"],
            "controller_root": payload["controller_root"],
            "profiles": [],
            "schema_version": "1",
            "tool_version": AGENT_VERSION,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "healthy": True,
            "findings": [],
            "next_steps": [],
        }

    # -- watchdog ----------------------------------------------------------

    def watchdog_tick(self) -> None:
        """Restart supervised profiles that crashed mid-session only.

        Does *not* read active-profile from disk: that would reload a model on
        every agent/login boot after a prior `switch`. Session supervision is
        the only source of truth for auto-restart.
        """
        if time.monotonic() < self._watchdog_suppressed_until:
            return
        for name in list(self._supervised):
            try:
                profile = self.resolve_profile(name)
            except AgentError:
                self._supervised.discard(name)
                continue
            current = self.status(profile)
            if current["ready"] or current["running"]:
                continue
            try:
                self.start(name)
            except AgentError:
                pass

    def start_watchdog(self) -> None:
        def tick() -> None:
            self.watchdog_tick()
            self._watchdog_timer = threading.Timer(WATCHDOG_INTERVAL_SECONDS, tick)
            self._watchdog_timer.daemon = True
            self._watchdog_timer.start()

        self._watchdog_timer = threading.Timer(WATCHDOG_INTERVAL_SECONDS, tick)
        self._watchdog_timer.daemon = True
        self._watchdog_timer.start()

    # -- internals ---------------------------------------------------------

    def _pid_file(self, name: str) -> Path:
        return self.configuration.run_directory / f"{name}.pid"

    def _read_pid(self, name: str) -> int | None:
        try:
            return int(self._pid_file(name).read_text(encoding="utf-8").strip())
        except (OSError, ValueError):
            return None

    def _process_matches(self, pid: int, profile: Profile) -> bool:
        command = (process_command(pid) or "").lower()
        if not command:
            return False
        markers = [
            profile.name, profile.get("MODEL_ALIAS"), profile.request_model,
            profile.server_model_id, profile.get("MODEL_PATH"), profile.get("MODEL_DIR"),
            profile.get("MODEL_FILE"), profile.get("MODEL_REPO"),
            profile.get("START_COMMAND"),
        ]
        for marker in markers:
            if marker and len(marker) >= 4 and marker.lower() in command:
                return True
        # Port tokens common to llama-server / vllm argv.
        port = profile.endpoint_port
        if port:
            if f"--port {port}" in command or f"--port={port}" in command:
                return True
            if f":{port}" in command:
                return True
        return command_looks_like_model_server(command) and port_is_listening(port)

    def _probe_health(self, profile: Profile) -> tuple[bool, list[str]]:
        if profile.healthcheck_mode == "disabled":
            return False, []
        url = profile.healthcheck_url
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False, []
        remote_allowed = (os.environ.get("ALLOW_REMOTE_HEALTHCHECK") or "").lower() in (
            "1", "true", "yes",
        )
        if not remote_allowed and not is_loopback(parsed.hostname or ""):
            return False, []
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=HEALTH_TIMEOUT_SECONDS) as response:
                body = response.read()
        except (urllib.error.URLError, OSError, ValueError):
            return False, []
        if profile.healthcheck_mode == "http-200":
            return True, []
        try:
            parsed_body = json.loads(body)
            entries = parsed_body.get("data", [])
        except (json.JSONDecodeError, AttributeError):
            return False, []
        ids = [
            entry["id"]
            for entry in entries
            if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"]
        ]
        expected = profile.get("HEALTHCHECK_EXPECT_ID") or profile.server_model_id
        return (bool(ids) if not expected else expected in ids), ids

    def _terminate_profile_processes(
        self,
        profile: Profile,
        primary_pid: int | None,
        *,
        force: bool = False,
    ) -> None:
        if primary_pid:
            if process_is_zombie(primary_pid):
                reap_child(primary_pid)
            else:
                terminate_process_tree(primary_pid, force=force)
        # Always re-check the listen port: vLLM may leave EngineCore on the
        # port under a different pid after the launcher shell exits.
        listener = listener_pid(profile.endpoint_port)
        if listener and listener != primary_pid:
            if force or self._process_matches(listener, profile):
                if process_is_zombie(listener):
                    reap_child(listener)
                else:
                    terminate_process_tree(listener, force=force)

    def _wait_until_stopped(
        self,
        profile: Profile,
        primary_pid: int | None,
        timeout: float = STOP_WAIT_SECONDS,
    ) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if primary_pid:
                reap_child(primary_pid)
            primary_gone = not process_is_alive(primary_pid)
            if primary_gone:
                if not port_is_listening(profile.endpoint_port):
                    return True
                listener = listener_pid(profile.endpoint_port)
                if listener is None:
                    return True
                # Port held by an unrelated process — not our problem for stop.
                if listener != primary_pid and not self._process_matches(listener, profile):
                    return True
                # Our listener is a zombie → treat as stopped for status.
                if process_is_zombie(listener):
                    reap_child(listener)
                    return True
            time.sleep(0.2)
        # Final assessment: zombies / free ports count as stopped.
        if process_is_alive(primary_pid):
            return False
        if not port_is_listening(profile.endpoint_port):
            return True
        listener = listener_pid(profile.endpoint_port)
        if listener is None:
            return True
        if process_is_zombie(listener):
            reap_child(listener)
            return True
        return not self._process_matches(listener, profile)

    def _suppress_watchdog(self) -> None:
        self._watchdog_suppressed_until = time.monotonic() + WATCHDOG_SUPPRESSION_SECONDS

    def _clear_active_profile(self, if_matching: str) -> None:
        try:
            current = self.configuration.active_profile_file.read_text(encoding="utf-8").strip()
        except OSError:
            return
        if current == if_matching:
            self.configuration.active_profile_file.unlink(missing_ok=True)


# --------------------------------------------------------------------------
# HTTP layer (parity with ControllerRouter.swift + HTTPServer limits)
# --------------------------------------------------------------------------


def _error_body(status: int, code: str, message: str) -> tuple[int, dict[str, Any]]:
    return status, {"ok": False, "error": code, "message": message}


class AgentRequestHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = f"ModelSwitchboardAgent/{AGENT_VERSION}"
    service: AgentService
    auth_token: str | None = None
    verbose = False

    # -- plumbing ----------------------------------------------------------

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        if self.verbose:
            sys.stderr.write(f"[http] {format % args}\n")

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        if not self.auth_token:
            return True
        supplied = self.headers.get("Authorization", "")
        return hmac.compare_digest(supplied, f"Bearer {self.auth_token}")

    def _read_body(self) -> bytes | None:
        """Read the request body; None means an error response was already sent."""
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            return b""
        try:
            length = int(raw_length)
            if length < 0:
                raise ValueError
        except ValueError:
            self._send_json(*_error_body(400, "invalid_content_length", "invalid Content-Length"))
            self.close_connection = True
            return None
        if length > MAXIMUM_BODY_BYTES:
            self._send_json(*_error_body(413, "payload_too_large", "request body too large"))
            self.close_connection = True
            return None
        return self.rfile.read(length)

    def _request_object(self, body: bytes) -> dict[str, Any]:
        if not body:
            return {}
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError as error:
            raise InvalidJSONError("invalid JSON") from error
        if not isinstance(parsed, dict):
            raise UsageError("request body must be a JSON object")
        return parsed

    @staticmethod
    def _required_string(payload: dict[str, Any], key: str) -> str:
        value = payload.get(key)
        if not isinstance(value, str) or not value:
            raise UsageError(f"missing required string field: {key}")
        return value

    # -- routing -----------------------------------------------------------

    def do_GET(self) -> None:  # noqa: N802
        self._handle("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._handle("POST")

    def _handle(self, method: str) -> None:
        path = urllib.parse.urlparse(self.path).path or "/"
        try:
            if path.startswith("/api/") and not self._authorized():
                # The body has not been read yet; drop the connection so an
                # unread payload cannot corrupt a kept-alive request stream.
                self.close_connection = True
                self._send_json(*_error_body(401, "unauthorized", "unauthorized"))
                return
            body: bytes | None = b""
            if method == "POST":
                body = self._read_body()
                if body is None:
                    return
            handler = self._route(method, path)
            if handler is None:
                self._send_json(*_error_body(404, "not_found", "not found"))
                return
            self._send_json(200, handler(self._request_object(body or b"")))
        except AgentError as error:
            self._send_json(*_error_body(error.http_status, error.code, error.public_message))
        except Exception:  # pragma: no cover - defensive parity with router fallback
            self._send_json(*_error_body(500, "internal_error", "internal server error"))

    def _route(self, method: str, path: str) -> Callable[[dict[str, Any]], dict[str, Any]] | None:
        service = self.service
        if method == "GET":
            if path == "/api/status":
                return lambda _: service.status_payload()
            if path == "/api/ports":
                return lambda _: service.ports_payload()
            if path == "/api/doctor":
                return lambda _: service.doctor_report()
            if path == "/api/benchmark/status":
                return lambda _: service.benchmark_status()
            if path == "/api/host/metrics":
                return lambda _: service.host_metrics()
            if path == "/api/integrations":
                return lambda _: {
                    "integrations": [],
                    "profiles_dir": str(service.configuration.profiles_directory),
                    "controller_root": str(service.configuration.root),
                }
            return None
        if method == "POST":
            if path == "/api/start":
                return self._profile_action(service.start)
            if path == "/api/stop":
                return self._stop_action(service)
            if path == "/api/restart":
                return self._profile_action(service.restart)
            if path == "/api/switch":
                return self._profile_action(service.switch_profile)
            if path == "/api/stop-all":
                return self._stop_all_action(service)
            if path == "/api/integrations/run":
                def run_integration(payload: dict[str, Any]) -> dict[str, Any]:
                    service.run_integration(
                        self._required_string(payload, "integration"),
                        payload.get("action", "sync"),
                    )
                    return service.action_response()
                return run_integration
            if path == "/api/benchmark/start":
                def benchmark_start(payload: dict[str, Any]) -> dict[str, Any]:
                    selected = payload.get("profiles")
                    if selected is not None and not isinstance(selected, list):
                        raise UsageError("profiles must be a list of strings")
                    names: list[str] | None = None
                    if selected is not None:
                        names = []
                        for item in selected:
                            if not isinstance(item, str) or not item:
                                raise UsageError("profiles must be a list of strings")
                            names.append(item)
                    service.start_benchmark(
                        profiles=names,
                        suite=str(payload.get("suite") or "quick"),
                        allow_concurrent=bool(payload.get("allow_concurrent")),
                        keep_running=bool(payload.get("keep_running")),
                    )
                    return service.action_response()
                return benchmark_start
            return None
        return None

    def _profile_action(
        self, action: Callable[[str], None]
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            action(self._required_string(payload, "profile"))
            return self.service.action_response()
        return handle

    def _stop_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            force = bool(payload.get("force"))
            service.stop(self._required_string(payload, "profile"), force=force)
            return service.action_response()
        return handle

    def _stop_all_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            force = bool(payload.get("force"))
            service.stop_all(force=force)
            return service.action_response()
        return handle

    def _plain_action(
        self, action: Callable[[], None]
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            action()
            return self.service.action_response()
        return handle


def make_server(
    service: AgentService, verbose: bool = False
) -> ThreadingHTTPServer:
    configuration = service.configuration

    class BoundHandler(AgentRequestHandler):
        pass

    BoundHandler.service = service
    BoundHandler.auth_token = configuration.auth_token
    BoundHandler.verbose = verbose

    host = configuration.host.strip("[]")
    server = ThreadingHTTPServer((host, configuration.port), BoundHandler)
    server.daemon_threads = True
    return server


# --------------------------------------------------------------------------
# Pairing link codes
# --------------------------------------------------------------------------


def build_link_code(agent_port: int, direct_host: str | None = None) -> dict[str, str]:
    """Best-effort pairing code the Mac app can paste to prefill a gateway.

    Everything stays local: the code only encodes host/user/ports for the
    gateway form, which remains fully editable on the Mac. With `direct_host`
    (e.g. a Tailscale MagicDNS name or IP) the code describes a direct-URL
    gateway instead of an SSH tunnel.
    """
    short_host = socket.gethostname().split(".")[0] or "remote"
    if direct_host is not None:
        link = (
            "modelswitchboard-gateway://"
            f"{direct_host}"
            f"?name={urllib.parse.quote(short_host)}&agent_port={agent_port}&mode=direct"
        )
        return {
            "user": "",
            "host": direct_host,
            "name": short_host,
            "agent_port": str(agent_port),
            "mode": "direct",
            "link": link,
        }
    user = getpass.getuser()
    fqdn = socket.getfqdn()
    host = fqdn if fqdn and "." in fqdn and fqdn != "localhost" else socket.gethostname()
    link = (
        "modelswitchboard-gateway://"
        f"{urllib.parse.quote(user)}@{host}"
        f"?name={urllib.parse.quote(short_host)}&agent_port={agent_port}"
    )
    return {
        "user": user,
        "host": host,
        "name": short_host,
        "agent_port": str(agent_port),
        "mode": "ssh",
        "link": link,
    }


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="model-switchboard-agent",
        description="Model Switchboard remote agent: launch and monitor model servers over the controller HTTP contract.",
    )
    parser.add_argument("--version", action="version", version=f"model-switchboard-agent {AGENT_VERSION}")
    parser.add_argument("--root", type=Path, default=None, help="agent root directory (default: ~/.local/share/model-switchboard-agent)")
    parser.add_argument(
        "--profiles-dir",
        type=Path,
        default=None,
        help="folder of model .env/.json profiles (default: ~/model-profiles, or config.json / legacy <root>/model-profiles)",
    )
    parser.add_argument("--host", default="127.0.0.1", help="bind host (loopback only unless --unsafe-bind)")
    parser.add_argument("--unsafe-bind", metavar="HOST", default=None, help="bind a non-loopback host; requires --auth-token")
    parser.add_argument("--tailscale", action="store_true", help="bind this host's Tailscale address (tailnet-only; token recommended)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"bind port (default {DEFAULT_PORT})")
    parser.add_argument("--auth-token", default=None, help="bearer token (>= 16 bytes)")
    parser.add_argument("--auth-token-file", type=Path, default=None, help="file containing the bearer token")
    parser.add_argument(
        "--allow-unauthenticated",
        action="store_true",
        help="allow --tailscale without a bearer token (personal tailnet only)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="with stop/stop-all: SIGKILL immediately and clear state",
    )
    parser.add_argument("--json", action="store_true", help="print machine-readable output for CLI commands")
    parser.add_argument("--verbose", action="store_true", help="log HTTP requests to stderr")
    parser.add_argument(
        "--yes",
        action="store_true",
        help="non-interactive link: keep the resolved profiles folder (skip the scan prompt)",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="serve",
        choices=[
            "serve",
            "status",
            "list",
            "start",
            "stop",
            "restart",
            "switch",
            "activate",
            "stop-all",
            "kill-all",
            "link",
            "scan-profiles",
            "scan-ports",
            "ports",
        ],
    )
    parser.add_argument("profiles", nargs="*", help="profile names for start/stop/restart/switch")
    return parser


def build_configuration(args: argparse.Namespace) -> AgentConfiguration:
    token = args.auth_token
    if args.auth_token_file is not None:
        token = args.auth_token_file.expanduser().read_text(encoding="utf-8").strip()
    host = args.host
    unsafe = False
    tailscale = False
    if args.unsafe_bind is not None:
        host = args.unsafe_bind
        unsafe = True
    if getattr(args, "tailscale", False):
        ipv4, _ = tailscale_status()
        if ipv4 is None:
            raise InvalidConfigurationError(
                "--tailscale: no Tailscale address found — is tailscaled running?"
            )
        host = ipv4
        tailscale = True
    explicit_profiles = getattr(args, "profiles_dir", None)
    if explicit_profiles is not None:
        # Persist so serve (systemd) keeps using the same folder without flags.
        save_profiles_directory(args.root or _default_root(), explicit_profiles)
    return AgentConfiguration(
        root=args.root or _default_root(),
        host=host,
        port=args.port,
        auth_token=token,
        unsafe_bind=unsafe,
        tailscale_bind=tailscale,
        allow_unauthenticated=bool(getattr(args, "allow_unauthenticated", False)),
        profiles_dir=explicit_profiles,
    )


def _print_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))


def _run_link(args: argparse.Namespace, configuration: AgentConfiguration) -> int:
    interactive = (
        not args.json
        and not args.yes
        and args.profiles_dir is None
        and sys.stdin.isatty()
        and sys.stdout.isatty()
    )
    if interactive:
        print()
        configuration.profiles_dir = prompt_profiles_directory(
            configuration.root,
            current=configuration.profiles_directory,
        )
    elif args.profiles_dir is not None:
        configuration.profiles_dir = resolve_profiles_directory(
            configuration.root, args.profiles_dir
        )
    configuration.profiles_directory.mkdir(parents=True, exist_ok=True)

    direct_host: str | None = None
    if getattr(args, "tailscale", False):
        ipv4, dns_name = tailscale_status()
        if ipv4 is None and dns_name is None:
            raise InvalidConfigurationError(
                "--tailscale: no Tailscale address found — is tailscaled running?"
            )
        direct_host = dns_name or ipv4
    info = build_link_code(configuration.port, direct_host=direct_host)
    info["profiles_dir"] = str(configuration.profiles_directory)
    claims = scan_port_claim_directories(agent_root=configuration.root)
    info["port_claims"] = len(claims)
    info["scan_roots_env"] = SCAN_ROOTS_ENV
    if args.json:
        _print_json(info)
    else:
        print()
        print("Pairing code for Model Switchboard on your Mac:")
        print()
        print(f"  {info['link']}")
        print()
        print(f"Profiles folder: {configuration.profiles_directory}")
        print("Drop one .env/.json per model there (PORT / START_COMMAND / …), then")
        print("Settings → Remote Gateways → Add Remote Gateway → paste the link.")
        print("Every gateway field stays editable on the Mac.")
        print()
        print("Discovery is host-generic: listening model ports + any numeric")
        print("port folders (…/8080/flags.env) under $HOME or")
        print(f"${SCAN_ROOTS_ENV}. Nothing is invented for unknown ports.")
    return 0


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        configuration = build_configuration(args)
    except AgentError as error:
        sys.stderr.write(f"model-switchboard-agent: {error.message}\n")
        return 2

    service = AgentService(configuration)
    try:
        if args.command == "serve":
            configuration.profiles_directory.mkdir(parents=True, exist_ok=True)
            configuration.run_directory.mkdir(parents=True, exist_ok=True)
            server = make_server(service, verbose=args.verbose)
            service.start_watchdog()
            if configuration.tailscale_bind and configuration.auth_token is None:
                sys.stderr.write(
                    "warning: serving on the tailnet without a bearer token "
                    "(--allow-unauthenticated); anyone on the tailnet can "
                    "start/stop models\n"
                )
            print(f"controller=http://{configuration.host}:{configuration.port}", flush=True)
            print(f"profiles_dir={configuration.profiles_directory}", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                server.shutdown()
            return 0
        if args.command == "status":
            _print_json(service.status_payload(args.profiles or None))
            return 0
        if args.command == "list":
            profiles = service.profiles.load()
            _print_json({
                "profiles": [
                    {
                        "profile": profile.name,
                        "display_name": profile.display_name,
                        "runtime": profile.runtime,
                        "request_model": profile.request_model,
                        "base_url": profile.base_url,
                    }
                    for profile in sorted(profiles.values(), key=lambda p: p.name)
                ],
                "profiles_dir": str(configuration.profiles_directory),
            })
            return 0
        if args.command == "scan-profiles":
            candidates = scan_profile_directories()
            claims = scan_port_claim_directories(agent_root=configuration.root)
            payload = {
                "profiles_dir": str(configuration.profiles_directory),
                "candidates": candidates,
                "port_claims": [
                    {
                        "port": item["port"],
                        "path": item["path"],
                        "display_name": item.get("display_name"),
                        "model_hint": item.get("model_hint"),
                        "runtime_hint": item.get("runtime_hint"),
                    }
                    for item in claims
                ],
                "scan_roots_env": SCAN_ROOTS_ENV,
            }
            if args.json:
                _print_json(payload)
            else:
                print(f"Current profiles folder: {configuration.profiles_directory}")
                if not candidates:
                    print("No launch-looking .env/.json folders found under $HOME.")
                for index, candidate in enumerate(candidates, start=1):
                    print(
                        f"[{index}] {candidate['path']} "
                        f"({candidate['profile_count']}: {', '.join(candidate['files'][:6])})"
                    )
                if claims:
                    print()
                    print("Claimed port folders (numeric dir + launch/flags markers):")
                    for claim in claims:
                        model = claim.get("model_hint") or "—"
                        print(
                            f"  :{claim['port']}  {claim['path']}  "
                            f"({claim.get('runtime_hint') or 'unknown'})  {model}"
                        )
                else:
                    print()
                    print(
                        "No claimed port folders found. Optional: export "
                        f"{SCAN_ROOTS_ENV}=/path/to/scan"
                    )
            return 0
        if args.command in ("scan-ports", "ports"):
            payload = service.ports_payload()
            if args.json:
                _print_json(payload)
            else:
                print("Listening / claimed ports (Ports-style):")
                for entry in payload["ports"]:
                    port = entry["port"]
                    claimed = entry.get("claimed")
                    model = entry.get("model")
                    cmd = (entry.get("command") or "")[:80]
                    flags = []
                    if entry.get("looks_like_model"):
                        flags.append("model-cmd")
                    if claimed:
                        flags.append("claimed")
                    if model and model.get("ready"):
                        flags.append("ready")
                    elif model:
                        flags.append("probe-fail")
                    flag_s = ",".join(flags) if flags else "-"
                    identity = ""
                    if model and model.get("request_model"):
                        identity = str(model["request_model"])
                    elif claimed and claimed.get("model_hint"):
                        identity = str(claimed["model_hint"])
                    print(f"  :{port:<5}  {flag_s:<18}  {identity or cmd or '—'}")
            return 0
        if args.command in ("start", "stop", "restart"):
            if not args.profiles:
                raise UsageError("No profiles selected")
            names = args.profiles
            if names == ["all"]:
                names = sorted(service.profiles.load().keys())
            for name in names:
                if args.command == "stop":
                    service.stop(name, force=bool(args.force))
                else:
                    getattr(service, args.command)(name)
            _print_json(service.action_response())
            return 0
        if args.command in ("switch", "activate"):
            if not args.profiles:
                raise UsageError("No profile selected")
            service.switch_profile(args.profiles[0])
            _print_json(service.action_response())
            return 0
        if args.command in ("stop-all", "kill-all"):
            # kill-all is the nuclear one-liner: always force.
            force = bool(args.force) or args.command == "kill-all"
            service.stop_all(force=force)
            _print_json(service.action_response())
            return 0
        if args.command == "link":
            return _run_link(args, configuration)
    except AgentError as error:
        sys.stderr.write(f"model-switchboard-agent: {error.message}\n")
        return 2 if isinstance(error, (UsageError, InvalidConfigurationError)) else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

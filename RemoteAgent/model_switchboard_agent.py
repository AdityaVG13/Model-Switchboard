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

AGENT_VERSION = "1.0.0"
DEFAULT_PORT = 8877
MINIMUM_TOKEN_BYTES = 16
MAXIMUM_BODY_BYTES = 64 * 1024
WATCHDOG_INTERVAL_SECONDS = 30.0
WATCHDOG_SUPPRESSION_SECONDS = 45.0
STOP_WAIT_SECONDS = 8.0
TERMINATE_TIMEOUT_SECONDS = 12.0
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

PROFILE_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}


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


def process_is_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        # Launched servers are direct children of the agent; reap them here so
        # an exited server does not linger as a zombie that kill(pid, 0) still
        # reports as alive (which would make every stop time out).
        reaped, _ = os.waitpid(pid, os.WNOHANG)
        if reaped == pid:
            return False
    except (ChildProcessError, OSError):
        pass
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


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


def terminate_process_tree(pid: int, timeout: float = TERMINATE_TIMEOUT_SECONDS) -> None:
    _signal_process_tree(pid, signal.SIGTERM)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and process_is_alive(pid):
        time.sleep(0.2)
    if process_is_alive(pid):
        _signal_process_tree(pid, signal.SIGKILL)


def process_command(pid: int | None) -> str | None:
    if not pid:
        return None
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
    if not pid:
        return None
    try:
        result = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            capture_output=True, text=True, timeout=5, check=False,
        )
        rss_kb = float(result.stdout.strip())
    except (OSError, subprocess.TimeoutExpired, ValueError):
        return None
    return round(rss_kb / 1024 * 10) / 10


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


# --------------------------------------------------------------------------
# Agent service (parity with ControllerService.swift)
# --------------------------------------------------------------------------


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
        if not is_loopback(self.host) and not self.tailscale_bind:
            # A tailnet is a private, WireGuard-encrypted network, so the
            # Tailscale bind skips the unsafe-bind gate; a token stays
            # recommended for shared tailnets.
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

    # -- status ------------------------------------------------------------

    def status_payload(self, selected: list[str] | None = None) -> dict[str, Any]:
        loaded = self.profiles.load()
        conflicts = self.profiles.conflicts(loaded)
        names = selected if selected is not None else sorted(loaded.keys())
        statuses = []
        for name in names:
            profile = loaded.get(name)
            if profile is None:
                raise ProfileNotFoundError(name)
            statuses.append(self.status(profile, allow_port_fallback=name not in conflicts))
        return {
            "statuses": statuses,
            "benchmark": self.benchmark_status(),
            "integrations": [],
            "profiles_dir": str(self.configuration.profiles_directory),
            "controller_root": str(self.configuration.root),
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

    def benchmark_status(self) -> dict[str, Any]:
        return {"running": False, "pid": None, "log_path": None, "latest": None}

    def status(self, profile: Profile, allow_port_fallback: bool = True) -> dict[str, Any]:
        ready, server_ids = self._probe_health(profile)
        pid = self._read_pid(profile.name)
        if pid is not None and not process_is_alive(pid):
            self._pid_file(profile.name).unlink(missing_ok=True)
            pid = None
        if pid is None and allow_port_fallback:
            listener = listener_pid(profile.endpoint_port)
            if listener is not None and self._process_matches(listener, profile):
                pid = listener
        label, _, launch_mode = profile.runtime_spec
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
            "pid": pid,
            "running": process_is_alive(pid),
            "ready": ready,
            "server_ids": server_ids,
            "rss_mb": process_rss_mb(pid),
            "command": process_command(pid),
            "log_path": profile.log_path,
        }

    # -- lifecycle ---------------------------------------------------------

    def start(self, name: str) -> None:
        with self._mutation_lock:
            loaded = self.profiles.load()
            if name not in loaded:
                raise ProfileNotFoundError(name)
            self.profiles.ensure_unique(name, "start", loaded)
            profile = loaded[name]
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

    def stop(self, name: str) -> None:
        with self._mutation_lock:
            self._suppress_watchdog()
            self._clear_active_profile(if_matching=name)
            profile = self.profiles.profile(name)
            current = self.status(profile)
            stop_error: Exception | None = None

            stop_command = (profile.get("STOP_COMMAND") or "").strip()
            if stop_command:
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

            if profile.get("STOP_COMMAND_ONLY") != "1":
                self._terminate_profile_processes(profile, current.get("pid"))
                if not self._wait_until_stopped(profile, current.get("pid")):
                    raise OperationFailedError(
                        f"failed to stop {name}: endpoint or process is still alive"
                    )
            self._pid_file(name).unlink(missing_ok=True)
            if stop_error is not None:
                raise OperationFailedError(f"STOP_COMMAND failed for {name}: {stop_error}")

    def restart(self, name: str) -> None:
        with self._mutation_lock:
            loaded = self.profiles.load()
            if name not in loaded:
                raise ProfileNotFoundError(name)
            self.profiles.ensure_unique(name, "restart", loaded)
            self.stop(name)
            self.start(name)

    def switch_profile(self, name: str) -> None:
        with self._mutation_lock:
            loaded = self.profiles.load()
            if name not in loaded:
                raise ProfileNotFoundError(name)
            self.profiles.ensure_unique(name, "activate", loaded)
            for item in self.status_payload()["statuses"]:
                if item["profile"] != name and item["running"]:
                    self.stop(item["profile"])
            self.start(name)
            self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
            self.configuration.active_profile_file.write_text(f"{name}\n", encoding="utf-8")

    def stop_all(self) -> None:
        with self._mutation_lock:
            failures: list[str] = []
            for name in sorted(self.profiles.load().keys()):
                try:
                    self.stop(name)
                except AgentError as error:
                    failures.append(f"{name}: {error.message}")
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
        if time.monotonic() < self._watchdog_suppressed_until:
            return
        try:
            name = self.configuration.active_profile_file.read_text(encoding="utf-8").strip()
        except OSError:
            return
        if not name:
            return
        try:
            profile = self.profiles.profile(name)
        except AgentError:
            self.configuration.active_profile_file.unlink(missing_ok=True)
            return
        current = self.status(profile)
        if not current["ready"] and not current["running"]:
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
        ]
        return any(
            marker.lower() in command
            for marker in markers
            if marker and len(marker) >= 4
        )

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

    def _terminate_profile_processes(self, profile: Profile, primary_pid: int | None) -> None:
        if primary_pid:
            terminate_process_tree(primary_pid)
        listener = listener_pid(profile.endpoint_port)
        if listener and listener != primary_pid and self._process_matches(listener, profile):
            terminate_process_tree(listener)

    def _wait_until_stopped(self, profile: Profile, primary_pid: int | None) -> bool:
        deadline = time.monotonic() + STOP_WAIT_SECONDS
        while time.monotonic() < deadline:
            if not process_is_alive(primary_pid):
                if not port_is_listening(profile.endpoint_port):
                    return True
                listener = listener_pid(profile.endpoint_port)
                listener_alive = listener is not None and (
                    listener == primary_pid or self._process_matches(listener, profile)
                )
                if not listener_alive:
                    return True
            time.sleep(0.2)
        return False

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
            if path == "/api/doctor":
                return lambda _: service.doctor_report()
            if path == "/api/benchmark/status":
                return lambda _: service.benchmark_status()
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
                return self._profile_action(service.stop)
            if path == "/api/restart":
                return self._profile_action(service.restart)
            if path == "/api/switch":
                return self._profile_action(service.switch_profile)
            if path == "/api/stop-all":
                return self._plain_action(service.stop_all)
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
                    raise UnsupportedError("Benchmarks are not supported by the remote agent")
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
            "link",
            "scan-profiles",
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
                    "note: serving on the tailnet without a bearer token; "
                    "add --auth-token-file if other people share this tailnet\n"
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
            payload = {
                "profiles_dir": str(configuration.profiles_directory),
                "candidates": candidates,
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
            return 0
        if args.command in ("start", "stop", "restart"):
            if not args.profiles:
                raise UsageError("No profiles selected")
            names = args.profiles
            if names == ["all"]:
                names = sorted(service.profiles.load().keys())
            for name in names:
                getattr(service, args.command)(name)
            _print_json(service.action_response())
            return 0
        if args.command in ("switch", "activate"):
            if not args.profiles:
                raise UsageError("No profile selected")
            service.switch_profile(args.profiles[0])
            _print_json(service.action_response())
            return 0
        if args.command == "stop-all":
            service.stop_all()
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

"""Shared types and process/host helpers for the remote agent and discovery.

Imported by both `model_switchboard_agent` and `discovery`. Lives beside them
so `python3 model_switchboard_agent.py` resolves it as a sibling module.
"""

from __future__ import annotations

import json
import os
import re
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any

DEFAULT_PORT = 8877

TERMINATE_TIMEOUT_SECONDS = 20.0

FORCE_TERMINATE_TIMEOUT_SECONDS = 3.0

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

SCAN_ROOTS_ENV = "MODEL_SWITCHBOARD_SCAN_ROOTS"

PROFILE_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}

def is_loopback(host: str) -> bool:
    return host.strip().strip("[]").lower() in LOOPBACK_HOSTS

class _NoHTTPRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Refuse redirects so loopback-only health/discovery cannot SSRF off-box."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        return None

def _urlopen_no_redirect(request: urllib.request.Request, timeout: float):
    # Empty ProxyHandler so HTTP(S)_PROXY cannot pull loopback health/discovery
    # (or benchmark prompts) off-box on corp GPU hosts.
    opener = urllib.request.build_opener(
        _NoHTTPRedirectHandler(),
        urllib.request.ProxyHandler({}),
    )
    return opener.open(request, timeout=timeout)

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
    code = "usage_error"
    public_message = "invalid request"

class InvalidConfigurationError(AgentError):
    http_status = 400
    code = "invalid_configuration"
    public_message = "invalid request"

class InvalidProfileError(AgentError):
    http_status = 400
    code = "invalid_profile"
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

    def __init__(self, message: str):
        super().__init__(message)
        # Busy-port / ensure_unique detail is operator-actionable — surface it.
        self.public_message = message

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
    # L07-part: unknown is a first-class runtime id, not a special-cased string.
    "unknown": ("Unknown", ["discovered", "external"], "external"),
}

def canonical_runtime(value: str | None) -> str:
    # L06: an absent runtime stays unknown — never silently "llama.cpp".
    normalized = (value or "unknown").strip().lower().replace("_", "-")
    return RUNTIME_ALIASES.get(normalized, normalized)

def first_known(*values: str | None) -> str:
    """First value that is not None/empty and not the "unknown" sentinel.

    L07: the single place "unknown" is special-cased for prefer-known merges.
    Every caller that must prefer a real runtime over an unknown one routes
    through here instead of re-implementing the rule.
    """
    for value in values:
        if value and value != "unknown":
            return value
    return "unknown"

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
    # L24: parsed tag list supplied at the claim boundary (profile_from_claim).
    # Env-file profiles leave this None; RUNTIME_TAGS/TAGS parse in
    # runtime_tags below — the single comma-string parse site.
    tags: list[str] | None = None

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
            list(self.tags)
            if self.tags is not None
            else parse_tag_string(self.values.get("RUNTIME_TAGS") or self.values.get("TAGS") or "")
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

_WEIGHT_SUFFIXES = (".gguf", ".safetensors", ".bin", ".pt", ".pth", ".onnx")

def _looks_like_local_fs_path(raw: str) -> bool:
    """True for filesystem-looking paths; false for HF ids and URLs."""
    value = (raw or "").strip()
    if not value or "://" in value:
        return False
    if value.startswith(("/", "~", "./", "../")):
        return True
    lower = value.lower()
    return any(lower.endswith(suffix) for suffix in _WEIGHT_SUFFIXES)

def resolve_model_artifact_fields(
    values: dict[str, str] | dict[str, Any],
) -> tuple[str, str, str]:
    """Single owner of the MODEL_DIR / MODEL_PATH / MODEL_FILE precedence (L20).

    Documented precedence:
      1. MODEL_DIR  — weights/checkpoint directory (HF / vLLM style).
      2. MODEL_PATH — explicit path, file or directory.
      3. MODEL_FILE — single-file weights; a RELATIVE MODEL_FILE resolves
         against MODEL_DIR when the directory looks like a local path.
    Non-local values (HF ids, URLs) are kept as data but never validated
    against disk. Callers use this one function instead of re-deriving the
    triple or re-implementing the relative-join rule.
    """
    model_dir_raw = str(values.get("MODEL_DIR") or "").strip()
    model_path_raw = str(values.get("MODEL_PATH") or "").strip()
    model_file_raw = str(values.get("MODEL_FILE") or "").strip()
    resolved_file = model_file_raw
    if model_file_raw and not Path(model_file_raw).expanduser().is_absolute():
        if model_dir_raw and _looks_like_local_fs_path(model_dir_raw):
            resolved_file = str(Path(model_dir_raw).expanduser() / model_file_raw)
    return model_dir_raw, model_path_raw, resolved_file

def missing_local_model_artifacts(values: dict[str, str] | dict[str, Any]) -> list[str]:
    """Return local MODEL_* paths that are missing on disk (empty = ok / nothing to check)."""
    missing: list[str] = []
    model_dir_raw, model_path_raw, model_file_raw = resolve_model_artifact_fields(values)

    if model_dir_raw and _looks_like_local_fs_path(model_dir_raw):
        model_dir = Path(model_dir_raw).expanduser()
        if not model_dir.is_dir():
            missing.append(str(model_dir))

    if model_path_raw and _looks_like_local_fs_path(model_path_raw):
        model_path = Path(model_path_raw).expanduser()
        if not (model_path.is_file() or model_path.is_dir()):
            missing.append(str(model_path))

    if model_file_raw and _looks_like_local_fs_path(model_file_raw):
        model_file = Path(model_file_raw).expanduser()
        # HF / vLLM style checkpoints are directories; single-file weights are files.
        # Claim profiles historically stuffed MODEL= into MODEL_FILE for both.
        if not (model_file.is_file() or model_file.is_dir()):
            missing.append(str(model_file))

    # Stable unique order
    seen: set[str] = set()
    ordered: list[str] = []
    for path in missing:
        if path not in seen:
            seen.add(path)
            ordered.append(path)
    return ordered

def parse_tag_string(raw: str) -> list[str]:
    """Comma/space-separated tag list from an env value (L20/L24).

    The single parse owner for the RUNTIME_TAGS/TAGS env format; claim
    profiles pass a parsed list via Profile.tags instead of re-encoding.
    """
    return (raw or "").replace(",", " ").split()

def process_stat_state(pid: int) -> str | None:
    """Return the /proc process state, including Z for zombies, when available."""
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
    """Return whether /proc stat is an authoritative process table."""
    try:
        return Path("/proc/self/stat").is_file()
    except OSError:
        return False

def process_is_zombie(pid: int | None) -> bool:
    """Detect defunct processes through /proc or the ps fallback."""
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
    """Return liveness while treating zombies as dead and reaping owned children."""
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

_GPU_METRICS_CACHE: dict[str, Any] = {"at": 0.0, "payload": None}

_GPU_METRICS_TTL_SECONDS = 2.0

_CPU_SAMPLE_LOCK = threading.Lock()

_CPU_PREV: tuple[float, float] | None = None

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

_NVIDIA_SMI_MISSING = frozenset({
    "",
    "n/a",
    "[n/a]",
    "na",
    "not supported",
    "[not supported]",
})

def _nvidia_smi_number(raw: str) -> float | None:
    """Parse an nvidia-smi csv field. N/A / Not Supported are missing, not zero."""
    text = raw.strip()
    if text.lower() in _NVIDIA_SMI_MISSING:
        return None
    try:
        return float(text)
    except ValueError:
        return None

def _apply_unified_memory_vram(
    gpus: list[dict[str, Any]],
    vram_by_pid: dict[int, float],
    mem: dict[str, Any] | None,
) -> None:
    """Fill GB10 N/A framebuffer fields without lying that host RAM used is VRAM.

    nvidia-smi `memory.used`/`memory.total` are N/A on unified-memory iGPUs
    (DGX Spark / GB10). Per-process compute-apps memory still works and matches
    the NVIDIA DGX dashboard VRAM used figure. Host MemTotal is the shared
    pool size (denominator only). Never copy /proc MemUsed into vram_used_mb.
    """
    mem_total = mem.get("total_mb") if isinstance(mem, dict) else None
    apps_used = round(sum(vram_by_pid.values()) * 10) / 10
    for entry in gpus:
        if entry.get("vram_total_mb") is None and mem_total is not None:
            entry["vram_total_mb"] = mem_total
        if entry.get("vram_used_mb") is None:
            entry["vram_used_mb"] = apps_used

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
        except ValueError:
            continue
        gpus.append(
            {
                "index": index,
                "name": parts[1],
                "util_percent": _nvidia_smi_number(parts[2]),
                "temp_c": _nvidia_smi_number(parts[3]),
                "vram_used_mb": _nvidia_smi_number(parts[4]),
                "vram_total_mb": _nvidia_smi_number(parts[5]),
            }
        )
    # Per-process VRAM (compute apps). Still populated on GB10 when FB is N/A.
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
                except ValueError:
                    continue
                mem = _nvidia_smi_number(parts[1])
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


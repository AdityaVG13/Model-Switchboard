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


def path_is_regular_file(path: Path) -> bool:
    """``Path.is_file()`` that treats permission errors as absent.

    Numeric uid dirs such as ``/run/user/126`` match port-claim names; stating
    ``flags.env`` or ``MODEL=*`` there must not 500 ``/api/status``.
    """
    try:
        return path.is_file()
    except OSError:
        return False


def path_is_dir(path: Path) -> bool:
    """``Path.is_dir()`` that treats permission errors as absent."""
    try:
        return path.is_dir()
    except OSError:
        return False


def path_exists(path: Path) -> bool:
    """True when ``path`` is a readable file or directory; OSError is absent."""
    return path_is_regular_file(path) or path_is_dir(path)

SCAN_ROOTS_ENV = "MODEL_SWITCHBOARD_SCAN_ROOTS"

PROFILE_KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}

def is_loopback(host: str) -> bool:
    return host.strip().strip("[]").lower() in LOOPBACK_HOSTS


def is_valid_tcp_port(port: int) -> bool:
    return 1 <= port <= 65535


def _round_tenths(value: float) -> float:
    return round(value * 10) / 10


def env_flag(raw: str | None) -> bool:
    """Single owner of env-string booleans. Empty never matches."""
    return (raw or "").strip().lower() in {"1", "true", "yes"}


def strip_export_prefix(line: str) -> str:
    prefix = "export "
    if line.startswith(prefix):
        return line[len(prefix):].strip()
    return line


def _stripped_assignment_line(raw_line: str) -> str | None:
    line = raw_line.strip()
    if not line or line.startswith("#"):
        return None
    return strip_export_prefix(line)


def _profile_assignment_key(line: str, equals: int) -> str | None:
    key = line[:equals].strip()
    return key if PROFILE_KEY_RE.match(key) else None


def _assignment_key_rest(line: str) -> tuple[str, str] | None:
    equals = line.find("=")
    if equals <= 0:
        return None
    key = _profile_assignment_key(line, equals)
    if key is None:
        return None
    return key, line[equals + 1 :].strip()


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
        # Busy-port / ensure_unique detail is operator-actionable - surface it.
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
    "mlx": ("MLX", ["managed", "openai-compatible", "mlx", "apple-silicon"], "adapter"),
    "rvllm-mlx": ("rVLLM MLX", ["managed", "openai-compatible", "mlx", "continuous-batching"], "adapter"),
    "vllm-mlx": ("vLLM-MLX", ["managed", "openai-compatible", "mlx", "server"], "adapter"),
    "ddtree-mlx": ("DDTree MLX", ["managed", "openai-compatible", "mlx", "speculative-decoding"], "adapter"),
    "turboquant": ("TurboQuant", ["managed", "openai-compatible", "gguf", "quantized"], "adapter"),
    "mlx-vlm": ("MLX-VLM", ["managed", "openai-compatible", "mlx", "vision"], "adapter"),
    "mlx-omni-server": ("MLX Omni Server", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
    "mlx-openai-server": ("MLX OpenAI Server", ["managed", "openai-compatible", "mlx"], "adapter"),
    "mlx-llm-server": ("MLX-LLM Server", ["managed", "openai-compatible", "mlx"], "adapter"),
    "mlx-serve": ("MLX Serve", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
    "mlxengine": ("MLX Engine", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
    "ollmlx": ("ollmlx", ["external", "openai-compatible", "mlx"], "external"),
    "omlx": ("oMLX", ["managed", "openai-compatible", "mlx", "agent-cache"], "adapter"),
    "mlc-llm": ("MLC-LLM", ["managed", "openai-compatible", "mlc", "metal"], "adapter"),
    "nexa": ("Nexa SDK", ["managed", "openai-compatible", "multimodal"], "adapter"),
    "lm-studio": ("LM Studio", ["external", "openai-compatible", "desktop"], "external"),
    "jan": ("Jan", ["external", "openai-compatible", "desktop"], "external"),
    # L07-part: unknown is a first-class runtime id, not a special-cased string.
    "unknown": ("Unknown", ["discovered", "external"], "external"),
}

def canonical_runtime(value: str | None) -> str:
    # L06: an absent runtime stays unknown - never silently "llama.cpp".
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


def first_present(*values: Any) -> Any:
    """First truthy value, or the last argument (including a falsy last)."""
    if not values:
        return None
    for value in values[:-1]:
        if value:
            return value
    return values[-1]


def openai_model_ids_from_entries(entries: Any) -> list[str]:
    return [
        entry["id"]
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"]
    ]


def run_captured(argv: list[str], timeout: float) -> subprocess.CompletedProcess[str] | None:
    try:
        return subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None


def is_placeholder_model_name(value: str | None) -> bool:
    """True for the synthetic "port-N" identity the claim scanner invents.

    A claim folder with no model-name key gets request_model="port-N" so the
    profile validates; that placeholder is NOT an operator-asserted identity
    and must never gate a health check or become the visible model name.
    """
    raw = (value or "").strip()
    return raw.startswith("port-") and raw[len("port-"):].isdigit()

def _unquoted_env_value(raw: str) -> str:
    return raw.split("#", 1)[0].strip()


def _quoted_env_value(raw: str, first: str, file: Path, line: int) -> str:
    if len(raw) < 2 or raw[-1] != first:
        raise InvalidProfileError(f"{file}:{line}: invalid quoted value")
    inner = raw[1:-1]
    if first == "'":
        return inner
    return _unescape_double_quoted(inner)


def _parse_env_value(raw: str, file: Path, line: int) -> str:
    first = raw[:1]
    if first not in ("'", '"'):
        return _unquoted_env_value(raw)
    return _quoted_env_value(raw, first, file, line)


def _unescape_quoted_char(character: str, escaped: bool) -> tuple[str, bool]:
    if escaped:
        return {"n": "\n", "t": "\t"}.get(character, character), False
    if character == "\\":
        return "", True
    return character, False


def _unescape_double_quoted(inner: str) -> str:
    value: list[str] = []
    escaped = False
    for character in inner:
        piece, escaped = _unescape_quoted_char(character, escaped)
        if piece:
            value.append(piece)
    if escaped:
        value.append("\\")
    return "".join(value)

def parse_env_profile(file: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    content = file.read_text(encoding="utf-8")
    for offset, raw_line in enumerate(content.splitlines()):
        parsed = _env_profile_assignment(raw_line, file, offset + 1)
        if parsed is None:
            continue
        key, value = parsed
        values[key] = value
    return values


def _env_assignment_key(line: str, file: Path, line_no: int) -> tuple[str, str]:
    equals = line.find("=")
    if equals < 0:
        raise InvalidProfileError(f"{file}:{line_no}: expected KEY=value")
    key = line[:equals].strip()
    if not PROFILE_KEY_RE.match(key):
        raise InvalidProfileError(f"{file}:{line_no}: invalid profile key {key}")
    return key, line[equals + 1:].strip()


def _env_profile_assignment(raw_line: str, file: Path, line_no: int) -> tuple[str, str] | None:
    line = _stripped_assignment_line(raw_line)
    if line is None:
        return None
    key, raw_value = _env_assignment_key(line, file, line_no)
    return key, _parse_env_value(raw_value, file, line_no)

def _json_profile_scalar(value: Any) -> str:
    if isinstance(value, str):
        return value
    encoded = _json_profile_encoded(value)
    return encoded if encoded is not None else str(value)


def _json_profile_null_or_container(value: Any) -> str | None:
    if value is None:
        return ""
    if isinstance(value, (list, dict)):
        return json.dumps(value, separators=(",", ":"))
    return None


def _json_profile_encoded(value: Any) -> str | None:
    if isinstance(value, bool):
        # NSNumber.stringValue renders booleans as 1/0.
        return "1" if value else "0"
    if isinstance(value, (int, float)):
        return str(value)
    return _json_profile_null_or_container(value)


def _json_profile_item(file: Path, key: Any, value: Any) -> tuple[str, str]:
    if not PROFILE_KEY_RE.match(key):
        raise InvalidProfileError(f"{file}: invalid profile key {key}")
    return key, _json_profile_scalar(value)


def parse_json_profile(file: Path) -> dict[str, str]:
    try:
        parsed = json.loads(file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise InvalidProfileError(f"Profile JSON is invalid: {file}: {error}") from error
    if not isinstance(parsed, dict):
        raise InvalidProfileError(f"Profile JSON must be an object: {file}")
    values: dict[str, str] = {}
    for key, value in parsed.items():
        item_key, item_value = _json_profile_item(file, key, value)
        values[item_key] = item_value
    return values


def _bracket_ipv6_host(host: str) -> str:
    if ":" in host and not host.startswith("["):
        return f"[{host}]"
    return host


def _profile_host_literal(values: dict[str, str]) -> str:
    configured_host = (values.get("HOST") or "127.0.0.1").strip()
    host = configured_host if is_loopback(configured_host) else "127.0.0.1"
    return _bracket_ipv6_host(host)


def _require_profile_identity(name: str, normalized: dict[str, str]) -> None:
    if not normalized.get("REQUEST_MODEL", ""):
        raise InvalidProfileError(f"{name}: missing REQUEST_MODEL")
    if not normalized.get("PORT") and not normalized.get("BASE_URL"):
        raise InvalidProfileError(f"{name}: missing PORT or BASE_URL")


@dataclass
class Profile:
    name: str
    values: dict[str, str]
    # L24: parsed tag list supplied at the claim boundary (profile_from_claim).
    # Env-file profiles leave this None; RUNTIME_TAGS/TAGS parse in
    # runtime_tags below - the single comma-string parse site.
    tags: list[str] | None = None
    origin: str = "profile"
    healthcheck_any_id: bool = False

    def __post_init__(self) -> None:
        normalized = dict(self.values)
        normalized.setdefault("PROFILE_NAME", self.name)
        normalized.setdefault("DISPLAY_NAME", self.name)
        _require_profile_identity(self.name, normalized)
        flag = env_flag(normalized.pop("HEALTHCHECK_ANY_ID", None))
        self.healthcheck_any_id = self.healthcheck_any_id or flag
        if self.origin not in {"profile", "claim"}:
            self.origin = "profile"
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
        configured = self._configured_runtime_tags()
        _, spec_tags, _ = self.runtime_spec
        return _unique_preserve([self.runtime] + spec_tags + [tag.lower() for tag in configured])

    def _configured_runtime_tags(self) -> list[str]:
        if self.tags is not None:
            return list(self.tags)
        return parse_tag_string(self.values.get("RUNTIME_TAGS") or self.values.get("TAGS") or "")

    @property
    def request_model(self) -> str:
        return self.values.get("REQUEST_MODEL", self.name)

    @property
    def server_model_id(self) -> str:
        return self.values.get("SERVER_MODEL_ID") or self.request_model

    @property
    def healthcheck_mode(self) -> str:
        raw = (self.values.get("HEALTHCHECK_MODE") or "openai-models").lower()
        if raw in {"http-200", "http200"}:
            return "http-200"
        if raw in {"disabled", "off", "none"}:
            return "disabled"
        return "openai-models"

    @property
    def endpoint_host(self) -> str:
        host = self.values.get("HOST", "")
        if host in {"0.0.0.0", "::", "[::]"}:
            return "127.0.0.1"
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
        return f"http://{_profile_host_literal(self.values)}:{port}/v1"

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

def _has_weight_suffix(value: str) -> bool:
    lower = value.lower()
    return any(lower.endswith(suffix) for suffix in _WEIGHT_SUFFIXES)


def _has_local_path_prefix(value: str) -> bool:
    return value.startswith(("/", "~", "./", "../"))


def _looks_like_local_fs_path(raw: str) -> bool:
    """True for filesystem-looking paths; false for HF ids and URLs."""
    value = (raw or "").strip()
    if not value or "://" in value:
        return False
    if _has_local_path_prefix(value):
        return True
    return _has_weight_suffix(value)

def resolve_model_artifact_fields(
    values: dict[str, str] | dict[str, Any],
) -> tuple[str, str, str]:
    """Single owner of the MODEL_DIR / MODEL_PATH / MODEL_FILE precedence (L20).

    Documented precedence:
      1. MODEL_DIR  - weights/checkpoint directory (HF / vLLM style).
      2. MODEL_PATH - explicit path, file or directory.
      3. MODEL_FILE - single-file weights; a RELATIVE MODEL_FILE resolves
         against MODEL_DIR when the directory looks like a local path.
    Non-local values (HF ids, URLs) are kept as data but never validated
    against disk. Callers use this one function instead of re-deriving the
    triple or re-implementing the relative-join rule.
    """
    model_dir_raw = str(values.get("MODEL_DIR") or "").strip()
    model_path_raw = str(values.get("MODEL_PATH") or "").strip()
    model_file_raw = str(values.get("MODEL_FILE") or "").strip()
    return model_dir_raw, model_path_raw, _resolve_relative_model_file(model_dir_raw, model_file_raw)


def _resolve_relative_model_file(model_dir_raw: str, model_file_raw: str) -> str:
    if _join_relative_model_file(model_dir_raw, model_file_raw):
        return str(Path(model_dir_raw).expanduser() / model_file_raw)
    return model_file_raw


def _join_relative_model_file(model_dir_raw: str, model_file_raw: str) -> bool:
    if not model_file_raw or Path(model_file_raw).expanduser().is_absolute():
        return False
    return bool(model_dir_raw and _looks_like_local_fs_path(model_dir_raw))

def _expanded_missing_path(path: Path, *, require_dir: bool) -> str | None:
    present = path_is_dir(path) if require_dir else path_exists(path)
    return None if present else str(path)


def _missing_local_path(raw: str, *, require_dir: bool) -> str | None:
    if not (raw and _looks_like_local_fs_path(raw)):
        return None
    return _expanded_missing_path(Path(raw).expanduser(), require_dir=require_dir)


def _append_missing_local(
    missing: list[str],
    raw: str,
    *,
    require_dir: bool = False,
) -> None:
    missing_path = _missing_local_path(raw, require_dir=require_dir)
    if missing_path is not None:
        missing.append(missing_path)


def missing_local_model_artifacts(values: dict[str, str] | dict[str, Any]) -> list[str]:
    """Return local MODEL_* paths that are missing on disk (empty = ok / nothing to check)."""
    missing: list[str] = []
    model_dir_raw, model_path_raw, model_file_raw = resolve_model_artifact_fields(values)
    _append_missing_local(missing, model_dir_raw, require_dir=True)
    _append_missing_local(missing, model_path_raw)
    # HF / vLLM style checkpoints are directories; single-file weights are files.
    # Claim profiles historically stuffed MODEL= into MODEL_FILE for both.
    _append_missing_local(missing, model_file_raw)
    return _unique_preserve(missing)

def parse_tag_string(raw: str) -> list[str]:
    """Comma/space-separated tag list from an env value (L20/L24).

    The single parse owner for the RUNTIME_TAGS/TAGS env format; claim
    profiles pass a parsed list via Profile.tags instead of re-encoding.
    """
    return (raw or "").replace(",", " ").split()


def _append_unique(result: list[str], item: str) -> None:
    if item not in result:
        result.append(item)


def _unique_preserve(items: list[str]) -> list[str]:
    result: list[str] = []
    for item in items:
        _append_unique(result, item)
    return result

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

def _state_is_zombie(state: str | None) -> bool:
    return bool(state and state.upper().startswith("Z"))


def _zombie_without_proc_stat(pid: int) -> bool:
    if _proc_stat_table_available():
        return False
    return _state_is_zombie(process_ps_state(pid))


def process_is_zombie(pid: int | None) -> bool:
    """Detect defunct processes through /proc or the ps fallback."""
    if not pid or pid <= 0:
        return False
    state = process_stat_state(pid)
    if state is not None:
        return _state_is_zombie(state)
    return _zombie_without_proc_stat(pid)

def reap_child(pid: int) -> bool:
    """Reap *pid* if it is our zombie/exited child. True if reaped or gone."""
    try:
        reaped, _ = os.waitpid(pid, os.WNOHANG)
        return reaped == pid
    except ChildProcessError:
        return False
    except OSError:
        return False

def _alive_from_letter(state: str | None) -> bool | None:
    if state is None:
        return None
    return not _state_is_zombie(state)


def _alive_via_kill(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        # Exists but we cannot signal it; state probes already failed.
        return True
    return True


def process_is_alive(pid: int | None) -> bool:
    """Return liveness while treating zombies as dead and reaping owned children."""
    if not pid or pid <= 0:
        return False
    # Reap our own children first so unreaped zombies do not linger.
    if reap_child(pid):
        return False
    return _alive_after_reap(pid)


def _alive_after_reap(pid: int) -> bool:
    letter = _alive_from_letter(process_stat_state(pid))
    if letter is not None:
        # Authoritative on Linux: Z is not "running"; any other letter is live.
        return letter
    if _proc_stat_table_available():
        # /proc is the process table and this pid has no entry ⇒ dead.
        return False
    return _alive_without_proc(pid)


def _alive_without_proc(pid: int) -> bool:
    # No /proc (macOS, etc.): ps state, then kill(0).
    letter = _alive_from_letter(process_ps_state(pid))
    if letter is not None:
        return letter
    return _alive_via_kill(pid)

def _signal_process_group(pid: int, signal_number: int) -> bool:
    pgid = os.getpgid(pid)
    if pgid > 0 and pgid != os.getpgrp():
        os.killpg(pgid, signal_number)
        return True
    return False


def _kill_process_group(pid: int, signal_number: int) -> bool:
    try:
        return _signal_process_group(pid, signal_number)
    except ProcessLookupError:
        return True
    except PermissionError:
        return False


def _signal_process_tree(pid: int, signal_number: int) -> None:
    if _kill_process_group(pid, signal_number):
        return
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
        _reap_until_dead(pid, min(timeout, FORCE_TERMINATE_TIMEOUT_SECONDS), 0.1)
        reap_child(pid)
        return

    _signal_process_tree(pid, signal.SIGTERM)
    _reap_until_dead(pid, timeout, 0.2)
    if process_is_alive(pid):
        _signal_process_tree(pid, signal.SIGKILL)
        _reap_until_dead(pid, FORCE_TERMINATE_TIMEOUT_SECONDS, 0.1)
    reap_child(pid)


def _reap_until_dead(pid: int, timeout: float, interval: float) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and process_is_alive(pid):
        reap_child(pid)
        time.sleep(interval)

def process_command(pid: int | None) -> str | None:
    """Return the process command line for *pid*, or None.

    Linux: read /proc/<pid>/cmdline (NUL-separated → spaces) without spawning.
    Other platforms, or empty/missing /proc entry: fall back to `ps -o command=`.
    """
    if not pid:
        return None
    command = _proc_cmdline(pid)
    if command:
        return command
    return _ps_command(pid)


def _proc_cmdline(pid: int) -> str | None:
    # Prefer /proc on Linux -- avoids one `ps` subprocess per listener PID.
    try:
        raw = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return None
    if not raw:
        return None
    command = raw.replace(b"\x00", b" ").decode("utf-8", errors="replace").strip()
    return command or None


def _ps_command(pid: int) -> str | None:
    result = run_captured(["ps", "-o", "command=", "-p", str(pid)], 5)
    if result is None:
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
    rss = _rss_mb_from_proc(pid)
    if rss is not None:
        return rss
    return _rss_mb_from_ps(pid)


def _rss_mb_from_proc(pid: int) -> float | None:
    # Prefer /proc on Linux -- avoids one `ps` subprocess per listener PID.
    try:
        status = Path(f"/proc/{pid}/status").read_text(encoding="utf-8")
    except OSError:
        return None
    if not status:
        return None
    return _rss_mb_from_proc_status(status)


def _rss_mb_from_ps(pid: int) -> float | None:
    result = run_captured(["ps", "-o", "rss=", "-p", str(pid)], 5)
    if result is None:
        return None
    try:
        rss_kb = float(result.stdout.strip())
    except ValueError:
        return None
    return round(rss_kb / 1024 * 10) / 10


def _vmrss_mb(line: str) -> float | None:
    parts = line.split()
    if len(parts) < 2:
        return None
    try:
        return round(float(parts[1]) / 1024 * 10) / 10
    except ValueError:
        return None


def _rss_mb_from_proc_status(status: str) -> float | None:
    for line in status.splitlines():
        if line.startswith("VmRSS:"):
            return _vmrss_mb(line)
    return None

_GPU_METRICS_CACHE: dict[str, Any] = {"at": 0.0, "payload": None}

_GPU_METRICS_TTL_SECONDS = 2.0

# SAFETY: the cache dict is read by concurrent ThreadingHTTPServer handlers.
# Readers may see a torn (timestamp, payload) pair under CPython's GIL; the
# write order below (payload first, timestamp last) makes a torn read at worst
# extend the previous TTL by one fill - never serve a new timestamp with the
# OLD payload. Do not reorder the writes.
_GPU_METRICS_CACHE_LOCK = threading.Lock()

def gpu_metrics_snapshot() -> dict[str, Any]:
    """Cached GPU snapshot for status rows + /api/host/metrics."""
    now = time.time()
    cached = _gpu_metrics_if_fresh(now)
    if cached is not None:
        return cached
    nvidia = _run_nvidia_smi_query()
    payload = {"gpus": [], "vram_by_pid": {}, "source": "unavailable"} if nvidia is None else nvidia
    _store_gpu_metrics(payload, now)
    return payload


def _gpu_cache_is_fresh(now: float, cached: dict[str, Any] | None) -> bool:
    return cached is not None and now - float(_GPU_METRICS_CACHE.get("at") or 0) < _GPU_METRICS_TTL_SECONDS


def _gpu_metrics_if_fresh(now: float) -> dict[str, Any] | None:
    with _GPU_METRICS_CACHE_LOCK:
        cached = _GPU_METRICS_CACHE.get("payload")
        if _gpu_cache_is_fresh(now, cached):
            return cached
    return None


def _store_gpu_metrics(payload: dict[str, Any], now: float) -> None:
    with _GPU_METRICS_CACHE_LOCK:
        # Payload first, timestamp last: a torn read extends the OLD entry's
        # TTL instead of stamping stale data as fresh.
        _GPU_METRICS_CACHE["payload"] = payload
        _GPU_METRICS_CACHE["at"] = now

_CPU_SAMPLE_LOCK = threading.Lock()

_CPU_PREV: tuple[float, float] | None = None

def _read_proc_meminfo() -> dict[str, int]:
    """Return /proc/meminfo keys in kB (Linux). Empty on non-Linux."""
    out: dict[str, int] = {}
    try:
        for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
            _admit_meminfo_line(out, line)
    except OSError:
        return {}
    return out


def _admit_meminfo_line(out: dict[str, int], line: str) -> None:
    if ":" not in line:
        return
    key, rest = line.split(":", 1)
    parts = rest.split()
    if not parts:
        return
    try:
        out[key] = int(parts[0])
    except ValueError:
        pass

def _cpu_nums_from_parts(parts: list[str]) -> list[float] | None:
    try:
        # user nice system idle iowait irq softirq steal ...
        nums = [float(x) for x in parts[1:8]]
    except ValueError:
        return None
    return nums if len(nums) >= 4 else None


def _proc_stat_cpu_nums(first: str) -> list[float] | None:
    if not first.startswith("cpu "):
        return None
    return _cpu_nums_from_parts(first.split())


def _parse_proc_stat_cpu(first: str) -> tuple[float, float] | None:
    nums = _proc_stat_cpu_nums(first)
    if nums is None:
        return None
    idle = nums[3] + (nums[4] if len(nums) > 4 else 0.0)
    return sum(nums), idle


def _cpu_busy_percent(d_total: float, d_idle: float) -> float:
    return max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100.0))


def _cpu_busy_from_delta(total: float, idle: float, prev: tuple[float, float] | None) -> float | None:
    if prev is None:
        return None
    d_total = total - prev[0]
    d_idle = idle - prev[1]
    if d_total <= 0:
        return None
    return _round_tenths(_cpu_busy_percent(d_total, d_idle))


def _cpu_percent_from_loadavg() -> float | None:
    try:
        load1, _, _ = os.getloadavg()
        cpus = os.cpu_count() or 1
        return round(min(100.0, (load1 / cpus) * 100.0) * 10) / 10
    except OSError:
        return None


def _sample_cpu_percent() -> float | None:
    """Busy CPU % from /proc/stat deltas, or loadavg fallback."""
    global _CPU_PREV
    try:
        first = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0]
    except OSError:
        first = ""
    parsed = _parse_proc_stat_cpu(first)
    if parsed is None:
        return _cpu_percent_from_loadavg()
    total, idle = parsed
    with _CPU_SAMPLE_LOCK:
        prev = _CPU_PREV
        _CPU_PREV = (total, idle)
    return _cpu_busy_from_delta(total, idle, prev)

def _sample_memory() -> dict[str, Any]:
    info = _read_proc_meminfo()
    payload = _meminfo_used_payload(info)
    if payload is not None:
        return payload
    # Fallback: no absolute numbers without platform APIs.
    return {
        "used_mb": None,
        "total_mb": None,
        "percent": None,
        "source": "unavailable",
    }


def _meminfo_used_kb(info: dict[str, int]) -> tuple[int, int]:
    total_kb = info["MemTotal"]
    # Match common "used" definition: total - free - buffers - cached
    free_kb = info.get("MemFree", 0)
    buffers_kb = info.get("Buffers", 0)
    cached_kb = info.get("Cached", 0) + info.get("SReclaimable", 0)
    used_kb = max(0, total_kb - free_kb - buffers_kb - cached_kb)
    return total_kb, used_kb


def _meminfo_percent(used_kb: int, total_kb: int) -> float | None:
    if not total_kb:
        return None
    return _round_tenths((used_kb / total_kb) * 100.0)


def _meminfo_used_payload(info: dict[str, int]) -> dict[str, Any] | None:
    if not info.get("MemTotal"):
        return None
    total_kb, used_kb = _meminfo_used_kb(info)
    return {
        "used_mb": _round_tenths(used_kb / 1024),
        "total_mb": _round_tenths(total_kb / 1024),
        "percent": _meminfo_percent(used_kb, total_kb),
        "source": "proc",
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
        _fill_unified_vram_entry(entry, mem_total, apps_used)


def _fill_unified_vram_entry(
    entry: dict[str, Any], mem_total: Any, apps_used: float
) -> None:
    if entry.get("vram_total_mb") is None and mem_total is not None:
        entry["vram_total_mb"] = mem_total
    if entry.get("vram_used_mb") is None:
        entry["vram_used_mb"] = apps_used

def _nvidia_smi_csv(query: str) -> str | None:
    try:
        result = subprocess.run(
            ["nvidia-smi", f"--query-{query}", "--format=csv,noheader,nounits"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def _nvidia_gpu_row(parts: list[str]) -> dict[str, Any] | None:
    if len(parts) < 6:
        return None
    try:
        index = int(parts[0])
    except ValueError:
        return None
    return {
        "index": index,
        "name": parts[1],
        "util_percent": _nvidia_smi_number(parts[2]),
        "temp_c": _nvidia_smi_number(parts[3]),
        "vram_used_mb": _nvidia_smi_number(parts[4]),
        "vram_total_mb": _nvidia_smi_number(parts[5]),
    }


def _parse_nvidia_gpu_rows(text: str) -> list[dict[str, Any]]:
    gpus: list[dict[str, Any]] = []
    for line in text.splitlines():
        row = _nvidia_gpu_row([part.strip() for part in line.split(",")])
        if row is not None:
            gpus.append(row)
    return gpus


def _parse_nvidia_compute_apps(text: str) -> tuple[dict[int, float], dict[int, str]]:
    by_pid: dict[int, float] = {}
    proc_names: dict[int, str] = {}
    for line in text.splitlines():
        _accumulate_nvidia_app_row(
            [part.strip() for part in line.split(",")],
            by_pid,
            proc_names,
        )
    return by_pid, proc_names


def _nvidia_app_pid(parts: list[str]) -> int | None:
    if len(parts) < 2:
        return None
    try:
        return int(parts[0])
    except ValueError:
        return None


def _add_nvidia_app_mem(pid: int, parts: list[str], by_pid: dict[int, float]) -> None:
    mem = _nvidia_smi_number(parts[1])
    if mem is not None:
        by_pid[pid] = by_pid.get(pid, 0.0) + mem


def _set_nvidia_app_name(pid: int, parts: list[str], proc_names: dict[int, str]) -> None:
    if len(parts) >= 3 and parts[2]:
        proc_names[pid] = parts[2]


def _accumulate_nvidia_app_row(
    parts: list[str],
    by_pid: dict[int, float],
    proc_names: dict[int, str],
) -> None:
    pid = _nvidia_app_pid(parts)
    if pid is None:
        return
    _add_nvidia_app_mem(pid, parts, by_pid)
    _set_nvidia_app_name(pid, parts, proc_names)


def _run_nvidia_smi_query() -> dict[str, Any] | None:
    """Query nvidia-smi once. Returns None when the binary/driver is absent."""
    gpu_text = _nvidia_smi_csv(
        "gpu=index,name,utilization.gpu,temperature.gpu,memory.used,memory.total"
    )
    if gpu_text is None:
        return None
    gpus = _parse_nvidia_gpu_rows(gpu_text)
    by_pid: dict[int, float] = {}
    proc_names: dict[int, str] = {}
    proc_text = _nvidia_smi_csv("compute-apps=pid,used_gpu_memory,process_name")
    if proc_text is not None:
        by_pid, proc_names = _parse_nvidia_compute_apps(proc_text)
    return {"gpus": gpus, "vram_by_pid": by_pid, "process_names": proc_names, "source": "nvidia-smi"}

def process_vram_mb(pid: int | None) -> float | None:
    """GPU memory (MiB) attributed to *pid* via nvidia-smi, if available."""
    if not pid:
        return None
    snap = gpu_metrics_snapshot()
    by_pid = snap.get("vram_by_pid") or {}
    return _rounded_tenth_or_none(by_pid.get(int(pid)))


def _rounded_tenth_or_none(value: Any) -> float | None:
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
    pid = _lsof_listen_pid(port)
    if pid is not None:
        return pid
    return _ss_listen_pid(port)


def _lsof_listen_pid(port: str) -> int | None:
    result = run_captured(["lsof", f"-tiTCP:{port}", "-sTCP:LISTEN"], 5)
    if result is None:
        return None
    pids = [int(line) for line in result.stdout.split() if line.strip().isdigit()]
    return pids[0] if pids else None


def _ss_listen_pid(port: str) -> int | None:
    result = run_captured(["ss", "-tlnpH", f"sport = :{port}"], 5)
    if result is None:
        return None
    match = re.search(r"pid=(\d+)", result.stdout)
    return int(match.group(1)) if match else None

def _inventory_port_equals(row: dict[str, Any], want: int) -> bool:
    try:
        return int(row.get("port", -1)) == want
    except (TypeError, ValueError):
        return False


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
    return any(_inventory_port_equals(row, want) for row in listeners)

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
        if _listener_row_port(row) != want:
            continue
        return _listener_row_pid(row)
    return None


def _listener_row_port(row: dict[str, Any]) -> int | None:
    try:
        return int(row.get("port", -1))
    except (TypeError, ValueError):
        return None


def _listener_row_pid(row: dict[str, Any]) -> int | None:
    pid = row.get("pid")
    if pid is None:
        return None
    try:
        return int(pid)
    except (TypeError, ValueError):
        return None

def agent_config_path(root: Path) -> Path:
    return root.expanduser() / "config.json"

def load_agent_config(root: Path) -> dict[str, Any]:
    path = agent_config_path(root)
    if not path_is_regular_file(path):
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return payload if isinstance(payload, dict) else {}


# ---- host extras: uptime / storage / network / tailnet ----------------------

def parse_proc_uptime_seconds(text: str) -> float | None:
    """First field of /proc/uptime is total uptime seconds."""
    try:
        return float(text.split()[0])
    except (IndexError, ValueError):
        return None

def parse_macos_boottime_seconds(text: str) -> float | None:
    """Extract `sec = <int>` from `sysctl -n kern.boottime` output."""
    match = re.search(r"sec\s*=\s*(\d+)", text)
    if not match:
        return None
    return time.time() - float(match.group(1))

def _macos_uptime_seconds() -> float | None:
    try:
        result = subprocess.run(
            ["sysctl", "-n", "kern.boottime"],
            capture_output=True, text=True, timeout=3, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    boot = parse_macos_boottime_seconds(result.stdout)
    if boot is None:
        return None
    return max(0.0, time.time() - boot)


def read_uptime_seconds() -> float | None:
    """Uptime via /proc/uptime (Linux) or kern.boottime (macOS)."""
    try:
        return parse_proc_uptime_seconds(
            Path("/proc/uptime").read_text(encoding="utf-8")
        )
    except OSError:
        pass
    return _macos_uptime_seconds()

def storage_usage(path: str = "/") -> dict[str, Any] | None:
    """Root filesystem usage via os.statvfs (POSIX). None on unsupported platforms."""
    statvfs = getattr(os, "statvfs", None)
    if statvfs is None:
        return None
    try:
        st = statvfs(path)
    except OSError:
        return None
    return _storage_payload(st)


def _storage_block_bytes(st: Any) -> tuple[float, float] | None:
    if st.f_blocks <= 0 or st.f_frsize <= 0:
        return None
    return st.f_blocks * st.f_frsize, st.f_bavail * st.f_frsize


def _storage_payload(st: Any) -> dict[str, Any] | None:
    bytes_pair = _storage_block_bytes(st)
    if bytes_pair is None:
        return None
    return _storage_bytes_payload(*bytes_pair)


def _storage_bytes_payload(total_bytes: float, free_bytes: float) -> dict[str, Any]:
    used_bytes = max(0, total_bytes - free_bytes)
    percent = (used_bytes / total_bytes) * 100.0 if total_bytes else None
    return {
        "used_mb": _round_tenths(used_bytes / (1024 * 1024)),
        "total_mb": round(total_bytes / (1024 * 1024)),
        "percent": _round_tenths(percent) if percent is not None else None,
        "source": "statvfs",
    }

_PROC_NET_DEV_LOCK = threading.Lock()
_PROC_NET_DEV_PREV: tuple[float, int, int] | None = None

def _accumulate_proc_net_dev(text: str) -> tuple[int, int, bool]:
    rx_total = 0
    tx_total = 0
    saw_any = False
    for line in text.splitlines():
        parsed = _iface_rx_tx(line)
        if parsed is None:
            continue
        rx_total += parsed[0]
        tx_total += parsed[1]
        saw_any = True
    return rx_total, tx_total, saw_any


def _sum_proc_net_dev(text: str) -> tuple[int, int] | None:
    """Sum rx/tx byte counters across interfaces (loopback excluded)."""
    rx_total, tx_total, saw_any = _accumulate_proc_net_dev(text)
    return (rx_total, tx_total) if saw_any else None


def _iface_rx_tx_parts(line: str) -> list[str] | None:
    if ":" not in line:
        return None
    iface, rest = line.split(":", 1)
    iface = iface.strip()
    if _skip_net_iface(iface):
        return None
    parts = rest.split()
    if len(parts) < 9:
        return None
    return parts


def _iface_rx_tx(line: str) -> tuple[int, int] | None:
    parts = _iface_rx_tx_parts(line)
    if parts is None:
        return None
    try:
        return int(parts[0]), int(parts[8])
    except ValueError:
        return None


def _skip_net_iface(iface: str) -> bool:
    return not iface or iface == "lo" or iface.startswith(("docker", "veth", "br-"))

def sample_network_rates() -> dict[str, Any] | None:
    """RX/TX rates from /proc/net/dev deltas. None off-Linux or on first sample."""
    global _PROC_NET_DEV_PREV
    try:
        text = Path("/proc/net/dev").read_text(encoding="utf-8")
    except OSError:
        return None
    totals = _sum_proc_net_dev(text)
    if totals is None:
        return None
    now = time.monotonic()
    with _PROC_NET_DEV_LOCK:
        prev = _PROC_NET_DEV_PREV
        _PROC_NET_DEV_PREV = (now, totals[0], totals[1])
    return _network_rates_from_delta(now, totals, prev)


def _empty_network_rates() -> dict[str, Any]:
    return {"rx_kbps": None, "tx_kbps": None, "source": "proc"}


def _network_delta_in_window(dt: float) -> bool:
    return 0 < dt <= 30


def _network_delta_seconds(now: float, prev: tuple[float, int, int] | None) -> float | None:
    if prev is None:
        return None
    dt = now - prev[0]
    return dt if _network_delta_in_window(dt) else None


def _network_rates_from_delta(
    now: float,
    totals: tuple[int, int],
    prev: tuple[float, int, int] | None,
) -> dict[str, Any]:
    dt = _network_delta_seconds(now, prev)
    if dt is None or prev is None:
        return _empty_network_rates()
    rx_kbps = max(0.0, (totals[0] - prev[1]) / dt / 1024)
    tx_kbps = max(0.0, (totals[1] - prev[2]) / dt / 1024)
    return {
        "rx_kbps": _round_tenths(rx_kbps),
        "tx_kbps": _round_tenths(tx_kbps),
        "source": "proc",
    }

_TAILSCALE_HEALTH_TTL_SECONDS = 30.0
_TAILSCALE_HEALTH_CACHE: dict[str, Any] = {"at": 0.0, "payload": None, "present": False}
# Same contract as _GPU_METRICS_CACHE_LOCK: payload before timestamp on fill.
_TAILSCALE_HEALTH_LOCK = threading.Lock()

def parse_tailscale_status_health(payload: Any) -> dict[str, Any] | None:
    """The node's own tailnet view: Self.Online + backend state + warnings.

    Peer state is never the verdict; this is what `tailscale status --json`
    reports about the host itself. Read-only parsing, no tailscale mutations.
    """
    if not isinstance(payload, dict):
        return None
    self_info = payload.get("Self")
    if not isinstance(self_info, dict):
        return None
    return _tailscale_health_fields(payload, self_info)


def _tailscale_ipv4(ips: list[str]) -> str | None:
    return next((ip for ip in ips if is_tailscale_ip(ip)), None)


def _tailscale_dns_name(self_info: dict[str, Any]) -> str | None:
    return str(self_info.get("DNSName") or "").rstrip(".") or None


def _tailscale_health_fields(payload: dict[str, Any], self_info: dict[str, Any]) -> dict[str, Any]:
    ips = _tailscale_self_ips(self_info)
    return {
        "online": bool(self_info.get("Online")),
        "backend_state": str(payload.get("BackendState") or ""),
        "ipv4": _tailscale_ipv4(ips),
        "dns_name": _tailscale_dns_name(self_info),
        "health": _tailscale_health_messages(payload.get("Health")),
    }


def _tailscale_self_ips(self_info: dict[str, Any]) -> list[str]:
    return [ip for ip in (self_info.get("TailscaleIPs") or []) if isinstance(ip, str)]


def _tailscale_health_messages(health: Any) -> list[str]:
    return [str(h) for h in health] if isinstance(health, list) else []

def _tailscale_cache_is_fresh(cached: dict[str, Any], now: float) -> bool:
    return bool(cached.get("present") and now - float(cached.get("at") or 0) < _TAILSCALE_HEALTH_TTL_SECONDS)


def _cached_tailscale_health(now: float) -> tuple[bool, dict[str, Any] | None]:
    with _TAILSCALE_HEALTH_LOCK:
        cached = _TAILSCALE_HEALTH_CACHE
        if _tailscale_cache_is_fresh(cached, now):
            return True, cached.get("payload")
        return False, None


def _remember_tailscale_health(payload: dict[str, Any] | None) -> None:
    with _TAILSCALE_HEALTH_LOCK:
        _TAILSCALE_HEALTH_CACHE.update({"payload": payload, "present": True, "at": time.monotonic()})


def _probe_tailscale_health_json() -> dict[str, Any] | None:
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    try:
        return parse_tailscale_status_health(json.loads(result.stdout))
    except json.JSONDecodeError:
        return None


def tailscale_health_snapshot() -> dict[str, Any] | None:
    """Cached `tailscale status --json` self-health; None when CLI absent."""
    hit, cached = _cached_tailscale_health(time.monotonic())
    if hit:
        return cached
    payload = _probe_tailscale_health_json()
    _remember_tailscale_health(payload)
    return payload

# ---- LLM serving rates: llama.cpp / vLLM / sglang ---------------------------

_LLM_RATE_LOCK = threading.Lock()
_LLM_RATE_STATE: dict[str, dict[str, Any]] = {}
_LLM_BACKEND_TTL_SECONDS = 60.0
_LLM_RATE_MIN_INTERVAL_SECONDS = 1.0

def _llm_root_url(base_url: str) -> str:
    """http://host:port root for an OpenAI-style base_url ending in /v1."""
    root = (base_url or "").strip().rstrip("/")
    if root.endswith("/v1"):
        root = root[: -len("/v1")]
    return root

def _first_or_zero(raw: Any) -> Any:
    if isinstance(raw, list):
        return raw[0] if raw else 0
    return raw


def _as_int(raw: Any) -> int:
    raw = _first_or_zero(raw)
    try:
        return int(raw or 0)
    except (TypeError, ValueError):
        return 0


def _next_token_decoded(slot: dict[str, Any]) -> Any:
    next_token = slot.get("next_token")
    if isinstance(next_token, list) and next_token and isinstance(next_token[0], dict):
        return next_token[0].get("n_decoded")
    return None


def _slot_decoded_count(slot: dict[str, Any]) -> int:
    decoded_raw = slot.get("n_decoded")
    if decoded_raw is None:
        decoded_raw = _next_token_decoded(slot)
    return _as_int(decoded_raw)


def parse_llamacpp_slots_tokens(text: str) -> dict[str, tuple[int, int]] | None:
    """Per-slot (decoded, processed-prompt) cumulative counters from /slots.

    Accepts the n_decoded and next_token[0].n_decoded layouts; prompt side
    prefers n_prompt_tokens_processed and falls back to n_prompt_tokens.
    Returns None when the body is not a slots array.
    """
    slots = _json_list(text)
    if slots is None:
        return None
    return _slot_token_map(slots) or None


def _slot_token_map(slots: list[Any]) -> dict[str, tuple[int, int]]:
    out: dict[str, tuple[int, int]] = {}
    for index, slot in enumerate(slots):
        if isinstance(slot, dict):
            out[str(slot.get("id", index))] = _slot_token_counts(slot)
    return out


def _json_list(text: str) -> list[Any] | None:
    payload = _json_if_type(text, list)
    return payload if isinstance(payload, list) else None


def _json_object(text: str) -> dict[str, Any] | None:
    payload = _json_if_type(text, dict)
    return payload if isinstance(payload, dict) else None


def _json_if_type(text: str, expected: type) -> Any | None:
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, expected) else None


def _json_object_file(path: Path) -> dict[str, Any] | None:
    try:
        return _json_object(path.read_text(encoding="utf-8"))
    except OSError:
        return None


def _slot_token_counts(slot: dict[str, Any]) -> tuple[int, int]:
    return _slot_decoded_count(slot), _slot_prompt_count(slot)


def _slot_prompt_count(slot: dict[str, Any]) -> int:
    prompt_raw = slot.get("n_prompt_tokens_processed")
    if prompt_raw is None:
        prompt_raw = slot.get("n_prompt_tokens")
    return _as_int(prompt_raw)

def parse_prometheus_metric_sum(text: str, metric: str) -> float | None:
    """Sum one Prometheus metric family across labeled lines (no HELP/#)."""
    total = 0.0
    saw_any = False
    for line in text.splitlines():
        value = _prometheus_metric_value(line.strip(), metric)
        if value is None:
            continue
        total += value
        saw_any = True
    return total if saw_any else None


def _prometheus_metric_value(line: str, metric: str) -> float | None:
    if not line or line.startswith("#"):
        return None
    if not _prometheus_metric_matches(line, metric):
        return None
    return _float_or_none(line.rsplit(" ", 1)[-1].strip())


def _prometheus_metric_matches(line: str, metric: str) -> bool:
    return line == metric or line.startswith(metric + "{") or line.startswith(metric + " ")


def _float_or_none(text: str) -> float | None:
    try:
        return float(text)
    except ValueError:
        return None

def parse_sglang_server_info(text: str) -> dict[str, Any] | None:
    """Cumulative token counters + sticky throughput gauge from /server_info."""
    payload = _json_object(text)
    if payload is None:
        return None
    return {
        "input_tokens": payload.get("total_input_tokens"),
        "output_tokens": payload.get("total_output_tokens"),
        "last_gen_throughput": _sglang_last_gen_throughput(payload),
    }


def _sglang_last_gen_throughput(payload: dict[str, Any]) -> Any:
    states = payload.get("internal_states")
    if not isinstance(states, list):
        return None
    return _first_last_gen_throughput(states)


def _first_last_gen_throughput(states: list[Any]) -> Any:
    for state in states:
        if isinstance(state, dict) and state.get("last_gen_throughput") is not None:
            return state.get("last_gen_throughput")
    return None

def _llm_rate_state_for(root: str) -> dict[str, Any]:
    with _LLM_RATE_LOCK:
        state = _LLM_RATE_STATE.get(root)
        if state is None:
            state = {
                "backend": None,
                "backend_checked_at": 0.0,
                "last_ts": None,
                "in": None,
                "out": None,
                "slots": {},
                "sticky_last": None,
                "sticky_moves": 0,
            }
            _LLM_RATE_STATE[root] = state
        return state

def _http_text(url: str, accept: str, timeout: float) -> str:
    try:
        request = urllib.request.Request(url, headers={"Accept": accept})
        with _urlopen_no_redirect(request, timeout) as response:
            if not (200 <= response.status < 300):
                return ""
            return response.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, OSError, ValueError):
        return ""


def _backend_from_probes(root: str) -> str | None:
    backend = _probe_llamacpp_backend(root)
    if backend:
        return backend
    backend = _probe_vllm_backend(root)
    if backend:
        return backend
    return _probe_sglang_backend(root)


def _probe_llamacpp_backend(root: str) -> str | None:
    slots = _http_text(f"{root}/slots", "application/json", 1.0)
    if slots and parse_llamacpp_slots_tokens(slots) is not None:
        return "llama.cpp"
    return None


def _probe_vllm_backend(root: str) -> str | None:
    metrics = _http_text(f"{root}/metrics", "text/plain", 1.5)
    if metrics and parse_prometheus_metric_sum(metrics, "vllm:generation_tokens_total") is not None:
        return "vllm"
    return None


def _probe_sglang_backend(root: str) -> str | None:
    for path in ("/server_info", "/get_server_info"):
        info = _http_text(f"{root}{path}", "application/json", 1.0)
        if info and parse_sglang_server_info(info) is not None:
            return "sglang"
    return None


def _llm_backend_cache_is_fresh(checked_at: float, now: float) -> bool:
    return now - checked_at < _LLM_BACKEND_TTL_SECONDS


def _cached_llm_backend(state: dict[str, Any], now: float) -> str | None:
    cached = state.get("backend")
    checked_at = float(state.get("backend_checked_at") or 0)
    if cached is not None and _llm_backend_cache_is_fresh(checked_at, now):
        return cached
    return None


def _store_llm_backend(state: dict[str, Any], backend: str | None, now: float) -> None:
    with _LLM_RATE_LOCK:
        state["backend"] = backend
        state["backend_checked_at"] = now


def _detect_llm_backend(root: str) -> str | None:
    """Cheap backend classification: /slots, /metrics, /server_info."""
    state = _llm_rate_state_for(root)
    now = time.monotonic()
    cached = _cached_llm_backend(state, now)
    if cached is not None:
        return cached
    backend = _backend_from_probes(root)
    _store_llm_backend(state, backend, now)
    return backend

def _llm_rates_from_counters(state: dict[str, Any], now: float, in_total: float, out_total: float) -> tuple[float | None, float | None, bool]:
    """Counter-diff rates. Returns (tok_s, prompt_tok_s, sampled_now).

    SAFETY: caller MUST hold _LLM_RATE_LOCK. The read-modify-write of
    last_ts/in/out is the only synchronization for these counters; unlocked
    concurrent status requests on the same endpoint lose deltas and spike
    the reported rate.
    """
    last_ts, prev_in, prev_out = _remember_counter_totals(state, now, in_total, out_total)
    return _counter_window_rates(last_ts, prev_in, prev_out, now, in_total, out_total)


def _counter_window_rates(
    last_ts: Any,
    prev_in: Any,
    prev_out: Any,
    now: float,
    in_total: float,
    out_total: float,
) -> tuple[float | None, float | None, bool]:
    if not _counter_window_ready(last_ts, prev_in, prev_out, now):
        return None, None, True
    dt = now - float(last_ts)
    return (
        _rounded_hundredths(_counter_delta_rate(prev_out, out_total, dt)),
        _rounded_hundredths(_counter_delta_rate(prev_in, in_total, dt)),
        True,
    )


def _counter_window_ready(
    last_ts: Any, prev_in: Any, prev_out: Any, now: float
) -> bool:
    if last_ts is None or prev_in is None or prev_out is None:
        return False
    dt = now - float(last_ts)
    return 0 < dt < 10


def _remember_counter_totals(
    state: dict[str, Any], now: float, in_total: float, out_total: float
) -> tuple[Any, Any, Any]:
    last_ts = state.get("last_ts")
    prev_in = state.get("in")
    prev_out = state.get("out")
    state["last_ts"] = now
    state["in"] = in_total
    state["out"] = out_total
    return last_ts, prev_in, prev_out


def _counter_delta_rate(prev: float, current: float, dt: float) -> float:
    return max(0.0, (current - prev) / dt)


def _rounded_hundredths(value: float) -> float:
    return round(value * 100) / 100

def _llm_rate_host_allowed(root: str, allow_remote: bool) -> bool:
    host = urllib.parse.urlparse(root).hostname or ""
    if not host:
        return False
    return allow_remote or is_loopback(host)


def _llm_rate_interval_elapsed(last_ts: Any, now: float) -> bool:
    return last_ts is None or now - float(last_ts) >= _LLM_RATE_MIN_INTERVAL_SECONDS


def _llm_rate_cache_hit(state: dict[str, Any], now: float) -> dict[str, Any] | None:
    if _llm_rate_interval_elapsed(state.get("last_ts"), now):
        return None
    cached = state.get("cached_result")
    return dict(cached) if isinstance(cached, dict) else None


def _cached_llm_rates(state: dict[str, Any], now: float) -> dict[str, Any] | None:
    with _LLM_RATE_LOCK:
        return _llm_rate_cache_hit(state, now)


def _allowed_llm_root(base_url: str, allow_remote: bool) -> str | None:
    root = _llm_root_url(base_url)
    if not root or not _llm_rate_host_allowed(root, allow_remote):
        return None
    return root


def sample_llm_serving_rates(base_url: str, allow_remote: bool = False) -> dict[str, Any] | None:
    """Live decode/prefill tok/s for a running model endpoint (TTL-coalesced).

    Loopback-only unless allow_remote (same SSRF posture as health probes).
    All failures degrade to None fields; never raises.
    """
    root = _allowed_llm_root(base_url, allow_remote)
    if root is None:
        return None
    state = _llm_rate_state_for(root)
    cached = _cached_llm_rates(state, time.monotonic())
    if cached is not None:
        return cached
    return _sample_fresh_llm_rates(root, state)


def _sample_fresh_llm_rates(root: str, state: dict[str, Any]) -> dict[str, Any] | None:
    backend = _detect_llm_backend(root)
    if backend is None:
        return None
    result = _empty_llm_rate_result(backend)
    _run_llm_rate_sampler(backend, root, state, result)
    with _LLM_RATE_LOCK:
        state["cached_result"] = dict(result)
    return result


def _empty_llm_rate_result(backend: str) -> dict[str, Any]:
    return {
        "backend": backend,
        "tok_s": None,
        "prompt_tok_s": None,
        "kv_cache_usage": None,
        "requests_running": None,
        "requests_waiting": None,
    }


def _run_llm_rate_sampler(
    backend: str,
    root: str,
    state: dict[str, Any],
    result: dict[str, Any],
) -> None:
    sampler = _LLM_RATE_SAMPLERS.get(backend)
    if sampler is not None:
        sampler(root, state, result)


def _apply_counter_rates(
    state: dict[str, Any],
    result: dict[str, Any],
    in_total: float,
    out_total: float,
) -> None:
    # Fresh timestamp AFTER the probe: the counter snapshot is post-probe,
    # so dt must start post-probe too (the probe itself takes up to 1.5s;
    # using the pre-probe now would understate dt and overstate the rate).
    with _LLM_RATE_LOCK:
        tok_s, prompt_tok_s, _ = _llm_rates_from_counters(
            state, time.monotonic(), in_total, out_total
        )
    result["tok_s"] = tok_s
    result["prompt_tok_s"] = prompt_tok_s


def _llamacpp_slot_totals(slots: dict[Any, tuple[Any, Any]]) -> tuple[float, float]:
    total_out = sum(decoded for decoded, _ in slots.values())
    total_in = sum(prompted for _, prompted in slots.values())
    return float(total_in), float(total_out)


def _sample_llamacpp_rates(root: str, state: dict[str, Any], result: dict[str, Any]) -> None:
    body = _http_text(f"{root}/slots", "application/json", 1.5)
    if not body:
        return
    slots = parse_llamacpp_slots_tokens(body)
    if not slots:
        return
    total_in, total_out = _llamacpp_slot_totals(slots)
    _apply_counter_rates(state, result, total_in, total_out)


def _apply_vllm_token_rates(
    state: dict[str, Any], result: dict[str, Any], gen: Any, prompt: Any
) -> None:
    if gen is not None and prompt is not None:
        _apply_counter_rates(state, result, prompt, gen)


def _sample_vllm_rates(root: str, state: dict[str, Any], result: dict[str, Any]) -> None:
    text = _http_text(f"{root}/metrics", "text/plain", 2.0)
    if not text:
        return
    gen = parse_prometheus_metric_sum(text, "vllm:generation_tokens_total")
    prompt = parse_prometheus_metric_sum(text, "vllm:prompt_tokens_total")
    _apply_vllm_token_rates(state, result, gen, prompt)
    result["kv_cache_usage"] = parse_prometheus_metric_sum(text, "vllm:gpu_cache_usage_perc")
    result["requests_running"] = parse_prometheus_metric_sum(text, "vllm:num_requests_running")
    result["requests_waiting"] = parse_prometheus_metric_sum(text, "vllm:num_requests_waiting")


def _sglang_server_info(root: str) -> dict[str, Any] | None:
    for path in ("/server_info", "/get_server_info"):
        body = _http_text(f"{root}{path}", "application/json", 1.5)
        if not body:
            continue
        info = parse_sglang_server_info(body)
        if info is not None:
            return info
    return None


def _sticky_move_count(state: dict[str, Any], current: float) -> int:
    sticky_prev = state.get("sticky_last")
    return 0 if current != sticky_prev else int(state.get("sticky_moves") or 0) + 1


def _apply_sglang_sticky_gauge(state: dict[str, Any], result: dict[str, Any], current: float) -> None:
    with _LLM_RATE_LOCK:
        moves = _sticky_move_count(state, current)
        state["sticky_last"] = current
        state["sticky_moves"] = moves
    result["tok_s"] = round(current * 100) / 100 if moves < 2 else 0.0


def _apply_sglang_throughput_gauge(
    state: dict[str, Any], result: dict[str, Any], info: dict[str, Any]
) -> None:
    if result["tok_s"] is not None or info.get("last_gen_throughput") is None:
        return
    try:
        current = float(info["last_gen_throughput"])
    except (TypeError, ValueError):
        current = 0.0
    _apply_sglang_sticky_gauge(state, result, current)


def _sample_sglang_rates(root: str, state: dict[str, Any], result: dict[str, Any]) -> None:
    info = _sglang_server_info(root)
    if info is None:
        return
    _apply_sglang_counters(state, result, info)
    _apply_sglang_throughput_gauge(state, result, info)


def _apply_sglang_counters(
    state: dict[str, Any],
    result: dict[str, Any],
    info: dict[str, Any],
) -> None:
    in_raw = info.get("input_tokens")
    out_raw = info.get("output_tokens")
    try:
        if in_raw is not None and out_raw is not None:
            _apply_counter_rates(state, result, float(in_raw), float(out_raw))
    except (TypeError, ValueError):
        pass


_LLM_RATE_SAMPLERS = {
    "llama.cpp": _sample_llamacpp_rates,
    "vllm": _sample_vllm_rates,
    "sglang": _sample_sglang_rates,
}


# F01 public surface. Peers import these; leading-underscore names stay internal.
WEIGHT_SUFFIXES = _WEIGHT_SUFFIXES
apply_unified_memory_vram = _apply_unified_memory_vram
looks_like_local_fs_path = _looks_like_local_fs_path
nvidia_smi_number = _nvidia_smi_number
sample_cpu_percent = _sample_cpu_percent
sample_memory = _sample_memory
urlopen_no_redirect = _urlopen_no_redirect

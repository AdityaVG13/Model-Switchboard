#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import difflib
import hashlib
import hmac
import io
import ipaddress
import json
import os
import pathlib
import secrets
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import BinaryIO, TypedDict

from contracts import (
    BenchmarkLatestReportPayload,
    BenchmarkLatestRowPayload,
    BenchmarkStatusPayload,
    ControllerActionResponsePayload,
    ControllerHeartbeatPayload,
    ControllerIntegrationPayload,
    ControllerStatusPayload,
    DoctorReportPayload,
    LaunchAgentStatusPayload,
    ModelProfileStatusPayload,
    ProfileEnv,
    ProfileDiagnosticPayload,
    make_action_response_payload,
    make_cached_status_payload,
    make_controller_status_payload,
)
from profile_env import ProfileFormatError, load_env_profile, load_json_profile, load_profile  # noqa: F401

BASE = pathlib.Path(__file__).resolve().parent
PROJECT_ROOT = BASE.parent
PROFILE_DIR = BASE / "model-profiles"
RUN_DIR = BASE / "run"
ACTIVE_PROFILE_PATH = RUN_DIR / "active-profile"
START_SCRIPT = BASE / "start-model-mac.sh"
STOP_ALL_SCRIPT = BASE / "stop-all-models.sh"
SYNC_SCRIPT = BASE / "sync-droid-local-models.py"
BENCH_SCRIPT = BASE / "benchmark-local-models.py"
BENCH_RESULTS_DIR = BASE / "benchmark-results"
DEFAULT_WEB_HOST = "127.0.0.1"
DEFAULT_WEB_PORT = 8877
MIN_AUTH_TOKEN_BYTES = 16
MAX_JSON_BODY_BYTES = 64 * 1024
FACTORY_SETTINGS_PATH = pathlib.Path.home() / ".factory" / "settings.json"
LAUNCH_AGENT_LABEL = "io.modelswitchboard.controller"
LAUNCH_AGENT_PLIST = pathlib.Path.home() / "Library/LaunchAgents" / f"{LAUNCH_AGENT_LABEL}.plist"
STATUS_CACHE_PATH = pathlib.Path.home() / "Library/Caches/io.modelswitchboard/controller-status.json"
CLI_CONTRACT_VERSION = "1.0"
CLI_SCHEMA_VERSION = "1"
DOCTOR_CONTRACT_VERSION = "1.0"
DOCTOR_SCHEMA_VERSION = "1"
DOCTOR_ARTIFACT_DIR = PROJECT_ROOT / ".doctor"
DOCTOR_RUNS_DIR = DOCTOR_ARTIFACT_DIR / "runs"
DOCTOR_LATEST_PATH = DOCTOR_ARTIFACT_DIR / "latest"
CLI_EXIT_CODES = {
    "0": "success",
    "1": "operation failed or diagnostic findings are present",
    "2": "safety block or partially applied repair",
    "3": "tool environment error or rollback failure",
    "4": "unsafe state refused",
    "5": "conflict or concurrency loss",
    "64": "usage error",
}
CLI_COMMAND_ALIASES = {
    "activate": ["switch"],
    "diagnose": ["doctor"],
    "validate": ["doctor"],
    "health": ["doctor", "health"],
    "docs": ["robot-docs", "guide"],
    "robot-help": ["robot-docs", "guide"],
}
CLI_GLOBAL_ALIASES = {
    "--capabilities": ["capabilities", "--json"],
    "--robot-docs": ["robot-docs", "guide"],
    "--robot-help": ["robot-docs", "guide"],
    "--robot-triage": ["triage", "--json"],
}
CLI_COMMAND_NAMES = [
    "status",
    "list",
    "start",
    "stop",
    "restart",
    "switch",
    "activate",
    "benchmark",
    "doctor",
    "diagnose",
    "health",
    "capabilities",
    "robot-docs",
    "triage",
    "integrations",
    "run-integration",
    "stop-all",
    "serve-web",
]
CLI_KNOWN_FLAGS = [
    "--allow-concurrent",
    "--auth-token",
    "--auth-token-file",
    "--background",
    "--dry-run",
    "--fix",
    "--help",
    "--host",
    "--json",
    "--keep-running",
    "--no-strict",
    "--plan",
    "--port",
    "--run-id",
    "--suite",
    "--unsafe-bind",
]


class ProfileConflictError(RuntimeError):
    """Raised when two or more profiles resolve to the same endpoint."""


class ControllerAPIError(Exception):
    def __init__(self, status: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def closest_cli_token(value: str, choices: list[str]) -> str | None:
    matches = difflib.get_close_matches(value, choices, n=1, cutoff=0.58)
    return matches[0] if matches else None


def normalize_cli_argv(argv: list[str]) -> list[str]:
    if not argv:
        return argv
    first = argv[0]
    if first in CLI_GLOBAL_ALIASES:
        return [*CLI_GLOBAL_ALIASES[first], *argv[1:]]
    if first in CLI_COMMAND_ALIASES:
        return [*CLI_COMMAND_ALIASES[first], *argv[1:]]
    return argv


def cli_usage_hint(prog: str, message: str) -> str:
    hint_parts: list[str] = []
    if "invalid choice:" in message:
        attempted = message.split("invalid choice:", 1)[1].split("(", 1)[0].strip().strip("'\"")
        suggestion = closest_cli_token(attempted, CLI_COMMAND_NAMES)
        if suggestion:
            hint_parts.append(f"did you mean: `{prog} {suggestion}`")
    if "unrecognized arguments:" in message:
        unknown = message.split("unrecognized arguments:", 1)[1].strip().split()[0]
        suggestion = closest_cli_token(unknown, CLI_KNOWN_FLAGS)
        if suggestion:
            hint_parts.append(f"did you mean: `{prog} {suggestion}`")
    hint_parts.append(f"inspect machine-readable commands with `{prog} capabilities --json`")
    return "\n".join(f"hint: {hint}" for hint in hint_parts)


class AgentArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        self.exit(64, f"{self.prog}: usage error: {message}\n{cli_usage_hint(self.prog, message)}\n")


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


class ControllerRequest(TypedDict, total=False):
    profile: str
    profiles: list[str]
    integration: str
    action: str
    suite: str
    allow_concurrent: bool
    keep_running: bool


class RuntimeSpec(TypedDict):
    label: str
    tags: list[str]
    launch_mode: str


RUNTIME_ALIASES = {
    "llamacpp": "llama.cpp",
    "llama-cpp": "llama.cpp",
    "llama.cpp": "llama.cpp",
    "mlx-lm": "mlx",
    "mlx_lm": "mlx",
    "rvllm": "rvllm-mlx",
    "rvllm_mlx": "rvllm-mlx",
    "rvllm-mlx": "rvllm-mlx",
    "vllm_mlx": "vllm-mlx",
    "vllm-mlx": "vllm-mlx",
    "ddtree": "ddtree-mlx",
    "ddtree_mlx": "ddtree-mlx",
    "ddtree-mlx": "ddtree-mlx",
    "turboquant": "turboquant",
    "mlx-vlm": "mlx-vlm",
    "mlx_vlm": "mlx-vlm",
    "mlx-omni": "mlx-omni-server",
    "mlx-omni-server": "mlx-omni-server",
    "mlx-openai": "mlx-openai-server",
    "mlx-openai-server": "mlx-openai-server",
    "mlx-llm-server": "mlx-llm-server",
    "mlx-serve": "mlx-serve",
    "mlx-engine": "mlxengine",
    "mlxengine": "mlxengine",
    "ollmlx": "ollmlx",
    "openai": "external",
    "openai-compatible": "external",
    "endpoint": "external",
    "external": "external",
    "custom": "command",
    "command": "command",
    "lmstudio": "lm-studio",
    "lm-studio": "lm-studio",
    "local-ai": "localai",
    "text-generation-inference": "tgi",
    "huggingface-tgi": "tgi",
    "text-generation-webui": "text-generation-webui",
    "oobabooga": "text-generation-webui",
    "kobold-cpp": "koboldcpp",
    "llama-cpp-python": "llama-cpp-python",
    "exllama": "exllamav2",
    "exllama-v2": "exllamav2",
    "exllamav2": "exllamav2",
    "aphrodite-engine": "aphrodite",
    "lmdeploy": "lmdeploy",
    "mistral-rs": "mistral.rs",
    "mistralrs": "mistral.rs",
    "mistral.rs": "mistral.rs",
    "mlc": "mlc-llm",
    "mlc-llm": "mlc-llm",
    "lightllm": "lightllm",
    "fast-chat": "fastchat",
    "fastchat": "fastchat",
    "openllm": "openllm",
    "bentoml-openllm": "openllm",
    "nexa": "nexa",
    "nexa-sdk": "nexa",
    "nexaai": "nexa",
    "litellm": "litellm",
    "litellm-proxy": "litellm",
    "transformers": "transformers",
    "hf-transformers": "transformers",
    "huggingface-transformers": "transformers",
    "triton": "triton",
    "nvidia-triton": "triton",
    "tensorrt-llm": "tensorrt-llm",
    "tensorrtllm": "tensorrt-llm",
    "onnxruntime-genai": "onnxruntime-genai",
    "ort-genai": "onnxruntime-genai",
}


RUNTIME_SPECS: dict[str, RuntimeSpec] = {
    "llama.cpp": {
        "label": "llama.cpp",
        "tags": ["managed", "openai-compatible", "gguf", "metal", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "mlx": {
        "label": "MLX",
        "tags": ["managed", "openai-compatible", "mlx", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "rvllm-mlx": {
        "label": "rVLLM MLX",
        "tags": ["managed", "openai-compatible", "mlx", "continuous-batching", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "vllm-mlx": {
        "label": "vLLM-MLX",
        "tags": ["managed", "openai-compatible", "mlx", "server", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "ddtree-mlx": {
        "label": "DDTree MLX",
        "tags": ["managed", "openai-compatible", "mlx", "speculative-decoding", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "turboquant": {
        "label": "TurboQuant",
        "tags": ["managed", "openai-compatible", "gguf", "quantized"],
        "launch_mode": "adapter",
    },
    "mlx-vlm": {
        "label": "MLX-VLM",
        "tags": ["managed", "openai-compatible", "mlx", "vision", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "mlx-omni-server": {
        "label": "MLX Omni Server",
        "tags": ["managed", "openai-compatible", "anthropic-compatible", "mlx", "multimodal", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "mlx-openai-server": {
        "label": "MLX OpenAI Server",
        "tags": ["managed", "openai-compatible", "mlx", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "mlx-llm-server": {
        "label": "MLX-LLM Server",
        "tags": ["managed", "openai-compatible", "mlx", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "mlx-serve": {
        "label": "MLX Serve",
        "tags": ["managed", "openai-compatible", "mlx", "multimodal", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "mlxengine": {
        "label": "MLX Engine",
        "tags": ["managed", "openai-compatible", "mlx", "multimodal", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "ollmlx": {
        "label": "ollmlx",
        "tags": ["external", "openai-compatible", "ollama-compatible", "mlx", "apple-silicon"],
        "launch_mode": "external",
    },
    "omlx": {
        "label": "oMLX",
        "tags": ["managed", "openai-compatible", "mlx", "agent-cache", "apple-silicon"],
        "launch_mode": "adapter",
    },
    "ollama": {
        "label": "Ollama",
        "tags": ["daemon", "openai-compatible", "model-registry", "local"],
        "launch_mode": "adapter",
    },
    "vllm": {
        "label": "vLLM",
        "tags": ["managed", "openai-compatible", "server", "continuous-batching"],
        "launch_mode": "adapter",
    },
    "sglang": {
        "label": "SGLang",
        "tags": ["managed", "openai-compatible", "server", "radix-cache"],
        "launch_mode": "adapter",
    },
    "tgi": {
        "label": "Text Generation Inference",
        "tags": ["managed", "openai-compatible", "server", "hugging-face"],
        "launch_mode": "adapter",
    },
    "llama-cpp-python": {
        "label": "llama-cpp-python",
        "tags": ["managed", "openai-compatible", "gguf", "python"],
        "launch_mode": "adapter",
    },
    "llamafile": {
        "label": "llamafile",
        "tags": ["managed", "openai-compatible", "gguf", "single-binary"],
        "launch_mode": "adapter",
    },
    "koboldcpp": {
        "label": "KoboldCpp",
        "tags": ["managed", "openai-compatible", "gguf"],
        "launch_mode": "adapter",
    },
    "tabbyapi": {
        "label": "TabbyAPI",
        "tags": ["managed", "openai-compatible", "exllamav2", "gptq"],
        "launch_mode": "adapter",
    },
    "exllamav2": {
        "label": "ExLlamaV2",
        "tags": ["managed", "openai-compatible", "exllamav2", "gptq", "exl2"],
        "launch_mode": "adapter",
    },
    "aphrodite": {
        "label": "Aphrodite Engine",
        "tags": ["managed", "openai-compatible", "server", "vllm-family"],
        "launch_mode": "adapter",
    },
    "lmdeploy": {
        "label": "LMDeploy",
        "tags": ["managed", "openai-compatible", "server", "turbomind"],
        "launch_mode": "adapter",
    },
    "mistral.rs": {
        "label": "mistral.rs",
        "tags": ["managed", "openai-compatible", "rust", "gguf", "multimodal", "continuous-batching"],
        "launch_mode": "adapter",
    },
    "mlc-llm": {
        "label": "MLC-LLM",
        "tags": ["managed", "openai-compatible", "mlc", "metal", "cross-platform"],
        "launch_mode": "adapter",
    },
    "lightllm": {
        "label": "LightLLM",
        "tags": ["managed", "openai-compatible", "server", "high-throughput"],
        "launch_mode": "adapter",
    },
    "fastchat": {
        "label": "FastChat",
        "tags": ["managed", "openai-compatible", "server", "vicuna"],
        "launch_mode": "adapter",
    },
    "openllm": {
        "label": "OpenLLM",
        "tags": ["managed", "openai-compatible", "server", "bentoml"],
        "launch_mode": "adapter",
    },
    "nexa": {
        "label": "Nexa SDK",
        "tags": ["managed", "openai-compatible", "multimodal", "cross-platform"],
        "launch_mode": "adapter",
    },
    "litellm": {
        "label": "LiteLLM",
        "tags": ["external", "openai-compatible", "proxy"],
        "launch_mode": "external",
    },
    "transformers": {
        "label": "Transformers",
        "tags": ["managed", "openai-compatible", "python", "hugging-face"],
        "launch_mode": "adapter",
    },
    "triton": {
        "label": "Triton Inference Server",
        "tags": ["external", "openai-compatible", "server", "nvidia"],
        "launch_mode": "external",
    },
    "tensorrt-llm": {
        "label": "TensorRT-LLM",
        "tags": ["managed", "openai-compatible", "server", "nvidia"],
        "launch_mode": "adapter",
    },
    "onnxruntime-genai": {
        "label": "ONNX Runtime GenAI",
        "tags": ["managed", "openai-compatible", "onnx", "cross-platform"],
        "launch_mode": "adapter",
    },
    "text-generation-webui": {
        "label": "text-generation-webui",
        "tags": ["managed", "openai-compatible", "launcher", "extensions"],
        "launch_mode": "adapter",
    },
    "localai": {
        "label": "LocalAI",
        "tags": ["external", "openai-compatible", "multi-backend"],
        "launch_mode": "external",
    },
    "lm-studio": {
        "label": "LM Studio",
        "tags": ["external", "openai-compatible", "desktop"],
        "launch_mode": "external",
    },
    "jan": {
        "label": "Jan",
        "tags": ["external", "openai-compatible", "desktop"],
        "launch_mode": "external",
    },
    "external": {
        "label": "OpenAI-compatible endpoint",
        "tags": ["external", "openai-compatible"],
        "launch_mode": "external",
    },
    "command": {
        "label": "Custom command",
        "tags": ["managed", "custom", "openai-compatible"],
        "launch_mode": "command",
    },
}


def canonical_runtime(value: str | None) -> str:
    raw = (value or "llama.cpp").strip()
    normalized = raw.lower().replace("_", "-")
    return RUNTIME_ALIASES.get(normalized, normalized)


def runtime_spec(env: ProfileEnv) -> RuntimeSpec:
    runtime = canonical_runtime(env.get("RUNTIME"))
    if runtime in RUNTIME_SPECS:
        spec = RUNTIME_SPECS[runtime]
    else:
        spec = {
            "label": runtime,
            "tags": ["managed", "custom"],
            "launch_mode": "adapter",
        }
    if env.get("START_COMMAND"):
        return {**spec, "launch_mode": "command"}
    if env.get("LAUNCH_MODE"):
        return {**spec, "launch_mode": env["LAUNCH_MODE"].strip().lower()}
    return spec


def split_tags(value: str | None) -> list[str]:
    if not value:
        return []
    tags: list[str] = []
    for part in value.replace(",", " ").split():
        tag = part.strip().lower()
        if tag and tag not in tags:
            tags.append(tag)
    return tags


def runtime_tags(env: ProfileEnv) -> list[str]:
    tags: list[str] = []
    for tag in [canonical_runtime(env.get("RUNTIME")), *runtime_spec(env)["tags"], *split_tags(env.get("RUNTIME_TAGS") or env.get("TAGS"))]:
        if tag and tag not in tags:
            tags.append(tag)
    return tags


HTML_PAGE = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Model Switchboard Dashboard</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0f1218;
      --panel: #171c24;
      --panel-soft: #1f2530;
      --line: rgba(255, 255, 255, 0.08);
      --line-strong: rgba(255, 255, 255, 0.14);
      --text: #f3f5f7;
      --muted: #a7b0bc;
      --good: #69d18f;
      --warn: #f0c06b;
      --bad: #ef7d7d;
      --accent: #8bb8ff;
      --accent-strong: #5e94f0;
      --shadow: 0 18px 48px rgba(0, 0, 0, 0.26);
      --radius: 18px;
      --radius-sm: 12px;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      background: linear-gradient(180deg, #0d1015 0%, #11151d 100%);
      color: var(--text);
      font-family: "SF Pro Text", "Inter", system-ui, sans-serif;
    }

    button,
    code {
      font: inherit;
    }

    code {
      font-family: "SF Mono", "JetBrains Mono", monospace;
    }

    .shell {
      width: min(1040px, calc(100vw - 32px));
      margin: 20px auto 28px;
      display: grid;
      gap: 16px;
    }

    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }

    .header {
      display: flex;
      align-items: start;
      justify-content: space-between;
      gap: 16px;
      padding: 20px 22px;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 8px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
    }

    .eyebrow::before {
      content: "";
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: var(--accent);
    }

    h1 {
      margin: 0 0 6px;
      font-size: 30px;
      line-height: 1.05;
      letter-spacing: -0.03em;
    }

    .header p,
    .muted {
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
      font-size: 14px;
    }

    .heartbeat {
      color: var(--muted);
      font-size: 13px;
      white-space: nowrap;
    }

    .toolbar,
    .section,
    .footer {
      padding: 16px 18px;
    }

    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
    }

    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
    }

    .stat {
      padding: 14px 16px;
      background: var(--panel-soft);
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
    }

    .stat .label {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      margin-bottom: 8px;
    }

    .stat .value {
      font-size: 24px;
      font-weight: 700;
      letter-spacing: -0.03em;
    }

    .stat .subvalue {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }

    .section-header {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
      margin-bottom: 12px;
    }

    .section-header h2 {
      margin: 0;
      font-size: 18px;
    }

    .integration-actions,
    .card-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    .cards {
      display: grid;
      gap: 12px;
    }

    .card {
      padding: 16px;
      background: var(--panel-soft);
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
      display: grid;
      gap: 12px;
    }

    .card-top {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: start;
    }

    .card-title {
      margin: 0 0 4px;
      font-size: 21px;
      line-height: 1.15;
    }

    .card-meta,
    .card-endpoint,
    .card-inspect {
      color: var(--muted);
      font-size: 14px;
      line-height: 1.45;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      padding: 5px 10px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      white-space: nowrap;
    }

    .badge.running {
      background: rgba(105, 209, 143, 0.16);
      color: var(--good);
    }

    .badge.booting {
      background: rgba(240, 192, 107, 0.16);
      color: var(--warn);
    }

    .badge.offline {
      background: rgba(239, 125, 125, 0.16);
      color: var(--bad);
    }

    button {
      appearance: none;
      border: 1px solid var(--line-strong);
      background: #262d39;
      color: var(--text);
      border-radius: 10px;
      padding: 9px 13px;
      cursor: pointer;
      transition: background 0.14s ease, border-color 0.14s ease;
    }

    button:hover {
      background: #2d3645;
      border-color: rgba(255, 255, 255, 0.22);
    }

    button:disabled {
      opacity: 0.5;
      cursor: default;
    }

    button.primary {
      background: rgba(94, 148, 240, 0.18);
      border-color: rgba(94, 148, 240, 0.46);
    }

    button.warn {
      background: rgba(239, 125, 125, 0.12);
      border-color: rgba(239, 125, 125, 0.36);
    }

    .footer {
      display: flex;
      flex-wrap: wrap;
      gap: 10px 18px;
      color: var(--muted);
      font-size: 13px;
    }

    @media (max-width: 720px) {
      .shell {
        width: calc(100vw - 18px);
        margin: 10px auto 18px;
      }

      .header,
      .toolbar,
      .section,
      .footer {
        padding: 14px;
      }

      .card-top,
      .section-header,
      .header {
        flex-direction: column;
      }

      h1 {
        font-size: 24px;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="panel header">
      <div>
        <div class="eyebrow">Model Switchboard Dashboard</div>
        <h1>Local model control plane</h1>
        <p>Compact browser view for the same actions exposed in the menu bar. No oversized hero, no selection deck, no extra drag.</p>
      </div>
      <div class="heartbeat" id="heartbeat">Refreshing controller state...</div>
    </section>

    <section class="panel toolbar">
      <button class="primary" id="refresh-button">Refresh</button>
      <button id="bench-all-button">Run Benchmark</button>
      <button class="warn" id="stop-all-button">Stop All</button>
    </section>

    <section class="summary" id="summary"></section>

    <section class="panel section" id="integrations-section" hidden>
      <div class="section-header">
        <h2>Optional integrations</h2>
        <div class="muted" id="integration-summary"></div>
      </div>
      <div class="integration-actions" id="integration-actions"></div>
    </section>

    <section class="panel section">
      <div class="section-header">
        <h2>Profiles</h2>
        <div class="muted" id="profile-summary"></div>
      </div>
      <div class="cards" id="cards"></div>
    </section>

    <section class="panel footer" id="footer"></section>
  </main>

  <script>
    const REFRESH_INTERVAL_MS = 5000;
    const heartbeatEl = document.getElementById('heartbeat');
    const summaryEl = document.getElementById('summary');
    const integrationsSectionEl = document.getElementById('integrations-section');
    const integrationSummaryEl = document.getElementById('integration-summary');
    const integrationActionsEl = document.getElementById('integration-actions');
    const profileSummaryEl = document.getElementById('profile-summary');
    const cardsEl = document.getElementById('cards');
    const footerEl = document.getElementById('footer');
    const refreshButton = document.getElementById('refresh-button');
    const benchAllButton = document.getElementById('bench-all-button');
    const stopAllButton = document.getElementById('stop-all-button');

    function escapeHTML(value) {
      return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    function statusTone(item) {
      if (item.ready) return 'running';
      if (item.running) return 'booting';
      return 'offline';
    }

    function statusLabel(item) {
      if (item.ready) return 'Running';
      if (item.running) return 'Starting';
      return 'Not Running';
    }

    function formatMemory(value) {
      if (value === null || value === undefined || value === '') return 'n/a';
      return `${Number(value).toFixed(1)} MB`;
    }

    function metric(label, value, subvalue = '') {
      return `
        <article class="panel stat">
          <div class="label">${escapeHTML(label)}</div>
          <div class="value">${escapeHTML(value)}</div>
          <div class="subvalue">${escapeHTML(subvalue)}</div>
        </article>
      `;
    }

    function suiteLabel(value) {
      if (!value) return 'Idle';
      const normalized = String(value).trim().toLowerCase();
      if (normalized === 'quick') return 'Default';
      return normalized
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replace(/\b\w/g, (char) => char.toUpperCase());
    }

    const queryToken = new URLSearchParams(window.location.search).get('token');
    if (queryToken) {
      sessionStorage.setItem('controllerToken', queryToken);
      history.replaceState(null, '', window.location.pathname);
    }
    const controllerToken = queryToken || sessionStorage.getItem('controllerToken') || '';

    async function api(path, options = {}) {
      const { headers: optionHeaders = {}, ...fetchOptions } = options;
      const headers = { 'Content-Type': 'application/json', ...optionHeaders };
      if (controllerToken) headers.Authorization = `Bearer ${controllerToken}`;
      const response = await fetch(path, {
        ...fetchOptions,
        headers,
      });
      if (!response.ok) {
        throw new Error((await response.text()) || `HTTP ${response.status}`);
      }
      return response.json();
    }

    async function postAction(path, payload = {}) {
      try {
        heartbeatEl.textContent = 'Executing action...';
        await api(path, { method: 'POST', body: JSON.stringify(payload) });
        await refreshStatus();
      } catch (error) {
        heartbeatEl.textContent = `Action failed: ${error.message}`;
        alert(error.message);
      }
    }

    function renderSummary(data) {
      const statuses = data.statuses || [];
      const running = statuses.filter(item => item.running).length;
      const ready = statuses.filter(item => item.ready).length;
      const benchmark = data.benchmark || {};
      const latest = benchmark.latest || {};

      summaryEl.innerHTML = [
        metric('Ready', `${ready}/${statuses.length}`, `${running} process${running === 1 ? '' : 'es'} live`),
        metric('Benchmark', benchmark.running ? 'Running' : suiteLabel(latest.suite), latest.generated_at ? new Date(latest.generated_at).toLocaleTimeString() : 'No recent benchmark'),
        metric('Profiles folder', statuses.length ? 'Live' : 'Waiting', data.profiles_dir || 'not reported'),
      ].join('');

      profileSummaryEl.textContent = `${statuses.length} profiles • auto-refresh ${REFRESH_INTERVAL_MS / 1000}s`;
    }

    function renderIntegrations(integrations) {
      const syncable = (integrations || []).filter(item => (item.capabilities || []).includes('sync'));
      integrationsSectionEl.hidden = syncable.length === 0;
      if (syncable.length === 0) {
        integrationActionsEl.innerHTML = '';
        integrationSummaryEl.textContent = '';
        return;
      }

      integrationActionsEl.innerHTML = syncable.map(item => `
        <button data-integration="${escapeHTML(item.id)}" data-integration-action="sync">${escapeHTML(item.sync_label || ('Sync ' + item.display_name))}</button>
      `).join('');
      integrationSummaryEl.textContent = syncable.map(item => item.description || item.display_name).join(' ');
    }

    function renderCards(data) {
      const normalizeHost = (value) => {
        const normalized = (value || '').trim().toLowerCase();
        if (normalized === '127.0.0.1' || normalized === 'localhost' || normalized === '::1') return 'localhost';
        return normalized;
      };
      const hostRank = (value) => normalizeHost(value) === 'localhost' ? 0 : 1;
      const portRank = (value) => {
        const parsed = Number.parseInt(String(value || '').trim(), 10);
        return Number.isFinite(parsed) ? parsed : Number.MAX_SAFE_INTEGER;
      };
      const statuses = [...(data.statuses || [])].sort((a, b) => {
        if (a.running !== b.running) return Number(b.running) - Number(a.running);
        if (a.running && a.ready !== b.ready) return Number(b.ready) - Number(a.ready);
        if (hostRank(a.host) !== hostRank(b.host)) return hostRank(a.host) - hostRank(b.host);
        const aHost = normalizeHost(a.host);
        const bHost = normalizeHost(b.host);
        const hostCompare = aHost.localeCompare(bHost);
        if (hostCompare !== 0) return hostCompare;
        if (portRank(a.port) !== portRank(b.port)) return portRank(a.port) - portRank(b.port);
        return a.display_name.localeCompare(b.display_name);
      });

      cardsEl.innerHTML = statuses.map(item => {
        const tone = statusTone(item);
        const runtime = item.runtime || 'unknown';
        const pid = item.pid || 'none';
        return `
          <article class="card">
            <div class="card-top">
              <div>
                <h3 class="card-title">${escapeHTML(item.display_name)}</h3>
                <div class="card-meta">${escapeHTML(runtime)} • ${escapeHTML(statusLabel(item))}</div>
                <div class="card-endpoint"><code>${escapeHTML(item.base_url || 'no endpoint')}</code></div>
              </div>
              <span class="badge ${tone}">${escapeHTML(statusLabel(item))}</span>
            </div>
            <div class="card-inspect">Profile: <code>${escapeHTML(item.profile)}</code> • Request model: <code>${escapeHTML(item.request_model || 'n/a')}</code> • PID: <code>${escapeHTML(pid)}</code> • RSS: <code>${escapeHTML(formatMemory(item.rss_mb))}</code></div>
            <div class="card-actions">
              <button class="primary" data-action="switch" data-profile="${escapeHTML(item.profile)}">Activate</button>
              <button data-action="start" data-profile="${escapeHTML(item.profile)}">Start</button>
              <button class="warn" data-action="stop" data-profile="${escapeHTML(item.profile)}">Stop</button>
              <button data-action="restart" data-profile="${escapeHTML(item.profile)}">Restart</button>
              <button data-action="bench" data-profile="${escapeHTML(item.profile)}">Bench</button>
            </div>
          </article>
        `;
      }).join('');
    }

    function renderFooter(data) {
      const benchmark = data.benchmark || {};
      const latest = benchmark.latest || {};
      footerEl.innerHTML = `
        <div><strong>Controller:</strong> ${escapeHTML(window.location.origin)}</div>
        <div><strong>Profiles:</strong> ${escapeHTML(data.profiles_dir || 'not reported')}</div>
        <div><strong>Benchmark:</strong> ${escapeHTML(benchmark.running ? 'Running' : suiteLabel(latest.suite))}</div>
      `;
    }

    function render(data) {
      renderSummary(data);
      renderIntegrations(data.integrations || []);
      renderCards(data);
      renderFooter(data);
      heartbeatEl.textContent = 'Controller online';
    }

    async function refreshStatus() {
      try {
        refreshButton.disabled = true;
        heartbeatEl.textContent = 'Refreshing controller state...';
        const data = await api('/api/status');
        render(data);
      } catch (error) {
        heartbeatEl.textContent = `Refresh failed: ${error.message}`;
      } finally {
        refreshButton.disabled = false;
      }
    }

    integrationActionsEl.addEventListener('click', async (event) => {
      const button = event.target.closest('button[data-integration]');
      if (!button) return;
      await postAction('/api/integrations/run', {
        integration: button.dataset.integration,
        action: button.dataset.integrationAction || 'sync',
      });
    });

    cardsEl.addEventListener('click', async (event) => {
      const button = event.target.closest('button[data-action]');
      if (!button) return;
      const action = button.dataset.action;
      const profile = button.dataset.profile;
      if (action === 'start') await postAction('/api/start', { profile });
      if (action === 'stop') await postAction('/api/stop', { profile });
      if (action === 'restart') await postAction('/api/restart', { profile });
      if (action === 'switch') await postAction('/api/switch', { profile });
      if (action === 'bench') await postAction('/api/benchmark/start', { suite: 'quick', profiles: [profile] });
    });

    refreshButton.addEventListener('click', () => refreshStatus());
    benchAllButton.addEventListener('click', () => postAction('/api/benchmark/start', { suite: 'quick' }));
    stopAllButton.addEventListener('click', () => postAction('/api/stop-all'));

    refreshStatus();
    setInterval(refreshStatus, REFRESH_INTERVAL_MS);
  </script>
</body>
</html>
"""


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = True,
    env: ProfileEnv | None = None,
    cwd: pathlib.Path | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
        env=env,
        cwd=cwd,
    )


def profile_paths() -> list[pathlib.Path]:
    return sorted(list(PROFILE_DIR.glob("*.env")) + list(PROFILE_DIR.glob("*.json")))


def load_profiles() -> dict[str, ProfileEnv]:
    profiles: dict[str, ProfileEnv] = {}
    for path in profile_paths():
        try:
            profiles[path.stem] = load_profile(path)
        except ProfileFormatError as exc:
            raise SystemExit(str(exc)) from exc
    return profiles


def require_profile(name: str) -> ProfileEnv:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    return profiles[name]


def pid_path(profile_name: str) -> pathlib.Path:
    return RUN_DIR / f"{profile_name}.pid"


def read_active_profile() -> str | None:
    if not ACTIVE_PROFILE_PATH.exists():
        return None
    name = ACTIVE_PROFILE_PATH.read_text().strip()
    return name or None


def write_active_profile(name: str) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    ACTIVE_PROFILE_PATH.write_text(f"{name}\n")


def clear_active_profile(name: str | None = None) -> None:
    if name is None or read_active_profile() == name:
        ACTIVE_PROFILE_PATH.unlink(missing_ok=True)


def log_path(env: ProfileEnv) -> str:
    raw_name = env.get("LOG_ALIAS") or env.get("MODEL_ALIAS") or env["PROFILE_NAME"]
    safe_name = "".join(char if char.isalnum() or char in {"_", ".", "-"} else "_" for char in raw_name)
    return f"/tmp/{safe_name}.log"


def profile_working_directory(env: ProfileEnv) -> pathlib.Path | None:
    raw = env.get("WORKING_DIRECTORY") or env.get("WORKDIR") or ""
    raw = raw.strip()
    return expand_profile_path(raw) if raw else None


def validate_http_url(url: str, *, field: str = "URL") -> str:
    value = url.strip()
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.netloc:
        raise ValueError(f"{field} must use http or https")
    return value.rstrip("/")


def url_host_literal(host: str) -> str:
    value = host.strip()
    if ":" in value and not (value.startswith("[") and value.endswith("]")):
        return f"[{value}]"
    return value


def default_client_host(env: ProfileEnv) -> str:
    host = env.get("HOST", "127.0.0.1").strip() or "127.0.0.1"
    if is_loopback_host(host):
        return host
    return "127.0.0.1"


def base_url(env: ProfileEnv) -> str:
    configured = env.get("BASE_URL", "").strip()
    if configured:
        return validate_http_url(configured, field="BASE_URL")
    port = env.get("PORT", "").strip()
    if not port:
        return ""
    return f"http://{url_host_literal(default_client_host(env))}:{port}/v1"


def models_url(env: ProfileEnv) -> str:
    configured = env.get("MODEL_LIST_URL", "").strip()
    if configured:
        return validate_http_url(configured, field="MODEL_LIST_URL")
    url = base_url(env)
    if not url:
        return ""
    return f"{url}/models"


def healthcheck_mode(env: ProfileEnv) -> str:
    return env.get("HEALTHCHECK_MODE", "openai-models").strip().lower()


def healthcheck_url(env: ProfileEnv) -> str:
    configured = env.get("HEALTHCHECK_URL", "").strip()
    if configured:
        return validate_http_url(configured, field="HEALTHCHECK_URL")
    if healthcheck_mode(env) == "openai-models":
        return models_url(env)
    return base_url(env)


def endpoint_host(env: ProfileEnv) -> str:
    if env.get("HOST"):
        return env["HOST"]
    url = base_url(env)
    parsed = urllib.parse.urlparse(url)
    return parsed.hostname or "127.0.0.1"


def endpoint_port(env: ProfileEnv) -> str:
    if env.get("PORT"):
        return env["PORT"]
    url = base_url(env)
    parsed = urllib.parse.urlparse(url)
    return str(parsed.port or "")


def normalized_endpoint_host(host: str) -> str:
    normalized = host.strip().lower().strip("[]")
    if normalized in {"127.0.0.1", "localhost", "::1"}:
        return "localhost"
    return normalized


def endpoint_identity(env: ProfileEnv) -> tuple[str, str] | None:
    port = endpoint_port(env).strip()
    if not port:
        return None
    host = normalized_endpoint_host(endpoint_host(env))
    if not host:
        return None
    return host, port


def profile_endpoint_conflicts(profiles: dict[str, ProfileEnv]) -> dict[str, tuple[str, list[str]]]:
    groups: dict[tuple[str, str], list[str]] = {}
    for name, env in sorted(profiles.items()):
        identity = endpoint_identity(env)
        if not identity:
            continue
        groups.setdefault(identity, []).append(name)

    conflicts: dict[str, tuple[str, list[str]]] = {}
    for (host, port), names in groups.items():
        if len(names) < 2:
            continue
        ordered_names = sorted(names, key=str.lower)
        endpoint = f"{host}:{port}"
        for name in ordered_names:
            conflicts[name] = (endpoint, [other for other in ordered_names if other != name])
    return conflicts


def format_endpoint_conflict(endpoint: str, other_profiles: list[str]) -> str:
    label = "profile" if len(other_profiles) == 1 else "profiles"
    peers = ", ".join(other_profiles)
    return f"endpoint {endpoint} is also configured for {label} {peers}"


def ensure_unique_profile_endpoint(
    name: str,
    profiles: dict[str, ProfileEnv],
    *,
    action: str,
) -> None:
    conflict = profile_endpoint_conflicts(profiles).get(name)
    if not conflict:
        return
    endpoint, other_profiles = conflict
    detail = format_endpoint_conflict(endpoint, other_profiles)
    raise ProfileConflictError(
        f"Cannot {action} {name}: {detail}. Each profile must use a unique HOST:PORT or BASE_URL."
    )


def read_pid(profile_name: str) -> int | None:
    path = pid_path(profile_name)
    if not path.exists():
        return None
    raw = path.read_text().strip()
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def process_alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def child_pids(pid: int) -> list[int]:
    try:
        output = run(["pgrep", "-P", str(pid)]).stdout.strip().splitlines()
    except subprocess.CalledProcessError:
        return []
    children: list[int] = []
    for item in output:
        item = item.strip()
        if item.isdigit():
            children.append(int(item))
    return children


def process_tree_pids(pid: int) -> list[int]:
    seen: set[int] = set()
    ordered: list[int] = []

    def visit(current: int) -> None:
        if current in seen:
            return
        seen.add(current)
        ordered.append(current)
        for child in child_pids(current):
            visit(child)

    visit(pid)
    return ordered


def pid_command(pid: int | None) -> str | None:
    if not pid:
        return None
    try:
        return run(["ps", "-o", "command=", "-p", str(pid)]).stdout.strip() or None
    except subprocess.CalledProcessError:
        return None


def pid_matches_profile(pid: int | None, name: str, env: ProfileEnv) -> bool:
    command = pid_command(pid)
    if not command:
        return False

    normalized_command = command.lower()
    markers = {
        name,
        env.get("PROFILE_NAME"),
        env.get("MODEL_ALIAS"),
        env.get("REQUEST_MODEL"),
        env.get("SERVER_MODEL_ID"),
        env.get("MODEL_PATH"),
        env.get("MODEL_DIR"),
        env.get("MODEL_FILE"),
        env.get("MODEL_REPO"),
    }
    return any(marker and marker.lower() in normalized_command for marker in markers)


def pid_rss_mb(pid: int | None) -> float | None:
    if not pid:
        return None
    try:
        rss_kb = run(["ps", "-o", "rss=", "-p", str(pid)]).stdout.strip()
        if not rss_kb:
            return None
        return round(int(rss_kb) / 1024, 1)
    except (subprocess.CalledProcessError, ValueError):
        return None


def port_listener_pid(port: str) -> int | None:
    if not port:
        return None
    try:
        output = run(["lsof", "-tiTCP:" + port, "-sTCP:LISTEN"]).stdout.strip().splitlines()
    except subprocess.CalledProcessError:
        return None
    for item in output:
        item = item.strip()
        if item.isdigit():
            return int(item)
    return None


def fetch_openai_models(url: str, timeout: float = 1.5) -> list[str]:
    if not url:
        return []
    try:
        url = validate_http_url(url)
    except ValueError:
        return []
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- validate_http_url rejects non-http profile URLs before this request.
            payload = json.loads(response.read().decode())
        return [item.get("id", "") for item in payload.get("data", []) if item.get("id")]
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return []


def probe_health(env: ProfileEnv, timeout: float = 1.5) -> tuple[bool, list[str]]:
    mode = healthcheck_mode(env)
    try:
        url = healthcheck_url(env)
    except ValueError:
        return False, []
    if mode == "disabled":
        return False, []
    if mode == "http-200":
        if not url:
            return False, []
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=timeout):  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- healthcheck_url validates explicit profile URLs and generated URLs are loopback http.
                return True, []
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            return False, []
    server_ids = fetch_openai_models(url, timeout=timeout)
    expected = env.get("HEALTHCHECK_EXPECT_ID") or env.get("SERVER_MODEL_ID") or env.get("REQUEST_MODEL")
    if expected:
        return expected in server_ids, server_ids
    return bool(server_ids), server_ids


def status_for_profile(
    name: str,
    env: ProfileEnv,
    *,
    allow_port_fallback: bool = True,
) -> ModelProfileStatusPayload:
    runtime = canonical_runtime(env.get("RUNTIME"))
    spec = runtime_spec(env)
    ready, server_ids = probe_health(env)
    pid = read_pid(name)
    if pid and not process_alive(pid):
        pid_path(name).unlink(missing_ok=True)
        pid = None
    if not pid and allow_port_fallback:
        fallback_pid = port_listener_pid(endpoint_port(env))
        if fallback_pid and (ready or pid_matches_profile(fallback_pid, name, env)):
            pid = fallback_pid
    return {
        "profile": name,
        "display_name": env["DISPLAY_NAME"],
        "runtime": runtime,
        "runtime_label": spec["label"],
        "runtime_tags": runtime_tags(env),
        "launch_mode": spec["launch_mode"],
        "host": endpoint_host(env),
        "port": endpoint_port(env),
        "base_url": base_url(env),
        "request_model": env["REQUEST_MODEL"],
        "server_model_id": env.get("SERVER_MODEL_ID", env["REQUEST_MODEL"]),
        "pid": pid,
        "running": bool(pid and process_alive(pid)),
        "ready": ready,
        "server_ids": server_ids,
        "rss_mb": pid_rss_mb(pid),
        "command": pid_command(pid),
        "log_path": log_path(env),
    }


def status_snapshot(selected: list[str] | None = None) -> list[ModelProfileStatusPayload]:
    profiles = load_profiles()
    conflicts = profile_endpoint_conflicts(profiles)
    names = selected or sorted(profiles)
    return [
        status_for_profile(name, profiles[name], allow_port_fallback=name not in conflicts)
        for name in names
    ]


def status_payload(selected: list[str] | None = None) -> ControllerStatusPayload:
    return make_controller_status_payload(
        statuses=status_snapshot(selected),
        benchmark=benchmark_status(),
        integrations=integration_status(),
        profiles_dir=str(PROFILE_DIR),
        controller_root=str(BASE),
    )


def action_response_from_status(
    payload: ControllerStatusPayload,
    *,
    ok: bool = True,
    error: str | None = None,
) -> ControllerActionResponsePayload:
    return make_action_response_payload(
        statuses=payload["statuses"],
        benchmark=payload["benchmark"],
        integrations=payload["integrations"],
        profiles_dir=payload["profiles_dir"],
        controller_root=payload["controller_root"],
        ok=ok,
        error=error,
    )


def write_status_cache(payload: ControllerStatusPayload) -> None:
    STATUS_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    cache_payload = make_cached_status_payload(
        cached_at=dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        payload=payload,
    )
    temp_path = STATUS_CACHE_PATH.with_suffix(".tmp")
    temp_path.write_text(json.dumps(cache_payload, indent=2, sort_keys=True), encoding="utf-8")
    temp_path.replace(STATUS_CACHE_PATH)


def print_status(selected: list[str] | None = None, *, as_json: bool = False) -> None:
    payload = status_payload(selected)
    statuses = payload["statuses"]
    if as_json:
        print(json.dumps(payload, indent=2))
        return
    print("profile | runtime | state | pid | port | request_model | base_url")
    print("--- | --- | --- | --- | --- | --- | ---")
    for item in statuses:
        if item["ready"]:
            state = "ready"
        elif item["running"]:
            state = "process-only"
        else:
            state = "stopped"
        print(
            " | ".join(
                [
                    item["profile"],
                    item["runtime"],
                    state,
                    str(item["pid"] or "-"),
                    item["port"],
                    item["request_model"],
                    item["base_url"],
                ]
            )
        )


def mutation_action(
    action: str,
    *,
    profile: str | None = None,
    mutates: bool = True,
    command: list[str] | None = None,
    details: dict[str, object] | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "action": action,
        "mutates": mutates,
    }
    if profile:
        payload["profile"] = profile
    if command:
        payload["command"] = command
    if details:
        payload["details"] = details
    return payload


def plan_start_profile(name: str, profiles: dict[str, ProfileEnv] | None = None) -> dict[str, object]:
    profiles = profiles or load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="start")
    env = profiles[name]
    return mutation_action(
        "start-profile",
        profile=name,
        command=["bash", str(START_SCRIPT)],
        details={
            "environment": {"MODEL_PROFILE": name},
            "runtime": env.get("RUNTIME", "llama.cpp"),
            "base_url": base_url(env),
            "request_model": env.get("REQUEST_MODEL"),
        },
    )


def plan_stop_profile(name: str) -> dict[str, object]:
    env = require_profile(name)
    status = status_for_profile(name, env)
    stop_command = env.get("STOP_COMMAND", "").strip()
    return mutation_action(
        "stop-profile",
        profile=name,
        details={
            "pid": status.get("pid"),
            "running": bool(status.get("running")),
            "ready": bool(status.get("ready")),
            "stop_command": stop_command or None,
            "stop_command_only": env.get("STOP_COMMAND_ONLY", "0") == "1",
            "will_clear_active_profile": True,
        },
    )


def plan_restart_profile(name: str, profiles: dict[str, ProfileEnv] | None = None) -> dict[str, object]:
    profiles = profiles or load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="restart")
    return mutation_action(
        "restart-profile",
        profile=name,
        details={
            "steps": [
                plan_stop_profile(name),
                plan_start_profile(name, profiles),
            ]
        },
    )


def plan_switch_profile(name: str) -> dict[str, object]:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="activate")
    running_others = sorted(
        item["profile"] for item in status_snapshot() if item["profile"] != name and item["running"]
    )
    steps = [
        *[
            mutation_action(
                "stop-running-profile",
                profile=profile,
                details={"reason": f"switch activates {name} exclusively"},
            )
            for profile in running_others
        ],
        plan_start_profile(name, profiles),
        mutation_action("write-active-profile", profile=name, details={"path": str(ACTIVE_PROFILE_PATH)}),
    ]
    return mutation_action(
        "switch-profile",
        profile=name,
        details={
            "stop_first": running_others,
            "steps": steps,
        },
    )


def plan_stop_all() -> dict[str, object]:
    profiles = load_profiles()
    benchmark_pid = read_pid("benchmark")
    steps = []
    if benchmark_pid:
        steps.append(mutation_action("stop-benchmark", details={"pid": benchmark_pid}))
    steps.extend(mutation_action("stop-profile", profile=name) for name in sorted(profiles))
    steps.append(mutation_action("run-stop-all-script", command=["bash", str(STOP_ALL_SCRIPT)]))
    return mutation_action(
        "stop-all",
        details={
            "benchmark_pid": benchmark_pid,
            "profiles": sorted(profiles),
            "steps": steps,
        },
    )


def mutating_plan_for_args(args: argparse.Namespace) -> list[dict[str, object]]:
    if args.command == "switch":
        return [plan_switch_profile(args.profile)]
    if args.command == "stop-all":
        return [plan_stop_all()]
    selected = resolve_selected(args)
    if not selected:
        if getattr(args, "dry_run", False) and getattr(args, "profiles", None) == ["all"]:
            return [mutation_action(f"{args.command}-all", details={"profiles": [], "steps": []})]
        raise SystemExit("No profiles selected")
    if args.command == "start":
        profiles = load_profiles()
        return [plan_start_profile(name, profiles) for name in selected]
    if args.command == "stop":
        return [plan_stop_profile(name) for name in selected]
    if args.command == "restart":
        profiles = load_profiles()
        return [plan_restart_profile(name, profiles) for name in selected]
    raise SystemExit(f"Unsupported mutating command: {args.command}")


def mutation_envelope(
    args: argparse.Namespace,
    *,
    dry_run: bool,
    plan: list[dict[str, object]],
    ok: bool = True,
    results: list[dict[str, object]] | None = None,
    error: dict[str, object] | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "schema_version": CLI_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "command": args.command,
        "dry_run": dry_run,
        "status": "planned" if dry_run else ("applied" if ok else "failed"),
        "ok": ok,
        "generated_at": utc_now().isoformat().replace("+00:00", "Z"),
        "plan": plan,
        "results": results or [],
    }
    if error:
        payload["error"] = error
    if not dry_run and ok:
        payload["status_after"] = status_payload()
    return payload


def print_mutation_plan(envelope: dict[str, object]) -> None:
    print(f"plan {envelope['command']} dry_run={str(envelope['dry_run']).lower()}")
    for item in envelope["plan"]:
        profile = f" {item['profile']}" if item.get("profile") else ""
        print(f"- {item['action']}{profile}")
        details = item.get("details")
        if isinstance(details, dict):
            steps = details.get("steps")
            if isinstance(steps, list):
                for step in steps:
                    step_profile = f" {step['profile']}" if step.get("profile") else ""
                    print(f"  - {step['action']}{step_profile}")


def mutation_exit_code(exc: BaseException) -> int:
    if isinstance(exc, ProfileConflictError):
        return 5
    if isinstance(exc, SystemExit) and isinstance(exc.code, int):
        return exc.code
    return 1


def mutation_error_payload(exc: BaseException) -> dict[str, object]:
    if isinstance(exc, ProfileConflictError):
        code = "profile_conflict"
    elif isinstance(exc, SystemExit):
        code = "usage_error" if isinstance(exc.code, int) and exc.code == 64 else "user_input_error"
    else:
        code = "operation_failed"
    return {
        "code": code,
        "message": str(exc),
    }


def execute_mutating_args(args: argparse.Namespace) -> None:
    if args.command == "switch":
        switch_profile(args.profile)
        return
    if args.command == "stop-all":
        stop_all(capture_script=True)
        return
    selected = resolve_selected(args)
    if not selected:
        raise SystemExit("No profiles selected")
    for name in selected:
        if args.command == "start":
            start_profile(name)
        elif args.command == "stop":
            stop_profile(name)
        elif args.command == "restart":
            restart_profile(name)
        else:
            raise SystemExit(f"Unsupported mutating command: {args.command}")


def capture_mutating_execution(args: argparse.Namespace) -> tuple[list[dict[str, object]], BaseException | None]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    try:
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            execute_mutating_args(args)
    except (Exception, SystemExit) as exc:  # noqa: BLE001
        return [
            {
                "ok": False,
                "stdout": stdout.getvalue().splitlines(),
                "stderr": stderr.getvalue().splitlines(),
            }
        ], exc
    return [
        {
            "ok": True,
            "stdout": stdout.getvalue().splitlines(),
            "stderr": stderr.getvalue().splitlines(),
        }
    ], None


def handle_mutating_command(args: argparse.Namespace) -> int:
    as_json = bool(getattr(args, "json", False))
    dry_run = bool(getattr(args, "dry_run", False))
    try:
        plan = mutating_plan_for_args(args)
    except (Exception, SystemExit) as exc:  # noqa: BLE001
        if not as_json:
            raise
        payload = mutation_envelope(
            args,
            dry_run=dry_run,
            plan=[],
            ok=False,
            error=mutation_error_payload(exc),
        )
        print(json.dumps(payload, indent=2))
        return mutation_exit_code(exc)

    if dry_run:
        payload = mutation_envelope(args, dry_run=True, plan=plan)
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            print_mutation_plan(payload)
        return 0

    if as_json:
        results, error = capture_mutating_execution(args)
        payload = mutation_envelope(
            args,
            dry_run=False,
            plan=plan,
            ok=error is None,
            results=results,
            error=mutation_error_payload(error) if error else None,
        )
        print(json.dumps(payload, indent=2))
        return 0 if error is None else mutation_exit_code(error)

    execute_mutating_args(args)
    return 0



def start_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="start")
    env = os.environ.copy()
    env["MODEL_PROFILE"] = name
    result = run(["bash", str(START_SCRIPT)], env=env)
    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)



def signal_pid(pid: int, sig: int) -> None:
    try:
        os.kill(pid, sig)
    except ProcessLookupError:
        return
    except OSError:
        return


def signal_process_tree(pid: int, sig: int) -> None:
    try:
        pgid = os.getpgid(pid)
    except ProcessLookupError:
        return
    except OSError:
        pgid = None

    if pgid and pgid != os.getpgrp():
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        except OSError:
            pass

    for item in reversed(process_tree_pids(pid)):
        signal_pid(item, sig)


def terminate_pid(pid: int, *, timeout: float = 12.0) -> None:
    signal_process_tree(pid, signal.SIGTERM)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return
        time.sleep(0.5)
    signal_process_tree(pid, signal.SIGKILL)


def terminate_profile_processes(name: str, env: ProfileEnv, pid: int | None) -> bool:
    terminated = False
    if pid:
        terminate_pid(pid)
        terminated = True

    # A stale PID file should not leave a model server behind. If the profile
    # endpoint is still answering, reclaim the listener too.
    listener_pid = port_listener_pid(endpoint_port(env))
    if listener_pid and listener_pid != pid:
        ready, _ = probe_health(env)
        if ready or pid_matches_profile(listener_pid, name, env):
            terminate_pid(listener_pid)
            terminated = True
    return terminated


def wait_for_profile_stopped(name: str, env: ProfileEnv, pid: int | None, *, timeout: float = 8.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        listener_pid = port_listener_pid(endpoint_port(env))
        ready, _ = probe_health(env, timeout=0.5)
        primary_alive = process_alive(pid)
        listener_alive = bool(
            listener_pid and (listener_pid == pid or ready or pid_matches_profile(listener_pid, name, env))
        )
        if not primary_alive and not listener_alive and not ready:
            return True
        time.sleep(0.5)
    return False


def run_profile_shell(command: str, env: ProfileEnv) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    merged_env.update(env)
    return run(["bash", "-lc", command], env=merged_env, cwd=profile_working_directory(env))



def stop_profile(name: str) -> None:
    env = require_profile(name)
    status = status_for_profile(name, env)
    pid = status["pid"]
    stop_command = env.get("STOP_COMMAND", "").strip()
    stop_error: Exception | None = None
    if stop_command:
        try:
            run_profile_shell(stop_command, env)
        except Exception as exc:  # noqa: BLE001
            stop_error = exc
    if not pid:
        terminated = False
        if env.get("STOP_COMMAND_ONLY", "0") != "1":
            terminated = terminate_profile_processes(name, env, None)
            if terminated and not wait_for_profile_stopped(name, env, None):
                raise RuntimeError(f"failed to stop {name}: endpoint or process is still alive")
        pid_path(name).unlink(missing_ok=True)
        clear_active_profile(name)
        if stop_error:
            raise RuntimeError(f"STOP_COMMAND failed for {name}: {stop_error}") from stop_error
        if terminated:
            print(f"[INFO] stopped {name} (stale listener)")
        else:
            print(f"[INFO] {name} already stopped")
        return
    if env.get("STOP_COMMAND_ONLY", "0") != "1":
        terminate_profile_processes(name, env, pid)
        if not wait_for_profile_stopped(name, env, pid):
            raise RuntimeError(f"failed to stop {name}: endpoint or process is still alive")
    pid_path(name).unlink(missing_ok=True)
    clear_active_profile(name)
    if stop_error:
        raise RuntimeError(f"STOP_COMMAND failed for {name}: {stop_error}") from stop_error
    print(f"[INFO] stopped {name} (pid {pid})")



def restart_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="restart")
    stop_profile(name)
    start_profile(name)



def stop_all(*, capture_script: bool = False) -> None:
    benchmark_pid = read_pid("benchmark")
    if benchmark_pid:
        terminate_pid(benchmark_pid)
        benchmark_pid_path().unlink(missing_ok=True)
    profiles = load_profiles()
    errors: list[str] = []
    for name in sorted(profiles):
        try:
            stop_profile(name)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {exc}")
    result = run(["bash", str(STOP_ALL_SCRIPT)], capture=capture_script)
    if capture_script:
        sys.stdout.write(result.stdout)
        if result.stderr:
            sys.stderr.write(result.stderr)
    if errors:
        raise RuntimeError("Failed to stop profiles: " + "; ".join(errors))



def sync_droid() -> None:
    run([sys.executable, str(SYNC_SCRIPT)], capture=False)


def integration_status() -> list[ControllerIntegrationPayload]:
    integrations: list[ControllerIntegrationPayload] = []
    droid_available = SYNC_SCRIPT.exists() and (FACTORY_SETTINGS_PATH.exists() or shutil.which("droid"))
    if droid_available:
        integrations.append(
            {
                "id": "droid",
                "display_name": "Factory Droid",
                "kind": "model_registry",
                "capabilities": ["sync"],
                "sync_label": "Sync Droid",
                "description": "Sync managed local profiles into Factory Droid custom model settings.",
            }
        )
    return integrations


def run_integration_action(integration_id: str, action: str = "sync") -> None:
    if integration_id == "droid" and action == "sync":
        sync_droid()
        return
    raise SystemExit(f"Unsupported integration action: {integration_id}:{action}")


def switch_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="activate")
    for item in status_snapshot():
        if item["profile"] != name and item["running"]:
            stop_profile(item["profile"])
    start_profile(name)
    write_active_profile(name)


def active_profile_watchdog_once() -> None:
    name = read_active_profile()
    if not name:
        return
    profiles = load_profiles()
    env = profiles.get(name)
    if not env:
        clear_active_profile(name)
        return
    status = status_for_profile(name, env)
    if status["ready"] or status["running"]:
        return
    start_profile(name)


def run_active_profile_watchdog(interval: float = 30.0) -> None:
    while True:
        try:
            active_profile_watchdog_once()
        except Exception as exc:  # noqa: BLE001
            print(f"[WARN] active profile watchdog failed: {exc}", file=sys.stderr)
        time.sleep(interval)


def latest_benchmark_report() -> BenchmarkLatestReportPayload | None:
    latest_json = BENCH_RESULTS_DIR / "latest.json"
    latest_md = BENCH_RESULTS_DIR / "latest.md"
    if not latest_json.exists():
        return None
    try:
        payload = json.loads(latest_json.read_text())
    except json.JSONDecodeError:
        return None
    rows: list[BenchmarkLatestRowPayload] = []
    for item in payload.get("benchmarks", []):
        avg = item.get("averages", {})
        rows.append(
            {
                "profile": item.get("profile"),
                "runtime": item.get("runtime"),
                "ttft_ms": avg.get("ttft_ms"),
                "decode_tokens_per_sec": avg.get("decode_tokens_per_sec"),
                "e2e_tokens_per_sec": avg.get("e2e_tokens_per_sec"),
                "rss_mb": item.get("rss_mb"),
            }
        )
    return {
        "generated_at": payload.get("generated_at"),
        "suite": payload.get("suite"),
        "profiles": payload.get("profiles", []),
        "rows": rows,
        "json_path": str(latest_json),
        "markdown_path": str(latest_md),
    }


def benchmark_pid_path() -> pathlib.Path:
    return RUN_DIR / "benchmark.pid"


def benchmark_log_dir() -> pathlib.Path:
    return RUN_DIR / "logs"


def benchmark_log_pointer_path() -> pathlib.Path:
    return RUN_DIR / "benchmark.log.path"


def secure_benchmark_log_dir() -> pathlib.Path:
    log_dir = benchmark_log_dir()
    log_dir.mkdir(parents=True, exist_ok=True)
    log_dir.chmod(0o700)
    return log_dir


def benchmark_log_path() -> pathlib.Path:
    pointer = benchmark_log_pointer_path()
    if pointer.exists():
        try:
            path = pathlib.Path(pointer.read_text(encoding="utf-8").strip())
        except OSError:
            path = pathlib.Path()
        if path.is_absolute() and path.parent == benchmark_log_dir():
            return path
    return benchmark_log_dir() / "benchmark.log"


def open_benchmark_log_file(path: pathlib.Path) -> BinaryIO:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    return os.fdopen(fd, "ab", buffering=0)


def create_benchmark_log_file() -> tuple[pathlib.Path, BinaryIO]:
    log_dir = secure_benchmark_log_dir()
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    for _ in range(32):
        path = log_dir / f"benchmark-{timestamp}-{secrets.token_hex(8)}.log"
        try:
            return path, open_benchmark_log_file(path)
        except FileExistsError:
            continue
    raise RuntimeError("could not create unique benchmark log")


def write_benchmark_log_pointer(path: pathlib.Path) -> None:
    pointer = benchmark_log_pointer_path()
    pointer.parent.mkdir(parents=True, exist_ok=True)
    temp_path = pointer.with_suffix(".tmp")
    temp_path.write_text(f"{path}\n", encoding="utf-8")
    temp_path.chmod(0o600)
    temp_path.replace(pointer)


def benchmark_status() -> BenchmarkStatusPayload:
    pid = read_pid("benchmark")
    alive = bool(pid and process_alive(pid))
    if pid and not alive:
        benchmark_pid_path().unlink(missing_ok=True)
        pid = None
    return {
        "running": alive,
        "pid": pid,
        "log_path": str(benchmark_log_path()),
        "latest": latest_benchmark_report(),
    }


def start_benchmark(
    profiles: list[str] | None = None,
    *,
    suite: str = "quick",
    allow_concurrent: bool = False,
    keep_running: bool = False,
) -> BenchmarkStatusPayload:
    current = benchmark_status()
    if current["running"]:
        return current
    selected = profiles or ["all"]
    cmd = [sys.executable, str(BENCH_SCRIPT), "--suite", suite, "--profiles", *selected]
    if allow_concurrent:
        cmd.append("--allow-concurrent")
    if keep_running:
        cmd.append("--keep-running")
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    log_path, log_fp = create_benchmark_log_file()
    with log_fp, open(os.devnull, "rb") as stdin_fp:
        proc = subprocess.Popen(
            cmd,
            stdin=stdin_fp,
            stdout=log_fp,
            stderr=log_fp,
            start_new_session=True,
            close_fds=True,
        )
    write_benchmark_log_pointer(log_path)
    benchmark_pid_path().write_text(f"{proc.pid}\n")
    return benchmark_status()


def resolve_executable(*candidates: str | None) -> str | None:
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return None


def resolve_llama_server_bin(env: ProfileEnv | None = None) -> str | None:
    env = env or {}
    return (
        resolve_executable(
            env.get("SERVER_BIN"),
            env.get("LLAMA_SERVER_BIN"),
            env.get("LLAMA_CPP_SERVER_BIN"),
            os.environ.get("SERVER_BIN"),
            os.environ.get("LLAMA_SERVER_BIN"),
            os.environ.get("LLAMA_CPP_SERVER_BIN"),
        )
        or shutil.which("llama-server")
        or shutil.which("llama.cpp-server")
    )


def resolve_mlx_server_bin(env: ProfileEnv | None = None) -> str | None:
    env = env or {}
    return (
        resolve_executable(
            env.get("SERVER_BIN"),
            env.get("MLX_SERVER_BIN"),
            env.get("MLX_LM_SERVER_BIN"),
            os.environ.get("SERVER_BIN"),
            os.environ.get("MLX_SERVER_BIN"),
            os.environ.get("MLX_LM_SERVER_BIN"),
        )
        or shutil.which("mlx_lm.server")
    )


def resolve_vllm_mlx_server_bin(env: ProfileEnv | None = None) -> str | None:
    env = env or {}
    return (
        resolve_executable(
            env.get("SERVER_BIN"),
            env.get("VLLM_MLX_BIN"),
            os.environ.get("SERVER_BIN"),
            os.environ.get("VLLM_MLX_BIN"),
        )
        or shutil.which("vllm-mlx")
    )


def expand_profile_path(value: str) -> pathlib.Path:
    return pathlib.Path(os.path.expanduser(value))


def detect_model_root(env: ProfileEnv, *, base: pathlib.Path = BASE) -> pathlib.Path | None:
    configured_root = env.get("MODEL_ROOT", "").strip()
    if configured_root:
        return expand_profile_path(configured_root)

    configured_hint = env.get("MODEL_ROOT_HINT", "").strip()
    if configured_hint:
        return expand_profile_path(configured_hint)

    for candidate in (pathlib.Path.home() / "AI" / "models", base.parent / "models"):
        if candidate.is_dir():
            return candidate

    return None


def model_path_for_profile(env: ProfileEnv, *, base: pathlib.Path = BASE) -> pathlib.Path | None:
    configured_path = env.get("MODEL_PATH", "").strip()
    if configured_path:
        return expand_profile_path(configured_path)

    model_file = env.get("MODEL_FILE", "").strip()
    if not model_file:
        return None

    model_root = detect_model_root(env, base=base)
    if model_root:
        return model_root / model_file
    return None


def adapter_model_source(env: ProfileEnv, *, base: pathlib.Path = BASE) -> str | None:
    for key in ("MODEL_DIR", "MODEL_PATH"):
        value = env.get(key, "").strip()
        if value:
            return str(expand_profile_path(value))
    model_path = model_path_for_profile(env, base=base)
    if model_path:
        return str(model_path)
    for key in ("MODEL_ID", "MODEL_REPO"):
        value = env.get(key, "").strip()
        if value:
            return value
    return None


def executable_configured(env: ProfileEnv, *keys: str) -> bool:
    return bool(resolve_executable(*(env.get(key) for key in keys)))


def launch_agent_status() -> LaunchAgentStatusPayload:
    try:
        output = run(["launchctl", "list"], check=False).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"warn: failed to read launchctl status: {exc}", file=sys.stderr)
        output = ""
    running = LAUNCH_AGENT_LABEL in output
    return {"plist_path": str(LAUNCH_AGENT_PLIST), "installed": LAUNCH_AGENT_PLIST.exists(), "running": running}


def controller_status() -> ControllerHeartbeatPayload:
    url = f"http://{DEFAULT_WEB_HOST}:{DEFAULT_WEB_PORT}/api/status"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=1.5) as response:  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- controller_status probes the fixed loopback controller URL.
            payload = json.loads(response.read().decode())
        return {
            "url": url,
            "reachable": True,
            "profiles": len(payload.get("statuses", [])),
            "integrations": len(payload.get("integrations", [])),
        }
    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        TimeoutError,
        json.JSONDecodeError,
        UnicodeDecodeError,
    ):
        return {"url": url, "reachable": False, "profiles": 0, "integrations": 0}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def utc_stamp() -> str:
    return utc_now().strftime("%Y%m%dT%H%M%SZ")


def tool_version() -> str:
    version_path = PROJECT_ROOT / "VERSION"
    try:
        return version_path.read_text(encoding="utf-8").strip() or "unknown"
    except OSError:
        return "unknown"


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_path(path: pathlib.Path) -> str | None:
    if not path.exists() or path.is_dir():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def doctor_run_id(label: str = "doctor") -> str:
    stamp = utc_stamp()
    seed = f"{PROJECT_ROOT}:{stamp}:{label}:{os.getpid()}"
    return f"{stamp}__{hashlib.sha256(seed.encode('utf-8')).hexdigest()[:8]}"


def doctor_run_dir(run_id: str) -> pathlib.Path:
    return DOCTOR_RUNS_DIR / run_id


def write_json_atomic(path: pathlib.Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temp_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temp_path.replace(path)


def append_jsonl(path: pathlib.Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def update_doctor_latest(run_dir: pathlib.Path) -> None:
    DOCTOR_ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = DOCTOR_ARTIFACT_DIR / f".latest.{os.getpid()}.tmp"
    tmp.unlink(missing_ok=True)
    os.symlink(f"runs/{run_dir.name}", tmp)
    tmp.replace(DOCTOR_LATEST_PATH)


def doctor_finding(
    *,
    finding_id: str,
    severity: str,
    subsystem: str,
    message: str,
    evidence: str,
    remediation: str,
    auto_fixable: bool = False,
    fixer: str | None = None,
) -> dict[str, object]:
    return {
        "id": finding_id,
        "severity": severity,
        "subsystem": subsystem,
        "message": message,
        "evidence": evidence,
        "remediation": remediation,
        "auto_fixable": auto_fixable,
        "fixer": fixer,
        "online_required": False,
    }


def profile_finding_id(profile: str, kind: str, message: str) -> str:
    slug = "".join(char.lower() if char.isalnum() else "-" for char in profile).strip("-") or "profile"
    digest = sha256_text(f"{profile}:{kind}:{message}")[:8]
    return f"fm-profile-{slug}-{kind}-{digest}"


def doctor_findings(report: DoctorReportPayload) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    profiles_dir = pathlib.Path(report["profiles_dir"])
    if not profiles_dir.exists():
        findings.append(
            doctor_finding(
                finding_id="fm-profiles-dir-missing",
                severity="P1",
                subsystem="profiles",
                message="profiles directory is missing",
                evidence=str(profiles_dir),
                remediation="./Controller/modelctl.py doctor --fix",
                auto_fixable=True,
                fixer="create-profiles-dir",
            )
        )
    elif not profiles_dir.is_dir():
        findings.append(
            doctor_finding(
                finding_id="fm-profiles-dir-not-directory",
                severity="P0",
                subsystem="profiles",
                message="profiles path exists but is not a directory",
                evidence=str(profiles_dir),
                remediation="Move the file aside, then run ./Controller/modelctl.py doctor --fix",
            )
        )
    controller = report["controller"]
    if not controller["reachable"]:
        findings.append(
            doctor_finding(
                finding_id="fm-controller-unreachable",
                severity="P2",
                subsystem="controller",
                message="controller API is not reachable",
                evidence=controller["url"],
                remediation="./Controller/modelctl.py serve-web",
            )
        )
    launch_agent = report["launch_agent"]
    if not launch_agent["installed"]:
        findings.append(
            doctor_finding(
                finding_id="fm-launch-agent-not-installed",
                severity="P2",
                subsystem="launch-agent",
                message="controller LaunchAgent is not installed",
                evidence=launch_agent["plist_path"],
                remediation="./Controller/install-model-switchboard-controller.sh",
            )
        )
    elif not launch_agent["running"]:
        findings.append(
            doctor_finding(
                finding_id="fm-launch-agent-not-running",
                severity="P2",
                subsystem="launch-agent",
                message="controller LaunchAgent is installed but not running",
                evidence=launch_agent["plist_path"],
                remediation="launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.modelswitchboard.controller.plist",
            )
        )
    for profile in report["profiles"]:
        for message in profile["errors"]:
            findings.append(
                doctor_finding(
                    finding_id=profile_finding_id(profile["profile"], "error", message),
                    severity="P1",
                    subsystem="profile",
                    message=message,
                    evidence=f"profile={profile['profile']} base_url={profile['base_url'] or 'n/a'}",
                    remediation=f"Edit {PROFILE_DIR / (profile['profile'] + '.env')} or run ./Controller/modelctl.py doctor explain {profile_finding_id(profile['profile'], 'error', message)}",
                )
            )
        for message in profile["warnings"]:
            findings.append(
                doctor_finding(
                    finding_id=profile_finding_id(profile["profile"], "warning", message),
                    severity="P3",
                    subsystem="profile",
                    message=message,
                    evidence=f"profile={profile['profile']} base_url={profile['base_url'] or 'n/a'}",
                    remediation=f"Review {PROFILE_DIR / (profile['profile'] + '.env')}",
                )
            )
    return findings


def doctor_next_steps(findings: list[dict[str, object]]) -> list[str]:
    if not findings:
        return ["No findings. Re-run with --json for machine-readable status."]
    steps = ["Run ./Controller/modelctl.py doctor --json for structured findings."]
    if any(finding.get("auto_fixable") for finding in findings):
        steps.append("Preview safe repairs with ./Controller/modelctl.py doctor --dry-run --fix --json.")
        steps.append("Apply safe repairs with ./Controller/modelctl.py doctor --fix --json.")
    steps.append("Use ./Controller/modelctl.py doctor explain <finding-id> for evidence and remediation.")
    return steps


def write_doctor_run_artifact(payload: object, *, run_id: str, command: str) -> pathlib.Path:
    run_dir = doctor_run_dir(run_id)
    run_dir.mkdir(parents=True, exist_ok=True)
    write_json_atomic(
        run_dir / "report.json",
        {
            "command": command,
            "generated_at": utc_now().isoformat().replace("+00:00", "Z"),
            "payload": payload,
        },
    )
    update_doctor_latest(run_dir)
    return run_dir


def doctor_capabilities() -> dict[str, object]:
    return {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "doctor_contract_version": DOCTOR_CONTRACT_VERSION,
        "default_command": "diagnose",
        "offline_default": True,
        "subcommands": ["diagnose", "health", "capabilities", "robot-docs", "explain", "undo"],
        "detectors": [
            {"id": "profiles-dir", "subsystem": "profiles", "online_required": False},
            {"id": "controller-api", "subsystem": "controller", "online_required": False},
            {"id": "launch-agent", "subsystem": "launch-agent", "online_required": False},
            {"id": "profile-config", "subsystem": "profile", "online_required": False},
        ],
        "fixers": [
            {
                "id": "create-profiles-dir",
                "description": "Create the controller model-profiles directory when it is absent.",
                "writes_to": [str(PROFILE_DIR)],
                "undo": True,
            }
        ],
        "write_scopes": [str(PROFILE_DIR), str(DOCTOR_ARTIFACT_DIR)],
        "artifacts": {
            "runs_dir": str(DOCTOR_RUNS_DIR),
            "latest": str(DOCTOR_LATEST_PATH),
            "actions_jsonl": "actions.jsonl",
            "backups_dir": "backups/",
        },
        "exit_codes": {
            "0": "healthy, fix complete, or undo complete",
            "1": "findings present in diagnose mode",
            "2": "fix partially applied",
            "3": "fix failed and rolled back",
            "4": "refused unsafe state",
            "5": "concurrency lost",
            "64": "usage error",
        },
        "env_vars": ["MODEL_SWITCHBOARD_URL", "MODEL_SWITCHBOARD_APP_PATH", "MODEL_SWITCHBOARD_VARIANT"],
    }


def doctor_health_payload() -> dict[str, object]:
    report = doctor_report()
    findings = report["findings"]
    return {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "healthy": not findings,
        "finding_count": len(findings),
        "auto_fixable_count": sum(1 for finding in findings if finding.get("auto_fixable")),
        "controller_reachable": report["controller"]["reachable"],
        "launch_agent_installed": report["launch_agent"]["installed"],
        "launch_agent_running": report["launch_agent"]["running"],
    }


def doctor_robot_docs() -> str:
    capabilities = doctor_capabilities()
    exit_codes = capabilities["exit_codes"]
    return "\n".join(
        [
            "Model Switchboard doctor robot docs",
            "",
            "Safe defaults:",
            "- `doctor` and `doctor diagnose` do not modify profile/controller state.",
            "- `doctor --fix` only applies fixers declared by `doctor capabilities --json`.",
            "- `doctor --dry-run --fix --json` prints the planned actions first.",
            "- `doctor undo <run-id>` reverses recorded fix actions from `.doctor/runs/<run-id>/actions.jsonl`.",
            "- Network probes are not used by this doctor.",
            "",
            "Primary commands:",
            "- `./Controller/modelctl.py doctor --json`",
            "- `./Controller/modelctl.py doctor health --json`",
            "- `./Controller/modelctl.py doctor capabilities --json`",
            "- `./Controller/modelctl.py doctor --dry-run --fix --json`",
            "- `./Controller/modelctl.py doctor explain <finding-id> --json`",
            "- `./Controller/modelctl.py doctor undo <run-id> --json`",
            "",
            "Exit codes:",
            *[f"- {code}: {meaning}" for code, meaning in exit_codes.items()],
        ]
    )


def modelctl_command_contracts() -> list[dict[str, object]]:
    return [
        {
            "name": "capabilities",
            "aliases": ["--capabilities"],
            "mutates": False,
            "json": True,
            "purpose": "Return the machine-readable CLI contract.",
            "examples": ["./Controller/modelctl.py capabilities --json"],
        },
        {
            "name": "robot-docs",
            "aliases": ["docs", "--robot-docs", "--robot-help"],
            "mutates": False,
            "json": False,
            "purpose": "Print paste-ready agent guidance.",
            "examples": ["./Controller/modelctl.py robot-docs guide"],
        },
        {
            "name": "triage",
            "aliases": ["--robot-triage"],
            "mutates": False,
            "json": True,
            "purpose": "Return health, recommended commands, and next actions in one call.",
            "examples": ["./Controller/modelctl.py triage --json", "./Controller/modelctl.py --robot-triage"],
        },
        {
            "name": "doctor",
            "aliases": ["diagnose", "validate"],
            "mutates": "only with --fix",
            "json": True,
            "purpose": "Diagnose profiles, controller reachability, LaunchAgent state, and safe repairs.",
            "examples": [
                "./Controller/modelctl.py doctor --json",
                "./Controller/modelctl.py diagnose --json",
                "./Controller/modelctl.py doctor --dry-run --fix --json",
            ],
        },
        {
            "name": "health",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "Alias for doctor health.",
            "examples": ["./Controller/modelctl.py health --json"],
        },
        {
            "name": "status",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "Show profile runtime status.",
            "examples": ["./Controller/modelctl.py status --json"],
        },
        {
            "name": "list",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "List configured profiles.",
            "examples": ["./Controller/modelctl.py list --json"],
        },
        {
            "name": "integrations",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "List optional backend integrations.",
            "examples": ["./Controller/modelctl.py integrations"],
        },
        {
            "name": "start",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Start one or more profiles.",
            "examples": [
                "./Controller/modelctl.py start qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py start qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py doctor --json",
        },
        {
            "name": "stop",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Stop one or more profiles.",
            "examples": [
                "./Controller/modelctl.py stop qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py stop qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "restart",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Restart one or more profiles.",
            "examples": [
                "./Controller/modelctl.py restart qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py restart qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "switch",
            "aliases": ["activate"],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Stop other running profiles and start the selected profile.",
            "examples": [
                "./Controller/modelctl.py switch qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py switch qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "benchmark",
            "aliases": [],
            "mutates": "starts benchmark workers unless --background is omitted and the harness exits inline",
            "json": "with --background",
            "purpose": "Run the benchmark harness.",
            "safe_alternative": "./Controller/modelctl.py triage --json",
        },
        {
            "name": "stop-all",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Stop every managed model process.",
            "examples": [
                "./Controller/modelctl.py stop-all --dry-run --json",
                "./Controller/modelctl.py stop-all --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "serve-web",
            "aliases": [],
            "mutates": "starts a local HTTP server",
            "json": False,
            "purpose": "Serve the local model dashboard.",
            "safe_alternative": "./Controller/modelctl.py doctor --json",
        },
    ]


def modelctl_capabilities() -> dict[str, object]:
    return {
        "schema_version": CLI_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "contract_version": CLI_CONTRACT_VERSION,
        "default_probe": "./Controller/modelctl.py triage --json",
        "offline_first": True,
        "commands": modelctl_command_contracts(),
        "aliases": {**CLI_COMMAND_ALIASES, **CLI_GLOBAL_ALIASES},
        "exit_codes": CLI_EXIT_CODES,
        "env_vars": [
            "MODEL_SWITCHBOARD_URL",
            "MODEL_SWITCHBOARD_APP_PATH",
            "MODEL_SWITCHBOARD_VARIANT",
            "SOURCE_DATE_EPOCH",
            "NO_COLOR",
            "CI",
            "TERM",
        ],
        "stdout_stderr_contract": {
            "stdout": "requested human or JSON data only",
            "stderr": "usage errors, diagnostics, and actionable hints",
        },
        "doctor": doctor_capabilities(),
    }


def modelctl_triage_payload() -> dict[str, object]:
    profiles = load_profiles()
    health = doctor_health_payload()
    recommendations = [
        {
            "id": "inspect-contract",
            "command": "./Controller/modelctl.py capabilities --json",
            "reason": "Discover commands, aliases, mutability, JSON support, and exit codes.",
        },
        {
            "id": "read-agent-guide",
            "command": "./Controller/modelctl.py robot-docs guide",
            "reason": "Get paste-ready usage guidance without opening external docs.",
        },
    ]
    if not health["healthy"]:
        recommendations.insert(
            0,
            {
                "id": "diagnose-findings",
                "command": "./Controller/modelctl.py doctor --json",
                "reason": "Structured findings are present; inspect exact evidence and remediation.",
            },
        )
    if health["auto_fixable_count"]:
        recommendations.insert(
            1,
            {
                "id": "preview-safe-fix",
                "command": "./Controller/modelctl.py doctor --dry-run --fix --json",
                "reason": "Preview reversible fixes before changing local state.",
            },
        )
    return {
        "schema_version": CLI_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "health": health,
        "profiles": {
            "count": len(profiles),
            "names": sorted(profiles),
        },
        "commands": [
            "./Controller/modelctl.py status --json",
            "./Controller/modelctl.py list --json",
            "./Controller/modelctl.py doctor --json",
            "./Controller/modelctl.py capabilities --json",
            "./Controller/modelctl.py robot-docs guide",
        ],
        "recommendations": recommendations,
        "exit_codes": CLI_EXIT_CODES,
    }


def print_modelctl_triage(payload: dict[str, object]) -> None:
    health = payload["health"]
    profiles = payload["profiles"]
    print(f"healthy={str(health['healthy']).lower()} findings={health['finding_count']}")
    print(f"profiles={profiles['count']}")
    for recommendation in payload["recommendations"]:
        print(f"next | {recommendation['id']} | {recommendation['command']}")


def modelctl_robot_docs(topic: str = "guide") -> str:
    if topic != "guide":
        raise ValueError(f"unknown robot-docs topic {topic!r}; use `./Controller/modelctl.py robot-docs guide`")
    return "\n".join(
        [
            "Model Switchboard modelctl robot docs",
            "",
            "First commands to try:",
            "- `./Controller/modelctl.py triage --json` returns health, profile names, recommended commands, and exit codes.",
            "- `./Controller/modelctl.py capabilities --json` returns the machine-readable CLI contract.",
            "- `./Controller/modelctl.py doctor --json` returns structured findings with evidence and remediation.",
            "- `./Controller/modelctl.py status --json` returns live profile status.",
            "- `./Controller/modelctl.py list --json` returns configured profiles.",
            "",
            "Intent aliases:",
            "- `./Controller/modelctl.py diagnose --json` is accepted as `doctor --json`.",
            "- `./Controller/modelctl.py health --json` is accepted as `doctor health --json`.",
            "- `./Controller/modelctl.py --robot-triage` is accepted as `triage --json`.",
            "- `./Controller/modelctl.py --capabilities` is accepted as `capabilities --json`.",
            "",
            "Mutation safety:",
            "- `start`, `stop`, `restart`, `switch`, `benchmark --background`, `stop-all`, and `serve-web` mutate local runtime state.",
            "- Use `status --json`, `doctor --json`, or `triage --json` before mutating when you need a safe probe.",
            "- Use `start|stop|restart|switch <profile> --dry-run --json` or `stop-all --dry-run --json` to preview profile mutations.",
            "- Use `--json` on applied profile mutations to receive a stable envelope with plan, captured output, errors, and post-action status.",
            "- Use `doctor --dry-run --fix --json` before `doctor --fix --json`.",
            "",
            "Output contract:",
            "- JSON commands print data to stdout.",
            "- Usage errors and hints print to stderr and exit 64.",
            "- Diagnostic findings exit non-zero so agents can branch deterministically.",
        ]
    )


def doctor_mutate_create_directory(path: pathlib.Path, *, run_dir: pathlib.Path, dry_run: bool = False) -> dict[str, object]:
    before_exists = path.exists()
    before_hash = sha256_path(path)
    action = {
        "action": "create_directory",
        "path": str(path),
        "before_exists": before_exists,
        "before_hash": before_hash,
        "after_exists": before_exists,
        "after_hash": before_hash,
        "dry_run": dry_run,
    }
    if before_exists:
        action["status"] = "skipped_already_exists"
        return action
    if dry_run:
        action["status"] = "planned"
        return action
    path.mkdir(parents=True, exist_ok=True)
    action["after_exists"] = path.exists()
    action["after_hash"] = sha256_path(path)
    action["status"] = "applied"
    append_jsonl(run_dir / "actions.jsonl", action)
    return action


def doctor_fix(*, dry_run: bool = False, run_id: str | None = None) -> tuple[dict[str, object], int]:
    before = doctor_report()
    run_id = run_id or doctor_run_id("fix")
    run_dir = doctor_run_dir(run_id)
    run_dir.mkdir(parents=True, exist_ok=True)
    actions: list[dict[str, object]] = []
    for finding in before["findings"]:
        if finding.get("fixer") == "create-profiles-dir":
            actions.append(doctor_mutate_create_directory(PROFILE_DIR, run_dir=run_dir, dry_run=dry_run))
    after = before if dry_run else doctor_report()
    payload = {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "run_id": run_id,
        "dry_run": dry_run,
        "actions_taken": sum(1 for action in actions if action.get("status") == "applied"),
        "actions": actions,
        "healthy": after["healthy"],
        "findings": after["findings"],
        "next_steps": doctor_next_steps(after["findings"]),
    }
    write_doctor_run_artifact(payload, run_id=run_id, command="fix")
    if dry_run:
        return payload, 0 if not actions else 1
    if payload["actions_taken"] == 0 and before["findings"]:
        return payload, 1
    return payload, 0 if after["healthy"] else 2


def doctor_undo(run_id: str, *, strict: bool = True) -> tuple[dict[str, object], int]:
    run_dir = doctor_run_dir(run_id)
    actions_path = run_dir / "actions.jsonl"
    if not actions_path.exists():
        return {
            "schema_version": DOCTOR_SCHEMA_VERSION,
            "run_id": run_id,
            "ok": False,
            "error": "actions.jsonl not found",
            "strict": strict,
        }, 4
    actions = [json.loads(line) for line in actions_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    undone: list[dict[str, object]] = []
    quarantine = run_dir / "quarantine"
    for action in reversed(actions):
        if action.get("action") != "create_directory" or action.get("before_exists"):
            continue
        path = pathlib.Path(str(action["path"]))
        item: dict[str, object] = {"action": "undo_create_directory", "path": str(path)}
        if not path.exists():
            item["status"] = "skipped_missing"
            undone.append(item)
            continue
        if any(path.iterdir()):
            item["status"] = "refused_non_empty_directory"
            undone.append(item)
            if strict:
                return {
                    "schema_version": DOCTOR_SCHEMA_VERSION,
                    "run_id": run_id,
                    "ok": False,
                    "strict": strict,
                    "undone": undone,
                    "error": "refused to undo non-empty created directory",
                }, 4
            continue
        quarantine.mkdir(parents=True, exist_ok=True)
        target = quarantine / f"{path.name}.{sha256_text(str(path))[:8]}"
        path.replace(target)
        item["status"] = "quarantined"
        item["quarantine_path"] = str(target)
        undone.append(item)
    payload = {"schema_version": DOCTOR_SCHEMA_VERSION, "run_id": run_id, "ok": True, "strict": strict, "undone": undone}
    write_doctor_run_artifact(payload, run_id=doctor_run_id("undo"), command=f"undo {run_id}")
    return payload, 0


def explain_doctor_finding(finding_id: str) -> tuple[dict[str, object], int]:
    report = doctor_report()
    for finding in report["findings"]:
        if finding["id"] == finding_id:
            return {
                "schema_version": DOCTOR_SCHEMA_VERSION,
                "finding": finding,
                "capabilities": {
                    "fixer": finding.get("fixer"),
                    "auto_fixable": finding.get("auto_fixable"),
                    "online_required": finding.get("online_required"),
                },
                "next_steps": doctor_next_steps([finding]),
            }, 0
    return {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "error": "finding not present in current doctor report",
        "finding_id": finding_id,
        "known_findings": [finding["id"] for finding in report["findings"]],
    }, 1


def diagnose_profile(
    name: str,
    env: ProfileEnv,
    *,
    endpoint_conflict: tuple[str, list[str]] | None = None,
) -> ProfileDiagnosticPayload:
    runtime = canonical_runtime(env.get("RUNTIME"))
    spec = runtime_spec(env)
    launch_mode = spec["launch_mode"]
    errors: list[str] = []
    warnings: list[str] = []
    profile_base_url = ""
    url_config_error = False

    try:
        profile_base_url = base_url(env)
    except ValueError as exc:
        errors.append(str(exc))
        url_config_error = True

    health_url = ""
    health_url_error = False
    if healthcheck_mode(env) != "disabled":
        try:
            health_url = healthcheck_url(env)
        except ValueError as exc:
            message = str(exc)
            if message not in errors:
                errors.append(message)
            health_url_error = True
            url_config_error = True

    if not env.get("DISPLAY_NAME"):
        errors.append("missing DISPLAY_NAME")
    if not env.get("REQUEST_MODEL"):
        errors.append("missing REQUEST_MODEL")

    if launch_mode == "external":
        if healthcheck_mode(env) != "disabled" and not health_url and not health_url_error:
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    elif runtime == "llama.cpp":
        if not resolve_llama_server_bin(env):
            errors.append("llama-server not found")
        model_path = model_path_for_profile(env)
        if not model_path:
            errors.append(
                "missing MODEL_PATH or MODEL_FILE with a model root "
                "(MODEL_ROOT, MODEL_ROOT_HINT, ~/AI/models, or ../models)"
            )
        elif not model_path.exists():
            errors.append(f"model file not found: {model_path}")
    elif runtime == "mlx":
        if not resolve_mlx_server_bin(env):
            errors.append("mlx_lm.server not found")
        model_dir = env.get("MODEL_DIR")
        model_repo = env.get("MODEL_REPO")
        if model_dir:
            if not pathlib.Path(model_dir).exists():
                errors.append(f"MODEL_DIR not found: {model_dir}")
        elif not model_repo:
            errors.append("missing MODEL_DIR or MODEL_REPO")
    elif runtime == "rvllm-mlx":
        server_bin = env.get("SERVER_BIN")
        if not server_bin:
            errors.append("missing SERVER_BIN")
        elif not pathlib.Path(server_bin).exists():
            errors.append(f"SERVER_BIN not found: {server_bin}")
        elif not os.access(server_bin, os.X_OK):
            errors.append(f"SERVER_BIN is not executable: {server_bin}")
        model_dir = env.get("MODEL_DIR")
        if not model_dir:
            errors.append("missing MODEL_DIR")
        elif not pathlib.Path(model_dir).exists():
            errors.append(f"MODEL_DIR not found: {model_dir}")
    elif runtime == "vllm-mlx":
        if not resolve_vllm_mlx_server_bin(env):
            errors.append("vllm-mlx not found")
        model_source = adapter_model_source(env)
        if not model_source:
            errors.append("missing MODEL_REPO, MODEL_ID, MODEL_DIR, MODEL_PATH, or MODEL_FILE for vllm-mlx")
        elif env.get("MODEL_DIR") and not pathlib.Path(env["MODEL_DIR"]).exists():
            errors.append(f"MODEL_DIR not found: {env['MODEL_DIR']}")
    elif runtime == "ollama":
        if not executable_configured(env, "SERVER_BIN", "OLLAMA_BIN") and not shutil.which("ollama"):
            errors.append("ollama not found")
    elif runtime in {"vllm", "sglang", "tgi"}:
        if not adapter_model_source(env):
            errors.append(f"missing MODEL_REPO, MODEL_ID, MODEL_DIR, MODEL_PATH, or MODEL_FILE for {runtime}")
        if runtime == "tgi":
            if not executable_configured(env, "SERVER_BIN", "TGI_SERVER_BIN") and not shutil.which("text-generation-launcher"):
                errors.append("text-generation-launcher not found")
        elif not executable_configured(env, "PYTHON_BIN") and not shutil.which("python3") and not shutil.which("python"):
            errors.append(f"python not found for {runtime}")
    elif runtime == "llama-cpp-python":
        model_source = adapter_model_source(env)
        if not model_source:
            errors.append("missing MODEL_PATH or MODEL_FILE for llama-cpp-python")
        elif not pathlib.Path(model_source).exists():
            errors.append(f"model file not found: {model_source}")
        if not executable_configured(env, "PYTHON_BIN") and not shutil.which("python3") and not shutil.which("python"):
            errors.append("python not found for llama-cpp-python")
    elif runtime == "command":
        if not env.get("START_COMMAND"):
            errors.append("missing START_COMMAND")
        if healthcheck_mode(env) != "disabled" and not health_url and not health_url_error:
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    elif env.get("START_COMMAND"):
        if healthcheck_mode(env) != "disabled" and not health_url and not health_url_error:
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    elif env.get("SERVER_BIN"):
        if not pathlib.Path(env["SERVER_BIN"]).exists():
            errors.append(f"SERVER_BIN not found: {env['SERVER_BIN']}")
        elif not os.access(env["SERVER_BIN"], os.X_OK):
            errors.append(f"SERVER_BIN is not executable: {env['SERVER_BIN']}")
        if not env.get("SERVER_ARGS_JSON"):
            errors.append("missing SERVER_ARGS_JSON for generic SERVER_BIN runtime")
    else:
        warnings.append(f"runtime '{runtime}' has no adapter-specific validation; use START_COMMAND or SERVER_BIN with SERVER_ARGS_JSON")

    if not profile_base_url:
        warnings.append("base_url is empty; endpoint health checks may fail")
    if healthcheck_mode(env) == "disabled":
        warnings.append("healthcheck disabled; ready state cannot be verified")
    if endpoint_conflict:
        endpoint, other_profiles = endpoint_conflict
        errors.append(f"duplicate {format_endpoint_conflict(endpoint, other_profiles)}")

    if url_config_error:
        live = {
            "running": False,
            "ready": False,
            "pid": None,
            "base_url": profile_base_url,
        }
    else:
        try:
            live = status_for_profile(name, env, allow_port_fallback=endpoint_conflict is None)
        except Exception as exc:  # noqa: BLE001
            live = {
                "running": False,
                "ready": False,
                "pid": None,
                "base_url": profile_base_url,
                "error": str(exc),
            }
            errors.append(f"status probe failed: {exc}")

    return {
        "profile": name,
        "display_name": env.get("DISPLAY_NAME", name),
        "runtime": runtime,
        "runtime_label": spec["label"],
        "runtime_tags": runtime_tags(env),
        "launch_mode": spec["launch_mode"],
        "errors": errors,
        "warnings": warnings,
        "running": live.get("running", False),
        "ready": live.get("ready", False),
        "pid": live.get("pid"),
        "base_url": live.get("base_url", profile_base_url),
    }


def doctor_report() -> DoctorReportPayload:
    profiles = load_profiles()
    conflicts = profile_endpoint_conflicts(profiles)
    diagnostics = [
        diagnose_profile(name, env, endpoint_conflict=conflicts.get(name))
        for name, env in sorted(profiles.items())
    ]
    report = {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "doctor_contract_version": DOCTOR_CONTRACT_VERSION,
        "tool_version": tool_version(),
        "generated_at": utc_now().isoformat().replace("+00:00", "Z"),
        "controller": controller_status(),
        "launch_agent": launch_agent_status(),
        "integrations": integration_status(),
        "profiles_dir": str(PROFILE_DIR),
        "controller_root": str(BASE),
        "profiles": diagnostics,
    }
    findings = doctor_findings(report)
    report["healthy"] = not findings
    report["findings"] = findings
    report["next_steps"] = doctor_next_steps(findings)
    return report


def print_doctor(report: DoctorReportPayload) -> None:
    controller = report["controller"]
    launch_agent = report["launch_agent"]
    print("component | status | details")
    print("--- | --- | ---")
    print(
        f"controller | {'ok' if controller['reachable'] else 'warn'} | "
        f"{controller['url']} • profiles={controller['profiles']} • integrations={controller['integrations']}"
    )
    print(
        f"launch-agent | {'ok' if launch_agent['installed'] else 'warn'} | "
        f"installed={launch_agent['installed']} running={launch_agent['running']} • {launch_agent['plist_path']}"
    )
    print(f"profiles-dir | ok | {report['profiles_dir']}")
    for item in report["profiles"]:
        if item["errors"]:
            state = "error"
        elif item["warnings"]:
            state = "warn"
        else:
            state = "ok"
        details = [
            f"{item['display_name']} ({item['runtime_label']})",
            f"launch={item['launch_mode']}",
            f"tags={','.join(item['runtime_tags']) or '-'}",
            f"running={item['running']}",
            f"ready={item['ready']}",
            f"pid={item['pid'] or '-'}",
            item["base_url"] or "base_url=n/a",
        ]
        if item["errors"]:
            details.append("errors=" + "; ".join(item["errors"]))
        if item["warnings"]:
            details.append("warnings=" + "; ".join(item["warnings"]))
        print(f"profile:{item['profile']} | {state} | {' • '.join(details)}")
    findings = report.get("findings", [])
    print(f"doctor | {'ok' if not findings else 'warn'} | findings={len(findings)} contract={DOCTOR_CONTRACT_VERSION}")
    for step in report.get("next_steps", []):
        print(f"next | info | {step}")


def print_doctor_health(payload: dict[str, object]) -> None:
    print("component | status | details")
    print("--- | --- | ---")
    print(
        "doctor | "
        f"{'ok' if payload['healthy'] else 'warn'} | "
        f"findings={payload['finding_count']} auto_fixable={payload['auto_fixable_count']}"
    )
    print(f"controller | {'ok' if payload['controller_reachable'] else 'warn'} | reachable={payload['controller_reachable']}")
    print(
        "launch-agent | "
        f"{'ok' if payload['launch_agent_installed'] and payload['launch_agent_running'] else 'warn'} | "
        f"installed={payload['launch_agent_installed']} running={payload['launch_agent_running']}"
    )


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
            if self.path.startswith("/api/") and not self._check_auth():
                return
            if self.path in {"/", "/index.html"}:
                self._send_html(HTML_PAGE)
                return
            if self.path == "/api/status":
                payload = status_payload()
                write_status_cache(payload)
                self._send_json(payload)
                return
            if self.path == "/api/doctor":
                self._send_json(doctor_report())
                return
            if self.path == "/api/benchmark/status":
                self._send_json(benchmark_status())
                return
            if self.path == "/api/integrations":
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
            payload = self._read_json()
            if self.path == "/api/start":
                start_profile(self._required_string(payload, "profile"))
            elif self.path == "/api/stop":
                stop_profile(self._required_string(payload, "profile"))
            elif self.path == "/api/restart":
                restart_profile(self._required_string(payload, "profile"))
            elif self.path == "/api/switch":
                switch_profile(self._required_string(payload, "profile"))
            elif self.path == "/api/stop-all":
                stop_all()
            elif self.path == "/api/integrations/run":
                run_integration_action(
                    self._required_string(payload, "integration"),
                    payload.get("action", "sync"),
                )
            elif self.path == "/api/benchmark/start":
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



def resolve_selected(args: argparse.Namespace) -> list[str] | None:
    if not getattr(args, "profiles", None):
        return None
    if args.profiles == ["all"]:
        return sorted(load_profiles())
    return args.profiles



def build_parser() -> argparse.ArgumentParser:
    parser = AgentArgumentParser(description="Control local llama.cpp and MLX profiles", allow_abbrev=False)
    sub = parser.add_subparsers(dest="command", required=True, parser_class=AgentArgumentParser)

    status_cmd = sub.add_parser("status", help="Show status for profiles")
    status_cmd.add_argument("profiles", nargs="*", default=[])
    status_cmd.add_argument("--json", action="store_true")

    list_cmd = sub.add_parser("list", help="List profiles")
    list_cmd.add_argument("--json", action="store_true")

    start_cmd = sub.add_parser("start", help="Start one or more profiles")
    start_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")
    start_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    start_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    stop_cmd = sub.add_parser("stop", help="Stop one or more profiles")
    stop_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")
    stop_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    stop_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    restart_cmd = sub.add_parser("restart", help="Restart one or more profiles")
    restart_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")
    restart_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    restart_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    switch_cmd = sub.add_parser("switch", help="Stop other running profiles and start the selected one")
    switch_cmd.add_argument("profile", help="Profile name")
    switch_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    switch_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    bench_cmd = sub.add_parser("benchmark", help="Run the benchmark harness")
    bench_cmd.add_argument("profiles", nargs="*", default=["all"], help="Profile names or 'all'")
    bench_cmd.add_argument("--suite", choices=["quick", "local", "context", "coding"], default="quick")
    bench_cmd.add_argument("--allow-concurrent", action="store_true")
    bench_cmd.add_argument("--keep-running", action="store_true")
    bench_cmd.add_argument("--background", action="store_true")

    capabilities_cmd = sub.add_parser("capabilities", help="Describe the machine-readable CLI contract")
    capabilities_cmd.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    robot_docs_cmd = sub.add_parser("robot-docs", help="Print agent-facing CLI usage docs")
    robot_docs_cmd.add_argument("topic", nargs="?", default="guide", choices=["guide"])

    triage_cmd = sub.add_parser("triage", help="Print one-call agent triage")
    triage_cmd.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    doctor_cmd = sub.add_parser("doctor", help="Validate profiles, controller, and launch agent")
    doctor_cmd.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    doctor_cmd.add_argument("--fix", action="store_true", help="Apply safe, reversible repairs")
    doctor_cmd.add_argument("--dry-run", action="store_true", help="Show the repair plan without mutating state")
    doctor_cmd.add_argument("--run-id", help="Override the doctor run id for artifacts")
    doctor_sub = doctor_cmd.add_subparsers(dest="doctor_command")
    doctor_diagnose = doctor_sub.add_parser("diagnose", help="Run diagnostics (default)")
    doctor_diagnose.add_argument("--json", action="store_true")
    doctor_diagnose.add_argument("--fix", action="store_true")
    doctor_diagnose.add_argument("--dry-run", action="store_true")
    doctor_diagnose.add_argument("--run-id")
    doctor_health = doctor_sub.add_parser("health", help="Print a compact health summary")
    doctor_health.add_argument("--json", action="store_true")
    doctor_capabilities = doctor_sub.add_parser("capabilities", help="Describe doctor capabilities")
    doctor_capabilities.add_argument("--json", action="store_true")
    doctor_robot_docs_cmd = doctor_sub.add_parser("robot-docs", help="Print agent-facing doctor usage docs")
    doctor_robot_docs_cmd.add_argument("topic", nargs="?", default="guide", choices=["guide"])
    doctor_explain = doctor_sub.add_parser("explain", help="Explain a current finding")
    doctor_explain.add_argument("finding_id")
    doctor_explain.add_argument("--json", action="store_true")
    doctor_undo_cmd = doctor_sub.add_parser("undo", help="Undo a recorded doctor fix run")
    doctor_undo_cmd.add_argument("run_id")
    doctor_undo_cmd.add_argument("--json", action="store_true")
    doctor_undo_cmd.add_argument("--no-strict", action="store_true", help="Continue past non-critical undo refusals")

    sub.add_parser("integrations", help="List optional backend integrations")
    integration_cmd = sub.add_parser("run-integration", help="Run an action on an optional integration")
    integration_cmd.add_argument("integration", help="Integration id")
    integration_cmd.add_argument("--action", default="sync", help="Integration action to run")

    stop_all_cmd = sub.add_parser("stop-all", help="Stop every managed model process")
    stop_all_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    stop_all_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    web_cmd = sub.add_parser("serve-web", help="Serve the local model dashboard")
    web_cmd.add_argument("--host", default=None)
    web_cmd.add_argument("--unsafe-bind", metavar="HOST", help="Bind a non-loopback host; requires an auth token")
    web_cmd.add_argument("--port", type=int, default=DEFAULT_WEB_PORT)
    web_cmd.add_argument("--auth-token")
    web_cmd.add_argument("--auth-token-file")

    return parser



def handle_doctor(args: argparse.Namespace) -> int:
    doctor_command = args.doctor_command or "diagnose"
    as_json = bool(getattr(args, "json", False))
    if doctor_command == "capabilities":
        payload = doctor_capabilities()
        print(json.dumps(payload, indent=2) if as_json else json.dumps(payload, indent=2))
        return 0
    if doctor_command == "robot-docs":
        print(doctor_robot_docs())
        return 0
    if doctor_command == "health":
        payload = doctor_health_payload()
        write_doctor_run_artifact(payload, run_id=doctor_run_id("health"), command="health")
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            print_doctor_health(payload)
        return 0 if payload["healthy"] else 1
    if doctor_command == "explain":
        payload, code = explain_doctor_finding(args.finding_id)
        if as_json:
            print(json.dumps(payload, indent=2))
        elif code == 0:
            finding = payload["finding"]
            print(f"{finding['id']}: {finding['message']}")
            print(f"evidence: {finding['evidence']}")
            print(f"remediation: {finding['remediation']}")
        else:
            print(f"finding not present: {args.finding_id}", file=sys.stderr)
        return code
    if doctor_command == "undo":
        payload, code = doctor_undo(args.run_id, strict=not args.no_strict)
        if as_json:
            print(json.dumps(payload, indent=2))
        elif payload.get("ok"):
            print(f"undone {args.run_id}: {len(payload.get('undone', []))} actions")
        else:
            print(f"undo failed for {args.run_id}: {payload.get('error')}", file=sys.stderr)
        return code
    if args.fix:
        payload, code = doctor_fix(dry_run=bool(args.dry_run), run_id=args.run_id)
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            mode = "planned" if args.dry_run else "applied"
            print(f"doctor fix {mode}: actions={payload['actions_taken']} run_id={payload['run_id']}")
            for action in payload["actions"]:
                print(f"action | {action['status']} | {action['action']} {action['path']}")
        return code
    report = doctor_report()
    run_id = args.run_id or doctor_run_id("diagnose")
    write_doctor_run_artifact(report, run_id=run_id, command="diagnose")
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        print_doctor(report)
    return 0 if report["healthy"] else 1


def main() -> None:
    parser = build_parser()
    args = parser.parse_args(normalize_cli_argv(sys.argv[1:]))

    if args.command == "capabilities":
        payload = modelctl_capabilities()
        print(json.dumps(payload, indent=2) if args.json else json.dumps(payload, indent=2))
        return

    if args.command == "robot-docs":
        print(modelctl_robot_docs(args.topic))
        return

    if args.command == "triage":
        payload = modelctl_triage_payload()
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print_modelctl_triage(payload)
        return

    if args.command == "list":
        profiles = load_profiles()
        rows = [
            {
                "profile": name,
                "display_name": env["DISPLAY_NAME"],
                "runtime": env.get("RUNTIME", "llama.cpp"),
                "request_model": env["REQUEST_MODEL"],
                "base_url": base_url(env),
            }
            for name, env in sorted(profiles.items())
        ]
        if args.json:
            print(json.dumps({"profiles": rows}, indent=2))
        else:
            print("profile | runtime | displayName | request_model | base_url")
            print("--- | --- | --- | --- | ---")
            for row in rows:
                print(
                    " | ".join(
                        [
                            row["profile"],
                            row["runtime"],
                            row["display_name"],
                            row["request_model"],
                            row["base_url"],
                        ]
                    )
                )
        return

    if args.command == "status":
        print_status(resolve_selected(args), as_json=args.json)
        return

    if args.command == "integrations":
        print(json.dumps({"integrations": integration_status()}, indent=2))
        return

    if args.command == "run-integration":
        run_integration_action(args.integration, args.action)
        return

    if args.command == "stop-all":
        code = handle_mutating_command(args)
        if code:
            raise SystemExit(code)
        return

    if args.command == "serve-web":
        host = args.unsafe_bind or args.host or DEFAULT_WEB_HOST
        auth_token = resolve_auth_token(args.auth_token, args.auth_token_file)
        serve_web(host, args.port, unsafe_bind=bool(args.unsafe_bind), auth_token=auth_token)
        return

    if args.command == "doctor":
        code = handle_doctor(args)
        if code:
            raise SystemExit(code)
        return

    if args.command == "switch":
        code = handle_mutating_command(args)
        if code:
            raise SystemExit(code)
        return

    if args.command == "benchmark":
        selected = None if args.profiles == ["all"] else args.profiles
        if args.background:
            print(json.dumps(start_benchmark(
                selected,
                suite=args.suite,
                allow_concurrent=args.allow_concurrent,
                keep_running=args.keep_running,
            ), indent=2))
            return
        cmd = [sys.executable, str(BENCH_SCRIPT), "--suite", args.suite, "--profiles", *(selected or ["all"])]
        if args.allow_concurrent:
            cmd.append("--allow-concurrent")
        if args.keep_running:
            cmd.append("--keep-running")
        run(cmd, capture=False)
        return

    code = handle_mutating_command(args)
    if code:
        raise SystemExit(code)


if __name__ == "__main__":
    main()

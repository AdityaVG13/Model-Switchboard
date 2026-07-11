from __future__ import annotations

import os
import pathlib
import shutil
from typing import TypedDict

from contracts import ProfileEnv
from msctl.paths import BASE

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
    "llama-swap": "llama-swap",
    "llamaswap": "llama-swap",
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
    "llama-swap": {
        "label": "llama-swap",
        "tags": ["external", "openai-compatible", "proxy", "on-demand-swap", "anthropic-compatible"],
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


def executable_not_found_message(executable: str, *profile_keys: str) -> str:
    profile_hint = " or ".join(profile_keys)
    if profile_hint:
        profile_hint = f"set {profile_hint} to an absolute executable path, or "
    return (
        f"{executable} not found in controller PATH; "
        f"{profile_hint}reinstall the LaunchAgent so ~/.local/bin and Homebrew paths are available"
    )

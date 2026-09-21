import Foundation

extension RuntimeCatalog {
    static let aliases: [String: String] = [
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
    ]
}

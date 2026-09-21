import Foundation

extension RuntimeCatalog {
    static let specEntries: [(String, String, [String], String)] = [
        ("llama.cpp", "llama.cpp", ["managed", "openai-compatible", "gguf", "metal", "apple-silicon"], "adapter"),
        ("mlx", "MLX", ["managed", "openai-compatible", "mlx", "apple-silicon"], "adapter"),
        ("rvllm-mlx", "rVLLM MLX", ["managed", "openai-compatible", "mlx", "continuous-batching"], "adapter"),
        ("vllm-mlx", "vLLM-MLX", ["managed", "openai-compatible", "mlx", "server"], "adapter"),
        ("ddtree-mlx", "DDTree MLX", ["managed", "openai-compatible", "mlx", "speculative-decoding"], "adapter"),
        ("turboquant", "TurboQuant", ["managed", "openai-compatible", "gguf", "quantized"], "adapter"),
        ("mlx-vlm", "MLX-VLM", ["managed", "openai-compatible", "mlx", "vision"], "adapter"),
        ("mlx-omni-server", "MLX Omni Server", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
        ("mlx-openai-server", "MLX OpenAI Server", ["managed", "openai-compatible", "mlx"], "adapter"),
        ("mlx-llm-server", "MLX-LLM Server", ["managed", "openai-compatible", "mlx"], "adapter"),
        ("mlx-serve", "MLX Serve", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
        ("mlxengine", "MLX Engine", ["managed", "openai-compatible", "mlx", "multimodal"], "adapter"),
        ("ollmlx", "ollmlx", ["external", "openai-compatible", "mlx"], "external"),
        ("omlx", "oMLX", ["managed", "openai-compatible", "mlx", "agent-cache"], "adapter"),
        ("ollama", "Ollama", ["daemon", "openai-compatible", "model-registry"], "adapter"),
        ("vllm", "vLLM", ["managed", "openai-compatible", "server"], "adapter"),
        ("sglang", "SGLang", ["managed", "openai-compatible", "server", "radix-cache"], "adapter"),
        ("tgi", "Text Generation Inference", ["managed", "openai-compatible", "server", "hugging-face"], "adapter"),
        ("llama-cpp-python", "llama-cpp-python", ["managed", "openai-compatible", "gguf", "python"], "adapter"),
        ("llamafile", "llamafile", ["managed", "openai-compatible", "gguf", "single-binary"], "adapter"),
        ("koboldcpp", "KoboldCpp", ["managed", "openai-compatible", "gguf"], "adapter"),
        ("tabbyapi", "TabbyAPI", ["managed", "openai-compatible", "exllamav2"], "adapter"),
        ("exllamav2", "ExLlamaV2", ["managed", "openai-compatible", "exllamav2", "gptq"], "adapter"),
        ("aphrodite", "Aphrodite Engine", ["managed", "openai-compatible", "server"], "adapter"),
        ("lmdeploy", "LMDeploy", ["managed", "openai-compatible", "server", "turbomind"], "adapter"),
        ("mistral.rs", "mistral.rs", ["managed", "openai-compatible", "rust", "gguf"], "adapter"),
        ("mlc-llm", "MLC-LLM", ["managed", "openai-compatible", "mlc", "metal"], "adapter"),
        ("lightllm", "LightLLM", ["managed", "openai-compatible", "server"], "adapter"),
        ("fastchat", "FastChat", ["managed", "openai-compatible", "server"], "adapter"),
        ("openllm", "OpenLLM", ["managed", "openai-compatible", "server", "bentoml"], "adapter"),
        ("nexa", "Nexa SDK", ["managed", "openai-compatible", "multimodal"], "adapter"),
        ("litellm", "LiteLLM", ["external", "openai-compatible", "proxy"], "external"),
        ("llama-swap", "llama-swap", ["external", "openai-compatible", "proxy", "on-demand-swap"], "external"),
        ("transformers", "Transformers", ["managed", "openai-compatible", "python", "hugging-face"], "adapter"),
        ("triton", "Triton Inference Server", ["external", "openai-compatible", "server"], "external"),
        ("tensorrt-llm", "TensorRT-LLM", ["managed", "openai-compatible", "server"], "adapter"),
        ("onnxruntime-genai", "ONNX Runtime GenAI", ["managed", "openai-compatible", "onnx"], "adapter"),
        ("text-generation-webui", "text-generation-webui", ["managed", "openai-compatible", "launcher"], "adapter"),
        ("localai", "LocalAI", ["external", "openai-compatible", "multi-backend"], "external"),
        ("lm-studio", "LM Studio", ["external", "openai-compatible", "desktop"], "external"),
        ("jan", "Jan", ["external", "openai-compatible", "desktop"], "external"),
        ("external", "OpenAI-compatible endpoint", ["external", "openai-compatible"], "external"),
        ("command", "Custom command", ["managed", "custom", "openai-compatible"], "command"),
        ("unknown", "Unknown", ["discovered", "external"], "external"),
    ]

    static let specs: [String: RuntimeSpec] = Dictionary(
        uniqueKeysWithValues: specEntries.map {
            ($0.0, RuntimeSpec(label: $0.1, tags: $0.2, launchMode: $0.3))
        })
}

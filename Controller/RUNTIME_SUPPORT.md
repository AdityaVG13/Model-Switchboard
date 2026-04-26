# Runtime Support

Model Switchboard treats every local model server as one of three launch modes:

- `adapter`: Model Switchboard knows how to build the server command.
- `command`: the profile owns `START_COMMAND`, optional `STOP_COMMAND`, and readiness.
- `external`: another app owns the server; Model Switchboard probes and routes to it.

This keeps the controller open-ended. If a runtime exposes an OpenAI-compatible endpoint, it can be represented without code changes. If a runtime has no native adapter yet, use `SERVER_BIN` plus `SERVER_ARGS_JSON`, or use `START_COMMAND`.

## Runtime Tags

Every status payload includes:

- `runtime`: canonical runtime id.
- `runtime_label`: human-readable runtime name.
- `runtime_tags`: capabilities and backend traits.
- `launch_mode`: `adapter`, `command`, or `external`.

Known runtime ids and aliases:

| Runtime | Aliases | Launch mode | Tags |
| --- | --- | --- | --- |
| `llama.cpp` | `llamacpp`, `llama-cpp` | adapter | `managed`, `openai-compatible`, `gguf`, `metal`, `apple-silicon` |
| `mlx` | `mlx-lm`, `mlx_lm` | adapter | `managed`, `openai-compatible`, `mlx`, `apple-silicon` |
| `rvllm-mlx` | `rvllm`, `rvllm_mlx` | adapter | `managed`, `openai-compatible`, `mlx`, `continuous-batching`, `apple-silicon` |
| `vllm-mlx` | `vllm_mlx` | adapter | `managed`, `openai-compatible`, `mlx`, `server`, `apple-silicon` |
| `ddtree-mlx` | `ddtree`, `ddtree_mlx` | command or generic binary | `managed`, `openai-compatible`, `mlx`, `speculative-decoding`, `apple-silicon` |
| `turboquant` | - | command or generic binary | `managed`, `openai-compatible`, `gguf`, `quantized` |
| `mlx-vlm` | `mlx_vlm` | command or generic binary | `managed`, `openai-compatible`, `mlx`, `vision`, `apple-silicon` |
| `mlx-omni-server` | `mlx-omni` | command, generic binary, or external | `managed`, `openai-compatible`, `anthropic-compatible`, `mlx`, `multimodal`, `apple-silicon` |
| `mlx-openai-server` | `mlx-openai` | command, generic binary, or external | `managed`, `openai-compatible`, `mlx`, `apple-silicon` |
| `mlx-llm-server` | - | command, generic binary, or external | `managed`, `openai-compatible`, `mlx`, `apple-silicon` |
| `mlx-serve` | - | command, generic binary, or external | `managed`, `openai-compatible`, `mlx`, `multimodal`, `apple-silicon` |
| `mlxengine` | `mlx-engine` | command, generic binary, or external | `managed`, `openai-compatible`, `mlx`, `multimodal`, `apple-silicon` |
| `ollmlx` | - | external by default | `external`, `openai-compatible`, `ollama-compatible`, `mlx`, `apple-silicon` |
| `omlx` | - | adapter or command | `managed`, `openai-compatible`, `mlx`, `agent-cache`, `apple-silicon` |
| `ollama` | - | adapter | `daemon`, `openai-compatible`, `model-registry`, `local` |
| `vllm` | - | adapter | `managed`, `openai-compatible`, `server`, `continuous-batching` |
| `sglang` | - | adapter | `managed`, `openai-compatible`, `server`, `radix-cache` |
| `tgi` | `text-generation-inference`, `huggingface-tgi` | adapter | `managed`, `openai-compatible`, `server`, `hugging-face` |
| `llama-cpp-python` | - | adapter | `managed`, `openai-compatible`, `gguf`, `python` |
| `llamafile` | - | generic binary | `managed`, `openai-compatible`, `gguf`, `single-binary` |
| `koboldcpp` | `kobold-cpp` | generic binary | `managed`, `openai-compatible`, `gguf` |
| `tabbyapi` | - | generic binary | `managed`, `openai-compatible`, `exllamav2`, `gptq` |
| `exllamav2` | `exllama`, `exllama-v2` | generic binary | `managed`, `openai-compatible`, `exllamav2`, `gptq`, `exl2` |
| `aphrodite` | `aphrodite-engine` | generic binary | `managed`, `openai-compatible`, `server`, `vllm-family` |
| `lmdeploy` | - | generic binary | `managed`, `openai-compatible`, `server`, `turbomind` |
| `mistral.rs` | `mistral-rs`, `mistralrs` | command, generic binary, or external | `managed`, `openai-compatible`, `rust`, `gguf`, `multimodal`, `continuous-batching` |
| `mlc-llm` | `mlc` | command, generic binary, or external | `managed`, `openai-compatible`, `mlc`, `metal`, `cross-platform` |
| `lightllm` | - | command, generic binary, or external | `managed`, `openai-compatible`, `server`, `high-throughput` |
| `fastchat` | `fast-chat` | command, generic binary, or external | `managed`, `openai-compatible`, `server`, `vicuna` |
| `openllm` | `bentoml-openllm` | command, generic binary, or external | `managed`, `openai-compatible`, `server`, `bentoml` |
| `nexa` | `nexa-sdk`, `nexaai` | command, generic binary, or external | `managed`, `openai-compatible`, `multimodal`, `cross-platform` |
| `litellm` | `litellm-proxy` | external by default | `external`, `openai-compatible`, `proxy` |
| `transformers` | `hf-transformers`, `huggingface-transformers` | command or generic binary | `managed`, `openai-compatible`, `python`, `hugging-face` |
| `triton` | `nvidia-triton` | external by default | `external`, `openai-compatible`, `server`, `nvidia` |
| `tensorrt-llm` | `tensorrtllm` | command, generic binary, or external | `managed`, `openai-compatible`, `server`, `nvidia` |
| `onnxruntime-genai` | `ort-genai` | command, generic binary, or external | `managed`, `openai-compatible`, `onnx`, `cross-platform` |
| `text-generation-webui` | `oobabooga` | generic binary | `managed`, `openai-compatible`, `launcher`, `extensions` |
| `lm-studio` | `lmstudio` | external by default | `external`, `openai-compatible`, `desktop` |
| `localai` | - | external by default | `external`, `openai-compatible`, `multi-backend` |
| `jan` | - | external by default | `external`, `openai-compatible`, `desktop` |
| `external` | `openai`, `openai-compatible`, `endpoint` | external | `external`, `openai-compatible` |
| `command` | `custom` | command | `managed`, `custom`, `openai-compatible` |

For any named runtime above, you can still set `LAUNCH_MODE=external` with a `BASE_URL` when the server is started outside Model Switchboard. Without `LAUNCH_MODE=external`, use `START_COMMAND` or `SERVER_BIN` plus `SERVER_ARGS_JSON` for runtimes that do not have a native command builder yet.

Profiles can add their own tags:

```env
RUNTIME_TAGS="coding long-context q8"
```

## Universal Profile Patterns

### External Endpoint

Use this for LM Studio, Jan, LocalAI, manually started llama.cpp, or any already-running OpenAI-compatible server.

```env
DISPLAY_NAME="LM Studio Qwen"
RUNTIME=lm-studio
BASE_URL=http://127.0.0.1:1234/v1
REQUEST_MODEL=qwen-local
SERVER_MODEL_ID=qwen-local
HEALTHCHECK_MODE=openai-models
```

### Managed Command

Use this for any launcher that needs a shell command.

```env
DISPLAY_NAME="My Runtime"
RUNTIME=command
START_COMMAND='cd /opt/my-runtime && ./serve --host 127.0.0.1 --port 8123'
STOP_COMMAND='curl -fsS -X POST http://127.0.0.1:8123/shutdown || true'
WORKING_DIRECTORY=/opt/my-runtime
BASE_URL=http://127.0.0.1:8123/v1
REQUEST_MODEL=my-local-model
SERVER_MODEL_ID=my-local-model
```

`STOP_COMMAND_ONLY=1` tells the controller not to signal the stored PID after `STOP_COMMAND`.

### Generic Binary

Use this when a runtime has an executable but no first-class adapter yet. Arguments are a JSON array so profiles do not need unsafe shell splitting.

```json
{
  "DISPLAY_NAME": "TabbyAPI GPTQ",
  "RUNTIME": "tabbyapi",
  "SERVER_BIN": "/opt/tabbyAPI/start-server",
  "SERVER_ARGS_JSON": ["--host", "127.0.0.1", "--port", "5000", "--model", "/models/model-gptq"],
  "HOST": "127.0.0.1",
  "PORT": "5000",
  "REQUEST_MODEL": "tabby-local",
  "SERVER_MODEL_ID": "tabby-local"
}
```

### vLLM

```json
{
  "DISPLAY_NAME": "Qwen vLLM",
  "RUNTIME": "vllm",
  "MODEL_REPO": "Qwen/Qwen3.5-32B-Instruct",
  "HOST": "127.0.0.1",
  "PORT": "8000",
  "REQUEST_MODEL": "Qwen/Qwen3.5-32B-Instruct",
  "SERVER_MODEL_ID": "Qwen/Qwen3.5-32B-Instruct",
  "SERVER_ARGS_JSON": ["--dtype", "auto", "--max-model-len", "32768"]
}
```

### Ollama

```env
DISPLAY_NAME="Ollama Qwen"
RUNTIME=ollama
HOST=127.0.0.1
PORT=11434
BASE_URL=http://127.0.0.1:11434/v1
REQUEST_MODEL=qwen3.5:32b
SERVER_MODEL_ID=qwen3.5:32b
```

### llama-cpp-python

```env
DISPLAY_NAME="llama-cpp-python GGUF"
RUNTIME=llama-cpp-python
MODEL_PATH=/models/model.gguf
HOST=127.0.0.1
PORT=8080
REQUEST_MODEL=local-gguf
SERVER_MODEL_ID=local-gguf
SERVER_ARGS_JSON='["--n_gpu_layers", "99", "--n_ctx", "32768"]'
```

## Health Checks

Default readiness is `openai-models`, which probes `/v1/models` and verifies `SERVER_MODEL_ID` or `REQUEST_MODEL`.

Other modes:

- `http-200`: any successful HTTP response means ready.
- `disabled`: process state only. Use only when the runtime has no reliable health endpoint.

## Lifecycle Rules

- Managed launches are detached into their own process group.
- Stop first runs `STOP_COMMAND`, when present.
- Stop then signals the process group and falls back to the stored PID.
- `stop-all` stops active benchmark jobs and every profile, then runs the legacy process sweeper.
- Port fallback only claims a listener when the health check matches or the process command contains profile markers.

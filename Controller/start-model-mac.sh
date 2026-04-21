#!/usr/bin/env bash
# Local model launcher for profile-backed runtimes on macOS.
set -euo pipefail

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE_DIR="$WORK_DIR/model-profiles"
MODEL_PROFILE="${MODEL_PROFILE:-}"
PROFILE_PATH="${MODEL_PROFILE_PATH:-}"
AGL_VENV="$WORK_DIR/.venv-agentlightning"
AGL_PYTHON="$AGL_VENV/bin/python"
AGL_UV_CACHE="${UV_CACHE_DIR:-/tmp/autoresearch-uv-cache}"
AGL_PYTHON_VERSION="${AGL_PYTHON_VERSION:-3.12}"

log() { printf '[INFO] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
die() { printf '[ERR] %s\n' "$*"; exit 1; }

expand_user_path() {
    local path="$1"
    case "$path" in
        "~")
            printf '%s\n' "$HOME"
            ;;
        "~/"*)
            printf '%s/%s\n' "$HOME" "${path#~/}"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

detect_model_root() {
    local candidate
    for candidate in "${MODEL_ROOT:-}" "${MODEL_ROOT_HINT:-}"; do
        if [ -n "$candidate" ]; then
            expand_user_path "$candidate"
            return 0
        fi
    done

    candidate="$HOME/AI/models"
    if [ -d "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    candidate="$WORK_DIR/../models"
    if [ -d "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    return 1
}

if [ -z "$PROFILE_PATH" ] && [ -z "$MODEL_PROFILE" ]; then
    die "Set MODEL_PROFILE or MODEL_PROFILE_PATH before launching a profile"
fi

if [ -z "$PROFILE_PATH" ]; then
    if [ -f "$PROFILE_DIR/${MODEL_PROFILE}.env" ]; then
        PROFILE_PATH="$PROFILE_DIR/${MODEL_PROFILE}.env"
    elif [ -f "$PROFILE_DIR/${MODEL_PROFILE}.json" ]; then
        PROFILE_PATH="$PROFILE_DIR/${MODEL_PROFILE}.json"
    else
        die "Unknown MODEL_PROFILE=$MODEL_PROFILE (expected $PROFILE_DIR/${MODEL_PROFILE}.env or .json)"
    fi
fi

if [ -z "$MODEL_PROFILE" ]; then
    MODEL_PROFILE="$(basename "$PROFILE_PATH")"
    MODEL_PROFILE="${MODEL_PROFILE%.*}"
fi

load_json_profile() {
    local path="$1"
    eval "$(
        python3 - "$path" <<'PY'
import json
import pathlib
import shlex
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
if not isinstance(data, dict):
    raise SystemExit(f"Profile JSON must be an object: {path}")
for key, value in data.items():
    if value is None:
        rendered = ""
    elif isinstance(value, bool):
        rendered = "1" if value else "0"
    else:
        rendered = str(value)
    print(f"export {key}={shlex.quote(rendered)}")
PY
    )"
}

if [[ "$PROFILE_PATH" == *.json ]]; then
    load_json_profile "$PROFILE_PATH"
else
    # shellcheck disable=SC1090
    source "$PROFILE_PATH"
fi

calc_threads() {
    local cpu_count
    cpu_count="$(sysctl -n hw.logicalcpu 2>/dev/null || echo 8)"
    if [ "$cpu_count" -gt 10 ] 2>/dev/null; then
        echo 10
    else
        echo "$cpu_count"
    fi
}

resolve_llama_server() {
    local candidate
    for candidate in \
        "${SERVER_BIN:-}" \
        "${LLAMA_SERVER_BIN:-}" \
        "${LLAMA_CPP_SERVER_BIN:-}"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v llama-server >/dev/null 2>&1; then
        command -v llama-server
        return 0
    fi
    if command -v llama.cpp-server >/dev/null 2>&1; then
        command -v llama.cpp-server
        return 0
    fi
    return 1
}

resolve_mlx_server() {
    local candidate
    for candidate in \
        "${SERVER_BIN:-}" \
        "${MLX_SERVER_BIN:-}" \
        "${MLX_LM_SERVER_BIN:-}"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    if command -v mlx_lm.server >/dev/null 2>&1; then
        command -v mlx_lm.server
        return 0
    fi
    return 1
}

resolve_rvllm_mlx_server() {
    local candidate
    for candidate in \
        "${SERVER_BIN:-}" \
        "${RVLLM_MLX_SERVER_BIN:-}"
    do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

spawn_detached() {
    local log_path="$1"
    local pid_path="$2"
    shift 2
    DETACHED_LOG_PATH="$log_path" DETACHED_PID_PATH="$pid_path" python3 - "$@" <<'PY'
import os
import pathlib
import subprocess
import sys

log_path = os.environ["DETACHED_LOG_PATH"]
pid_path = os.environ["DETACHED_PID_PATH"]
env = os.environ.copy()

with open(log_path, "ab", buffering=0) as log_fp, open(os.devnull, "rb") as stdin_fp:
    proc = subprocess.Popen(
        sys.argv[1:],
        stdin=stdin_fp,
        stdout=log_fp,
        stderr=log_fp,
        start_new_session=True,
        close_fds=True,
        env=env,
    )
pathlib.Path(pid_path).write_text(f"{proc.pid}\n")
print(proc.pid)
PY
}

wait_for_models_endpoint() {
    local models_url="$1"
    local expected_id="$2"
    local retries="${3:-60}"
    local response
    for i in $(seq 1 "$retries"); do
        if response="$(curl -fsS "$models_url" 2>/dev/null)"; then
            if [ -n "$expected_id" ] && ! RESPONSE_JSON="$response" python3 - "$expected_id" <<'PY'
import json
import os
import sys

expected = sys.argv[1]
raw = os.environ.get("RESPONSE_JSON", "")

try:
    obj = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(1)

ids = {item.get("id") for item in obj.get("data", [])}
raise SystemExit(0 if expected in ids else 1)
PY
            then
                sleep 2
                continue
            fi
            return 0
        fi
        sleep 2
    done
    return 1
}

wait_for_http_200() {
    local url="$1"
    local retries="${2:-60}"
    for i in $(seq 1 "$retries"); do
        if curl -fsS "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    return 1
}

wait_for_profile_ready() {
    local mode="$1"
    local url="$2"
    local expected_id="$3"
    local retries="${4:-60}"
    case "$mode" in
        disabled)
            return 0
            ;;
        http-200)
            wait_for_http_200 "$url" "$retries"
            ;;
        openai-models|*)
            wait_for_models_endpoint "$url" "$expected_id" "$retries"
            ;;
    esac
}

install_agentlightning() {
    if [ -x "$AGL_PYTHON" ] && "$AGL_PYTHON" -c "import agentlightning" >/dev/null 2>&1; then
        log "Agent Lightning already installed"
        return 0
    fi

    mkdir -p "$AGL_UV_CACHE"
    if command -v uv >/dev/null 2>&1; then
        if [ ! -x "$AGL_PYTHON" ]; then
            UV_CACHE_DIR="$AGL_UV_CACHE" uv venv --python "$AGL_PYTHON_VERSION" "$AGL_VENV" >/dev/null
        fi
        if UV_CACHE_DIR="$AGL_UV_CACHE" uv pip install --python "$AGL_PYTHON" agentlightning >/dev/null; then
            log "Installed Agent Lightning in $AGL_VENV"
            return 0
        fi
    fi
    warn "Agent Lightning install skipped"
}

THREADS="${THREADS:-$(calc_threads)}"
THREADS_BATCH="${THREADS_BATCH:-$THREADS}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8080}"
BASE_URL="${BASE_URL:-http://${HOST}:${PORT}/v1}"
BASE_URL="${BASE_URL%/}"
MODELS_URL="${MODEL_LIST_URL:-$BASE_URL/models}"
HEALTHCHECK_MODE="${HEALTHCHECK_MODE:-openai-models}"
HEALTHCHECK_URL="${HEALTHCHECK_URL:-}"
if [ -z "$HEALTHCHECK_URL" ]; then
    if [ "$HEALTHCHECK_MODE" = "openai-models" ]; then
        HEALTHCHECK_URL="$MODELS_URL"
    else
        HEALTHCHECK_URL="$BASE_URL"
    fi
fi
RUN_DIR="$WORK_DIR/run"
mkdir -p "$RUN_DIR"
LOG_PATH="/tmp/${MODEL_ALIAS:-$MODEL_PROFILE}.log"
PID_PATH="$RUN_DIR/${MODEL_PROFILE}.pid"

if [ "$RUNTIME" = "llama.cpp" ]; then
    MODEL_PATH="${MODEL_PATH:-}"
    if [ -z "$MODEL_PATH" ]; then
        [ -n "${MODEL_FILE:-}" ] || die "MODEL_PATH or MODEL_FILE is required for $MODEL_PROFILE"
        MODEL_ROOT_RESOLVED="$(detect_model_root || true)"
        [ -n "$MODEL_ROOT_RESOLVED" ] || die "MODEL_FILE requires MODEL_ROOT, MODEL_ROOT_HINT, ~/AI/models, or ../models for $MODEL_PROFILE"
        MODEL_PATH="$MODEL_ROOT_RESOLVED/$MODEL_FILE"
    fi
    if [ ! -f "$MODEL_PATH" ]; then
        die "Model file not found: $MODEL_PATH"
    fi
    LLAMA_SERVER="$(resolve_llama_server)" || die 'llama-server not found; set SERVER_BIN or LLAMA_SERVER_BIN in the profile, or add llama-server to PATH'

    if wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "$SERVER_MODEL_ID" 1; then
        log "Model server already responding on $HEALTHCHECK_URL"
    else
        log "Starting llama.cpp profile $MODEL_PROFILE"
        cmd=(
            "$LLAMA_SERVER"
            --model "$MODEL_PATH"
            --alias "$MODEL_ALIAS"
            --host "$HOST"
            --port "$PORT"
            --ctx-size "$CONTEXT_SIZE"
            --parallel "$N_PARALLEL"
            --threads "$THREADS"
            --threads-batch "$THREADS_BATCH"
            --n-gpu-layers "$GPU_LAYERS"
            --batch-size "$BATCH_SIZE"
            --ubatch-size "$UBATCH_SIZE"
            --cache-type-k "$CACHE_TYPE_K"
            --cache-type-v "$CACHE_TYPE_V"
            --flash-attn "$FLASH_ATTN"
            --reasoning "$REASONING"
            --fit "$FIT"
            --fit-target "$FIT_TARGET"
            --fit-ctx "$FIT_CTX"
            --metrics
            --cont-batching
        )
        if [ -n "${REASONING_FORMAT:-}" ]; then
            cmd+=(--reasoning-format "$REASONING_FORMAT")
        fi
        if [ -n "${REASONING_BUDGET:-}" ]; then
            cmd+=(--reasoning-budget "$REASONING_BUDGET")
        fi
        if [ -n "${CHAT_TEMPLATE_KWARGS:-}" ]; then
            cmd+=(--chat-template-kwargs "$CHAT_TEMPLATE_KWARGS")
        fi
        if [ -n "${CACHE_RAM:-}" ]; then
            cmd+=(--cache-ram "$CACHE_RAM")
        fi
        if [ "${USE_MMAP:-1}" = "1" ]; then
            cmd+=(--mmap)
        else
            cmd+=(--no-mmap)
        fi
        if [ "${USE_MLOCK:-0}" = "1" ]; then
            cmd+=(--mlock)
        fi
        GGML_METAL_N_CB="${METAL_N_CB:-1}" spawn_detached "$LOG_PATH" "$PID_PATH" "${cmd[@]}" >/dev/null
        if ! wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "$SERVER_MODEL_ID" 90; then
            tail -n 80 "$LOG_PATH" || true
            die "llama.cpp server failed to become ready for $MODEL_PROFILE"
        fi
    fi
elif [ "$RUNTIME" = "mlx" ]; then
    MODEL_SOURCE="${MODEL_DIR:-}"
    if [ -z "$MODEL_SOURCE" ] || [ ! -d "$MODEL_SOURCE" ]; then
        MODEL_SOURCE="${MODEL_REPO:-}"
    fi
    [ -n "$MODEL_SOURCE" ] || die "No MODEL_DIR or MODEL_REPO configured for $MODEL_PROFILE"
    MLX_SERVER="$(resolve_mlx_server)" || die 'mlx_lm.server not found; set SERVER_BIN or MLX_SERVER_BIN in the profile, or add mlx_lm.server to PATH'

    if wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "$SERVER_MODEL_ID" 1; then
        log "MLX server already responding on $HEALTHCHECK_URL"
    else
        log "Starting MLX profile $MODEL_PROFILE"
        cmd=(
            "$MLX_SERVER"
            --model "$MODEL_SOURCE"
            --host "$HOST"
            --port "$PORT"
            --temp "$TEMP"
            --top-p "$TOP_P"
            --max-tokens "$MAX_TOKENS"
            --prompt-cache-size "$PROMPT_CACHE_SIZE"
            --prompt-cache-bytes "$PROMPT_CACHE_BYTES"
            --prompt-concurrency "$PROMPT_CONCURRENCY"
            --decode-concurrency "$DECODE_CONCURRENCY"
            --prefill-step-size "$PREFILL_STEP_SIZE"
            --chat-template-args "$CHAT_TEMPLATE_ARGS"
        )
        spawn_detached "$LOG_PATH" "$PID_PATH" "${cmd[@]}" >/dev/null
        if ! wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "$SERVER_MODEL_ID" 180; then
            tail -n 120 "$LOG_PATH" || true
            die "MLX server failed to become ready for $MODEL_PROFILE"
        fi
    fi
elif [ "$RUNTIME" = "rvllm-mlx" ]; then
    MODEL_SOURCE="${MODEL_DIR:-}"
    [ -n "$MODEL_SOURCE" ] || die "MODEL_DIR is required for rvllm-mlx profiles"
    [ -d "$MODEL_SOURCE" ] || die "MODEL_DIR not found: $MODEL_SOURCE"
    RVLLM_MLX_SERVER="$(resolve_rvllm_mlx_server)" || die 'rvllm-mlx server not found; set SERVER_BIN in the profile'

    if wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "$SERVER_MODEL_ID" 1; then
        log "rvllm-mlx server already responding on $HEALTHCHECK_URL"
    else
        log "Starting rvllm-mlx profile $MODEL_PROFILE"
        cmd=(
            "$RVLLM_MLX_SERVER"
            --model-dir "$MODEL_SOURCE"
            --host "$HOST"
            --port "$PORT"
        )
        spawn_detached "$LOG_PATH" "$PID_PATH" "${cmd[@]}" >/dev/null
        if ! wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "$SERVER_MODEL_ID" 180; then
            tail -n 120 "$LOG_PATH" || true
            die "rvllm-mlx server failed to become ready for $MODEL_PROFILE"
        fi
    fi
elif [ "$RUNTIME" = "custom" ] || [ "$RUNTIME" = "command" ]; then
    START_COMMAND="${START_COMMAND:-}"
    [ -n "$START_COMMAND" ] || die "START_COMMAND is required for custom runtime profiles"

    if wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "${HEALTHCHECK_EXPECT_ID:-${SERVER_MODEL_ID:-}}" 1; then
        log "Custom profile already responding on $HEALTHCHECK_URL"
    else
        log "Starting custom profile $MODEL_PROFILE"
        spawn_detached "$LOG_PATH" "$PID_PATH" bash -lc "$START_COMMAND" >/dev/null
        if ! wait_for_profile_ready "$HEALTHCHECK_MODE" "$HEALTHCHECK_URL" "${HEALTHCHECK_EXPECT_ID:-${SERVER_MODEL_ID:-}}" 120; then
            tail -n 120 "$LOG_PATH" || true
            die "Custom runtime failed to become ready for $MODEL_PROFILE"
        fi
    fi
else
    die "Unsupported runtime '$RUNTIME' in $PROFILE_PATH"
fi

install_agentlightning || true

printf 'profile=%s\nruntime=%s\nbase_url=http://%s:%s/v1\nrequest_model=%s\nlog=%s\n' \
    "$MODEL_PROFILE" "$RUNTIME" "$HOST" "$PORT" "$REQUEST_MODEL" "$LOG_PATH"
if [ -f "$PID_PATH" ]; then
    printf 'pid=%s\n' "$(cat "$PID_PATH" 2>/dev/null || true)"
fi

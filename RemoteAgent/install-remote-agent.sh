#!/usr/bin/env bash
# Installs the Model Switchboard remote agent on a Linux/Unix host.
#
# Run ON the remote host (DGX, workstation, server):
#   ./install-remote-agent.sh                # loopback bind, port 8877
#   ./install-remote-agent.sh --port 9000
#   ./install-remote-agent.sh --uninstall
#
# The agent binds 127.0.0.1 only; pair it with the app's SSH tunnel so no
# ports are exposed. For direct LAN mode, run the agent manually with
# --unsafe-bind and --auth-token-file (see RemoteAgent/README.md).
set -euo pipefail

PORT=8877
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            PORT="$2"; shift 2 ;;
        --uninstall)
            UNINSTALL=1; shift ;;
        -h|--help)
            grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

log() { printf '[INFO] %s\n' "$*"; }
die() { printf '[ERR] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_SOURCE="$SCRIPT_DIR/model_switchboard_agent.py"
INSTALL_ROOT="$HOME/.local/share/model-switchboard-agent"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/model-switchboard-agent"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT_PATH="$UNIT_DIR/model-switchboard-agent.service"

has_systemd() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

if [ "$UNINSTALL" = "1" ]; then
    if has_systemd; then
        systemctl --user disable --now model-switchboard-agent.service 2>/dev/null || true
        rm -f "$UNIT_PATH"
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    rm -f "$BIN_PATH"
    log "Removed the agent service and launcher."
    log "Profiles and state kept at $INSTALL_ROOT (delete manually if unwanted)."
    exit 0
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required"
python3 - <<'EOF' || die "Python 3.10+ is required"
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
EOF
[ -f "$AGENT_SOURCE" ] || die "agent source not found next to installer: $AGENT_SOURCE"

mkdir -p "$INSTALL_ROOT/model-profiles" "$INSTALL_ROOT/run" "$BIN_DIR"
install -m 0755 "$AGENT_SOURCE" "$INSTALL_ROOT/model_switchboard_agent.py"

cat > "$BIN_PATH" <<EOF
#!/usr/bin/env bash
exec python3 "$INSTALL_ROOT/model_switchboard_agent.py" --root "$INSTALL_ROOT" "\$@"
EOF
chmod 0755 "$BIN_PATH"

# One sample per launch style. Rename any of them to <name>.env to activate;
# one file per model server. Full format reference: SETUP.md in the repo.
if [ ! -f "$INSTALL_ROOT/model-profiles/example-vllm.env.example" ]; then
    cat > "$INSTALL_ROOT/model-profiles/example-vllm.env.example" <<'EOF'
DISPLAY_NAME="Llama 3.1 8B (vLLM)"
RUNTIME=vllm
REQUEST_MODEL=meta-llama/Llama-3.1-8B-Instruct
PORT=8001
# EXTRA_ARGS="--max-model-len 8192 --gpu-memory-utilization 0.90"
EOF
fi
if [ ! -f "$INSTALL_ROOT/model-profiles/example-llamacpp.env.example" ]; then
    cat > "$INSTALL_ROOT/model-profiles/example-llamacpp.env.example" <<'EOF'
DISPLAY_NAME="Qwen 2.5 7B (llama.cpp)"
RUNTIME=llama.cpp
REQUEST_MODEL=qwen2.5-7b-instruct
MODEL_FILE=~/models/qwen2.5-7b-instruct-q5_k_m.gguf
PORT=8002
# EXTRA_ARGS="-c 8192 -ngl 99"
EOF
fi
if [ ! -f "$INSTALL_ROOT/model-profiles/example-custom.env.example" ]; then
    cat > "$INSTALL_ROOT/model-profiles/example-custom.env.example" <<'EOF'
# Any runtime works: give the agent a launch command and a health endpoint.
DISPLAY_NAME="My Server (custom)"
RUNTIME=command
REQUEST_MODEL=my-model
PORT=8003
START_COMMAND="my-model-server --port 8003"
# STOP_COMMAND="my-model-server --shutdown"     # optional
# HEALTHCHECK_MODE=http-200                     # if not OpenAI-compatible
EOF
fi

log "Installed agent to $INSTALL_ROOT"
log "Launcher: $BIN_PATH"

"$BIN_PATH" --version >/dev/null || die "agent smoke test failed"

if has_systemd; then
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Model Switchboard remote agent
After=network.target

[Service]
ExecStart=$BIN_PATH serve --port $PORT
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now model-switchboard-agent.service
    log "systemd user service enabled and started (port $PORT)."
    log "Tip: 'loginctl enable-linger $USER' keeps it running after logout."
else
    log "systemd not available; start the agent manually:"
    log "  nohup $BIN_PATH serve --port $PORT >/tmp/model-switchboard-agent.log 2>&1 &"
fi

sleep 1
if command -v curl >/dev/null 2>&1; then
    if curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
        log "Agent is answering on http://127.0.0.1:$PORT"
    else
        log "Agent not answering yet on port $PORT (fine if you skipped the service)."
    fi
fi

log "Next: add profiles to $INSTALL_ROOT/model-profiles, then pair your Mac:"
echo
"$BIN_PATH" --port "$PORT" link

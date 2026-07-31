#!/usr/bin/env bash
# Installs the Model Switchboard remote agent on a Linux/Unix host.
#
# Run ON the remote host (DGX, workstation, server):
#   ./install-remote-agent.sh                # loopback bind, port 8877
#   ./install-remote-agent.sh --port 9000
#   ./install-remote-agent.sh --tailscale    # bind the tailnet address instead
#   ./install-remote-agent.sh --uninstall
#
# Default: the agent binds 127.0.0.1 only; pair it with the app's SSH tunnel
# so no ports are exposed. --tailscale binds the host's Tailscale address so
# the Mac connects directly over the tailnet (no tunnel; token recommended on
# shared tailnets). For plain LAN mode, run the agent manually with
# --unsafe-bind and --auth-token-file (see RemoteAgent/README.md).
set -euo pipefail

PORT=8877
UNINSTALL=0
TAILSCALE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            PORT="$2"; shift 2 ;;
        --tailscale)
            TAILSCALE=1; shift ;;
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

mkdir -p "$INSTALL_ROOT/model-profiles" "$INSTALL_ROOT/run" "$BIN_DIR"

# Agent source, in order: next to this script (repo checkout), already pushed
# to the install root (the Mac app deploys it over SSH), or fetched from the
# repo (curl | bash one-liner with no checkout at all).
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/AdityaVG13/Model-Switchboard/main/RemoteAgent}"
if [ -f "$AGENT_SOURCE" ]; then
    install -m 0755 "$AGENT_SOURCE" "$INSTALL_ROOT/model_switchboard_agent.py"
elif [ -f "$INSTALL_ROOT/model_switchboard_agent.py" ]; then
    chmod 0755 "$INSTALL_ROOT/model_switchboard_agent.py"
    log "Using agent already present at $INSTALL_ROOT"
else
    command -v curl >/dev/null 2>&1 || die "no agent source found and curl is unavailable"
    log "Downloading agent from $REPO_RAW_URL"
    curl -fsSL "$REPO_RAW_URL/model_switchboard_agent.py" -o "$INSTALL_ROOT/model_switchboard_agent.py" \
        || die "could not download the agent"
    chmod 0755 "$INSTALL_ROOT/model_switchboard_agent.py"
fi

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

SERVE_FLAGS="--port $PORT"
if [ "$TAILSCALE" = "1" ]; then
    SERVE_FLAGS="$SERVE_FLAGS --tailscale"
fi

if has_systemd; then
    mkdir -p "$UNIT_DIR"
    cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Model Switchboard remote agent
After=network.target

[Service]
ExecStart=$BIN_PATH serve $SERVE_FLAGS
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now model-switchboard-agent.service
    log "systemd user service enabled and started ($SERVE_FLAGS)."
    log "Tip: 'loginctl enable-linger $USER' keeps it running after logout."
else
    log "systemd not available; start the agent manually:"
    log "  nohup $BIN_PATH serve $SERVE_FLAGS >/tmp/model-switchboard-agent.log 2>&1 &"
fi

sleep 1
if [ "$TAILSCALE" = "0" ] && command -v curl >/dev/null 2>&1; then
    if curl -fsS "http://127.0.0.1:$PORT/api/status" >/dev/null 2>&1; then
        log "Agent is answering on http://127.0.0.1:$PORT"
    else
        log "Agent not answering yet on port $PORT (fine if you skipped the service)."
    fi
fi

log "Next: add profiles to $INSTALL_ROOT/model-profiles, then pair your Mac:"
echo
if [ "$TAILSCALE" = "1" ]; then
    "$BIN_PATH" --port "$PORT" link --tailscale
else
    "$BIN_PATH" --port "$PORT" link
fi

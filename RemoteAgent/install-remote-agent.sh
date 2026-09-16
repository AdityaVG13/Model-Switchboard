#!/usr/bin/env bash
# Installs the Model Switchboard remote agent on a Linux/Unix host.
#
# Run ON the remote host (DGX, workstation, server):
#   ./install-remote-agent.sh                # loopback bind, port 8877
#   ./install-remote-agent.sh --port 9000
#   ./install-remote-agent.sh --tailscale    # bind the tailnet address + require token
#   ./install-remote-agent.sh --tailscale --allow-unauthenticated
#   ./install-remote-agent.sh --profiles-dir ~/models/profiles
#   ./install-remote-agent.sh --uninstall
#
# Default: the agent binds 127.0.0.1 only; pair it with the app's SSH tunnel
# so no ports are exposed. --tailscale binds the host's Tailscale address so
# the Mac connects directly over the tailnet (no tunnel) and generates a
# bearer token unless --allow-unauthenticated is set. For plain LAN mode, run
# the agent manually with --unsafe-bind and --auth-token-file (see README).
set -euo pipefail

PORT=8877
UNINSTALL=0
TAILSCALE=0
ALLOW_UNAUTH=0
PROFILES_DIR_CLI=""
AUTH_TOKEN_FILE="${MODEL_SWITCHBOARD_AUTH_TOKEN_FILE:-$HOME/.config/model-switchboard-agent.token}"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            PORT="$2"; shift 2 ;;
        --tailscale)
            TAILSCALE=1; shift ;;
        --allow-unauthenticated)
            ALLOW_UNAUTH=1; shift ;;
        --auth-token-file)
            AUTH_TOKEN_FILE="$2"; shift 2 ;;
        --profiles-dir)
            PROFILES_DIR_CLI="$2"; shift 2 ;;
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

# `bash -s` (Mac Update / curl|bash) has no script path: $0 is `bash` and
# PWD is usually $HOME. Adjacent copies would install leftover ~/agent_core.py
# over the modules the Mac just pushed.
ran_from_stdin=0
case "$0" in
    bash|-bash|sh|-sh|/bin/bash|/bin/sh) ran_from_stdin=1 ;;
esac
if [ ! -f "$0" ]; then
    ran_from_stdin=1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_SOURCE="$SCRIPT_DIR/model_switchboard_agent.py"
DISCOVERY_SOURCE="$SCRIPT_DIR/discovery.py"
CORE_SOURCE="$SCRIPT_DIR/agent_core.py"
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

mkdir -p "$INSTALL_ROOT/run" "$BIN_DIR"

# Visible default for launch .env/.json files. Agent state stays under
# INSTALL_ROOT; profiles are separate so people (and AI setups) can keep
# model.env next to their models without digging through ~/.local/share.
# Resolve: --profiles-dir → env → existing config.json → ~/model-profiles.
if [ -n "$PROFILES_DIR_CLI" ]; then
    PROFILES_DIR="$PROFILES_DIR_CLI"
elif [ -n "${MODEL_SWITCHBOARD_PROFILES_DIR:-}" ]; then
    PROFILES_DIR="$MODEL_SWITCHBOARD_PROFILES_DIR"
else
    EXISTING_PROFILES_DIR=""
    if [ -f "$INSTALL_ROOT/config.json" ]; then
        EXISTING_PROFILES_DIR="$(python3 - "$INSTALL_ROOT/config.json" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    payload = json.loads(path.read_text(encoding="utf-8"))
except Exception:
    raise SystemExit(0)
if isinstance(payload, dict):
    value = payload.get("profiles_dir")
    if isinstance(value, str) and value.strip():
        print(value.strip())
PY
)"
    fi
    if [ -n "$EXISTING_PROFILES_DIR" ]; then
        PROFILES_DIR="$EXISTING_PROFILES_DIR"
    else
        PROFILES_DIR="$HOME/model-profiles"
    fi
fi
# Expand a leading tilde for convenience; leave other paths as given.
case "$PROFILES_DIR" in
    "~") PROFILES_DIR="$HOME" ;;
    "~/"*) PROFILES_DIR="$HOME/${PROFILES_DIR#~/}" ;;
esac
mkdir -p "$PROFILES_DIR"

# Agent source, in order:
#   1. next to this script (a git checkout of install-remote-agent.sh)
#   2. already pushed to the install root (the Mac app deploys over SSH)
#   3. fetched from the repo (curl | bash with no checkout)
# Piped installs skip (1): $PWD leftovers must not clobber a just-pushed tree.
REPO_RAW_URL="${REPO_RAW_URL:-https://raw.githubusercontent.com/AdityaVG13/Model-Switchboard/main/RemoteAgent}"
install_agent_module() {
    local name="$1"
    local adjacent="$2"
    # SAFETY (cross-process file mutation): never write the live module path
    # in place - a concurrent `model-switchboard-agent` launch could exec a
    # partially-written file. Stage at $name.new, then a single atomic mv.
    if [ "$ran_from_stdin" != 1 ] && [ -f "$adjacent" ]; then
        install -m 0644 "$adjacent" "$INSTALL_ROOT/$name.new"
        mv -f "$INSTALL_ROOT/$name.new" "$INSTALL_ROOT/$name"
    elif [ -f "$INSTALL_ROOT/$name" ]; then
        chmod 0644 "$INSTALL_ROOT/$name" 2>/dev/null || true
        log "Using $name already present at $INSTALL_ROOT"
    else
        command -v curl >/dev/null 2>&1 || die "no agent source found and curl is unavailable"
        log "Downloading $name from $REPO_RAW_URL"
        curl -fsSL "$REPO_RAW_URL/$name" -o "$INSTALL_ROOT/$name.new" \
            || die "could not download $name"
        mv -f "$INSTALL_ROOT/$name.new" "$INSTALL_ROOT/$name"
        chmod 0644 "$INSTALL_ROOT/$name"
    fi
}

install_agent_module "agent_core.py" "$CORE_SOURCE"
install_agent_module "discovery.py" "$DISCOVERY_SOURCE"
# Same atomic-replace contract as install_agent_module (live-path safety).
if [ "$ran_from_stdin" != 1 ] && [ -f "$AGENT_SOURCE" ]; then
    install -m 0755 "$AGENT_SOURCE" "$INSTALL_ROOT/model_switchboard_agent.py.new"
    mv -f "$INSTALL_ROOT/model_switchboard_agent.py.new" "$INSTALL_ROOT/model_switchboard_agent.py"
elif [ -f "$INSTALL_ROOT/model_switchboard_agent.py" ]; then
    chmod 0755 "$INSTALL_ROOT/model_switchboard_agent.py"
    log "Using agent already present at $INSTALL_ROOT"
else
    command -v curl >/dev/null 2>&1 || die "no agent source found and curl is unavailable"
    log "Downloading agent from $REPO_RAW_URL"
    curl -fsSL "$REPO_RAW_URL/model_switchboard_agent.py" -o "$INSTALL_ROOT/model_switchboard_agent.py.new" \
        || die "could not download the agent"
    mv -f "$INSTALL_ROOT/model_switchboard_agent.py.new" "$INSTALL_ROOT/model_switchboard_agent.py"
    chmod 0755 "$INSTALL_ROOT/model_switchboard_agent.py"
fi
[ -f "$INSTALL_ROOT/agent_core.py" ] || die "agent_core.py missing next to the agent"
[ -f "$INSTALL_ROOT/discovery.py" ] || die "discovery.py missing next to the agent"

# Persist the profiles folder so `serve` (systemd) keeps using it without flags.
python3 - "$INSTALL_ROOT" "$PROFILES_DIR" <<'PY'
import fcntl, json, os, sys
from pathlib import Path
root, profiles = Path(sys.argv[1]), Path(sys.argv[2])
root.mkdir(parents=True, exist_ok=True)
path = root / "config.json"
lock_path = root / "config.json.lock"
payload = {}
# Cross-process safe read-modify-write: the running agent and `link` also
# write this file (flock-serialized, atomic replace). Same contract as
# save_agent_config in the agent.
with open(lock_path, "w", encoding="utf-8") as lock_handle:
    fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
    if path.is_file():
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            raise SystemExit(f"refusing to rewrite corrupt config.json: {exc}") from None
    if not isinstance(payload, dict):
        raise SystemExit("refusing to rewrite config.json: root value is not an object")
    payload["profiles_dir"] = str(profiles)
    temporary = root / "config.json.tmp"
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)
    path.chmod(0o600)
PY

cat > "$BIN_PATH" <<EOF
#!/usr/bin/env bash
exec python3 "$INSTALL_ROOT/model_switchboard_agent.py" --root "$INSTALL_ROOT" "\$@"
EOF
chmod 0755 "$BIN_PATH"

# One sample per launch style. Rename any of them to <name>.env to activate;
# one file per model server. Full format reference: SETUP.md in the repo.
if [ ! -f "$PROFILES_DIR/example-vllm.env.example" ]; then
    cat > "$PROFILES_DIR/example-vllm.env.example" <<'EOF'
DISPLAY_NAME="Llama 3.1 8B (vLLM)"
RUNTIME=vllm
REQUEST_MODEL=meta-llama/Llama-3.1-8B-Instruct
PORT=8001
# EXTRA_ARGS="--max-model-len 8192 --gpu-memory-utilization 0.90"
EOF
fi
if [ ! -f "$PROFILES_DIR/example-llamacpp.env.example" ]; then
    cat > "$PROFILES_DIR/example-llamacpp.env.example" <<'EOF'
DISPLAY_NAME="Qwen 2.5 7B (llama.cpp)"
RUNTIME=llama.cpp
REQUEST_MODEL=qwen2.5-7b-instruct
MODEL_FILE=~/models/your-model.gguf
PORT=8002
# EXTRA_ARGS="-c 8192 -ngl 99"
EOF
fi
if [ ! -f "$PROFILES_DIR/example-custom.env.example" ]; then
    cat > "$PROFILES_DIR/example-custom.env.example" <<'EOF'
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
log "Profiles folder: $PROFILES_DIR"
log "Launcher: $BIN_PATH"

"$BIN_PATH" --version >/dev/null || die "agent smoke test failed"

# 401/403 mean the process is up and asking for a token. 000/empty means down.
agent_http_up() {
    local url="$1"
    local code
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 2 "$url" 2>/dev/null || true)"
    case "$code" in
        200|401|403) return 0 ;;
        *) return 1 ;;
    esac
}

wait_for_agent_http() {
    command -v curl >/dev/null 2>&1 || return 0
    local i ts
    for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        if agent_http_up "http://127.0.0.1:$PORT/api/status"; then
            log "Agent is answering on http://127.0.0.1:$PORT"
            return 0
        fi
        if [ "$TAILSCALE" = "1" ]; then
            ts="$(tailscale ip -4 2>/dev/null | head -1 || true)"
            if [ -n "$ts" ] && agent_http_up "http://${ts}:$PORT/api/status"; then
                log "Agent is answering on http://${ts}:$PORT"
                return 0
            fi
        fi
        sleep 0.5
    done
    return 1
}

# User systemd units die on logout/reboot unless lingering is on. Best-effort
# only: do not fail Update if polkit/sudo refuses.
maybe_enable_linger() {
    command -v loginctl >/dev/null 2>&1 || return 0
    if loginctl show-user "$USER" -p Linger 2>/dev/null | grep -qx 'Linger=yes'; then
        return 0
    fi
    if loginctl enable-linger "$USER" >/dev/null 2>&1; then
        log "Enabled lingering for $USER so the agent survives logout/reboot."
        return 0
    fi
    log "Tip: 'loginctl enable-linger $USER' keeps it running after logout."
}

SERVE_FLAGS="--port $PORT"
if [ "$TAILSCALE" = "1" ]; then
    SERVE_FLAGS="$SERVE_FLAGS --tailscale"
    if [ "$ALLOW_UNAUTH" = "1" ]; then
        SERVE_FLAGS="$SERVE_FLAGS --allow-unauthenticated"
        log "Tailscale bind without auth (--allow-unauthenticated)."
    else
        mkdir -p "$(dirname "$AUTH_TOKEN_FILE")"
        if [ ! -s "$AUTH_TOKEN_FILE" ]; then
            if command -v openssl >/dev/null 2>&1; then
                openssl rand -hex 24 > "$AUTH_TOKEN_FILE"
            else
                python3 -c 'import secrets; print(secrets.token_hex(24))' > "$AUTH_TOKEN_FILE"
            fi
            chmod 600 "$AUTH_TOKEN_FILE"
            log "Generated bearer token at $AUTH_TOKEN_FILE"
        else
            log "Using existing bearer token at $AUTH_TOKEN_FILE"
        fi
        SERVE_FLAGS="$SERVE_FLAGS --auth-token-file $AUTH_TOKEN_FILE"
    fi
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
    # enable --now is a no-op restart when already running with a stale
    # ExecStart (token/port/tailscale changes). Always restart after rewrite.
    systemctl --user enable model-switchboard-agent.service
    systemctl --user restart model-switchboard-agent.service
    log "systemd user service enabled and restarted ($SERVE_FLAGS)."
    maybe_enable_linger
    if ! wait_for_agent_http; then
        die "agent service restarted but is not answering on port $PORT"
    fi
else
    log "systemd not available; start the agent manually:"
    log "  nohup $BIN_PATH serve $SERVE_FLAGS >/tmp/model-switchboard-agent.log 2>&1 &"
fi

if [ "$ran_from_stdin" = 1 ]; then
    # Mac Update already has the gateway. Do not rescan $HOME via `link`
    # (that walk is how Update hangs after a successful restart).
    if [ -n "${AUTH_TOKEN_FILE:-}" ] && [ -s "$AUTH_TOKEN_FILE" ]; then
        TOKEN_VALUE="$(cat "$AUTH_TOKEN_FILE")"
        echo "AUTH_TOKEN=$TOKEN_VALUE"
    fi
else
    log "Next: put one .env/.json per model in $PROFILES_DIR (or re-run link to"
    log "point at a folder that already has them), then pair your Mac:"
    echo
    if [ "$TAILSCALE" = "1" ]; then
        if [ "$ALLOW_UNAUTH" = "1" ]; then
            "$BIN_PATH" --port "$PORT" --allow-unauthenticated --yes link --tailscale
        else
            "$BIN_PATH" --port "$PORT" --auth-token-file "$AUTH_TOKEN_FILE" --yes link --tailscale
            echo
            log "Paste this bearer token into the Mac gateway settings (keychain):"
            echo
            TOKEN_VALUE="$(cat "$AUTH_TOKEN_FILE")"
            # Machine-readable line for in-app SSH deploy parsers.
            echo "AUTH_TOKEN=$TOKEN_VALUE"
            echo
            echo "  $TOKEN_VALUE"
            echo
            log "Token file: $AUTH_TOKEN_FILE"
        fi
    else
        "$BIN_PATH" --port "$PORT" --yes link
    fi
fi

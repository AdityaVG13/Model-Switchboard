#!/usr/bin/env bash
# Stop all managed local model server processes for the current user.

set -euo pipefail

MODE="${1:-stop}"
WAIT_SECONDS="${WAIT_SECONDS:-10}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok() {
    printf "${GREEN}[OK]${NC} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*"
}

err() {
    printf "${RED}[ERR]${NC} %s\n" "$*"
}

section() {
    printf "\n${CYAN}%s${NC}\n" "$*"
}

list_model_pids() {
    pgrep -u "$(id -u)" -f '(^|/)(llama-server|llama\.cpp-server|mlx_lm\.server)( |$)' || true
}

pids_csv() {
    printf '%s\n' "$1" | paste -sd, -
}

kill_pids() {
    local signal_arg="$1"
    local pids="$2"
    local pid
    while IFS= read -r pid; do
        [ -n "$pid" ] || continue
        if [ -n "$signal_arg" ]; then
            kill "$signal_arg" "$pid" 2>/dev/null || true
        else
            kill "$pid" 2>/dev/null || true
        fi
    done <<< "$pids"
}

print_status() {
    section "Active model servers"

    local pids
    pids="$(list_model_pids)"

    if [ -z "$pids" ]; then
        ok "No managed local model servers are running for user $(id -un)"
        return 0
    fi

    ps -o pid=,etime=,rss=,command= -p "$(pids_csv "$pids")" | while read -r pid etime rss command; do
        printf 'pid=%s  etime=%s  rss_kb=%s  cmd=%s\n' "$pid" "$etime" "$rss" "$command"
    done

    echo
    lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR==1 || /llama-server|llama\.cpp-server|mlx_lm\.server/'
}

stop_models() {
    local pids
    pids="$(list_model_pids)"

    if [ -z "$pids" ]; then
        ok "No managed local model servers are running"
        return 0
    fi

    section "Stopping model servers"
    ps -o pid=,command= -p "$(pids_csv "$pids")"
    kill_pids "" "$pids"

    local deadline
    deadline=$((SECONDS + WAIT_SECONDS))

    while [ "$SECONDS" -lt "$deadline" ]; do
        pids="$(list_model_pids)"
        if [ -z "$pids" ]; then
            ok "All managed local model servers stopped cleanly"
            find "$(cd "$(dirname "$0")" && pwd)/run" -type f -name '*.pid' -delete 2>/dev/null || true
            return 0
        fi
        sleep 1
    done

    warn "Some model servers did not exit after ${WAIT_SECONDS}s; forcing them down"
    ps -o pid=,command= -p "$(pids_csv "$pids")"
    kill_pids "-9" "$pids"
    sleep 1

    pids="$(list_model_pids)"
    if [ -z "$pids" ]; then
        ok "All lingering managed local model servers were force stopped"
        find "$(cd "$(dirname "$0")" && pwd)/run" -type f -name '*.pid' -delete 2>/dev/null || true
        return 0
    fi

    err "Some managed local model processes are still running"
    ps -o pid=,command= -p "$(pids_csv "$pids")"
    return 1
}

case "$MODE" in
    status)
        print_status
        ;;
    stop)
        print_status
        stop_models
        ;;
    *)
        err "Unknown mode: $MODE"
        echo "Usage: $0 [status|stop]"
        exit 1
        ;;
esac

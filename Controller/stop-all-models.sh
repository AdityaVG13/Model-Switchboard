#!/usr/bin/env bash
# Stop managed local model server processes for the current user.
#
# Default: only PIDs recorded under Controller/run/*.pid (plus the active
# profile marker cleanup). Broad pgrep orphan sweeps require FORCE_ORPHANS=1
# so manually started llama-server / mlx_lm.server processes are left alone.

set -euo pipefail

MODE="${1:-stop}"
WAIT_SECONDS="${WAIT_SECONDS:-10}"
FORCE_ORPHANS="${FORCE_ORPHANS:-0}"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_DIR="${ROOT_DIR}/run"

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

list_pidfile_pids() {
    local pid_file pid
    [ -d "$RUN_DIR" ] || return 0
    for pid_file in "$RUN_DIR"/*.pid; do
        [ -f "$pid_file" ] || continue
        case "$(basename "$pid_file")" in
            benchmark.pid) continue ;;
        esac
        pid="$(tr -d '[:space:]' < "$pid_file" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            printf '%s\n' "$pid"
        fi
    done
}

list_orphan_pids() {
    pgrep -u "$(id -u)" -f '(^|/)(llama-server|llama\.cpp-server|mlx_lm\.server)( |$)' || true
}

list_model_pids() {
    local pids
    pids="$(list_pidfile_pids | sort -u)"
    if [ "$FORCE_ORPHANS" = "1" ]; then
        pids="$(printf '%s\n%s\n' "$pids" "$(list_orphan_pids)" | awk 'NF' | sort -u)"
    fi
    printf '%s\n' "$pids" | awk 'NF'
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
    section "Active managed model servers"

    local pids
    pids="$(list_model_pids)"

    if [ -z "$pids" ]; then
        ok "No managed local model servers are running for user $(id -un)"
        if [ "$FORCE_ORPHANS" != "1" ]; then
            local orphans
            orphans="$(list_orphan_pids)"
            if [ -n "$orphans" ]; then
                warn "Untracked llama-server/mlx_lm.server processes exist; re-run with FORCE_ORPHANS=1 to stop them"
            fi
        fi
        return 0
    fi

    ps -o pid=,etime=,rss=,command= -p "$(pids_csv "$pids")" | while read -r pid etime rss command; do
        printf 'pid=%s  etime=%s  rss_kb=%s  cmd=%s\n' "$pid" "$etime" "$rss" "$command"
    done
}

stop_models() {
    local pids
    pids="$(list_model_pids)"

    if [ -z "$pids" ]; then
        ok "No managed local model servers are running"
        find "$RUN_DIR" -type f -name '*.pid' -delete 2>/dev/null || true
        return 0
    fi

    section "Stopping managed model servers"
    ps -o pid=,command= -p "$(pids_csv "$pids")"
    kill_pids "" "$pids"

    local deadline
    deadline=$((SECONDS + WAIT_SECONDS))

    while [ "$SECONDS" -lt "$deadline" ]; do
        pids="$(list_model_pids)"
        if [ -z "$pids" ]; then
            ok "All managed local model servers stopped cleanly"
            find "$RUN_DIR" -type f -name '*.pid' -delete 2>/dev/null || true
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
        find "$RUN_DIR" -type f -name '*.pid' -delete 2>/dev/null || true
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
        echo "Set FORCE_ORPHANS=1 to also stop untracked llama-server/mlx_lm.server processes."
        exit 1
        ;;
esac

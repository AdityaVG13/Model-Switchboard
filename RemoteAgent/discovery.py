"""Listener and port-claim discovery for the Model Switchboard remote agent."""

from __future__ import annotations

import json
import os
import re
import shlex
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

# Imported from the agent after its Profile / process helpers exist. The agent
# imports this module only once those symbols are defined (see the import site
# in model_switchboard_agent.py), so the cycle is safe at runtime.
from model_switchboard_agent import (
    DEFAULT_PORT,
    InvalidProfileError,
    PROFILE_KEY_RE,
    PROFILE_SCAN_SKIP_DIRS,
    Profile,
    RUNTIME_SPECS,
    SCAN_ROOTS_ENV,
    _WEIGHT_SUFFIXES,
    _looks_like_local_fs_path,
    _urlopen_no_redirect,
    canonical_runtime,
    first_known,
    listener_pid_from_inventory,
    load_agent_config,
    port_is_listening,
    process_command,
    process_is_alive,
    process_rss_mb,
    process_vram_mb,
)

PORT_CLAIM_DIR_RE = re.compile(r"^\d{2,5}$")
PORT_CLAIM_MARKERS = ("flags.env", "launch.sh", "start.sh", "run.sh", "serve.sh", "ctrl.sh")
MODEL_SERVER_COMMAND_MARKERS = (
    "llama-server",
    "llama.cpp",
    "llamacpp",
    "vllm",
    "sglang",
    "text-generation-launcher",
    "text-generation-server",
    "ollama",
    "tabbyapi",
    "aphrodite",
    "tgi-",
    "openai-compatible",
    "mlc_llm",
    "koboldcpp",
    "kobold",
    "exllamav2",
    "exllama",
    "lmdeploy",
    "tensorrt_llm",
    "trtllm",
    "localai",
    "llama-cpp",
    "gguf",
)
# Subprocess / engine workers that match MODEL_SERVER_COMMAND_MARKERS (e.g. the
# substring "vllm") but are not user-facing OpenAI HTTP endpoints. Probing them
# burns the discovery budget on connections that hang until timeout and makes
# /api/status take tens of seconds — longer than the Mac client's request
# timeout, so the panel stuck on DIRECT · ERROR even while the agent was up.
MODEL_SERVER_INTERNAL_COMMAND_MARKERS = (
    "vllm::enginecore",
    "vllm::enginecor",  # ss truncates the process title
    "vllm::workermain",
    "vllm::worker",
    "enginecore_executor",
    "enginecore.executor",
    "ray::",
    "multiprocessing.spawn",
    "multiprocessing.resource_tracker",
)
SKIP_LISTEN_PORTS = frozenset({
    22, 25, 53, 67, 68, 69, 80, 110, 123, 135, 139, 143, 161, 389, 443,
    445, 465, 587, 631, 636, 993, 995, 2375, 2376, 3306, 3389, 5432, 5900,
    6379, 6443, 8088, 8443, 9100, 10250, 27017,
})
DISCOVERY_PROBE_BUDGET = 24
DISCOVERY_PROBE_TIMEOUT = 0.6
LISTENING_TCP_CACHE_TTL_SECONDS = 2.0
SHELL_DEFAULT_RE = re.compile(
    r"^\$\{[A-Za-z_][A-Za-z0-9_]*:-((?:\\.|[^\\}])*)\}$"
)


def _configured_scan_roots(agent_root: Path | None = None) -> list[Path]:
    """Env + optional config.json scan_roots — never product-specific defaults."""
    roots: list[Path] = []
    raw = (os.environ.get(SCAN_ROOTS_ENV) or "").strip()
    if raw:
        for part in raw.split(":"):
            part = part.strip()
            if part:
                roots.append(Path(part).expanduser())
    if agent_root is not None:
        configured = load_agent_config(agent_root).get("scan_roots")
        if isinstance(configured, str) and configured.strip():
            roots.append(Path(configured).expanduser())
        elif isinstance(configured, list):
            for item in configured:
                if isinstance(item, str) and item.strip():
                    roots.append(Path(item).expanduser())
    return roots


def parse_loose_env_assignments(file: Path) -> dict[str, str]:
    """Parse KEY=value including bash ${VAR:-default} defaults — no shell exec."""
    try:
        content = file.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return {}
    values: dict[str, str] = {}
    for raw_line in content.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        equals = line.find("=")
        if equals <= 0:
            continue
        key = line[:equals].strip()
        if not PROFILE_KEY_RE.match(key):
            continue
        rest = line[equals + 1 :].strip()
        if " #" in rest and not (rest[:1] in "'\"" and rest.endswith(rest[:1])):
            rest = rest.split(" #", 1)[0].rstrip()
        if rest.startswith("#"):
            continue
        if len(rest) >= 2 and rest[0] == rest[-1] and rest[0] in "'\"":
            rest = rest[1:-1]
        match = SHELL_DEFAULT_RE.fullmatch(rest)
        if match:
            rest = match.group(1)
            # Unescape common shell sequences inside the default.
            rest = rest.replace("\\$", "$").replace("\\\"", '"').replace("\\'", "'")
        elif rest.startswith("$"):
            # Unresolved reference with no default — skip.
            continue
        values[key] = rest
    return values


# Inventory cache: (monotonic_ts, rows). Thread-safe for ThreadingHTTPServer;
# concurrent callers may share a snapshot that lags ≤LISTENING_TCP_CACHE_TTL_SECONDS.
# list_listening_tcp always returns a caller-private shallow copy so handlers
# cannot mutate cached rows. Misses fill under the lock (no stampede / DCL race
# with clear_listening_tcp_cache mid-inventory).
_listening_tcp_cache_lock = threading.Lock()
_listening_tcp_cache: tuple[float, list[dict[str, Any]]] | None = None


def clear_listening_tcp_cache() -> None:
    """Drop the short-TTL list_listening_tcp cache (tests / forced refresh)."""
    global _listening_tcp_cache
    with _listening_tcp_cache_lock:
        _listening_tcp_cache = None


def _copy_listening_tcp_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Caller-private copy of inventory rows (list + per-row dict)."""
    return [dict(row) for row in rows]


def list_listening_tcp() -> list[dict[str, Any]]:
    """Inventory TCP listeners; cached misses coalesce and results are caller-private."""
    global _listening_tcp_cache
    now = time.monotonic()
    with _listening_tcp_cache_lock:
        cached = _listening_tcp_cache
        if cached is not None and (now - cached[0]) < LISTENING_TCP_CACHE_TTL_SECONDS:
            return _copy_listening_tcp_rows(cached[1])
        # Hold the lock across inventory so concurrent misses coalesce into one
        # fill and clear_listening_tcp_cache cannot interleave mid-write.
        result = _list_listening_tcp_uncached()
        _listening_tcp_cache = (now, result)
        return _copy_listening_tcp_rows(result)


# /proc/net/tcp{,6} connection state: TCP_LISTEN
_PROC_TCP_LISTEN_STATE = "0A"


def _decode_proc_net_ip(addr_hex: str, *, ipv6: bool) -> str:
    """Decode a /proc/net/tcp{,6} local address field to a presentation string."""
    if not ipv6:
        try:
            value = int(addr_hex, 16)
        except ValueError:
            return addr_hex
        # Little-endian 32-bit host word → dotted IPv4.
        return (
            f"{value & 0xFF}."
            f"{(value >> 8) & 0xFF}."
            f"{(value >> 16) & 0xFF}."
            f"{(value >> 24) & 0xFF}"
        )
    # IPv6: eight-hex-digit words, each little-endian on the host.
    cleaned = addr_hex.strip()
    if len(cleaned) != 32:
        return cleaned
    try:
        words: list[str] = []
        for index in range(0, 32, 8):
            word = cleaned[index : index + 8]
            # Reverse byte pairs within the 32-bit word.
            words.append("".join(word[j : j + 2] for j in range(6, -1, -2)))
        packed = bytes.fromhex("".join(words))
        return socket.inet_ntop(socket.AF_INET6, packed)
    except (ValueError, OSError):
        return cleaned


def _parse_proc_net_tcp_table(
    text: str, *, ipv6: bool = False
) -> list[tuple[int, str, int]]:
    """Parse /proc/net/tcp or tcp6 into (port, bind, inode) LISTEN rows."""
    rows: list[tuple[int, str, int]] = []
    lines = text.splitlines()
    if len(lines) < 2:
        return rows
    for line in lines[1:]:
        parts = line.split()
        if len(parts) < 10:
            continue
        if parts[3] != _PROC_TCP_LISTEN_STATE:
            continue
        local = parts[1]
        if ":" not in local:
            continue
        ip_hex, port_hex = local.rsplit(":", 1)
        try:
            port = int(port_hex, 16)
            inode = int(parts[9])
        except ValueError:
            continue
        if port <= 0 or port > 65535:
            continue
        bind = _decode_proc_net_ip(ip_hex, ipv6=ipv6)
        rows.append((port, bind, inode))
    return rows


def _socket_inodes_to_pids(
    proc_root: Path, needed: set[int] | None = None
) -> dict[int, int]:
    """Map requested socket inodes to owning PIDs through proc fd links."""
    mapping: dict[int, int] = {}
    remaining: set[int] | None = set(needed) if needed is not None else None
    try:
        entries = os.listdir(proc_root)
    except OSError:
        return mapping
    for name in entries:
        if remaining is not None and not remaining:
            break
        if not name.isdigit():
            continue
        pid = int(name)
        fd_dir = proc_root / name / "fd"
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd_name in fds:
            try:
                target = os.readlink(fd_dir / fd_name)
            except OSError:
                continue
            if not (target.startswith("socket:[") and target.endswith("]")):
                continue
            try:
                inode = int(target[8:-1])
            except ValueError:
                continue
            if remaining is not None and inode not in remaining:
                continue
            if inode not in mapping:
                mapping[inode] = pid
                if remaining is not None:
                    remaining.discard(inode)
                    if not remaining:
                        break
    return mapping


def _linux_proc_listening_endpoints(
    proc_root: Path | None = None,
) -> list[tuple[int, int | None, str]] | None:
    """Return /proc listeners, or None when callers should fall back to ss/lsof."""
    root = proc_root if proc_root is not None else Path("/proc")
    tcp_path = root / "net" / "tcp"
    try:
        tcp_text = tcp_path.read_text(encoding="utf-8")
    except OSError:
        return None

    table = _parse_proc_net_tcp_table(tcp_text, ipv6=False)
    tcp6_path = root / "net" / "tcp6"
    try:
        table.extend(
            _parse_proc_net_tcp_table(
                tcp6_path.read_text(encoding="utf-8"), ipv6=True
            )
        )
    except OSError:
        pass

    need_inodes = {inode for _, _, inode in table if inode > 0}
    inode_to_pid = (
        _socket_inodes_to_pids(root, needed=need_inodes) if need_inodes else {}
    )

    endpoints: list[tuple[int, int | None, str]] = []
    for port, bind, inode in table:
        pid: int | None = None
        if inode > 0:
            pid = inode_to_pid.get(inode)
        endpoints.append((port, pid, bind))
    return endpoints


def _list_listening_tcp_uncached() -> list[dict[str, Any]]:
    by_port: dict[int, dict[str, Any]] = {}
    cmd_by_pid: dict[int, str | None] = {}
    self_pid = os.getpid()

    def cmdline(pid: int | None, *, port: int) -> str | None:
        if not pid:
            return None
        # System / clearly non-model ports and this agent: no /proc|ps.
        # Do not cache a miss for skip ports -- same pid may need resolve later.
        if port in SKIP_LISTEN_PORTS or pid == self_pid:
            return cmd_by_pid.get(pid)
        if pid not in cmd_by_pid:
            cmd_by_pid[pid] = process_command(pid)
        return cmd_by_pid[pid]

    def note(port: int, pid: int | None, command: str | None, bind: str) -> None:
        if port <= 0 or port > 65535:
            return
        existing = by_port.get(port)
        if existing is None:
            by_port[port] = {
                "port": port,
                "pid": pid,
                "command": command,
                "bind": bind,
            }
            return
        if existing.get("pid") is None and pid is not None:
            existing["pid"] = pid
        if not existing.get("command") and command:
            existing["command"] = command
        if bind and bind not in (existing.get("bind") or ""):
            existing["bind"] = bind

    # Prefer pure /proc on Linux -- avoids ss spawn (rank-1 after ps→/proc).
    proc_endpoints = _linux_proc_listening_endpoints()
    if proc_endpoints is not None:
        for port, pid, bind in proc_endpoints:
            note(port, pid, cmdline(pid, port=port), bind)
        return [by_port[key] for key in sorted(by_port)]

    try:
        result = subprocess.run(
            ["ss", "-lntupH"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) < 4:
                continue
            local = parts[3]
            if local.startswith("%"):
                continue
            port = _parse_local_port(local)
            if port is None:
                continue
            bind = local.rsplit(":", 1)[0].strip("[]") if ":" in local else local
            pid = None
            pid_match = re.search(r"pid=(\d+)", line)
            if pid_match:
                pid = int(pid_match.group(1))
            note(port, pid, cmdline(pid, port=port), bind)
    except (OSError, subprocess.TimeoutExpired):
        pass

    if not by_port:
        try:
            result = subprocess.run(
                ["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"],
                capture_output=True,
                text=True,
                timeout=8,
                check=False,
            )
            for line in result.stdout.splitlines()[1:]:
                parts = line.split()
                if len(parts) < 9:
                    continue
                try:
                    pid = int(parts[1])
                except ValueError:
                    pid = None
                name = parts[8]
                port = _parse_local_port(name)
                if port is None:
                    continue
                bind = name.rsplit(":", 1)[0].strip("[]") if ":" in name else name
                note(port, pid, cmdline(pid, port=port), bind)
        except (OSError, subprocess.TimeoutExpired):
            pass

    return [by_port[key] for key in sorted(by_port)]


def _parse_local_port(local: str) -> int | None:
    local = local.strip()
    if not local:
        return None
    if local.startswith("["):
        close = local.find("]")
        if close > 0 and close + 1 < len(local) and local[close + 1] == ":":
            try:
                return int(local[close + 2 :])
            except ValueError:
                return None
    if local.count(":") == 1:
        try:
            return int(local.rsplit(":", 1)[1])
        except ValueError:
            return None
    if local.startswith(":") and local[1:].isdigit():
        return int(local[1:])
    return None


def command_is_internal_model_worker(command: str | None) -> bool:
    """True for engine/worker children that are not public model HTTP APIs."""
    if not command:
        return False
    lowered = command.lower()
    return any(marker in lowered for marker in MODEL_SERVER_INTERNAL_COMMAND_MARKERS)


def command_looks_like_model_server(command: str | None) -> bool:
    """True when a live process looks like a model server (including workers).

    Use command_is_internal_model_worker() to filter workers out of discovery
    probes; keep this broader so stop/kill ownership matching still sees
    EngineCore leftovers on a profile port.
    """
    if not command:
        return False
    lowered = command.lower()
    return any(marker in lowered for marker in MODEL_SERVER_COMMAND_MARKERS)


def _shell_tokens(command: str) -> list[str]:
    try:
        return shlex.split(command)
    except ValueError:
        return command.split()


def infer_runtime_from_command(command: str | None) -> str:
    """Best-effort runtime label from a live process — never invent a stack."""
    if not command:
        return "unknown"
    lowered = command.lower()
    if "vllm" in lowered:
        return "vllm"
    if "sglang" in lowered:
        return "sglang"
    if "text-generation" in lowered or "tgi" in lowered:
        return "tgi"
    if "ollama" in lowered:
        return "ollama"
    if any(
        token in lowered
        for token in ("llama-server", "llama.cpp", "llamacpp", "llama-cpp", "kobold")
    ):
        return "llama.cpp"
    if "tabby" in lowered:
        return "tabbyapi"
    return "unknown"


def infer_model_from_command(command: str | None) -> str | None:
    """Pull a model path/id out of argv when present. None if not visible."""
    if not command:
        return None
    tokens = _shell_tokens(command)
    for index, token in enumerate(tokens):
        if token in ("-m", "--model", "--model-path", "--model-id", "--served-model-name"):
            if index + 1 < len(tokens):
                return tokens[index + 1]
        if token.startswith("--model="):
            return token.split("=", 1)[1]
        if token.startswith("--model-path="):
            return token.split("=", 1)[1]
        if token.startswith("--model-id="):
            return token.split("=", 1)[1]
    for index, token in enumerate(tokens):
        if token == "serve" and index + 1 < len(tokens):
            candidate = tokens[index + 1]
            if not candidate.startswith("-"):
                return candidate
    for token in reversed(tokens):
        if token.startswith("-"):
            continue
        if token.endswith(".gguf") or "/" in token:
            return token
    return None


@dataclass
class ProbeOutcome:
    """Outcome of probing one endpoint (L25).

    Make-unrepresentable: `ready` and `openai_models` are DERIVED, never
    stored — a probe can no longer claim ready while every check failed.
    The wire-facing dict shape (port/host/ready/health_ok/openai_models/
    model_ids/base_url) is preserved via as_item_dict().
    """

    port: int
    host: str = "127.0.0.1"
    health_ok: bool = False
    model_ids: list[str] = field(default_factory=list)

    @property
    def openai_models(self) -> bool:
        return bool(self.model_ids)

    @property
    def ready(self) -> bool:
        return self.health_ok or self.openai_models

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}/v1"


def probe_model_endpoint(port: int, host: str = "127.0.0.1") -> ProbeOutcome:
    """Probe common local model HTTP surfaces. Does not invent identity."""
    health_ok = False
    model_ids: list[str] = []
    health_urls = (
        f"http://{host}:{port}/health",
        f"http://{host}:{port}/v1/health",
    )
    for url in health_urls:
        try:
            request = urllib.request.Request(url, headers={"Accept": "application/json"})
            with _urlopen_no_redirect(request, DISCOVERY_PROBE_TIMEOUT) as response:
                if 200 <= response.status < 300:
                    health_ok = True
                    break
        except (urllib.error.URLError, OSError, ValueError):
            continue

    models_url = f"http://{host}:{port}/v1/models"
    try:
        request = urllib.request.Request(models_url, headers={"Accept": "application/json"})
        with _urlopen_no_redirect(request, DISCOVERY_PROBE_TIMEOUT) as response:
            body = response.read()
        parsed = json.loads(body)
        entries = parsed.get("data", []) if isinstance(parsed, dict) else []
        ids = [
            entry["id"]
            for entry in entries
            if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"]
        ]
        if ids:
            model_ids = ids
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError, AttributeError):
        pass

    return ProbeOutcome(port=port, host=host, health_ok=health_ok, model_ids=model_ids)


def _roots_hinted_by_path_token(token: str) -> list[Path]:
    """If a cmdline/profile path sits inside a numeric port folder, return its parent."""
    try:
        path = Path(token).expanduser()
    except (TypeError, ValueError):
        return []
    candidates: list[Path] = []
    current = path
    for _ in range(4):
        if PORT_CLAIM_DIR_RE.fullmatch(current.name):
            parent = current.parent
            if parent != current:
                candidates.append(parent)
        current = current.parent
        if current == current.parent:
            break
    return candidates


def roots_hinted_by_commands(commands: list[str | None]) -> list[Path]:
    """Derive scan roots from live argv / START_COMMAND paths (host-agnostic)."""
    found: list[Path] = []
    seen: set[Path] = set()
    for command in commands:
        if not command:
            continue
        for token in _shell_tokens(command):
            if "/" not in token and not token.startswith("~"):
                continue
            for root in _roots_hinted_by_path_token(token):
                try:
                    resolved = root.resolve()
                except OSError:
                    continue
                if resolved not in seen and resolved.is_dir():
                    seen.add(resolved)
                    found.append(resolved)
    return found


def _normalize_scan_root(root: Path) -> Path:
    """Resolve a scan root for stable identity across symlinks and overlaps."""
    return root.expanduser().resolve()


def scan_port_claim_directories(
    roots: list[Path] | None = None,
    *,
    agent_root: Path | None = None,
    listeners: list[dict[str, Any]] | None = None,
    max_depth: int = 3,
    home_depth: int = 2,
    limit: int = 64,
) -> list[dict[str, Any]]:
    """Find claimed-port folders under configured / hinted roots.

    Convention only: a directory whose name is a TCP port (2–5 digits) and that
    contains a launch/flags marker. Parent path is whatever the user chose —
    no product-specific roots are assumed. Roots come from:
      • explicit `roots` argument
      • MODEL_SWITCHBOARD_SCAN_ROOTS / config.json scan_roots
      • paths embedded in live process commands / profile START_COMMANDs
      • $HOME shallow claims always unioned (until limit)
        (developer homes are huge -- avoid re-walking when primary already hit)

    Dirent work is bounded within one call: remaining-depth visit map skips
    re-iterdir when roots overlap; is_dir is memoized for the scan.
    """
    hinted: list[Path] = []
    try:
        live = listeners if listeners is not None else list_listening_tcp()
        hinted.extend(
            roots_hinted_by_commands([item.get("command") for item in live])
        )
    except Exception:
        pass

    # Per-scan is_dir memo (root admission + walk); paths reappear under overlap.
    is_dir_memo: dict[Path, bool] = {}

    def path_is_dir(path: Path) -> bool:
        cached = is_dir_memo.get(path)
        if cached is not None:
            return cached
        try:
            ok = path.is_dir()
        except OSError:
            ok = False
        is_dir_memo[path] = ok
        return ok

    primary: list[Path] = []
    primary_set: set[Path] = set()
    for root in (roots or []) + _configured_scan_roots(agent_root) + hinted:
        try:
            resolved = _normalize_scan_root(root)
        except OSError:
            continue
        if resolved in primary_set:
            continue
        if path_is_dir(resolved):
            primary_set.add(resolved)
            primary.append(resolved)

    # Parents first so a higher remaining budget covers nested sibling roots.
    primary.sort(key=lambda p: (len(p.parts), str(p)))

    home_roots: list[Path] = []
    try:
        home = _normalize_scan_root(Path.home())
        if path_is_dir(home) and home not in primary_set:
            home_roots.append(home)
    except OSError:
        pass

    claims: dict[int, dict[str, Any]] = {}
    # directory -> best remaining depth already walked (skip re-iterdir on overlap)
    walked_remaining: dict[Path, int] = {}

    def consider_claim(directory: Path) -> None:
        if len(claims) >= limit:
            return
        name = directory.name
        if not PORT_CLAIM_DIR_RE.fullmatch(name):
            return
        markers = [m for m in PORT_CLAIM_MARKERS if (directory / m).is_file()]
        if not markers:
            return
        # Directory name is the claim identity / managed port. A mismatched
        # flags.env PORT= must not retarget the claim (e.g. folder 9999 with
        # PORT=22 would otherwise become port-22 and force-stop listeners there).
        port = int(name)
        flags: dict[str, str] = {}
        flags_path = directory / "flags.env"
        if flags_path.is_file():
            flags = parse_loose_env_assignments(flags_path)
        model_hint = (
            flags.get("MODEL")
            or flags.get("MODEL_FILE")
            or flags.get("MODEL_PATH")
            or flags.get("MODEL_DIR")
            or flags.get("MODEL_REPO")
            or flags.get("REQUEST_MODEL")
            or ""
        )
        runtime_hint = ""
        if flags.get("RUNTIME"):
            runtime_hint = canonical_runtime(flags.get("RUNTIME"))
        elif flags.get("BACKEND"):
            runtime_hint = infer_runtime_from_command(flags.get("BACKEND"))
        elif flags.get("LLAMA_BIN") or flags.get("LLAMA_SERVER"):
            runtime_hint = "llama.cpp"
        elif flags.get("VLLM_BIN") or "vllm" in (flags.get("BACKEND") or "").lower():
            runtime_hint = "vllm"
        display = flags.get("DISPLAY_NAME") or ""
        if not display and model_hint:
            display = Path(model_hint).name
        if not display:
            display = f"Port {port}"
        start_command = ""
        for candidate in ("ctrl.sh", "launch.sh", "start.sh", "run.sh", "serve.sh"):
            script = directory / candidate
            if script.is_file() and os.access(script, os.X_OK):
                if candidate == "ctrl.sh":
                    start_command = f"{shlex.quote(str(script))} start"
                else:
                    start_command = shlex.quote(str(script))
                break
        claims[port] = {
            "port": port,
            "path": str(directory),
            "markers": markers,
            "display_name": display,
            "model_hint": model_hint,
            "runtime_hint": first_known(runtime_hint),
            "host": flags.get("HOST") or "127.0.0.1",
            "start_command": start_command,
            "flags": {
                key: flags[key]
                for key in (
                    "MODEL",
                    "MODEL_FILE",
                    "MODEL_PATH",
                    "MODEL_DIR",
                    "MODEL_REPO",
                    "LLAMA_BIN",
                    "BACKEND",
                    "VLLM_BIN",
                    "REQUEST_MODEL",
                    "DISPLAY_NAME",
                    "PORT",
                    "HOST",
                )
                if key in flags
            },
        }

    def walk(directory: Path, depth: int, depth_limit: int) -> None:
        if depth > depth_limit or len(claims) >= limit:
            return
        remaining = depth_limit - depth
        prior = walked_remaining.get(directory)
        if prior is not None and prior >= remaining:
            return
        walked_remaining[directory] = remaining
        consider_claim(directory)
        if remaining == 0:
            return
        try:
            entries = list(directory.iterdir())
        except OSError:
            return
        for entry in entries:
            if entry.name in PROFILE_SCAN_SKIP_DIRS or entry.name.startswith("."):
                continue
            if path_is_dir(entry):
                walk(entry, depth + 1, depth_limit)

    for root in primary:
        walk(root, 0, max_depth)
        if len(claims) >= limit:
            break
    # Always union shallow $HOME claims. Primary scan_roots can be non-empty
    # while still missing user-owned port folders under $HOME.
    if len(claims) < limit:
        for root in home_roots:
            walk(root, 0, home_depth)
            if len(claims) >= limit:
                break

    return [claims[key] for key in sorted(claims)]


def discover_live_model_endpoints(
    *,
    profile_ports: set[int] | None = None,
    claim_ports: set[int] | None = None,
    listeners: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Discover model-looking listeners within a bounded probe budget."""
    profile_ports = profile_ports or set()
    claim_ports = claim_ports or set()
    discovered: list[dict[str, Any]] = []
    probes_left = DISCOVERY_PROBE_BUDGET

    self_pid = os.getpid()
    agent_ports = {DEFAULT_PORT}
    inventory = list(listeners if listeners is not None else list_listening_tcp())

    def _listener_priority(item: dict[str, Any]) -> tuple[int, int]:
        port = int(item["port"])
        claimed = 0 if (port in profile_ports or port in claim_ports) else 1
        return (claimed, port)

    for listener in sorted(inventory, key=_listener_priority):
        port = int(listener["port"])
        if port in SKIP_LISTEN_PORTS:
            continue
        listener_pid = listener.get("pid")
        if listener_pid is not None and int(listener_pid) == self_pid:
            agent_ports.add(port)
            continue
        if port in agent_ports and command_looks_like_model_server(
            listener.get("command") or ""
        ) is False:
            command = (listener.get("command") or "").lower()
            if "model_switchboard_agent" in command or "model-switchboard-agent" in command:
                continue

        command = listener.get("command")
        looks_model = command_looks_like_model_server(command)
        # Never surface or HTTP-probe internal engine/worker ports. They match
        # "vllm" etc. but are not OpenAI-compatible APIs; each failed probe is
        # up to ~3× DISCOVERY_PROBE_TIMEOUT and serializes /api/status.
        if looks_model and command_is_internal_model_worker(command):
            continue
        claimed = port in profile_ports or port in claim_ports
        if not looks_model and not claimed:
            continue

        probe = ProbeOutcome(port=port)
        if probes_left > 0 and port_is_listening(str(port)):
            probes_left -= 1
            probe = probe_model_endpoint(port)

        if not probe.ready and not looks_model and not claimed:
            continue

        runtime = infer_runtime_from_command(command)
        model_from_cmd = infer_model_from_command(command)
        model_ids = list(probe.model_ids)
        request_model = (
            (model_ids[0] if model_ids else None)
            or model_from_cmd
            or f"port-{port}"
        )
        display = request_model
        if isinstance(display, str) and ("/" in display or display.endswith(".gguf")):
            display = Path(display).name

        discovered.append(
            {
                "port": port,
                "pid": listener.get("pid"),
                "command": command,
                "bind": listener.get("bind"),
                "runtime": runtime,
                "request_model": request_model,
                "server_ids": model_ids,
                "display_name": display,
                "ready": probe.ready,
                "health_ok": probe.health_ok,
                "base_url": probe.base_url,
                "source": "discovery",
            }
        )
    return discovered


def status_dict_from_discovery(
    item: dict[str, Any],
    *,
    source: str,
    profile_name: str | None = None,
    listeners: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Shape a discovery/claim record like a controller status entry."""
    port = str(item.get("port", ""))
    runtime = first_known(item.get("runtime"), item.get("runtime_hint"))
    label, tags, launch_mode = RUNTIME_SPECS.get(
        runtime, (runtime, ["discovered", "external"], "external")
    )
    if source == "claim":
        launch_mode = "command" if item.get("start_command") else "external"
        tags = list(dict.fromkeys(["claimed", "launch-folder"] + list(tags)))
    else:
        tags = list(dict.fromkeys(["discovered", "listening"] + list(tags)))
        launch_mode = "external"

    ready = bool(item.get("ready"))
    pid = item.get("pid")
    if pid is None and listeners is not None:
        pid = listener_pid_from_inventory(port, listeners)
    # Ownership only — ready listeners without an attributed pid stay
    # ready=true / running=false (same contract as profile status()).
    alive = bool(pid) and process_is_alive(pid)

    request_model = item.get("request_model") or item.get("model_hint") or f"port-{port}"
    display = item.get("display_name") or Path(str(request_model)).name or f"Port {port}"
    name = profile_name or f"discovered-{port}"
    # Mirror profile status(): ready can be visible without claiming ownership.
    # Do not force running=True / pid attribution for unmatched ready listeners.
    # (The stringly lifecycle "state" key was deleted from the wire contract —
    # L22: running/ready booleans are the single encoding Swift decodes.)

    return {
        "profile": name,
        "display_name": display,
        "runtime": runtime,
        "runtime_label": label,
        "runtime_tags": tags,
        "launch_mode": launch_mode,
        "host": item.get("host") or "127.0.0.1",
        "port": port,
        "base_url": item.get("base_url") or f"http://127.0.0.1:{port}/v1",
        "request_model": str(request_model),
        "server_model_id": str(
            (item.get("server_ids") or [None])[0] or request_model
        ),
        "pid": pid if alive else None,
        "running": alive,
        "ready": ready,
        "server_ids": item.get("server_ids") or item.get("model_ids") or [],
        "rss_mb": process_rss_mb(pid) if alive and pid else None,
        "vram_mb": process_vram_mb(pid) if alive and pid else None,
        "command": item.get("command") if alive else None,
        # L09: no invented log path — None when the row has no launch claim.
        "log_path": item.get("log_path"),
        "source": source,
    }


def profile_from_claim(claim: dict[str, Any]) -> Profile:
    """Build a manage-able Profile from a claimed port folder (no invented flags)."""
    port = str(claim.get("port") or "")
    if not port:
        raise InvalidProfileError("claim missing port")
    name = f"port-{port}"
    claim_path = claim.get("path") or ""
    request = claim.get("model_hint") or f"port-{port}"
    request_s = str(request)
    flags = claim.get("flags") if isinstance(claim.get("flags"), dict) else {}
    start = (claim.get("start_command") or "").strip()
    stop = ""
    if claim_path:
        directory = Path(claim_path)
        ctrl = directory / "ctrl.sh"
        launch = directory / "launch.sh"
        if ctrl.is_file() and os.access(ctrl, os.X_OK):
            start = start or f"{shlex.quote(str(ctrl))} start"
            stop = f"{shlex.quote(str(ctrl))} stop"
        elif launch.is_file() and os.access(launch, os.X_OK):
            start = start or shlex.quote(str(launch))
    display = claim.get("display_name") or Path(request_s).name or name
    flags_safe = flags if isinstance(flags, dict) else {}
    model_raw = str(flags_safe.get("MODEL") or flags_safe.get("MODEL_PATH") or request_s)
    model_file_flag = str(flags_safe.get("MODEL_FILE") or "").strip()
    # Prefer explicit MODEL_FILE; otherwise only treat MODEL= as a file when it
    # has a weight suffix. HF/vLLM directories stay on MODEL_PATH / MODEL_DIR so
    # missing_artifacts does not false-positive on live directory checkpoints.
    if model_file_flag:
        model_file = model_file_flag
    elif any(model_raw.lower().endswith(suffix) for suffix in _WEIGHT_SUFFIXES):
        model_file = model_raw
    elif request_s.endswith(".gguf"):
        model_file = request_s
    else:
        model_file = ""
    model_dir = str(flags_safe.get("MODEL_DIR") or flags_safe.get("MODEL_REPO") or "")
    if not model_dir and model_raw and not model_file:
        candidate = Path(model_raw).expanduser()
        if candidate.is_dir() or (
            _looks_like_local_fs_path(model_raw)
            and not any(model_raw.lower().endswith(s) for s in _WEIGHT_SUFFIXES)
        ):
            model_dir = model_raw
    values: dict[str, str] = {
        "DISPLAY_NAME": str(display),
        # L21: the claim scan's boundary inference (flags RUNTIME/BACKEND/
        # LLAMA_BIN/VLLM_BIN) is the single runtime source for claim profiles.
        # No interior re-derivation from START_COMMAND later.
        "RUNTIME": first_known(claim.get("runtime_hint")),
        "REQUEST_MODEL": request_s,
        "SERVER_MODEL_ID": Path(request_s).name if ("/" in request_s or request_s.endswith(".gguf")) else request_s,
        "PORT": port,
        "HOST": str(claim.get("host") or "127.0.0.1"),
        "START_COMMAND": start,
        "WORKING_DIRECTORY": claim_path,
        "LOG_ALIAS": f"launch-{port}",
        "MODEL_PATH": model_raw,
        "MODEL_FILE": model_file,
        "MODEL_DIR": model_dir,
        "MODEL_REPO": str(flags_safe.get("MODEL_REPO") or ""),
    }
    if stop:
        values["STOP_COMMAND"] = stop
    if not start:
        values["LAUNCH_MODE"] = "external"
    # L24: tags pass as a parsed list (no comma-string re-encoding); the
    # env-file comma format is only for real files on disk.
    return Profile(name=name, values=values, tags=["claimed", "launch-folder"])

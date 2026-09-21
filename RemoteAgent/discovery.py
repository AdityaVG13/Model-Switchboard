"""Listener and port-claim discovery for the Model Switchboard remote agent."""

from __future__ import annotations

import json
import os
import re
import shlex
import socket
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from agent_core import (
    DEFAULT_PORT,
    InvalidProfileError,
    is_placeholder_model_name,
    PROFILE_SCAN_SKIP_DIRS,
    Profile,
    RUNTIME_SPECS,
    SCAN_ROOTS_ENV,
    WEIGHT_SUFFIXES,
    canonical_runtime,
    first_known,
    first_present,
    is_valid_tcp_port,
    listener_pid_from_inventory,
    load_agent_config,
    looks_like_local_fs_path,
    openai_model_ids_from_entries,
    path_is_dir,
    path_is_regular_file,
    port_is_listening,
    process_command,
    process_is_alive,
    process_rss_mb,
    process_vram_mb,
    run_captured,
    _assignment_key_rest,
    _stripped_assignment_line,
    urlopen_no_redirect,
)

PORT_CLAIM_DIR_RE = re.compile(r"^\d{2,5}$")
PORT_CLAIM_MARKERS = ("flags.env", "launch.sh", "start.sh", "run.sh", "serve.sh", "ctrl.sh")


# Live cmdlines often mention ``/run/user/<uid>/...``. The uid looks like a
# TCP port, so those paths must never become scan roots or port claims.
# macOS resolves ``/var/run`` to ``/private/var/run``.
_OS_RUNTIME_PREFIXES = ("/proc", "/sys", "/dev", "/run", "/var/run", "/private/var/run")


def _text_is_os_runtime(text: str) -> bool:
    return any(
        text == prefix or text.startswith(prefix + "/") for prefix in _OS_RUNTIME_PREFIXES
    )


def is_os_runtime_path(path: Path) -> bool:
    """True for kernel/runtime mounts that are not user port-claim trees."""
    return any(_text_is_os_runtime(text) for text in _os_runtime_path_texts(path))


def _os_runtime_path_texts(path: Path) -> list[str]:
    candidates: list[str] = []
    try:
        candidates.append(path.as_posix())
    except (OSError, ValueError):
        return []
    try:
        candidates.append(path.resolve().as_posix())
    except OSError:
        pass
    return candidates


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
    "mlx",
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
# /api/status take tens of seconds - longer than the Mac client's request
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
# Well-known OS / infra ports that are never a local OpenAI-compatible model
# server. Do not put application HTTP ports here (8080, 8088, 8443, 9100, …):
# operators run models on those, and a skip list must not encode one machine.
SKIP_LISTEN_PORTS = frozenset({
    22, 25, 53, 67, 68, 69, 80, 110, 123, 135, 139, 143, 161, 389, 443,
    445, 465, 587, 631, 636, 993, 995, 2375, 2376, 3306, 3389, 5432, 5900,
    6379, 6443, 10250, 27017,
})
DISCOVERY_PROBE_BUDGET = 24
DISCOVERY_PROBE_TIMEOUT = 0.6
LISTENING_TCP_CACHE_TTL_SECONDS = 2.0
SHELL_DEFAULT_RE = re.compile(
    r"^\$\{[A-Za-z_][A-Za-z0-9_]*:-((?:\\.|[^\\}])*)\}$"
)


def _append_configured_scan_roots(roots: list[Path], configured: Any) -> None:
    if isinstance(configured, str):
        _append_configured_scan_root(roots, configured)
        return
    if isinstance(configured, list):
        for item in configured:
            _append_configured_scan_root(roots, item)


def _append_configured_scan_root(roots: list[Path], raw: Any) -> None:
    if isinstance(raw, str) and raw.strip():
        roots.append(Path(raw).expanduser())


def _configured_scan_roots(agent_root: Path | None = None) -> list[Path]:
    """Env + optional config.json scan_roots - never product-specific defaults."""
    roots: list[Path] = []
    _append_env_scan_roots(roots, (os.environ.get(SCAN_ROOTS_ENV) or "").strip())
    if agent_root is not None:
        _append_configured_scan_roots(roots, load_agent_config(agent_root).get("scan_roots"))
    return roots


def _append_env_scan_roots(roots: list[Path], raw: str) -> None:
    if not raw:
        return
    for part in raw.split(":"):
        part = part.strip()
        if part:
            roots.append(Path(part).expanduser())


configured_scan_roots = _configured_scan_roots


def _uncommented_env_rest(rest: str) -> str:
    if " #" in rest and not _is_fully_quoted(rest):
        return rest.split(" #", 1)[0].rstrip()
    return rest


def _strip_inline_env_comment(rest: str) -> str | None:
    rest = _uncommented_env_rest(rest)
    if rest.startswith("#"):
        return None
    return rest


def _is_fully_quoted(rest: str) -> bool:
    return bool(rest[:1] in "'\"" and rest.endswith(rest[:1]))


def _unquote_shell_default(rest: str) -> str | None:
    rest = _strip_matching_quotes(rest)
    match = SHELL_DEFAULT_RE.fullmatch(rest)
    if match:
        return _unescape_shell_default(match.group(1))
    if rest.startswith("$"):
        return None
    return rest


def _is_matching_quoted(rest: str) -> bool:
    return len(rest) >= 2 and rest[0] == rest[-1] and rest[0] in "'\""


def _strip_matching_quotes(rest: str) -> str:
    if _is_matching_quoted(rest):
        return rest[1:-1]
    return rest


def _unescape_shell_default(value: str) -> str:
    return value.replace("\\$", "$").replace("\\\"", '"').replace("\\'", "'")


def _loose_env_assignment(raw_line: str) -> tuple[str, str] | None:
    line = _stripped_assignment_line(raw_line)
    if line is None:
        return None
    return _loose_env_key_rest(line)


def _loose_env_key_rest(line: str) -> tuple[str, str] | None:
    parsed = _assignment_key_rest(line)
    if parsed is None:
        return None
    key, raw = parsed
    rest = _loose_env_value(raw)
    if rest is None:
        return None
    return key, rest


def _loose_env_value(raw: str) -> str | None:
    rest = _strip_inline_env_comment(raw)
    if rest is None:
        return None
    return _unquote_shell_default(rest)


def parse_loose_env_assignments(file: Path) -> dict[str, str]:
    """Parse KEY=value including bash ${VAR:-default} defaults - no shell exec."""
    try:
        content = file.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return {}
    values: dict[str, str] = {}
    for raw_line in content.splitlines():
        parsed = _loose_env_assignment(raw_line)
        if parsed is None:
            continue
        key, rest = parsed
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


def _decode_proc_net_ipv4(addr_hex: str) -> str:
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


def _reversed_ipv6_words(cleaned: str) -> list[str]:
    words: list[str] = []
    for index in range(0, 32, 8):
        word = cleaned[index : index + 8]
        # Reverse byte pairs within the 32-bit word.
        words.append("".join(word[j : j + 2] for j in range(6, -1, -2)))
    return words


def _decode_proc_net_ipv6(addr_hex: str) -> str:
    cleaned = addr_hex.strip()
    if len(cleaned) != 32:
        return cleaned
    try:
        packed = bytes.fromhex("".join(_reversed_ipv6_words(cleaned)))
        return socket.inet_ntop(socket.AF_INET6, packed)
    except (ValueError, OSError):
        return cleaned


def _decode_proc_net_ip(addr_hex: str, *, ipv6: bool) -> str:
    """Decode a /proc/net/tcp{,6} local address field to a presentation string."""
    if not ipv6:
        return _decode_proc_net_ipv4(addr_hex)
    return _decode_proc_net_ipv6(addr_hex)


def _proc_net_local_hex(local: str) -> tuple[str, str] | None:
    if ":" not in local:
        return None
    ip_hex, port_hex = local.rsplit(":", 1)
    return ip_hex, port_hex


def _proc_net_listen_local(parts: list[str]) -> tuple[str, str] | None:
    if len(parts) < 10 or parts[3] != _PROC_TCP_LISTEN_STATE:
        return None
    return _proc_net_local_hex(parts[1])


def _listen_row_from_proc_net(
    parts: list[str], *, ipv6: bool
) -> tuple[int, str, int] | None:
    split = _proc_net_listen_local(parts)
    if split is None:
        return None
    ip_hex, port_hex = split
    try:
        port = int(port_hex, 16)
        inode = int(parts[9])
    except ValueError:
        return None
    if not is_valid_tcp_port(port):
        return None
    return (port, _decode_proc_net_ip(ip_hex, ipv6=ipv6), inode)


def _parse_proc_net_tcp_table(
    text: str, *, ipv6: bool = False
) -> list[tuple[int, str, int]]:
    """Parse /proc/net/tcp or tcp6 into (port, bind, inode) LISTEN rows."""
    rows: list[tuple[int, str, int]] = []
    lines = text.splitlines()
    if len(lines) < 2:
        return rows
    for line in lines[1:]:
        parsed = _listen_row_from_proc_net(line.split(), ipv6=ipv6)
        if parsed is not None:
            rows.append(parsed)
    return rows


def _inode_from_socket_target(target: str) -> int | None:
    if not (target.startswith("socket:[") and target.endswith("]")):
        return None
    try:
        return int(target[8:-1])
    except ValueError:
        return None


def _collect_pid_socket_inodes(
    fd_dir: Path,
    pid: int,
    mapping: dict[int, int],
    remaining: set[int] | None,
) -> None:
    try:
        fds = os.listdir(fd_dir)
    except OSError:
        return
    for fd_name in fds:
        if _record_socket_inode(fd_dir / fd_name, pid, mapping, remaining):
            return


def _record_socket_inode(
    fd_path: Path,
    pid: int,
    mapping: dict[int, int],
    remaining: set[int] | None,
) -> bool:
    try:
        target = os.readlink(fd_path)
    except OSError:
        return False
    inode = _inode_from_socket_target(target)
    if not _inode_is_new(inode, mapping, remaining):
        return False
    mapping[inode] = pid
    return _mark_inode_seen(inode, remaining)


def _inode_is_new(
    inode: int | None,
    mapping: dict[int, int],
    remaining: set[int] | None,
) -> bool:
    if inode is None:
        return False
    if remaining is not None and inode not in remaining:
        return False
    return inode not in mapping


def _mark_inode_seen(inode: int, remaining: set[int] | None) -> bool:
    if remaining is None:
        return False
    remaining.discard(inode)
    return not remaining


def _needed_inode_set(needed: set[int] | None) -> set[int] | None:
    return set(needed) if needed is not None else None


def _socket_inodes_to_pids(
    proc_root: Path, needed: set[int] | None = None
) -> dict[int, int]:
    """Map requested socket inodes to owning PIDs through proc fd links."""
    mapping: dict[int, int] = {}
    remaining = _needed_inode_set(needed)
    for pid_dir in _proc_pid_dirs(proc_root):
        if _proc_pid_scan_done(remaining):
            break
        _collect_pid_socket_inodes(pid_dir / "fd", int(pid_dir.name), mapping, remaining)
    return mapping


def _proc_pid_dirs(proc_root: Path) -> list[Path]:
    try:
        names = os.listdir(proc_root)
    except OSError:
        return []
    return [proc_root / name for name in names if name.isdigit()]


def _proc_pid_scan_done(remaining: set[int] | None) -> bool:
    return remaining is not None and not remaining


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
    _extend_proc_tcp6(root, table)
    return _endpoints_from_proc_table(root, table)


def _extend_proc_tcp6(root: Path, table: list) -> None:
    try:
        table.extend(
            _parse_proc_net_tcp_table(
                (root / "net" / "tcp6").read_text(encoding="utf-8"), ipv6=True
            )
        )
    except OSError:
        pass


def _inode_pid_map(root: Path, table: list) -> dict[int, int]:
    need_inodes = {inode for _, _, inode in table if inode > 0}
    return _socket_inodes_to_pids(root, needed=need_inodes) if need_inodes else {}


def _endpoints_from_proc_table(
    root: Path, table: list
) -> list[tuple[int, int | None, str]]:
    inode_to_pid = _inode_pid_map(root, table)
    endpoints: list[tuple[int, int | None, str]] = []
    for port, bind, inode in table:
        endpoints.append((port, _pid_for_inode(inode, inode_to_pid), bind))
    return endpoints


def _pid_for_inode(inode: int, inode_to_pid: dict[int, int]) -> int | None:
    return inode_to_pid.get(inode) if inode > 0 else None


def _listen_cmdline(
    cmd_by_pid: dict[int, str | None],
    self_pid: int,
    pid: int | None,
    *,
    port: int,
) -> str | None:
    if not pid:
        return None
    # System / clearly non-model ports and this agent: no /proc|ps.
    # Do not cache a miss for skip ports -- same pid may need resolve later.
    if _skip_listen_command_lookup(port, pid, self_pid):
        return cmd_by_pid.get(pid)
    return _cached_process_command(cmd_by_pid, pid)


def _cached_process_command(cmd_by_pid: dict[int, str | None], pid: int) -> str | None:
    if pid not in cmd_by_pid:
        cmd_by_pid[pid] = process_command(pid)
    return cmd_by_pid[pid]


def _skip_listen_command_lookup(port: int, pid: int, self_pid: int) -> bool:
    return port in SKIP_LISTEN_PORTS or pid == self_pid


def _new_listener_row(
    port: int, pid: int | None, command: str | None, bind: str
) -> dict[str, Any]:
    return {
        "port": port,
        "pid": pid,
        "command": command,
        "bind": bind,
    }


def _upsert_listener_row(
    by_port: dict[int, dict[str, Any]],
    port: int,
    pid: int | None,
    command: str | None,
    bind: str,
) -> None:
    existing = by_port.get(port)
    if existing is None:
        by_port[port] = _new_listener_row(port, pid, command, bind)
        return
    _merge_listener_row(existing, pid, command, bind)


def _note_listener(
    by_port: dict[int, dict[str, Any]],
    port: int,
    pid: int | None,
    command: str | None,
    bind: str,
) -> None:
    if not is_valid_tcp_port(port):
        return
    _upsert_listener_row(by_port, port, pid, command, bind)


def _merge_listener_row(
    existing: dict[str, Any],
    pid: int | None,
    command: str | None,
    bind: str,
) -> None:
    _fill_missing_pid(existing, pid)
    _fill_missing_command(existing, command)
    _fill_distinct_bind(existing, bind)


def _fill_missing_pid(existing: dict[str, Any], pid: int | None) -> None:
    if existing.get("pid") is None and pid is not None:
        existing["pid"] = pid


def _fill_missing_command(existing: dict[str, Any], command: str | None) -> None:
    if not existing.get("command") and command:
        existing["command"] = command


def _fill_distinct_bind(existing: dict[str, Any], bind: str) -> None:
    if bind and bind not in (existing.get("bind") or ""):
        existing["bind"] = bind


def _bind_from_local(local: str) -> str:
    return local.rsplit(":", 1)[0].strip("[]") if ":" in local else local


def _ingest_ss_listeners(
    by_port: dict[int, dict[str, Any]],
    cmd_by_pid: dict[int, str | None],
    self_pid: int,
) -> None:
    result = run_captured(["ss", "-lntupH"], 5)
    if result is None:
        return
    _ingest_listener_lines(
        by_port, cmd_by_pid, self_pid, result.stdout.splitlines(), _ss_listener_fields
    )


def _ingest_listener_lines(
    by_port: dict[int, dict[str, Any]],
    cmd_by_pid: dict[int, str | None],
    self_pid: int,
    lines,
    parse_line,
) -> None:
    for line in lines:
        parsed = parse_line(line)
        if parsed is None:
            continue
        port, pid, extra = parsed
        _note_listener(
            by_port,
            port,
            pid,
            _listen_cmdline(cmd_by_pid, self_pid, pid, port=port),
            _bind_from_local(extra),
        )


def _ss_line_pid(line: str) -> int | None:
    pid_match = re.search(r"pid=(\d+)", line)
    return int(pid_match.group(1)) if pid_match else None


def _ss_listener_fields(line: str) -> tuple[int, int | None, str] | None:
    parts = line.split()
    if len(parts) < 4:
        return None
    local = parts[3]
    if local.startswith("%"):
        return None
    port = _parse_local_port(local)
    if port is None:
        return None
    return port, _ss_line_pid(line), local


def _ingest_lsof_listeners(
    by_port: dict[int, dict[str, Any]],
    cmd_by_pid: dict[int, str | None],
    self_pid: int,
) -> None:
    result = run_captured(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN"], 8)
    if result is None:
        return
    _ingest_listener_lines(
        by_port,
        cmd_by_pid,
        self_pid,
        result.stdout.splitlines()[1:],
        _lsof_listener_fields,
    )


def _lsof_line_pid(parts: list[str]) -> int | None:
    try:
        return int(parts[1])
    except ValueError:
        return None


def _lsof_listener_fields(line: str) -> tuple[int, int | None, str] | None:
    parts = line.split()
    if len(parts) < 9:
        return None
    name = parts[8]
    port = _parse_local_port(name)
    if port is None:
        return None
    return port, _lsof_line_pid(parts), name


def _list_listening_tcp_from_tools(
    by_port: dict[int, dict[str, Any]],
    cmd_by_pid: dict[int, str | None],
    self_pid: int,
) -> list[dict[str, Any]]:
    _ingest_ss_listeners(by_port, cmd_by_pid, self_pid)
    if not by_port:
        _ingest_lsof_listeners(by_port, cmd_by_pid, self_pid)
    return _sorted_listeners(by_port)


def _list_listening_tcp_uncached() -> list[dict[str, Any]]:
    by_port: dict[int, dict[str, Any]] = {}
    cmd_by_pid: dict[int, str | None] = {}
    self_pid = os.getpid()
    if _ingest_proc_listeners(by_port, cmd_by_pid, self_pid):
        return _sorted_listeners(by_port)
    return _list_listening_tcp_from_tools(by_port, cmd_by_pid, self_pid)


def _ingest_proc_listeners(
    by_port: dict[int, dict[str, Any]],
    cmd_by_pid: dict[int, str | None],
    self_pid: int,
) -> bool:
    # Prefer pure /proc on Linux -- avoids ss spawn (rank-1 after ps→/proc).
    proc_endpoints = _linux_proc_listening_endpoints()
    if proc_endpoints is None:
        return False
    for port, pid, bind in proc_endpoints:
        _note_listener(
            by_port,
            port,
            pid,
            _listen_cmdline(cmd_by_pid, self_pid, pid, port=port),
            bind,
        )
    return True


def _sorted_listeners(by_port: dict[int, dict[str, Any]]) -> list[dict[str, Any]]:
    return [by_port[key] for key in sorted(by_port)]


def _ipv6_bracket_close(local: str) -> int | None:
    close = local.find("]")
    if close <= 0 or close + 1 >= len(local) or local[close + 1] != ":":
        return None
    return close


def _port_after_ipv6_bracket(local: str) -> int | None:
    close = _ipv6_bracket_close(local)
    return None if close is None else _int_or_none(local[close + 2 :])


def _parse_local_port(local: str) -> int | None:
    local = local.strip()
    if not local:
        return None
    if local.startswith("["):
        return _port_after_ipv6_bracket(local)
    return _port_after_ipv4_or_bare(local)


def _port_after_ipv4_or_bare(local: str) -> int | None:
    if local.count(":") == 1:
        return _int_or_none(local.rsplit(":", 1)[1])
    return _bare_colon_port(local)


def _bare_colon_port(local: str) -> int | None:
    if local.startswith(":") and local[1:].isdigit():
        return int(local[1:])
    return None


def _int_or_none(text: str) -> int | None:
    try:
        return int(text)
    except ValueError:
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


_RUNTIME_COMMAND_HINTS = (
    ("vllm", "vllm"),
    ("sglang", "sglang"),
    ("text-generation", "tgi"),
    ("tgi", "tgi"),
    ("ollama", "ollama"),
    ("mlx", "mlx"),
    ("kobold", "koboldcpp"),
    ("llama-server", "llama.cpp"),
    ("llama.cpp", "llama.cpp"),
    ("llamacpp", "llama.cpp"),
    ("llama-cpp", "llama.cpp"),
    ("tabby", "tabbyapi"),
)
_MODEL_FLAG_TOKENS = ("-m", "--model", "--model-path", "--model-id", "--served-model-name")
_MODEL_FLAG_PREFIXES = ("--model=", "--model-path=", "--model-id=")


def infer_runtime_from_command(command: str | None) -> str:
    """Best-effort runtime label from a live process - never invent a stack."""
    if not command:
        return "unknown"
    lowered = command.lower()
    for needle, runtime in _RUNTIME_COMMAND_HINTS:
        if needle in lowered:
            return runtime
    return "unknown"


def _model_from_equals_prefix(token: str) -> str | None:
    for prefix in _MODEL_FLAG_PREFIXES:
        if token.startswith(prefix):
            return token.split("=", 1)[1]
    return None


def _model_from_flag_operand(tokens: list[str], index: int, token: str) -> str | None:
    if token in _MODEL_FLAG_TOKENS and index + 1 < len(tokens):
        return tokens[index + 1]
    return _model_from_equals_prefix(token)


def _model_from_flag_tokens(tokens: list[str]) -> str | None:
    for index, token in enumerate(tokens):
        found = _model_from_flag_operand(tokens, index, token)
        if found is not None:
            return found
    return None


def _serve_operand(tokens: list[str], index: int) -> str | None:
    if index + 1 >= len(tokens):
        return None
    operand = tokens[index + 1]
    return None if operand.startswith("-") else operand


def _model_from_serve_token(tokens: list[str]) -> str | None:
    for index, token in enumerate(tokens):
        if token == "serve":
            operand = _serve_operand(tokens, index)
            if operand is not None:
                return operand
    return None


def _looks_like_model_path_token(token: str) -> bool:
    return not token.startswith("-") and (token.endswith(".gguf") or "/" in token)


def _model_from_path_token(tokens: list[str]) -> str | None:
    for token in reversed(tokens):
        if _looks_like_model_path_token(token):
            return token
    return None


def infer_model_from_command(command: str | None) -> str | None:
    """Pull a model path/id out of argv when present. None if not visible."""
    if not command:
        return None
    tokens = _shell_tokens(command)
    return (
        _model_from_flag_tokens(tokens)
        or _model_from_serve_token(tokens)
        or _model_from_path_token(tokens)
    )


@dataclass
class ProbeOutcome:
    """Outcome of probing one endpoint (L25).

    Make-unrepresentable: `ready` and `openai_models` are DERIVED, never
    stored - a probe can no longer claim ready while every check failed.
    Wire-facing discovery rows expose derived `ready` only.
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


def _http_health_ok(url: str) -> bool:
    try:
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urlopen_no_redirect(request, DISCOVERY_PROBE_TIMEOUT) as response:
            return 200 <= response.status < 300
    except (urllib.error.URLError, OSError, ValueError):
        return False


def _probe_health_ok(host: str, port: int) -> bool:
    for url in (f"http://{host}:{port}/health", f"http://{host}:{port}/v1/health"):
        if _http_health_ok(url):
            return True
    return False


def _probe_model_ids(host: str, port: int) -> list[str]:
    try:
        request = urllib.request.Request(
            f"http://{host}:{port}/v1/models",
            headers={"Accept": "application/json"},
        )
        with urlopen_no_redirect(request, DISCOVERY_PROBE_TIMEOUT) as response:
            body = response.read()
        parsed = json.loads(body)
        entries = parsed.get("data", []) if isinstance(parsed, dict) else []
        return openai_model_ids_from_entries(entries)
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError, AttributeError):
        return []


def probe_model_endpoint(port: int, host: str = "127.0.0.1") -> ProbeOutcome:
    """Probe common local model HTTP surfaces. Does not invent identity."""
    return ProbeOutcome(
        port=port,
        host=host,
        health_ok=_probe_health_ok(host, port),
        model_ids=_probe_model_ids(host, port),
    )


def _roots_hinted_by_path_token(token: str) -> list[Path]:
    """If a cmdline/profile path sits inside a numeric port folder, return its parent."""
    try:
        path = Path(token).expanduser()
    except (TypeError, ValueError):
        return []
    return _walk_hinted_ancestors(path)


def _walk_hinted_ancestors(path: Path) -> list[Path]:
    candidates: list[Path] = []
    current = path
    for _ in range(4):
        _admit_port_folder_parent(current, candidates)
        current = current.parent
        if current == current.parent:
            break
    return candidates


def _admit_port_folder_parent(current: Path, candidates: list[Path]) -> None:
    if PORT_CLAIM_DIR_RE.fullmatch(current.name):
        parent = current.parent
        if parent != current:
            candidates.append(parent)


def _admit_resolved_hinted_root(
    resolved: Path, seen: set[Path], found: list[Path]
) -> None:
    if resolved in seen or is_os_runtime_path(resolved):
        return
    if path_is_dir(resolved):
        seen.add(resolved)
        found.append(resolved)


def _admit_hinted_root(root: Path, seen: set[Path], found: list[Path]) -> None:
    try:
        resolved = root.resolve()
    except OSError:
        return
    _admit_resolved_hinted_root(resolved, seen, found)


def _command_looks_like_path_token(token: str) -> bool:
    return "/" in token or token.startswith("~")


def _admit_hinted_tokens(command: str, seen: set[Path], found: list[Path]) -> None:
    for token in _shell_tokens(command):
        if not _command_looks_like_path_token(token):
            continue
        for root in _roots_hinted_by_path_token(token):
            _admit_hinted_root(root, seen, found)


def roots_hinted_by_commands(commands: list[str | None]) -> list[Path]:
    """Derive scan roots from live argv / START_COMMAND paths (host-agnostic)."""
    found: list[Path] = []
    seen: set[Path] = set()
    for command in commands:
        if command:
            _admit_hinted_tokens(command, seen, found)
    return found


def _normalize_scan_root(root: Path) -> Path:
    """Resolve a scan root for stable identity across symlinks and overlaps."""
    return root.expanduser().resolve()


_CLAIM_MODEL_KEYS = (
    "MODEL",
    "MODEL_FILE",
    "MODEL_PATH",
    "MODEL_DIR",
    "MODEL_REPO",
    "REQUEST_MODEL",
)
_CLAIM_FLAG_EXPORT_KEYS = (
    "MODEL",
    "MODEL_FILE",
    "MODEL_PATH",
    "MODEL_DIR",
    "MODEL_REPO",
    "LLAMA_BIN",
    "BACKEND",
    "VLLM_BIN",
    "REQUEST_MODEL",
    "SERVER_MODEL_ID",
    "DISPLAY_NAME",
    "PORT",
    "HOST",
)
_CLAIM_LAUNCH_SCRIPTS = ("ctrl.sh", "launch.sh", "start.sh", "run.sh", "serve.sh")


def _memoized_is_dir(memo: dict[Path, bool], path: Path) -> bool:
    cached = memo.get(path)
    if cached is not None:
        return cached
    try:
        ok = path.is_dir()
    except OSError:
        ok = False
    memo[path] = ok
    return ok


def _claim_model_hint(flags: dict[str, str]) -> str:
    for key in _CLAIM_MODEL_KEYS:
        value = flags.get(key)
        if value:
            return value
    return ""


def _claim_runtime_hint(flags: dict[str, str]) -> str:
    if flags.get("RUNTIME"):
        return canonical_runtime(flags.get("RUNTIME"))
    if flags.get("BACKEND"):
        return infer_runtime_from_command(flags.get("BACKEND"))
    return _claim_runtime_from_bins(flags)


def _llama_bin_runtime(flags: dict[str, str]) -> str | None:
    if flags.get("LLAMA_BIN") or flags.get("LLAMA_SERVER"):
        return "llama.cpp"
    return None


def _claim_runtime_from_bins(flags: dict[str, str]) -> str:
    llama = _llama_bin_runtime(flags)
    if llama is not None:
        return llama
    if _flags_look_like_vllm(flags):
        return "vllm"
    if _flags_look_like_gguf(flags):
        return "llama.cpp"
    return ""


def _flags_look_like_vllm(flags: dict[str, str]) -> bool:
    return bool(flags.get("VLLM_BIN") or "vllm" in (flags.get("BACKEND") or "").lower())


def _flags_look_like_gguf(flags: dict[str, str]) -> bool:
    return str(flags.get("MODEL_FILE") or "").strip().lower().endswith(".gguf")


def _claim_start_command(directory: Path, is_regular_file) -> str:
    for candidate in _CLAIM_LAUNCH_SCRIPTS:
        script = directory / candidate
        if _is_executable_file(script, is_regular_file):
            quoted = shlex.quote(str(script))
            return f"{quoted} start" if candidate == "ctrl.sh" else quoted
    return ""


def _is_executable_file(path: Path, is_regular_file=path_is_regular_file) -> bool:
    return bool(is_regular_file(path) and os.access(path, os.X_OK))


def _display_from_model_hint(model_hint: str) -> str:
    return Path(model_hint).name if model_hint else ""


def _claim_display_name(flags: dict[str, str], model_hint: str, port: int) -> str:
    display = flags.get("DISPLAY_NAME") or ""
    if not display:
        display = _display_from_model_hint(model_hint)
    return display or f"Port {port}"


def _admit_scan_root_dir(
    resolved: Path,
    seen: set[Path],
    primary: list[Path],
    path_is_dir,
) -> None:
    if path_is_dir(resolved):
        seen.add(resolved)
        primary.append(resolved)


def _admit_resolved_scan_root(
    resolved: Path | None,
    seen: set[Path],
    primary: list[Path],
    path_is_dir,
) -> None:
    if resolved is None or resolved in seen or is_os_runtime_path(resolved):
        return
    _admit_scan_root_dir(resolved, seen, primary, path_is_dir)


def _admit_scan_roots(roots: list[Path], path_is_dir) -> list[Path]:
    primary: list[Path] = []
    seen: set[Path] = set()
    for root in roots:
        _admit_resolved_scan_root(_try_normalize_scan_root(root), seen, primary, path_is_dir)
    primary.sort(key=lambda p: (len(p.parts), str(p)))
    return primary


def _try_normalize_scan_root(root: Path) -> Path | None:
    try:
        return _normalize_scan_root(root)
    except OSError:
        return None


def _hinted_claim_roots(listeners: list[dict[str, Any]] | None) -> list[Path]:
    try:
        live = listeners if listeners is not None else list_listening_tcp()
        return roots_hinted_by_commands([item.get("command") for item in live])
    except Exception:
        return []


def _optional_home_root(path_is_dir, primary_set: set[Path]) -> list[Path]:
    try:
        home = _normalize_scan_root(Path.home())
        if path_is_dir(home) and home not in primary_set:
            return [home]
    except OSError:
        pass
    return []


def _collect_claims(
    roots: list[Path],
    depth: int,
    claims: dict[int, dict[str, Any]],
    walked_remaining: dict[Path, int],
    path_is_dir,
    limit: int,
) -> None:
    for root in roots:
        _walk_claim_tree(root, 0, depth, claims, walked_remaining, path_is_dir, limit)
        if len(claims) >= limit:
            return


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

    Convention only: a directory whose name is a TCP port (2-5 digits) and that
    contains a launch/flags marker. Parent path is whatever the user chose -
    no product-specific roots are assumed. Roots come from:
      • explicit `roots` argument
      • MODEL_SWITCHBOARD_SCAN_ROOTS / config.json scan_roots
      • paths embedded in live process commands / profile START_COMMANDs
      • $HOME shallow claims always unioned (until limit)
        (developer homes are huge -- avoid re-walking when primary already hit)

    Dirent work is bounded within one call: remaining-depth visit map skips
    re-iterdir when roots overlap; is_dir is memoized for the scan.
    """
    primary, path_is_dir = _scan_claim_setup(roots, agent_root, listeners)
    return _collect_primary_and_home_claims(
        primary,
        path_is_dir,
        max_depth=max_depth,
        home_depth=home_depth,
        limit=limit,
    )


def _scan_claim_setup(
    roots: list[Path] | None,
    agent_root: Path | None,
    listeners: list[dict[str, Any]] | None,
) -> tuple[list[Path], Any]:
    hinted = _hinted_claim_roots(listeners)
    is_dir_memo: dict[Path, bool] = {}

    def path_is_dir(path: Path) -> bool:
        return _memoized_is_dir(is_dir_memo, path)

    primary = _admit_scan_roots(
        (roots or []) + _configured_scan_roots(agent_root) + hinted,
        path_is_dir,
    )
    return primary, path_is_dir


def _collect_primary_and_home_claims(
    primary: list[Path],
    path_is_dir,
    *,
    max_depth: int,
    home_depth: int,
    limit: int,
) -> list[dict[str, Any]]:
    claims: dict[int, dict[str, Any]] = {}
    walked_remaining: dict[Path, int] = {}
    _collect_claims(primary, max_depth, claims, walked_remaining, path_is_dir, limit)
    if len(claims) < limit:
        _collect_claims(
            _optional_home_root(path_is_dir, set(primary)),
            home_depth,
            claims,
            walked_remaining,
            path_is_dir,
            limit,
        )
    return [claims[key] for key in sorted(claims)]


def _port_claim_markers(directory: Path) -> list[str]:
    return [m for m in PORT_CLAIM_MARKERS if path_is_regular_file(directory / m)]


def _consider_port_claim(
    directory: Path,
    claims: dict[int, dict[str, Any]],
    limit: int,
    path_is_dir,
) -> None:
    if len(claims) >= limit or is_os_runtime_path(directory):
        return
    _admit_port_claim(directory, claims, path_is_regular_file)


def _admit_port_claim(
    directory: Path,
    claims: dict[int, dict[str, Any]],
    path_is_regular_file,
) -> None:
    name = directory.name
    if not PORT_CLAIM_DIR_RE.fullmatch(name):
        return
    markers = _port_claim_markers(directory)
    if not markers:
        return
    # Directory name is the claim identity / managed port. A mismatched
    # flags.env PORT= must not retarget the claim (e.g. folder 9999 with
    # PORT=22 would otherwise become port-22 and force-stop listeners there).
    port = int(name)
    flags = _claim_flags(directory, path_is_regular_file)
    model_hint = _claim_model_hint(flags)
    claims[port] = _claim_record(
        directory, port, markers, flags, model_hint, path_is_regular_file
    )


def _claim_record(
    directory: Path,
    port: int,
    markers: list[str],
    flags: dict[str, str],
    model_hint: str,
    path_is_regular_file,
) -> dict[str, Any]:
    return {
        "port": port,
        "path": str(directory),
        "markers": markers,
        "display_name": _claim_display_name(flags, model_hint, port),
        "model_hint": model_hint,
        "runtime_hint": first_known(_claim_runtime_hint(flags)),
        "host": flags.get("HOST") or "127.0.0.1",
        "start_command": _claim_start_command(directory, path_is_regular_file),
        "flags": {key: flags[key] for key in _CLAIM_FLAG_EXPORT_KEYS if key in flags},
    }


def _claim_flags(directory: Path, path_is_regular_file) -> dict[str, str]:
    flags_path = directory / "flags.env"
    if path_is_regular_file(flags_path):
        return parse_loose_env_assignments(flags_path)
    return {}


def _skip_claim_walk(
    directory: Path,
    depth: int,
    depth_limit: int,
    claims: dict[int, dict[str, Any]],
    walked_remaining: dict[Path, int],
    limit: int,
) -> bool:
    if depth > depth_limit or len(claims) >= limit or is_os_runtime_path(directory):
        return True
    return _claim_walk_exhausted(directory, depth_limit - depth, walked_remaining)


def _claim_walk_exhausted(
    directory: Path, remaining: int, walked_remaining: dict[Path, int]
) -> bool:
    prior = walked_remaining.get(directory)
    return prior is not None and prior >= remaining


def _walk_claim_tree(
    directory: Path,
    depth: int,
    depth_limit: int,
    claims: dict[int, dict[str, Any]],
    walked_remaining: dict[Path, int],
    path_is_dir,
    limit: int,
) -> None:
    if _skip_claim_walk(directory, depth, depth_limit, claims, walked_remaining, limit):
        return
    remaining = depth_limit - depth
    walked_remaining[directory] = remaining
    _consider_port_claim(directory, claims, limit, path_is_dir)
    if remaining == 0:
        return
    _walk_claim_children(
        directory,
        depth,
        depth_limit,
        claims,
        walked_remaining,
        path_is_dir,
        limit,
    )


def _claim_walk_entries(directory: Path) -> list[Path] | None:
    try:
        return list(directory.iterdir())
    except OSError:
        return None


def _walk_claim_children(
    directory: Path,
    depth: int,
    depth_limit: int,
    claims: dict[int, dict[str, Any]],
    walked_remaining: dict[Path, int],
    path_is_dir,
    limit: int,
) -> None:
    entries = _claim_walk_entries(directory)
    if entries is None:
        return
    for entry in entries:
        if not _is_claim_walk_child(entry, path_is_dir):
            continue
        _walk_claim_tree(
            entry,
            depth + 1,
            depth_limit,
            claims,
            walked_remaining,
            path_is_dir,
            limit,
        )


def _is_claim_walk_child(entry: Path, path_is_dir) -> bool:
    if entry.name in PROFILE_SCAN_SKIP_DIRS or entry.name.startswith("."):
        return False
    return bool(path_is_dir(entry))


def _unowned_agent_owns(
    port: int, command: str | None, agent_ports: set[int]
) -> bool:
    if _unowned_agent_port(port, command, agent_ports):
        return _command_names_agent(command or "")
    return False


def _agent_owns_listener(
    *,
    port: int,
    command: str | None,
    listener_pid: Any,
    self_pid: int,
    agent_ports: set[int],
) -> bool:
    if port in SKIP_LISTEN_PORTS:
        return True
    if _listener_pid_is_self(listener_pid, self_pid):
        agent_ports.add(port)
        return True
    return _unowned_agent_owns(port, command, agent_ports)


def _listener_pid_is_self(listener_pid: Any, self_pid: int) -> bool:
    return listener_pid is not None and int(listener_pid) == self_pid


def _unowned_agent_port(port: int, command: str | None, agent_ports: set[int]) -> bool:
    return port in agent_ports and command_looks_like_model_server(command or "") is False


def _command_names_agent(command: str) -> bool:
    lowered = command.lower()
    return "model_switchboard_agent" in lowered or "model-switchboard-agent" in lowered


def _claimed_discovered_port(port: int, profile_ports: set[int], claim_ports: set[int]) -> bool:
    return port in profile_ports or port in claim_ports


def _classify_after_ownership(
    *,
    port: int,
    command: str | None,
    profile_ports: set[int],
    claim_ports: set[int],
) -> tuple[bool, bool, bool]:
    # Never surface or HTTP-probe internal engine/worker ports. They match
    # "vllm" etc. but are not OpenAI-compatible APIs; each failed probe is
    # up to ~3× DISCOVERY_PROBE_TIMEOUT and serializes /api/status.
    looks_model = command_looks_like_model_server(command)
    if _skip_internal_model_worker(looks_model, command):
        return True, looks_model, False
    claimed = _claimed_discovered_port(port, profile_ports, claim_ports)
    skip = _skip_unclaimed_non_model(looks_model, claimed)
    return skip, looks_model, claimed


def _classify_discovered_listener(
    *,
    port: int,
    command: str | None,
    listener_pid: Any,
    self_pid: int,
    agent_ports: set[int],
    profile_ports: set[int],
    claim_ports: set[int],
) -> tuple[bool, bool, bool]:
    """Return (skip, looks_model, claimed). May add this process's ports to agent_ports."""
    if _agent_owns_listener(
        port=port,
        command=command,
        listener_pid=listener_pid,
        self_pid=self_pid,
        agent_ports=agent_ports,
    ):
        return True, False, False
    return _classify_after_ownership(
        port=port,
        command=command,
        profile_ports=profile_ports,
        claim_ports=claim_ports,
    )


def _skip_internal_model_worker(looks_model: bool, command: str | None) -> bool:
    return bool(looks_model and command_is_internal_model_worker(command))


def _skip_unclaimed_non_model(looks_model: bool, claimed: bool) -> bool:
    return not looks_model and not claimed


def _display_name_from_request_model(request_model: Any) -> Any:
    if isinstance(request_model, str) and ("/" in request_model or request_model.endswith(".gguf")):
        return Path(request_model).name
    return request_model


def _discovery_row(listener: dict[str, Any], probe: ProbeOutcome, command: str | None, port: int) -> dict[str, Any]:
    model_ids = list(probe.model_ids)
    request_model = (model_ids[0] if model_ids else None) or infer_model_from_command(command) or f"port-{port}"
    return {
        "port": port,
        "pid": listener.get("pid"),
        "command": command,
        "bind": listener.get("bind"),
        "runtime": infer_runtime_from_command(command),
        "request_model": request_model,
        "server_ids": model_ids,
        "display_name": _display_name_from_request_model(request_model),
        "ready": probe.ready,
        "base_url": probe.base_url,
        "source": "discovery",
    }


def _listener_priority(
    item: dict[str, Any],
    profile_ports: set[int],
    claim_ports: set[int],
) -> tuple[int, int]:
    port = int(item["port"])
    claimed = 0 if port in profile_ports or port in claim_ports else 1
    return (claimed, port)


def _discovery_probe_state() -> tuple[list[dict[str, Any]], int, int, set[int]]:
    return [], DISCOVERY_PROBE_BUDGET, os.getpid(), {DEFAULT_PORT}


def _discover_prioritized_listeners(
    profile_ports: set[int],
    claim_ports: set[int],
    listeners: list[dict[str, Any]] | None,
) -> list[dict[str, Any]]:
    discovered, probes_left, self_pid, agent_ports = _discovery_probe_state()
    for listener in _prioritized_listeners(profile_ports, claim_ports, listeners):
        probes_left = _consider_discovered_listener(
            listener,
            discovered,
            probes_left,
            self_pid=self_pid,
            agent_ports=agent_ports,
            profile_ports=profile_ports,
            claim_ports=claim_ports,
        )
    return discovered


def discover_live_model_endpoints(
    *,
    profile_ports: set[int] | None = None,
    claim_ports: set[int] | None = None,
    listeners: list[dict[str, Any]] | None = None,
) -> list[dict[str, Any]]:
    """Discover model-looking listeners within a bounded probe budget."""
    return _discover_prioritized_listeners(
        profile_ports or set(),
        claim_ports or set(),
        listeners,
    )


def _prioritized_listeners(
    profile_ports: set[int],
    claim_ports: set[int],
    listeners: list[dict[str, Any]] | None,
) -> list[dict[str, Any]]:
    inventory = list(listeners if listeners is not None else list_listening_tcp())
    return sorted(
        inventory,
        key=lambda item: _listener_priority(item, profile_ports, claim_ports),
    )


def _classified_discovered_listener(
    listener: dict[str, Any],
    *,
    self_pid: int,
    agent_ports: set[int],
    profile_ports: set[int],
    claim_ports: set[int],
) -> tuple[int, Any, bool, bool, bool]:
    port = int(listener["port"])
    skip, looks_model, claimed = _classify_discovered_listener(
        port=port,
        command=listener.get("command"),
        listener_pid=listener.get("pid"),
        self_pid=self_pid,
        agent_ports=agent_ports,
        profile_ports=profile_ports,
        claim_ports=claim_ports,
    )
    return port, listener.get("command"), skip, looks_model, claimed


def _consider_discovered_listener(
    listener: dict[str, Any],
    discovered: list[dict[str, Any]],
    probes_left: int,
    *,
    self_pid: int,
    agent_ports: set[int],
    profile_ports: set[int],
    claim_ports: set[int],
) -> int:
    port, command, skip, looks_model, claimed = _classified_discovered_listener(
        listener,
        self_pid=self_pid,
        agent_ports=agent_ports,
        profile_ports=profile_ports,
        claim_ports=claim_ports,
    )
    return _maybe_append_discovered(
        listener,
        discovered,
        probes_left,
        port=port,
        command=command,
        skip=skip,
        looks_model=looks_model,
        claimed=claimed,
    )


def _maybe_append_discovered(
    listener: dict[str, Any],
    discovered: list[dict[str, Any]],
    probes_left: int,
    *,
    port: int,
    command: str | None,
    skip: bool,
    looks_model: bool,
    claimed: bool,
) -> int:
    if skip:
        return probes_left
    probe, probes_left = _maybe_probe_listener(port, probes_left)
    if first_present(probe.ready, looks_model, claimed):
        discovered.append(_discovery_row(listener, probe, command, port))
    return probes_left


def _maybe_probe_listener(port: int, probes_left: int) -> tuple[ProbeOutcome, int]:
    if probes_left > 0 and port_is_listening(str(port)):
        return probe_model_endpoint(port), probes_left - 1
    return ProbeOutcome(port=port), probes_left


def _discovery_runtime_shape(item: dict[str, Any], source: str) -> tuple[str, str, list[str], str]:
    runtime = first_known(item.get("runtime"), item.get("runtime_hint"))
    label, tags, launch_mode = RUNTIME_SPECS.get(
        runtime, (runtime, ["discovered", "external"], "external")
    )
    if source == "claim":
        return runtime, label, list(dict.fromkeys(["claimed", "launch-folder"] + list(tags))), (
            "command" if item.get("start_command") else "external"
        )
    return runtime, label, list(dict.fromkeys(["discovered", "listening"] + list(tags))), "external"


def _inventory_pid_if_needed(
    pid: Any, port: str, listeners: list[dict[str, Any]] | None
):
    if pid is None and listeners is not None:
        return listener_pid_from_inventory(port, listeners)
    return pid


def _discovery_pid(item: dict[str, Any], port: str, listeners: list[dict[str, Any]] | None):
    return _inventory_pid_if_needed(item.get("pid"), port, listeners)


def _discovery_request_model(item: dict[str, Any], port: str) -> str:
    return str(item.get("request_model") or item.get("model_hint") or f"port-{port}")


def _discovery_alive_pid(item: dict[str, Any], port: str, listeners: list[dict[str, Any]] | None):
    pid = _discovery_pid(item, port, listeners)
    if pid and process_is_alive(pid):
        return pid
    return None


def _discovery_memory(pid) -> tuple[Any, Any]:
    if not pid:
        return None, None
    return process_rss_mb(pid), process_vram_mb(pid)


def status_dict_from_discovery(
    item: dict[str, Any],
    *,
    source: str,
    profile_name: str | None = None,
    listeners: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Shape a discovery/claim record like a controller status entry."""
    port = str(item.get("port", ""))
    runtime, label, tags, launch_mode = _discovery_runtime_shape(item, source)
    pid = _discovery_alive_pid(item, port, listeners)
    request_model = _discovery_request_model(item, port)
    served = (item.get("server_ids") or [None])[0]
    rss_mb, vram_mb = _discovery_memory(pid)
    return _discovery_status_fields(
        item,
        source=source,
        profile_name=profile_name,
        port=port,
        runtime=runtime,
        label=label,
        tags=tags,
        launch_mode=launch_mode,
        pid=pid,
        request_model=request_model,
        served=served,
        rss_mb=rss_mb,
        vram_mb=vram_mb,
    )


def _discovery_status_fields(
    item: dict[str, Any],
    *,
    source: str,
    profile_name: str | None,
    port: str,
    runtime: str,
    label: str,
    tags: list[str],
    launch_mode: str,
    pid,
    request_model: str,
    served,
    rss_mb,
    vram_mb,
) -> dict[str, Any]:
    return {
        **_discovery_identity_fields(
            item,
            source=source,
            profile_name=profile_name,
            port=port,
            runtime=runtime,
            label=label,
            tags=tags,
            launch_mode=launch_mode,
            request_model=request_model,
            served=served,
        ),
        **_discovery_process_fields(item, pid=pid, rss_mb=rss_mb, vram_mb=vram_mb),
    }


def _discovery_identity_fields(
    item: dict[str, Any],
    *,
    source: str,
    profile_name: str | None,
    port: str,
    runtime: str,
    label: str,
    tags: list[str],
    launch_mode: str,
    request_model: str,
    served,
) -> dict[str, Any]:
    return {
        "profile": first_present(profile_name, f"discovered-{port}"),
        "display_name": first_present(item.get("display_name"), Path(request_model).name, f"Port {port}"),
        "runtime": runtime,
        "runtime_label": label,
        "runtime_tags": tags,
        "launch_mode": launch_mode,
        "host": first_present(item.get("host"), "127.0.0.1"),
        "port": port,
        "base_url": first_present(item.get("base_url"), f"http://127.0.0.1:{port}/v1"),
        "request_model": request_model,
        "server_model_id": str(first_present(served, request_model)),
        "source": source,
    }


def _discovery_process_fields(
    item: dict[str, Any],
    *,
    pid,
    rss_mb,
    vram_mb,
) -> dict[str, Any]:
    return {
        "pid": pid,
        "running": bool(pid),
        "ready": bool(item.get("ready")),
        "server_ids": first_present(item.get("server_ids"), item.get("model_ids"), []),
        "rss_mb": rss_mb,
        "vram_mb": vram_mb,
        "command": item.get("command") if pid else None,
        "log_path": item.get("log_path"),
        "missing_artifacts": first_present(item.get("missing_artifacts"), []),
        "serving": item.get("serving"),
    }


def _has_weight_suffix(value: str) -> bool:
    lowered = value.lower()
    return any(lowered.endswith(suffix) for suffix in WEIGHT_SUFFIXES)


def _claim_weight_file(flags_safe: dict[str, Any], model_raw: str, request_s: str) -> str:
    # Prefer explicit MODEL_FILE; otherwise only treat MODEL= as a file when it
    # has a weight suffix. HF/vLLM directories stay on MODEL_PATH / MODEL_DIR so
    # missing_artifacts does not false-positive on live directory checkpoints.
    model_file_flag = str(flags_safe.get("MODEL_FILE") or "").strip()
    if model_file_flag:
        return model_file_flag
    return _inferred_weight_file(model_raw, request_s)


def _inferred_weight_file(model_raw: str, request_s: str) -> str:
    if _has_weight_suffix(model_raw):
        return model_raw
    if request_s.endswith(".gguf") and not is_placeholder_model_name(request_s):
        return request_s
    return ""


def _claim_model_directory(flags_safe: dict[str, Any], model_raw: str, model_file: str) -> str:
    model_dir = str(flags_safe.get("MODEL_DIR") or flags_safe.get("MODEL_REPO") or "")
    return _explicit_or_inferred_model_dir(model_dir, model_raw, model_file)


def _explicit_or_inferred_model_dir(model_dir: str, model_raw: str, model_file: str) -> str:
    if model_dir or not model_raw or model_file:
        return model_dir
    return _inferred_model_directory(model_raw)


def _inferred_model_directory(model_raw: str) -> str:
    candidate = Path(model_raw).expanduser()
    if path_is_dir(candidate) or (
        looks_like_local_fs_path(model_raw) and not _has_weight_suffix(model_raw)
    ):
        return model_raw
    return ""


def _claim_launch_scripts(claim_path: str, start: str) -> tuple[str, str]:
    if not claim_path:
        return start, ""
    directory = Path(claim_path)
    ctrl = _ctrl_sh_commands(directory, start)
    if ctrl is not None:
        return ctrl
    return _launch_sh_commands(directory, start)


def _ctrl_sh_commands(directory: Path, start: str) -> tuple[str, str] | None:
    ctrl = directory / "ctrl.sh"
    if not _is_executable_file(ctrl):
        return None
    quoted = shlex.quote(str(ctrl))
    return start or f"{quoted} start", f"{quoted} stop"


def _launch_sh_commands(directory: Path, start: str) -> tuple[str, str]:
    launch = directory / "launch.sh"
    if _is_executable_file(launch):
        return start or shlex.quote(str(launch)), ""
    return start, ""


def _claim_server_model_id(flags_safe: dict[str, Any], request_s: str) -> str:
    explicit = flags_safe.get("SERVER_MODEL_ID")
    if explicit:
        return str(explicit)
    if "/" in request_s or request_s.endswith(".gguf"):
        return Path(request_s).name
    return request_s


def _claim_flags_dict(claim: dict[str, Any]) -> dict[str, Any]:
    flags = claim.get("flags")
    return flags if isinstance(flags, dict) else {}


def _claim_profile_values(claim: dict[str, Any], port: str) -> dict[str, str]:
    name = f"port-{port}"
    claim_path = claim.get("path") or ""
    request_s = str(first_present(claim.get("model_hint"), f"port-{port}"))
    flags_safe = _claim_flags_dict(claim)
    start, stop = _claim_launch_scripts(claim_path, (claim.get("start_command") or "").strip())
    model_raw = str(first_present(flags_safe.get("MODEL"), flags_safe.get("MODEL_PATH"), request_s))
    model_file = _claim_weight_file(flags_safe, model_raw, request_s)
    values = _claim_profile_core_values(
        name=name,
        claim=claim,
        claim_path=claim_path,
        request_s=request_s,
        flags_safe=flags_safe,
        start=start,
        port=port,
        model_raw=model_raw,
        model_file=model_file,
    )
    return _apply_claim_launch_flags(values, start, stop)


def _apply_claim_launch_flags(values: dict[str, str], start: str, stop: str) -> dict[str, str]:
    if stop:
        values["STOP_COMMAND"] = stop
    if not start:
        values["LAUNCH_MODE"] = "external"
    return values


def _claim_profile_core_values(
    *,
    name: str,
    claim: dict[str, Any],
    claim_path: str,
    request_s: str,
    flags_safe: dict[str, Any],
    start: str,
    port: str,
    model_raw: str,
    model_file: str,
) -> dict[str, str]:
    return {
        "DISPLAY_NAME": str(first_present(claim.get("display_name"), Path(request_s).name, name)),
        "RUNTIME": first_known(claim.get("runtime_hint")),
        "REQUEST_MODEL": request_s,
        "SERVER_MODEL_ID": _claim_server_model_id(flags_safe, request_s),
        "PORT": port,
        "HOST": str(first_present(claim.get("host"), "127.0.0.1")),
        "START_COMMAND": start,
        "WORKING_DIRECTORY": claim_path,
        "LOG_ALIAS": f"launch-{port}",
        "MODEL_PATH": model_raw,
        "MODEL_FILE": model_file,
        "MODEL_DIR": _claim_model_directory(flags_safe, model_raw, model_file),
        "MODEL_REPO": str(flags_safe.get("MODEL_REPO") or ""),
    }


def _claim_healthcheck_any_id(values: dict[str, str]) -> bool:
    request_s = values["REQUEST_MODEL"]
    return is_placeholder_model_name(request_s) and values.get("SERVER_MODEL_ID") in (
        None,
        "",
        request_s,
    )


def profile_from_claim(claim: dict[str, Any]) -> Profile:
    """Build a manage-able Profile from a claimed port folder (no invented flags)."""
    port = str(claim.get("port") or "")
    if not port:
        raise InvalidProfileError("claim missing port")
    values = _claim_profile_values(claim, port)
    return Profile(
        name=f"port-{port}",
        values=values,
        tags=["claimed", "launch-folder"],
        origin="claim",
        healthcheck_any_id=_claim_healthcheck_any_id(values),
    )

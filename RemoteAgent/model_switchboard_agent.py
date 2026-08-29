#!/usr/bin/env python3
"""Stdlib remote gateway for launching and managing model servers."""

from __future__ import annotations

import argparse
import getpass
import hmac
import json
import os
import re
import shlex
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable

_AGENT_DIR = Path(__file__).resolve().parent
if str(_AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(_AGENT_DIR))

from agent_core import (
    AgentError,
    DEFAULT_PORT,
    FORCE_TERMINATE_TIMEOUT_SECONDS,
    InvalidConfigurationError,
    InvalidJSONError,
    InvalidProfileError,
    LOOPBACK_HOSTS,
    OperationFailedError,
    PROFILE_KEY_RE,
    PROFILE_SCAN_SKIP_DIRS,
    Profile,
    ProfileConflictError,
    ProfileNotFoundError,
    RUNTIME_ALIASES,
    RUNTIME_SPECS,
    SCAN_ROOTS_ENV,
    TERMINATE_TIMEOUT_SECONDS,
    UnsupportedError,
    UsageError,
    _CPU_PREV,
    _CPU_SAMPLE_LOCK,
    _GPU_METRICS_CACHE,
    _GPU_METRICS_TTL_SECONDS,
    _NVIDIA_SMI_MISSING,
    _NoHTTPRedirectHandler,
    _WEIGHT_SUFFIXES,
    _apply_unified_memory_vram,
    _looks_like_local_fs_path,
    _nvidia_smi_number,
    _parse_env_value,
    _proc_stat_table_available,
    _read_proc_meminfo,
    _run_nvidia_smi_query,
    _sample_cpu_percent,
    _sample_memory,
    _signal_process_tree,
    _urlopen_no_redirect,
    agent_config_path,
    canonical_runtime,
    first_known,
    gpu_metrics_snapshot,
    is_loopback,
    is_placeholder_model_name,
    listener_pid,
    listener_pid_from_inventory,
    load_agent_config,
    missing_local_model_artifacts,
    parse_env_profile,
    parse_json_profile,
    parse_tag_string,
    port_is_listening,
    port_listening_from_inventory,
    process_command,
    process_is_alive,
    process_is_zombie,
    process_ps_state,
    process_rss_mb,
    process_stat_state,
    process_vram_mb,
    reap_child,
    resolve_model_artifact_fields,
    terminate_process_tree,
)
from discovery import (  # noqa: E402
    PORT_CLAIM_DIR_RE,
    PORT_CLAIM_MARKERS,
    _configured_scan_roots,
    clear_listening_tcp_cache,
    command_looks_like_model_server,
    discover_live_model_endpoints,
    list_listening_tcp,
    profile_from_claim,
    roots_hinted_by_commands,
    scan_port_claim_directories,
    status_dict_from_discovery,
)

AGENT_VERSION = "1.1.4"

MINIMUM_TOKEN_BYTES = 16

MAXIMUM_BODY_BYTES = 64 * 1024

WATCHDOG_INTERVAL_SECONDS = 30.0

WATCHDOG_SUPPRESSION_SECONDS = 45.0

STOP_WAIT_SECONDS = 90.0

HEALTH_TIMEOUT_SECONDS = 1.5

PROFILES_DIR_ENV = "MODEL_SWITCHBOARD_PROFILES_DIR"

PROFILE_SIGNAL_KEYS = frozenset({
    "REQUEST_MODEL",
    "PORT",
    "BASE_URL",
    "START_COMMAND",
    "MODEL_FILE",
    "MODEL_PATH",
    "MODEL_REPO",
    "SERVER_MODEL_ID",
    "RUNTIME",
    "DISPLAY_NAME",
})

PROFILE_SCAN_MAX_DEPTH = 5

PROFILE_SCAN_MAX_CANDIDATES = 8

def is_tailscale_ip(address: str) -> bool:
    """Tailscale assigns IPv4 from the CGNAT range 100.64.0.0/10."""
    parts = address.split(".")
    if len(parts) != 4:
        return False
    try:
        first, second = int(parts[0]), int(parts[1])
    except ValueError:
        return False
    return first == 100 and 64 <= second <= 127

@dataclass(frozen=True)
class TailscalePresence:
    """This host's tailnet presence — present / absent / failed (L19).

    Smart-constructor union: the two-optional tuple is gone. A failed or
    absent presence carries no ipv4, and a present presence carries no error —
    the illegal combinations are unrepresentable.
    """

    _ipv4: str | None = None
    _dns_name: str | None = None
    _error: str | None = None

    @classmethod
    def present_with(cls, ipv4: str, dns_name: str | None = None) -> "TailscalePresence":
        return cls(_ipv4=ipv4, _dns_name=dns_name)

    @classmethod
    def absent(cls) -> "TailscalePresence":
        return cls()

    @classmethod
    def failed(cls, error: str) -> "TailscalePresence":
        return cls(_error=error)

    @property
    def present(self) -> bool:
        return self._ipv4 is not None

    @property
    def ipv4(self) -> str | None:
        return self._ipv4

    @property
    def dns_name(self) -> str | None:
        return self._dns_name

    @property
    def error(self) -> str | None:
        return self._error

def tailscale_status() -> TailscalePresence:
    """Tailnet presence for this host (CLI-backed, no interface sniffing).

    Requires the Tailscale CLI (`tailscale status` or `tailscale ip`). Interface
    scans for any CGNAT address are intentionally not used for bind decisions —
    that could treat a non-tailnet 100.64/10 address as "tailnet-only" and skip
    the normal non-loopback auth rules.
    """
    status_failed: str | None = None
    try:
        result = subprocess.run(
            ["tailscale", "status", "--json"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if result.returncode == 0:
            parsed = json.loads(result.stdout)
            self_info = parsed.get("Self") or {}
            ips = [ip for ip in self_info.get("TailscaleIPs") or [] if is_tailscale_ip(ip)]
            dns_name = (self_info.get("DNSName") or "").rstrip(".") or None
            if ips:
                return TailscalePresence.present_with(ips[0], dns_name)
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        status_failed = f"tailscale status failed: {error}"
    try:
        result = subprocess.run(
            ["tailscale", "ip", "-4"],
            capture_output=True, text=True, timeout=5, check=False,
        )
        if result.returncode == 0:
            for line in result.stdout.split():
                if is_tailscale_ip(line.strip()):
                    return TailscalePresence.present_with(line.strip(), None)
    except (OSError, subprocess.TimeoutExpired) as error:
        status_failed = status_failed or f"tailscale ip failed: {error}"
    if status_failed:
        return TailscalePresence.failed(status_failed)
    return TailscalePresence.absent()

class ProfileRepository:
    def __init__(self, directory: Path):
        self.directory = directory

    def load(self) -> dict[str, Profile]:
        if not self.directory.is_dir():
            return {}
        profiles: dict[str, Profile] = {}
        files = sorted(
            (
                path
                for path in self.directory.iterdir()
                if path.suffix.lower() in (".env", ".json") and not path.name.startswith(".")
            ),
            key=lambda path: path.name.lower(),
        )
        for file in files:
            name = file.stem
            try:
                values = (
                    parse_json_profile(file)
                    if file.suffix.lower() == ".json"
                    else parse_env_profile(file)
                )
                profiles[name] = Profile(name=name, values=values)
            except (AgentError, OSError, ValueError, json.JSONDecodeError) as error:
                # One bad file must not take down /api/status for the whole host.
                sys.stderr.write(f"[profiles] skipping {file.name}: {error}\n")
        # One-level nested port-claim folders (e.g. <dir>/8027/flags.env → port-8027).
        # Flat files win on name collision via setdefault.
        try:
            directory = self.directory.expanduser().resolve()
        except OSError:
            directory = self.directory
        claims = scan_port_claim_directories(
            roots=[self.directory],
            agent_root=None,
            listeners=[],
        )
        for claim in claims:
            claim_path = Path(str(claim.get("path") or ""))
            try:
                claim_path.resolve().relative_to(directory)
            except (ValueError, OSError):
                continue
            try:
                profile = profile_from_claim(claim)
            except (AgentError, OSError, TypeError, ValueError) as error:
                sys.stderr.write(
                    f"[profiles] skipping claim {claim.get('path')}: {error}\n"
                )
                continue
            profiles.setdefault(profile.name, profile)
        return profiles

    def profile(self, name: str) -> Profile:
        profile = self.load().get(name)
        if profile is None:
            raise ProfileNotFoundError(name)
        return profile

    def conflicts(self, profiles: dict[str, Profile]) -> dict[str, tuple[str, list[str]]]:
        groups: dict[str, list[str]] = {}
        for profile in profiles.values():
            identity = profile.endpoint_identity
            if identity:
                groups.setdefault(identity, []).append(profile.name)
        result: dict[str, tuple[str, list[str]]] = {}
        for endpoint, names in groups.items():
            if len(names) > 1:
                for name in sorted(names):
                    result[name] = (endpoint, sorted(n for n in names if n != name))
        return result

    def ensure_unique(self, name: str, action: str, profiles: dict[str, Profile]) -> None:
        conflict = self.conflicts(profiles).get(name)
        if conflict:
            endpoint, others = conflict
            raise ProfileConflictError(
                f"Cannot {action} {name}: endpoint {endpoint} is also configured for {', '.join(others)}."
            )

def build_start_command(profile: Profile) -> str:
    """Return the shell command that launches this profile's model server."""
    explicit = (profile.get("START_COMMAND") or "").strip()
    if explicit:
        return explicit
    if (profile.get("LAUNCH_MODE") or "").lower() == "external":
        raise UnsupportedError(
            f"{profile.name}: externally managed endpoint; set START_COMMAND or a launch claim to start"
        )

    runtime = profile.runtime
    host = profile.get("HOST") or "127.0.0.1"
    port = profile.endpoint_port
    extra = (profile.get("EXTRA_ARGS") or "").strip()
    model = profile.get("MODEL_PATH") or profile.get("MODEL_REPO") or profile.request_model
    model_file = profile.get("MODEL_FILE") or profile.get("MODEL_PATH") or ""

    if runtime == "vllm":
        command = (
            f"vllm serve {shlex.quote(model)} --host {shlex.quote(host)} --port {shlex.quote(port)}"
            f" --served-model-name {shlex.quote(profile.server_model_id)}"
        )
    elif runtime == "llama.cpp":
        if not model_file:
            raise InvalidProfileError(
                f"{profile.name}: llama.cpp launches need MODEL_FILE (or MODEL_PATH) or an explicit START_COMMAND"
            )
        command = (
            f"llama-server -m {shlex.quote(model_file)} --host {shlex.quote(host)}"
            f" --port {shlex.quote(port)} -a {shlex.quote(profile.server_model_id)}"
        )
    elif runtime == "sglang":
        command = (
            f"python3 -m sglang.launch_server --model-path {shlex.quote(model)}"
            f" --host {shlex.quote(host)} --port {shlex.quote(port)}"
        )
    elif runtime == "tgi":
        command = (
            f"text-generation-launcher --model-id {shlex.quote(model)}"
            f" --hostname {shlex.quote(host)} --port {shlex.quote(port)}"
        )
    else:
        _, _, launch_mode = profile.runtime_spec
        if launch_mode == "external":
            raise UnsupportedError(
                f"{profile.name}: runtime {runtime} is externally managed; the agent only reports its health"
            )
        raise InvalidProfileError(
            f"{profile.name}: no launch template for runtime {runtime}; set START_COMMAND"
        )

    if extra:
        command = f"{command} {extra}"
    venv = (profile.get("VENV") or "").strip()
    if venv:
        activate = Path(venv).expanduser() / "bin" / "activate"
        command = f"source {shlex.quote(str(activate))} && {command}"
    return command

def host_metrics_payload() -> dict[str, Any]:
    """SparkDash-like host snapshot for the Mac Remote Hosts panel.

    Units:
    - CPU/GPU util: percent 0-100
    - temp: Celsius
    - memory/VRAM: megabytes (MiB from nvidia-smi; MB from /proc)
    Graceful when nvidia-smi or /proc are absent (old agent / non-GPU host).
    """
    gpu = gpu_metrics_snapshot()
    mem = _sample_memory()
    cpu_percent = _sample_cpu_percent()
    hostname = socket.gethostname()
    # Copy GPU dicts so UMA fill does not mutate the nvidia-smi TTL cache.
    gpus = [dict(entry) for entry in (gpu.get("gpus") or [])]
    gpu_source = gpu.get("source") or "unavailable"
    vram_by_pid = gpu.get("vram_by_pid") or {}
    _apply_unified_memory_vram(gpus, vram_by_pid, mem if isinstance(mem, dict) else None)
    return {
        "host": hostname,
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "cpu_percent": cpu_percent,
        "memory": mem,
        "gpus": gpus,
        "gpu_source": gpu_source,
        "processes": [
            {"pid": pid, "vram_mb": round(float(mb) * 10) / 10}
            for pid, mb in sorted((gpu.get("vram_by_pid") or {}).items())
        ],
        "agent_version": AGENT_VERSION,
    }


def _default_root() -> Path:
    return Path.home() / ".local/share/model-switchboard-agent"

def preferred_profiles_directory() -> Path:
    """Visible default: ~/model-profiles (not buried under the agent install root)."""
    return Path.home() / "model-profiles"

def save_agent_config(root: Path, updates: dict[str, Any]) -> Path:
    root = root.expanduser()
    root.mkdir(parents=True, exist_ok=True)
    path = agent_config_path(root)
    payload = load_agent_config(root)
    payload.update(updates)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    try:
        path.chmod(0o600)
    except OSError:
        pass
    return path

def save_profiles_directory(root: Path, profiles_dir: Path) -> Path:
    resolved = profiles_dir.expanduser().resolve()
    save_agent_config(root, {"profiles_dir": str(resolved)})
    return resolved

def _directory_has_profile_files(directory: Path) -> bool:
    if not directory.is_dir():
        return False
    try:
        for path in directory.iterdir():
            if path.suffix.lower() in (".env", ".json") and not path.name.startswith("."):
                if path.name.endswith(".example"):
                    continue
                return True
    except OSError:
        return False
    return False

def _directory_has_port_claims(directory: Path) -> bool:
    """True when directory has a one-level port-claim child (flags.env / launch.sh / ...)."""
    if not directory.is_dir():
        return False
    try:
        for path in directory.iterdir():
            try:
                if not path.is_dir() or not PORT_CLAIM_DIR_RE.fullmatch(path.name):
                    continue
            except OSError:
                continue
            if any((path / marker).is_file() for marker in PORT_CLAIM_MARKERS):
                return True
    except OSError:
        return False
    return False

def _directory_has_loadable_profiles(directory: Path) -> bool:
    return _directory_has_profile_files(directory) or _directory_has_port_claims(directory)

def _profiles_dir_from_scan_roots(root: Path) -> Path | None:
    """First configured scan_roots entry that already holds port-claim markers."""
    for scan_root in _configured_scan_roots(root):
        try:
            resolved = scan_root.expanduser().resolve()
        except OSError:
            continue
        if _directory_has_port_claims(resolved):
            return resolved
    return None

def resolve_profiles_directory(
    root: Path,
    explicit: Path | str | None = None,
) -> Path:
    """Pick the profiles folder without inventing profile contents.

    Order: CLI/explicit → env → config.json profiles_dir (when it has loadable
    flat profiles or port-claim folders) → existing <root>/model-profiles
    (legacy installs with real profiles) → ~/model-profiles (when populated) →
    first configured scan_roots entry with port-claim markers → configured
    profiles_dir if set but empty → ~/model-profiles.
    """
    if explicit is not None:
        return Path(explicit).expanduser().resolve()
    env = (os.environ.get(PROFILES_DIR_ENV) or "").strip()
    if env:
        return Path(env).expanduser().resolve()

    configured: Path | None = None
    configured_raw = load_agent_config(root).get("profiles_dir")
    if isinstance(configured_raw, str) and configured_raw.strip():
        configured = Path(configured_raw).expanduser().resolve()
        if _directory_has_loadable_profiles(configured):
            return configured

    legacy = root.expanduser() / "model-profiles"
    if _directory_has_loadable_profiles(legacy):
        return legacy.resolve()

    preferred = preferred_profiles_directory().resolve()
    if _directory_has_loadable_profiles(preferred):
        return preferred

    scan_hit = _profiles_dir_from_scan_roots(root)
    if scan_hit is not None:
        return scan_hit

    if configured is not None:
        return configured
    return preferred

def _peek_profile_keys(path: Path) -> set[str]:
    """Best-effort key set for scan scoring — never executes file contents."""
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return set()
    if path.suffix.lower() == ".json":
        try:
            parsed = json.loads(text)
        except json.JSONDecodeError:
            return set()
        if not isinstance(parsed, dict):
            return set()
        return {str(key) for key in parsed.keys()}
    keys: set[str] = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export "):].strip()
        equals = line.find("=")
        if equals <= 0:
            continue
        key = line[:equals].strip()
        if PROFILE_KEY_RE.match(key):
            keys.add(key)
    return keys

def looks_like_profile_file(path: Path) -> bool:
    if path.suffix.lower() not in (".env", ".json") or path.name.startswith("."):
        return False
    # Skip installer samples that are not live profiles yet.
    if ".example" in path.name:
        return False
    keys = _peek_profile_keys(path)
    if not keys:
        return False
    signals = keys & PROFILE_SIGNAL_KEYS
    if "REQUEST_MODEL" in signals:
        return True
    if "START_COMMAND" in signals:
        return True
    if "PORT" in signals or "BASE_URL" in signals:
        return bool(signals & {"RUNTIME", "MODEL_FILE", "MODEL_PATH", "MODEL_REPO", "DISPLAY_NAME"})
    return False

def scan_profile_directories(
    home: Path | None = None,
    *,
    max_depth: int = PROFILE_SCAN_MAX_DEPTH,
    limit: int = PROFILE_SCAN_MAX_CANDIDATES,
) -> list[dict[str, Any]]:
    """Find directories that already hold Switchboard-shaped launch .env/.json files.

    Does not invent flags — only groups files an AI or user already wrote
    (often `model.env`, `qwen.env`, …) by parent folder.
    """
    home = (home or Path.home()).expanduser()
    tallies: dict[Path, list[str]] = {}

    def walk(directory: Path, depth: int) -> None:
        if depth > max_depth:
            return
        try:
            entries = list(directory.iterdir())
        except OSError:
            return
        for entry in entries:
            name = entry.name
            if name in PROFILE_SCAN_SKIP_DIRS:
                continue
            # Skip hidden directories; still consider visible files.
            try:
                is_dir = entry.is_dir()
            except OSError:
                continue
            if is_dir:
                if name.startswith("."):
                    continue
                walk(entry, depth + 1)
                continue
            if not looks_like_profile_file(entry):
                continue
            parent = entry.parent.resolve()
            tallies.setdefault(parent, []).append(entry.name)

    walk(home, 0)
    # Always consider the preferred default and common legacy path.
    for extra in (preferred_profiles_directory(), _default_root() / "model-profiles"):
        try:
            resolved = extra.expanduser().resolve()
        except OSError:
            continue
        if resolved in tallies:
            continue
        if not resolved.is_dir():
            continue
        try:
            children = list(resolved.iterdir())
        except OSError:
            continue
        for path in children:
            if looks_like_profile_file(path):
                tallies.setdefault(resolved, []).append(path.name)

    ranked = sorted(
        tallies.items(),
        key=lambda item: (-len(item[1]), str(item[0])),
    )
    results: list[dict[str, Any]] = []
    for directory, files in ranked[:limit]:
        unique_files = sorted(set(files))
        results.append({
            "path": str(directory),
            "profile_count": len(unique_files),
            "files": unique_files[:12],
        })
    return results

def prompt_profiles_directory(
    root: Path,
    *,
    current: Path,
    input_func: Callable[[str], str] | None = None,
    home: Path | None = None,
) -> Path:
    """Interactive: confirm a scanned folder or paste another path."""
    reader = input_func or input
    candidates = scan_profile_directories(home)
    print("Model profiles are plain .env/.json launch files (ports, START_COMMAND, …).")
    print("Switchboard only needs the folder that already holds them — it will not")
    print("author flags for every runtime fork.")
    print()
    print(f"Current profiles folder: {current}")
    if candidates:
        print("Found folders that look like they already have model launch profiles:")
        for index, candidate in enumerate(candidates, start=1):
            preview = ", ".join(candidate["files"][:4])
            extra = "" if len(candidate["files"]) <= 4 else ", …"
            print(
                f"  [{index}] {candidate['path']} "
                f"({candidate['profile_count']} file(s): {preview}{extra})"
            )
        print("  [Enter] keep current")
        print("  [0]     use ~/model-profiles (create if needed)")
        print("  or paste another folder path")
    else:
        print("No launch-looking .env/.json folders found under your home directory.")
        print("  [Enter] keep current / use ~/model-profiles")
        print("  or paste the folder path where your model .env files live")
    print()
    try:
        answer = reader("Profiles folder? ").strip()
    except EOFError:
        answer = ""
    if not answer:
        if current.exists() or _directory_has_profile_files(current):
            chosen = current
        elif candidates:
            chosen = Path(candidates[0]["path"])
        else:
            chosen = preferred_profiles_directory()
    elif answer == "0":
        chosen = preferred_profiles_directory()
    elif answer.isdigit() and candidates:
        index = int(answer)
        if 1 <= index <= len(candidates):
            chosen = Path(candidates[index - 1]["path"])
        else:
            raise UsageError(f"No candidate numbered {index}")
    else:
        chosen = Path(answer)
    chosen = chosen.expanduser().resolve()
    chosen.mkdir(parents=True, exist_ok=True)
    save_profiles_directory(root, chosen)
    print(f"Using profiles folder: {chosen}")
    return chosen

@dataclass
class AgentConfiguration:
    root: Path
    host: str = "127.0.0.1"
    port: int = DEFAULT_PORT
    auth_token: str | None = None
    unsafe_bind: bool = False
    tailscale_bind: bool = False
    # Tailscale binds require a token unless this is set (personal tailnet opt-out).
    allow_unauthenticated: bool = False
    profiles_dir: Path | None = None

    def __post_init__(self) -> None:
        token = (self.auth_token or "").strip()
        if token and len(token.encode("utf-8")) < MINIMUM_TOKEN_BYTES:
            raise InvalidConfigurationError(
                f"auth token must be at least {MINIMUM_TOKEN_BYTES} bytes"
            )
        if self.tailscale_bind and not is_tailscale_ip(self.host):
            raise InvalidConfigurationError(
                f"--tailscale bind resolved a non-Tailscale address: {self.host}"
            )
        if self.tailscale_bind and not token and not self.allow_unauthenticated:
            raise InvalidConfigurationError(
                "--tailscale requires a bearer auth token "
                "(--auth-token / --auth-token-file), or pass "
                "--allow-unauthenticated for a personal tailnet"
            )
        if not is_loopback(self.host) and not self.tailscale_bind:
            # Plain LAN / non-loopback: unsafe-bind + token always required.
            if not self.unsafe_bind:
                raise InvalidConfigurationError(
                    f"non-loopback agent bind requires --unsafe-bind: {self.host}"
                )
            if not token:
                raise InvalidConfigurationError(
                    "non-loopback agent bind requires a bearer auth token"
                )
        self.auth_token = token or None
        self.root = self.root.expanduser()
        self.profiles_dir = resolve_profiles_directory(self.root, self.profiles_dir)

    @property
    def profiles_directory(self) -> Path:
        assert self.profiles_dir is not None
        return self.profiles_dir

    @property
    def run_directory(self) -> Path:
        return self.root / "run"

    @property
    def active_profile_file(self) -> Path:
        return self.run_directory / "active-profile"

    @property
    def systemd_unit_path(self) -> Path:
        return Path.home() / ".config/systemd/user/model-switchboard-agent.service"

ANY_MODEL_ID = "<any-model-id>"

def openai_model_id_matches(expected: str | None, ids: list[str], *aliases: str) -> bool:
    """True when *expected* matches a /v1/models id loosely.

    Explicit matching rule (tested): an exact id match, or basename equality
    in either direction — llama.cpp often returns a full weights path as `id`
    while claim profiles store SERVER_MODEL_ID as the basename (or the
    reverse). Explicit aliases (e.g. REQUEST_MODEL) join the candidate set.
    L23: None (no expected id) NEVER matches — identity must be verifiable.
    Pass ANY_MODEL_ID to accept any non-empty id list explicitly.
    """
    if expected is ANY_MODEL_ID or expected == ANY_MODEL_ID:
        return bool(ids)
    if not expected:
        return False
    candidates = {expected}
    for alias in aliases:
        alias_s = (alias or "").strip()
        if alias_s:
            candidates.add(alias_s)
    id_set = set(ids)
    if candidates & id_set:
        return True
    id_names = {Path(item).name for item in ids}
    for candidate in list(candidates):
        if Path(candidate).name in id_names:
            return True
        if candidate in id_names:
            return True
    return False

class AgentService:
    def __init__(self, configuration: AgentConfiguration):
        self.configuration = configuration
        self.profiles = ProfileRepository(configuration.profiles_directory)
        self._mutation_lock = threading.RLock()
        self._watchdog_suppressed_until = 0.0
        self._watchdog_timer: threading.Timer | None = None
        # Profiles started by *this* agent process. Crash-recovery restarts only
        # these — an agent reboot / login never spontaneously loads a model.
        self._supervised: set[str] = set()
        self._benchmark_lock = threading.Lock()
        self._benchmark_running = False

    def resolve_profile(self, name: str) -> Profile:
        """Profiles folder first; then claimed port folders (port-N); never invent."""
        loaded = self.profiles.load()
        if name in loaded:
            return loaded[name]
        port: int | None = None
        if name.startswith("port-"):
            try:
                port = int(name.removeprefix("port-"))
            except ValueError:
                port = None
        elif name.startswith("discovered-"):
            try:
                port = int(name.removeprefix("discovered-"))
            except ValueError:
                port = None
        if port is not None:
            # One inventory for claim scan + live discovery (no second ss/lsof).
            listeners = list_listening_tcp()
            claims = scan_port_claim_directories(
                agent_root=self.configuration.root,
                listeners=listeners,
            )
            for claim in claims:
                try:
                    if int(claim["port"]) == port:
                        return profile_from_claim(claim)
                except (KeyError, TypeError, ValueError):
                    continue
            live = discover_live_model_endpoints(
                profile_ports=set(),
                claim_ports={port},
                listeners=listeners,
            )
            for item in live:
                try:
                    if int(item["port"]) != port:
                        continue
                except (KeyError, TypeError, ValueError):
                    continue
                request = str(item.get("request_model") or f"port-{port}")
                return Profile(
                    name=name,
                    values={
                        "DISPLAY_NAME": str(item.get("display_name") or request),
                        # L07: canonical_runtime is the single owner of the
                        # "absent runtime stays unknown" rule.
                        "RUNTIME": canonical_runtime(item.get("runtime")),
                        "REQUEST_MODEL": request,
                        "SERVER_MODEL_ID": request,
                        "PORT": str(port),
                        "HOST": "127.0.0.1",
                        "LAUNCH_MODE": "external",
                        "START_COMMAND": "",
                        "LOG_ALIAS": f"discovered-{port}",
                    },
                )
        raise ProfileNotFoundError(name)

    # -- status ------------------------------------------------------------

    def status_payload(self, selected: list[str] | None = None) -> dict[str, Any]:
        """Assemble controller status JSON (profiles + optional full discovery)."""
        loaded = self.profiles.load()
        conflicts = self.profiles.conflicts(loaded)
        names = selected if selected is not None else sorted(loaded.keys())
        # One inventory for profile port attribution (no N× socket/lsof) and,
        # when listing everything, claim scan + live discovery.
        listeners = list_listening_tcp()
        statuses = []
        profile_ports: set[int] = set()
        for name in names:
            profile = loaded.get(name)
            if profile is None:
                raise ProfileNotFoundError(name)
            statuses.append(
                self.status(
                    profile,
                    allow_port_fallback=name not in conflicts,
                    listeners=listeners,
                )
            )
            try:
                profile_ports.add(int(profile.endpoint_port))
            except (TypeError, ValueError):
                pass

        claims: list[dict[str, Any]] = []
        listening: list[dict[str, Any]] = []
        # Full discovery only when listing everything — targeted stays profile-only.
        if selected is None:
            # Visibility is owned by Swift (isBoardVisible on the wire facts):
            # stale flat configs are shipped and hidden client-side (L04) —
            # no second claim-visibility filter here.
            # Reuse the same listeners snapshot (no second inventory).
            start_cmds = [
                profile.get("START_COMMAND")
                for profile in loaded.values()
            ]
            # START_COMMAND path hints only; scan re-hints from listeners=.
            claim_roots = roots_hinted_by_commands(start_cmds)
            claims = scan_port_claim_directories(
                roots=claim_roots or None,
                agent_root=self.configuration.root,
                listeners=listeners,
            )
            claim_ports = {int(item["port"]) for item in claims}
            listening = discover_live_model_endpoints(
                profile_ports=profile_ports,
                claim_ports=claim_ports,
                listeners=listeners,
            )
            covered_ports = {
                int(item["port"])
                for item in statuses
                if str(item.get("port") or "").isdigit()
            }
            listening_by_port = {
                int(item["port"]): item
                for item in listening
                if str(item.get("port") or "").isdigit()
            }

            # Claimed port folders not already represented by a profile.
            for claim in claims:
                port = int(claim["port"])
                if port in covered_ports:
                    continue
                live = listening_by_port.get(port)
                merged = dict(claim)
                if live:
                    merged.update(
                        {
                            "pid": live.get("pid"),
                            "command": live.get("command"),
                            "ready": live.get("ready"),
                            "server_ids": live.get("server_ids"),
                            "base_url": live.get("base_url"),
                            # L07: prefer-known merge routes through the one
                            # helper — live discovery inference wins, the claim
                            # flag hint backs it up, "unknown" is the fallback.
                            "runtime": first_known(
                                live.get("runtime"), claim.get("runtime_hint")
                            ),
                            "request_model": live.get("request_model")
                            if live.get("request_model")
                            and not str(live.get("request_model")).startswith("port-")
                            else (claim.get("model_hint") or live.get("request_model")),
                            "display_name": claim.get("display_name")
                            or live.get("display_name"),
                        }
                    )
                else:
                    merged["ready"] = False
                    merged["request_model"] = claim.get("model_hint") or f"port-{port}"
                    merged["runtime"] = first_known(claim.get("runtime_hint"))
                statuses.append(
                    status_dict_from_discovery(
                        merged,
                        source="claim",
                        profile_name=f"port-{port}",
                        listeners=listeners,
                    )
                )
                covered_ports.add(port)

            # Pure listeners not claimed and not profiled.
            for live in listening:
                port = int(live["port"])
                if port in covered_ports:
                    continue
                statuses.append(
                    status_dict_from_discovery(
                        live,
                        source="discovery",
                        profile_name=f"discovered-{port}",
                        listeners=listeners,
                    )
                )
                covered_ports.add(port)

        benchmark = self.benchmark_status()
        # Ready N/M is derived by Swift (ProfileRuntimeCounts) from board-visible
        # statuses — the single owner. The wire no longer carries counts.
        return {
            "statuses": statuses,
            "benchmark": benchmark,
            "integrations": [],
            "profiles_dir": str(self.configuration.profiles_directory),
            "controller_root": str(self.configuration.root),
        }

    def ports_payload(self) -> dict[str, Any]:
        """Ports-style inventory: every listener + model probe outcome."""
        loaded = self.profiles.load()
        profile_ports: set[int] = set()
        for profile in loaded.values():
            try:
                profile_ports.add(int(profile.endpoint_port))
            except (TypeError, ValueError):
                pass
        # One inventory shared with claim scan + live discovery.
        listeners = list_listening_tcp()
        claims = scan_port_claim_directories(
            agent_root=self.configuration.root,
            listeners=listeners,
        )
        claim_ports = {int(item["port"]) for item in claims}
        live = discover_live_model_endpoints(
            profile_ports=profile_ports,
            claim_ports=claim_ports,
            listeners=listeners,
        )
        live_by_port = {int(item["port"]): item for item in live}
        claims_by_port = {int(item["port"]): item for item in claims}
        ports: list[dict[str, Any]] = []
        for listener in listeners:
            port = int(listener["port"])
            entry = {
                "port": port,
                "pid": listener.get("pid"),
                "command": listener.get("command"),
                "bind": listener.get("bind"),
                "looks_like_model": command_looks_like_model_server(listener.get("command")),
                "model": live_by_port.get(port),
                "claimed": claims_by_port.get(port),
            }
            ports.append(entry)
        # Claims with nothing listening yet still appear.
        listening_ports = {int(item["port"]) for item in listeners}
        for claim in claims:
            if int(claim["port"]) not in listening_ports:
                ports.append(
                    {
                        "port": int(claim["port"]),
                        "pid": None,
                        "command": None,
                        "bind": None,
                        "looks_like_model": False,
                        "model": None,
                        "claimed": claim,
                    }
                )
        ports.sort(key=lambda item: int(item["port"]))
        return {
            "ports": ports,
            "profiles_dir": str(self.configuration.profiles_directory),
            "controller_root": str(self.configuration.root),
            "scan_roots_env": SCAN_ROOTS_ENV,
        }

    def action_response(self) -> dict[str, Any]:
        payload = self.status_payload()
        return {
            "statuses": payload["statuses"],
            "benchmark": payload["benchmark"],
            "integrations": payload["integrations"],
            "profiles_dir": payload["profiles_dir"],
            "controller_root": payload["controller_root"],
            "error": None,
        }


    def set_profiles_directory(self, path: str) -> dict[str, Any]:
        """Persist and hot-reload the profiles folder without restarting the agent."""
        if not isinstance(path, str) or not path.strip():
            raise UsageError("missing required string field: profiles_dir")
        resolved = Path(path).expanduser().resolve()
        resolved.mkdir(parents=True, exist_ok=True)
        save_profiles_directory(self.configuration.root, resolved)
        self.configuration.profiles_dir = resolved
        self.profiles = ProfileRepository(resolved)
        return self.action_response()

    def _benchmark_dir(self) -> Path:
        path = self.configuration.run_directory / "benchmarks"
        path.mkdir(parents=True, exist_ok=True)
        return path

    def _benchmark_pid_file(self) -> Path:
        return self.configuration.run_directory / "benchmark.pid"

    def _benchmark_log_path(self) -> Path:
        return self.configuration.run_directory / "logs" / "benchmark.log"

    def _benchmark_latest_json(self) -> Path:
        return self._benchmark_dir() / "latest.json"

    def _benchmark_latest_md(self) -> Path:
        return self._benchmark_dir() / "latest.md"

    def _read_benchmark_pid(self) -> int | None:
        path = self._benchmark_pid_file()
        try:
            raw = path.read_text(encoding="utf-8").strip()
            pid = int(raw)
        except (OSError, ValueError):
            return None
        if not process_is_alive(pid):
            path.unlink(missing_ok=True)
            return None
        return pid

    def _latest_benchmark_report(self) -> dict[str, Any] | None:
        path = self._benchmark_latest_json()
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if not isinstance(payload, dict):
            return None
        reports = payload.get("benchmarks") or []
        rows: list[dict[str, Any]] = []
        for report in reports:
            if not isinstance(report, dict):
                continue
            averages = report.get("averages") or {}
            rows.append(
                {
                    "profile": report.get("profile"),
                    "runtime": report.get("runtime"),
                    "ttft_ms": averages.get("ttft_ms"),
                    "decode_tokens_per_sec": averages.get("decode_tokens_per_sec"),
                    "e2e_tokens_per_sec": averages.get("e2e_tokens_per_sec"),
                    "rss_mb": report.get("rss_mb"),
                    "vram_mb": report.get("vram_mb"),
                }
            )
        return {
            "generated_at": payload.get("generated_at"),
            "suite": payload.get("suite"),
            "profiles": payload.get("profiles") or [],
            "rows": rows,
            "json_path": str(path),
            "markdown_path": str(self._benchmark_latest_md()),
        }

    def benchmark_status(self) -> dict[str, Any]:
        pid = self._read_benchmark_pid() if self._benchmark_running else None
        # Clear stale pid files left after process crash.
        if not self._benchmark_running and self._benchmark_pid_file().exists():
            self._benchmark_pid_file().unlink(missing_ok=True)
            pid = None
        log_path = self._benchmark_log_path()
        return {
            "running": self._benchmark_running,
            "pid": pid if self._benchmark_running else None,
            "log_path": str(log_path) if log_path.exists() or self._benchmark_running else None,
            "latest": self._latest_benchmark_report(),
        }

    def start_benchmark(
        self,
        profiles: list[str] | None = None,
        suite: str = "quick",
        allow_concurrent: bool = False,
        keep_running: bool = False,
    ) -> dict[str, Any]:
        """Run a quick local-endpoint benchmark in a background thread.

        Hits the model on the agent host (always loopback-reachable here). The
        Mac app must only start a remote bench when the profile is ready; the
        agent will also try switch/start if needed.
        """
        with self._benchmark_lock:
            if self._benchmark_running:
                raise OperationFailedError("benchmark already running")
            self._benchmark_running = True
        loaded = self.profiles.load()
        if profiles:
            names = [n for n in profiles if n in loaded]
            missing = [n for n in profiles if n not in loaded]
            if missing and not names:
                with self._benchmark_lock:
                    self._benchmark_running = False
                raise ProfileNotFoundError(missing[0])
        else:
            names = sorted(loaded.keys())
        if not names:
            with self._benchmark_lock:
                self._benchmark_running = False
            raise UsageError("no profiles available to benchmark")

        log_path = self._benchmark_log_path()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("", encoding="utf-8")
        # Marker pid = this agent process while the worker thread runs.
        self._benchmark_pid_file().write_text(f"{os.getpid()}\n", encoding="utf-8")

        def worker() -> None:
            try:
                self._run_benchmark_worker(
                    names,
                    suite=suite,
                    allow_concurrent=allow_concurrent,
                    keep_running=keep_running,
                    log_path=log_path,
                )
            finally:
                self._benchmark_pid_file().unlink(missing_ok=True)
                with self._benchmark_lock:
                    self._benchmark_running = False

        thread = threading.Thread(target=worker, name="msw-benchmark", daemon=True)
        thread.start()
        return self.benchmark_status()

    def _run_benchmark_worker(
        self,
        names: list[str],
        *,
        suite: str,
        allow_concurrent: bool,
        keep_running: bool,
        log_path: Path,
    ) -> None:
        prompts = self._benchmark_prompts(suite)
        reports: list[dict[str, Any]] = []

        def log(line: str) -> None:
            try:
                with log_path.open("a", encoding="utf-8") as handle:
                    handle.write(line + "\n")
            except OSError:
                pass

        for name in names:
            try:
                profile = self.resolve_profile(name)
            except AgentError as error:
                log(f"{name}: resolve failed: {error}")
                continue
            before = self.status(profile)
            was_running = bool(before.get("running"))
            try:
                if not before.get("ready"):
                    if allow_concurrent:
                        self.start(name)
                    else:
                        self.switch_profile(name)
                    # Quick suite should not block the agent for minutes if the
                    # model never becomes ready (disabled healthcheck, OOM, …).
                    deadline = time.time() + (15 if suite == "quick" else 90)
                    while time.time() < deadline:
                        before = self.status(self.resolve_profile(name))
                        if before.get("ready"):
                            break
                        time.sleep(0.5)
                results: list[dict[str, Any]] = []
                if not before.get("ready"):
                    results.append(
                        {
                            "benchmark": "ready-wait",
                            "category": "setup",
                            "error": "profile not ready for benchmark",
                        }
                    )
                else:
                    for prompt in prompts:
                        results.append(self._benchmark_one(profile, prompt))
                successful = [r for r in results if not r.get("error")]
                def avg(key: str) -> float | None:
                    vals = [float(r[key]) for r in successful if r.get(key) is not None]
                    if not vals:
                        return None
                    return round(sum(vals) / len(vals) * 10) / 10
                current = self.status(self.resolve_profile(name))
                reports.append(
                    {
                        "profile": name,
                        "runtime": profile.runtime,
                        "rss_mb": current.get("rss_mb"),
                        "vram_mb": current.get("vram_mb"),
                        "averages": {
                            "ttft_ms": avg("ttft_ms"),
                            "decode_tokens_per_sec": avg("decode_tokens_per_sec"),
                            "e2e_tokens_per_sec": avg("e2e_tokens_per_sec"),
                        },
                        "results": results,
                    }
                )
                log(f"{name}: ok rows={len(successful)}/{len(results)}")
            except AgentError as error:
                log(f"{name}: {error}")
                reports.append(
                    {
                        "profile": name,
                        "runtime": profile.runtime,
                        "rss_mb": None,
                        "vram_mb": None,
                        "averages": {
                            "ttft_ms": None,
                            "decode_tokens_per_sec": None,
                            "e2e_tokens_per_sec": None,
                        },
                        "results": [{"error": str(error)}],
                    }
                )
            finally:
                # Prefer leaving the host as we found it for quick suite.
                if not keep_running and not was_running:
                    try:
                        self.stop(name, force=True)
                    except TypeError:
                        try:
                            self.stop(name)
                        except AgentError:
                            pass
                    except AgentError:
                        pass

        generated_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        payload = {
            "generated_at": generated_at,
            "suite": suite,
            "profiles": names,
            "benchmarks": reports,
        }
        latest = self._benchmark_latest_json()
        latest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        lines = [
            "# Model Switchboard Benchmark",
            "",
            f"Generated: {generated_at}",
            "",
            "| Profile | Runtime | TTFT ms | Decode tok/s |",
            "|---|---|---:|---:|",
        ]
        for report in reports:
            averages = report.get("averages") or {}
            lines.append(
                f"| {report.get('profile')} | {report.get('runtime')} | "
                f"{averages.get('ttft_ms') or '-'} | {averages.get('decode_tokens_per_sec') or '-'} |"
            )
        self._benchmark_latest_md().write_text("\n".join(lines) + "\n", encoding="utf-8")
        log(f"wrote {latest}")

    @staticmethod
    def _benchmark_prompts(suite: str) -> list[dict[str, Any]]:
        # Keep quick suite short: remote agents may hold large models.
        if suite == "context":
            return [
                {"benchmark": "prefill-1k", "category": "prefill", "prompt": "Hello " * 200, "max_tokens": 16},
                {"benchmark": "prefill-4k", "category": "prefill", "prompt": "Hello " * 800, "max_tokens": 16},
            ]
        return [
            {
                "benchmark": "quick-short",
                "category": "decode",
                "prompt": "Write a one-sentence greeting.",
                "max_tokens": 32,
            },
            {
                "benchmark": "quick-medium",
                "category": "decode",
                "prompt": "Explain what a token is in large language models in two sentences.",
                "max_tokens": 64,
            },
        ]

    def _benchmark_one(self, profile: Profile, prompt: dict[str, Any]) -> dict[str, Any]:
        """POST /v1/chat/completions on the local endpoint and time TTFT/decode."""
        url = profile.base_url.rstrip("/") + "/chat/completions"
        body = json.dumps(
            {
                "model": profile.request_model,
                "messages": [{"role": "user", "content": prompt["prompt"]}],
                "max_tokens": int(prompt.get("max_tokens") or 32),
                "temperature": 0,
                "stream": False,
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        started = time.perf_counter()
        try:
            with _urlopen_no_redirect(request, 30) as response:
                raw = response.read()
            elapsed_s = max(time.perf_counter() - started, 1e-6)
            payload = json.loads(raw.decode("utf-8"))
            choice = (payload.get("choices") or [{}])[0]
            message = choice.get("message") or {}
            content = message.get("content") or choice.get("text") or ""
            usage = payload.get("usage") or {}
            completion_tokens = usage.get("completion_tokens")
            if not isinstance(completion_tokens, int):
                completion_tokens = max(1, len(str(content).split()))
            prompt_tokens = usage.get("prompt_tokens")
            if not isinstance(prompt_tokens, int):
                prompt_tokens = max(1, len(str(prompt["prompt"]).split()))
            ttft_ms = elapsed_s * 1000.0  # non-stream: whole response latency as TTFT proxy
            return {
                "benchmark": prompt.get("benchmark"),
                "category": prompt.get("category"),
                "ttft_ms": round(ttft_ms * 10) / 10,
                "decode_tokens_per_sec": round((completion_tokens / elapsed_s) * 10) / 10,
                "e2e_tokens_per_sec": round(((prompt_tokens + completion_tokens) / elapsed_s) * 10) / 10,
                "completion_tokens": completion_tokens,
                "prompt_est_tokens": prompt_tokens,
            }
        except Exception as error:  # noqa: BLE001 - surface as row error
            return {
                "benchmark": prompt.get("benchmark"),
                "category": prompt.get("category"),
                "error": str(error),
            }

    def status(
        self,
        profile: Profile,
        allow_port_fallback: bool = True,
        *,
        listeners: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        ready, server_ids = self._probe_health(profile)
        # A claim with no model-name hint invents "port-N" as its identity; the
        # id the endpoint actually serves (while it is up) is the real name.
        request_model = profile.request_model
        server_model_id = profile.server_model_id
        display_name = profile.display_name
        if server_ids:
            if is_placeholder_model_name(request_model):
                request_model = server_ids[0]
            if is_placeholder_model_name(server_model_id):
                server_model_id = server_ids[0]
            if (
                display_name.lower() == f"port {profile.endpoint_port}"
                or is_placeholder_model_name(display_name)
            ):
                display_name = Path(request_model).name
        pid = self._read_pid(profile.name)
        zombie = bool(pid and process_is_zombie(pid))
        if pid is not None and not process_is_alive(pid):
            # Clear pid file for dead *and* zombie children once reaped/known.
            if not zombie:
                self._pid_file(profile.name).unlink(missing_ok=True)
                pid = None
            else:
                # Still show the defunct pid once so operators can see it, but
                # running stays false; next successful stop clears the file.
                pass
        if pid is None and allow_port_fallback:
            if listeners is not None:
                listener = listener_pid_from_inventory(profile.endpoint_port, listeners)
            else:
                listener = listener_pid(profile.endpoint_port)
            # Ownership only — never adopt a listener just because health
            # succeeded (that would make stop() SIGKILL foreign processes via
            # primary_pid without _process_matches). Mirrors Swift ControllerService.
            if listener is not None and self._process_matches(listener, profile):
                pid = listener
                zombie = process_is_zombie(pid)
        label, tags, launch_mode = profile.runtime_spec
        runtime = profile.runtime
        alive = process_is_alive(pid)
        listening = False
        if listeners is not None:
            listening = port_listening_from_inventory(profile.endpoint_port, listeners)
        else:
            listening = port_is_listening(profile.endpoint_port)
        # Health can succeed on a foreign listener; keep ready visible without
        # claiming ownership (running/pid stay unset) so stop stays safe.
        # The stringly lifecycle "state" key was deleted from the wire contract
        # (L22): running/ready booleans are the single encoding Swift decodes.
        # A zombie that is not ready must not report running.
        if zombie and not process_is_alive(pid) and not ready:
            alive = False
        ready_flag = bool(ready and (alive or listening))
        missing = missing_local_model_artifacts(profile.values)
        # L08: `launchable` was deleted from the wire — Swift derives it from
        # missing_artifacts + running + ready (provably the same formula).
        command = process_command(pid) if ((alive or zombie) and pid) else None
        # L21: no interior runtime re-derivation. `runtime` / `label` / `tags` /
        # `launch_mode` come from the boundary parse (profile.runtime_spec on
        # the profile's RUNTIME + START_COMMAND). The live process command
        # never overrides the configured runtime here; discovery rows get their
        # runtime inferred once at the discovery boundary instead.
        return {
            "profile": profile.name,
            "display_name": display_name,
            "runtime": runtime,
            "runtime_label": label,
            "runtime_tags": tags if isinstance(tags, list) else profile.runtime_tags,
            "launch_mode": launch_mode,
            "host": profile.endpoint_host,
            "port": profile.endpoint_port,
            "base_url": profile.base_url,
            "request_model": request_model,
            "server_model_id": server_model_id,
            "pid": pid if (alive or zombie) else None,
            "running": alive,
            # Health alone when the port answers (Swift-like). Unowned ready
            # endpoints stay stop-safe because pid/running stay false.
            "ready": ready_flag,
            "server_ids": server_ids if (alive or ready) else [],
            "rss_mb": process_rss_mb(pid) if alive and pid else None,
            # GPU VRAM when nvidia-smi can attribute memory to this pid (not RSS).
            "vram_mb": process_vram_mb(pid) if alive and pid else None,
            "command": command,
            "log_path": profile.log_path,
            "source": "profile",
            "missing_artifacts": missing,
        }

    # -- lifecycle ---------------------------------------------------------

    def start(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            # Always key pid files / supervision on the canonical profile name
            # (claims resolve discovered-N → port-N).
            canonical = profile.name
            if not (profile.get("START_COMMAND") or "").strip() and profile.runtime_spec[2] == "external":
                raise UnsupportedError(
                    f"{canonical}: discovered endpoint has no launch claim; cannot start from Switchboard"
                )
            # Idempotent only when *this* agent owns a live pid file — not when a
            # foreign listener happens to answer health on the profile port.
            owned_pid = self._read_pid(canonical)
            if owned_pid and process_is_alive(owned_pid):
                self._supervised.add(canonical)
                return
            loaded = self.profiles.load()
            # Include synthetic claim profile for conflict checks on the port.
            loaded = dict(loaded)
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "start", loaded)
            command = build_start_command(profile)

            # Refuse to launch into a foreign listener (daemonized leftovers /
            # another stack on the same PORT). Watchdog must not pile orphans.
            port = profile.endpoint_port
            if port and port_is_listening(port):
                listener = listener_pid(port)
                if listener and self._process_matches(listener, profile):
                    self._supervised.add(canonical)
                    return
                detail = f" by pid {listener}" if listener else ""
                raise ProfileConflictError(
                    f"Cannot start {canonical}: port {port} is already in use{detail}."
                )

            missing = missing_local_model_artifacts(profile.values)
            if missing:
                raise InvalidProfileError(
                    f"{canonical}: cannot start; missing model path(s): {', '.join(missing)}"
                )

            environment = dict(os.environ)
            environment.update(profile.values)
            environment["MODEL_PROFILE"] = canonical
            environment["MODEL_SWITCHBOARD_PROFILE_LOADED"] = "1"
            environment["MODEL_SWITCHBOARD_AGENT"] = "1"

            self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
            log_path = Path(profile.log_path)
            try:
                log_handle = log_path.open("ab")
            except OSError as error:
                raise OperationFailedError(f"cannot open log {log_path}: {error}") from error
            try:
                process = subprocess.Popen(
                    ["/bin/bash", "-lc", command],
                    stdout=log_handle,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                    cwd=profile.working_directory or self.configuration.root,
                    env=environment,
                    start_new_session=True,
                )
            except OSError as error:
                raise OperationFailedError(f"failed to launch {canonical}: {error}") from error
            finally:
                log_handle.close()
            self._pid_file(canonical).write_text(f"{process.pid}\n", encoding="utf-8")
            self._supervised.add(canonical)
            clear_listening_tcp_cache()

    def _reap_unresolved_pid(self, name: str, force: bool = False) -> None:
        """Pid-file leftover after resolve failed — kill only if it still looks like us."""
        orphan = self._read_pid(name)
        if (
            orphan
            and orphan != os.getpid()
            and process_is_alive(orphan)
        ):
            cmd = process_command(orphan) or ""
            if command_looks_like_model_server(cmd):
                terminate_process_tree(orphan, force=force)
        self._pid_file(name).unlink(missing_ok=True)

    def stop(self, name: str, force: bool = False) -> None:
        with self._mutation_lock:
            self._suppress_watchdog()
            profile = self.resolve_profile(name)
            canonical = profile.name
            was_supervised = canonical in self._supervised
            self._supervised.discard(canonical)
            self._clear_active_profile(if_matching=canonical)
            current = self.status(profile)
            primary_pid = current.get("pid")
            # Pid-file children we started this session are trusted even without
            # cmdline match. Leftover pid files from prior boots must look like
            # a model server — never killpg a reused unrelated PID.
            if primary_pid and not self._process_matches(primary_pid, profile):
                owned = self._read_pid(canonical)
                if (
                    owned
                    and owned == primary_pid
                    and process_is_alive(owned)
                    and (
                        was_supervised
                        or command_looks_like_model_server(process_command(owned) or "")
                    )
                ):
                    pass
                else:
                    primary_pid = None
            # Idle profiles must not run STOP_COMMAND (curl-to-shutdown dies
            # with connection-refused and would abort exclusive switch).
            if not current.get("running") and not primary_pid and not force:
                self._pid_file(canonical).unlink(missing_ok=True)
                clear_listening_tcp_cache()
                return
            stop_error: Exception | None = None

            stop_command = (profile.get("STOP_COMMAND") or "").strip()
            if stop_command and not force:
                environment = dict(os.environ)
                environment.update(profile.values)
                try:
                    subprocess.run(
                        ["/bin/bash", "-lc", stop_command],
                        cwd=profile.working_directory,
                        env=environment,
                        capture_output=True,
                        check=True,
                        timeout=60,
                    )
                except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as error:
                    stop_error = error

            if profile.get("STOP_COMMAND_ONLY") != "1" or force:
                self._terminate_profile_processes(
                    profile, primary_pid, force=force
                )
                wait_ok = self._wait_until_stopped(
                    profile,
                    primary_pid,
                    timeout=FORCE_TERMINATE_TIMEOUT_SECONDS * 3 if force else STOP_WAIT_SECONDS,
                )
                if not wait_ok:
                    # Last-chance SIGKILL of anything still matching the port.
                    self._terminate_profile_processes(profile, primary_pid, force=True)
                    wait_ok = self._wait_until_stopped(
                        profile,
                        primary_pid,
                        timeout=FORCE_TERMINATE_TIMEOUT_SECONDS * 2,
                    )
                if not wait_ok:
                    raise OperationFailedError(
                        f"failed to stop {canonical}: endpoint or process is still alive"
                    )
            self._pid_file(canonical).unlink(missing_ok=True)
            clear_listening_tcp_cache()
            if stop_error is not None and not force:
                raise OperationFailedError(f"STOP_COMMAND failed for {canonical}: {stop_error}")

    def restart(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            loaded = dict(self.profiles.load())
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "restart", loaded)
            self.stop(name)
            self.start(name)

    def switch_profile(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            canonical = profile.name
            loaded = dict(self.profiles.load())
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "activate", loaded)
            # Exclusive switch only stops managed profiles / session-supervised
            # claims — never discovered listeners. Do not assemble the full
            # status board (claim walk + live HTTP probes) just to find them.
            managed_names = set(loaded.keys()) | set(self._supervised)
            for other in sorted(managed_names - {canonical}):
                try:
                    self.stop(other)
                except ProfileNotFoundError:
                    self._reap_unresolved_pid(other)
                except AgentError as error:
                    # Keep going so a later idle/missing sibling cannot leave
                    # the board with the previous model already killed.
                    sys.stderr.write(f"[activate] stop {other}: {error.message}\n")
            self.start(canonical)
            self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
            self.configuration.active_profile_file.write_text(f"{canonical}\n", encoding="utf-8")

    def stop_all(self, force: bool = False) -> None:
        with self._mutation_lock:
            failures: list[str] = []
            # Folder profiles, session-supervised claims, and durable pid files
            # left from a prior agent process (claims survive reboot of the agent).
            names = set(self.profiles.load().keys()) | set(self._supervised)
            try:
                for path in self.configuration.run_directory.glob("*.pid"):
                    stem = path.stem
                    if stem in {"benchmark", "active-profile"}:
                        continue
                    names.add(stem)
            except OSError:
                pass
            for name in sorted(names):
                try:
                    # Nested stop also takes the mutation lock (RLock).
                    self.stop(name, force=force)
                except ProfileNotFoundError:
                    self._reap_unresolved_pid(name, force=force)
                except AgentError as error:
                    failures.append(f"{name}: {error.message}")
            # Clear any leftover active marker so a later watchdog cannot revive.
            self.configuration.active_profile_file.unlink(missing_ok=True)
            self._supervised.clear()
            clear_listening_tcp_cache()
            if failures:
                raise OperationFailedError("Failed to stop profiles: " + "; ".join(failures))

    def run_integration(self, integration: str, action: str) -> None:
        raise UnsupportedError(f"Unsupported integration action: {integration}:{action}")

    # -- doctor ------------------------------------------------------------

    def doctor_report(self) -> dict[str, Any]:
        payload = self.status_payload()
        unit = self.configuration.systemd_unit_path
        return {
            "controller": {
                "url": f"http://{self.configuration.host}:{self.configuration.port}",
                "reachable": True,
                "profiles": len(payload["statuses"]),
                "integrations": 0,
            },
            "launch_agent": {
                "plist_path": str(unit),
                "installed": unit.is_file(),
                "running": True,
            },
            "integrations": [],
            "profiles_dir": payload["profiles_dir"],
            "controller_root": payload["controller_root"],
            "profiles": [],
            "schema_version": "1",
            "tool_version": AGENT_VERSION,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "findings": [],
            "next_steps": [],
        }

    # -- watchdog ----------------------------------------------------------

    def watchdog_tick(self) -> None:
        """Restart supervised profiles that crashed mid-session only.

        Does *not* read active-profile from disk: that would reload a model on
        every agent/login boot after a prior `switch`. Session supervision is
        the only source of truth for auto-restart.
        """
        if time.monotonic() < self._watchdog_suppressed_until:
            return
        for name in list(self._supervised):
            with self._mutation_lock:
                # Re-check under the lock: a concurrent stop may have suppressed
                # the watchdog and discarded supervision after our snapshot.
                if time.monotonic() < self._watchdog_suppressed_until:
                    return
                if name not in self._supervised:
                    continue
                try:
                    profile = self.resolve_profile(name)
                except AgentError:
                    self._supervised.discard(name)
                    continue
                current = self.status(profile)
                if current["ready"] or current["running"]:
                    continue
                # Port held by a foreign process: drop supervision instead of
                # re-launching into a busy endpoint every watchdog tick.
                port = profile.endpoint_port
                if port and port_is_listening(port):
                    listener = listener_pid(port)
                    if listener is None or not self._process_matches(listener, profile):
                        self._supervised.discard(name)
                        continue
                try:
                    self.start(name)
                except AgentError as error:
                    sys.stderr.write(f"[watchdog] failed to restart {name}: {error}\n")

    def start_watchdog(self) -> None:
        def tick() -> None:
            self.watchdog_tick()
            self._watchdog_timer = threading.Timer(WATCHDOG_INTERVAL_SECONDS, tick)
            self._watchdog_timer.daemon = True
            self._watchdog_timer.start()

        self._watchdog_timer = threading.Timer(WATCHDOG_INTERVAL_SECONDS, tick)
        self._watchdog_timer.daemon = True
        self._watchdog_timer.start()

    # -- internals ---------------------------------------------------------

    def _pid_file(self, name: str) -> Path:
        return self.configuration.run_directory / f"{name}.pid"

    def _read_pid(self, name: str) -> int | None:
        try:
            return int(self._pid_file(name).read_text(encoding="utf-8").strip())
        except (OSError, ValueError):
            return None

    def _process_matches(self, pid: int, profile: Profile) -> bool:
        # Never treat the agent process as a model server — profile PORT equal
        # to the agent bind would otherwise match `serve --port N` and stop
        # would SIGKILL the agent itself.
        if pid == os.getpid():
            return False
        command = (process_command(pid) or "").lower()
        if not command:
            return False
        markers = [
            profile.name, profile.get("MODEL_ALIAS"), profile.request_model,
            profile.server_model_id, profile.get("MODEL_PATH"), profile.get("MODEL_DIR"),
            profile.get("MODEL_FILE"), profile.get("MODEL_REPO"),
            profile.get("START_COMMAND"),
        ]
        for marker in markers:
            if marker and len(marker) >= 4 and marker.lower() in command:
                return True
        # Port tokens common to llama-server / vllm argv — whole tokens only so
        # PORT=80 does not match --port 8080 / http://host:8080.
        port = profile.endpoint_port
        if port:
            try:
                argv = shlex.split(command)
            except ValueError:
                argv = command.split()
            for index, token in enumerate(argv):
                if token == f"--port={port}":
                    return True
                if token == "--port" and index + 1 < len(argv) and argv[index + 1] == port:
                    return True
            if re.search(rf"(?<!\d):{re.escape(port)}(?!\d)", command):
                return True
        return (
            command_looks_like_model_server(command)
            and port_is_listening(port)
            and listener_pid(port) == pid
        )

    def _probe_health(self, profile: Profile) -> tuple[bool, list[str]]:
        if profile.healthcheck_mode == "disabled":
            return False, []
        url = profile.healthcheck_url
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False, []
        remote_allowed = (os.environ.get("ALLOW_REMOTE_HEALTHCHECK") or "").lower() in (
            "1", "true", "yes",
        )
        if not remote_allowed and not is_loopback(parsed.hostname or ""):
            return False, []
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with _urlopen_no_redirect(request, HEALTH_TIMEOUT_SECONDS) as response:
                body = response.read()
        except (urllib.error.URLError, OSError, ValueError):
            return False, []
        if profile.healthcheck_mode == "http-200":
            return True, []
        try:
            parsed_body = json.loads(body)
            entries = parsed_body.get("data", [])
        except (json.JSONDecodeError, AttributeError):
            return False, []
        ids = [
            entry["id"]
            for entry in entries
            if isinstance(entry, dict) and isinstance(entry.get("id"), str) and entry["id"]
        ]
        # A claim with no model-name hint carries the synthetic port-N identity:
        # there is nothing to verify against, so a non-empty served id list is
        # the proof of readiness (the endpoint proves itself).
        if profile.get("HEALTHCHECK_ANY_ID") == "1":
            return bool(ids), ids
        expected = profile.get("HEALTHCHECK_EXPECT_ID") or profile.server_model_id
        matched = openai_model_id_matches(
            expected,
            ids,
            profile.request_model,
            profile.server_model_id,
        )
        return matched, ids

    def _terminate_profile_processes(
        self,
        profile: Profile,
        primary_pid: int | None,
        *,
        force: bool = False,
    ) -> None:
        self_pid = os.getpid()
        if primary_pid and primary_pid != self_pid:
            if process_is_zombie(primary_pid):
                reap_child(primary_pid)
            else:
                terminate_process_tree(primary_pid, force=force)
        # Always re-check the listen port: vLLM may leave EngineCore on the
        # port under a different pid after the launcher shell exits.
        # `force` only strengthens the signal — never skips ownership matching
        # (Swift terminateProfileProcesses always requires processMatches).
        listener = listener_pid(profile.endpoint_port)
        if (
            listener
            and listener != primary_pid
            and listener != self_pid
            and self._process_matches(listener, profile)
        ):
            if process_is_zombie(listener):
                reap_child(listener)
            else:
                terminate_process_tree(listener, force=force)

    def _wait_until_stopped(
        self,
        profile: Profile,
        primary_pid: int | None,
        timeout: float = STOP_WAIT_SECONDS,
    ) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if primary_pid:
                reap_child(primary_pid)
            if process_is_alive(primary_pid):
                time.sleep(0.2)
                continue
            # Prefer connect-only checks in the hot loop; resolve ownership via
            # the shared listening-TCP inventory (cached) instead of N× lsof.
            if not port_is_listening(profile.endpoint_port):
                return True
            listeners = list_listening_tcp()
            listener = listener_pid_from_inventory(profile.endpoint_port, listeners)
            if listener is None:
                return True
            # Port held by an unrelated process — not our problem for stop.
            if listener != primary_pid and not self._process_matches(listener, profile):
                return True
            if process_is_zombie(listener):
                reap_child(listener)
                return True
            time.sleep(0.2)
        # Final assessment: zombies / free ports count as stopped.
        if process_is_alive(primary_pid):
            return False
        if not port_is_listening(profile.endpoint_port):
            return True
        listeners = list_listening_tcp()
        listener = listener_pid_from_inventory(profile.endpoint_port, listeners)
        if listener is None:
            return True
        if process_is_zombie(listener):
            reap_child(listener)
            return True
        return not self._process_matches(listener, profile)

    def _suppress_watchdog(self) -> None:
        self._watchdog_suppressed_until = time.monotonic() + WATCHDOG_SUPPRESSION_SECONDS

    def _clear_active_profile(self, if_matching: str) -> None:
        try:
            current = self.configuration.active_profile_file.read_text(encoding="utf-8").strip()
        except OSError:
            return
        if current == if_matching:
            self.configuration.active_profile_file.unlink(missing_ok=True)

def _error_body(status: int, code: str, message: str) -> tuple[int, dict[str, Any]]:
    return status, {"error": code, "message": message}

class AgentRequestHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = f"ModelSwitchboardAgent/{AGENT_VERSION}"
    service: AgentService
    auth_token: str | None = None
    verbose = False

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        if self.verbose:
            sys.stderr.write(f"[http] {format % args}\n")

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self) -> bool:
        if not self.auth_token:
            return True
        supplied = self.headers.get("Authorization", "")
        return hmac.compare_digest(supplied, f"Bearer {self.auth_token}")

    def _read_body(self) -> bytes | None:
        """Read the request body; None means an error response was already sent."""
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            return b""
        try:
            length = int(raw_length)
            if length < 0:
                raise ValueError
        except ValueError:
            self._send_json(*_error_body(400, "invalid_content_length", "invalid Content-Length"))
            self.close_connection = True
            return None
        if length > MAXIMUM_BODY_BYTES:
            self._send_json(*_error_body(413, "payload_too_large", "request body too large"))
            self.close_connection = True
            return None
        return self.rfile.read(length)

    def _request_object(self, body: bytes) -> dict[str, Any]:
        if not body:
            return {}
        try:
            parsed = json.loads(body)
        except json.JSONDecodeError as error:
            raise InvalidJSONError("invalid JSON") from error
        if not isinstance(parsed, dict):
            raise UsageError("request body must be a JSON object")
        return parsed

    @staticmethod
    def _required_string(payload: dict[str, Any], key: str) -> str:
        value = payload.get(key)
        if not isinstance(value, str) or not value:
            raise UsageError(f"missing required string field: {key}")
        return value

    def do_GET(self) -> None:  # noqa: N802
        self._handle("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._handle("POST")

    def _handle(self, method: str) -> None:
        path = urllib.parse.urlparse(self.path).path or "/"
        try:
            if path.startswith("/api/") and not self._authorized():
                # The body has not been read yet; drop the connection so an
                # unread payload cannot corrupt a kept-alive request stream.
                self.close_connection = True
                self._send_json(*_error_body(401, "unauthorized", "unauthorized"))
                return
            body: bytes | None = b""
            if method == "POST":
                body = self._read_body()
                if body is None:
                    return
            handler = self._route(method, path)
            if handler is None:
                self._send_json(*_error_body(404, "not_found", "not found"))
                return
            self._send_json(200, handler(self._request_object(body or b"")))
        except AgentError as error:
            self._send_json(*_error_body(error.http_status, error.code, error.public_message))
        except Exception:  # pragma: no cover - defensive parity with router fallback
            self._send_json(*_error_body(500, "internal_error", "internal server error"))

    def _route(self, method: str, path: str) -> Callable[[dict[str, Any]], dict[str, Any]] | None:
        service = self.service
        if method == "GET":
            if path == "/api/status":
                return lambda _: service.status_payload()
            if path == "/api/ports":
                return lambda _: service.ports_payload()
            if path == "/api/doctor":
                return lambda _: service.doctor_report()
            if path == "/api/benchmark/status":
                return lambda _: service.benchmark_status()
            if path == "/api/host/metrics":
                return lambda _: host_metrics_payload()
            if path == "/api/integrations":
                return lambda _: {
                    "integrations": [],
                    "profiles_dir": str(service.configuration.profiles_directory),
                    "controller_root": str(service.configuration.root),
                }
            return None
        if method == "POST":
            if path == "/api/start":
                return self._profile_action(service.start)
            if path == "/api/stop":
                return self._stop_action(service)
            if path == "/api/restart":
                return self._profile_action(service.restart)
            if path == "/api/switch":
                return self._profile_action(service.switch_profile)
            if path == "/api/stop-all":
                return self._stop_all_action(service)
            if path == "/api/integrations/run":
                def run_integration(payload: dict[str, Any]) -> dict[str, Any]:
                    service.run_integration(
                        self._required_string(payload, "integration"),
                        payload.get("action", "sync"),
                    )
                    return service.action_response()
                return run_integration
            if path == "/api/config/profiles-dir":
                def set_profiles_dir(payload: dict[str, Any]) -> dict[str, Any]:
                    return service.set_profiles_directory(
                        self._required_string(payload, "profiles_dir")
                    )
                return set_profiles_dir
            if path == "/api/benchmark/start":
                def benchmark_start(payload: dict[str, Any]) -> dict[str, Any]:
                    selected = payload.get("profiles")
                    if selected is not None and not isinstance(selected, list):
                        raise UsageError("profiles must be a list of strings")
                    names: list[str] | None = None
                    if selected is not None:
                        names = []
                        for item in selected:
                            if not isinstance(item, str) or not item:
                                raise UsageError("profiles must be a list of strings")
                            names.append(item)
                    service.start_benchmark(
                        profiles=names,
                        suite=str(payload.get("suite") or "quick"),
                        allow_concurrent=bool(payload.get("allow_concurrent")),
                        keep_running=bool(payload.get("keep_running")),
                    )
                    return service.action_response()
                return benchmark_start
            return None
        return None

    def _profile_action(
        self, action: Callable[[str], None]
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            action(self._required_string(payload, "profile"))
            return self.service.action_response()
        return handle

    def _stop_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            force = bool(payload.get("force"))
            service.stop(self._required_string(payload, "profile"), force=force)
            return service.action_response()
        return handle

    def _stop_all_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            force = bool(payload.get("force"))
            service.stop_all(force=force)
            return service.action_response()
        return handle

def make_server(
    service: AgentService, verbose: bool = False
) -> ThreadingHTTPServer:
    configuration = service.configuration

    class BoundHandler(AgentRequestHandler):
        pass

    BoundHandler.service = service
    BoundHandler.auth_token = configuration.auth_token
    BoundHandler.verbose = verbose

    host = configuration.host.strip("[]")
    server = ThreadingHTTPServer((host, configuration.port), BoundHandler)
    server.daemon_threads = True
    return server

def build_link_code(agent_port: int, direct_host: str | None = None) -> dict[str, str]:
    """Build an editable SSH or direct gateway pairing code."""
    short_host = socket.gethostname().split(".")[0] or "remote"
    if direct_host is not None:
        link = (
            "modelswitchboard-gateway://"
            f"{direct_host}"
            f"?name={urllib.parse.quote(short_host)}&agent_port={agent_port}&mode=direct"
        )
        return {
            "user": "",
            "host": direct_host,
            "name": short_host,
            "agent_port": str(agent_port),
            "mode": "direct",
            "link": link,
        }
    user = getpass.getuser()
    fqdn = socket.getfqdn()
    host = fqdn if fqdn and "." in fqdn and fqdn != "localhost" else socket.gethostname()
    link = (
        "modelswitchboard-gateway://"
        f"{urllib.parse.quote(user)}@{host}"
        f"?name={urllib.parse.quote(short_host)}&agent_port={agent_port}&mode=ssh"
    )
    return {
        "user": user,
        "host": host,
        "name": short_host,
        "agent_port": str(agent_port),
        "mode": "ssh",
        "link": link,
    }

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="model-switchboard-agent",
        description="Model Switchboard remote agent: launch and monitor model servers over the controller HTTP contract.",
    )
    parser.add_argument("--version", action="version", version=f"model-switchboard-agent {AGENT_VERSION}")
    parser.add_argument("--root", type=Path, default=None, help="agent root directory (default: ~/.local/share/model-switchboard-agent)")
    parser.add_argument(
        "--profiles-dir",
        type=Path,
        default=None,
        help="folder of model .env/.json profiles (default: ~/model-profiles, or config.json / legacy <root>/model-profiles)",
    )
    parser.add_argument("--host", default="127.0.0.1", help="bind host (loopback only unless --unsafe-bind)")
    parser.add_argument("--unsafe-bind", metavar="HOST", default=None, help="bind a non-loopback host; requires --auth-token")
    parser.add_argument("--tailscale", action="store_true", help="bind this host's Tailscale address (tailnet-only; token recommended)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"bind port (default {DEFAULT_PORT})")
    parser.add_argument("--auth-token", default=None, help="bearer token (>= 16 bytes)")
    parser.add_argument("--auth-token-file", type=Path, default=None, help="file containing the bearer token")
    parser.add_argument(
        "--allow-unauthenticated",
        action="store_true",
        help="allow --tailscale without a bearer token (personal tailnet only)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="with stop/stop-all: SIGKILL immediately and clear state",
    )
    parser.add_argument("--json", action="store_true", help="print machine-readable output for CLI commands")
    parser.add_argument("--verbose", action="store_true", help="log HTTP requests to stderr")
    parser.add_argument(
        "--yes",
        action="store_true",
        help="non-interactive link: keep the resolved profiles folder (skip the scan prompt)",
    )
    parser.add_argument(
        "command",
        nargs="?",
        default="serve",
        choices=[
            "serve",
            "status",
            "list",
            "start",
            "stop",
            "restart",
            "switch",
            "activate",
            "stop-all",
            "kill-all",
            "link",
            "scan-profiles",
            "scan-ports",
            "ports",
        ],
    )
    parser.add_argument("profiles", nargs="*", help="profile names for start/stop/restart/switch")
    return parser

def build_configuration(args: argparse.Namespace) -> AgentConfiguration:
    token = args.auth_token
    if args.auth_token_file is not None:
        path = args.auth_token_file.expanduser()
        try:
            token = path.read_text(encoding="utf-8").strip()
        except OSError as error:
            raise InvalidConfigurationError(
                f"cannot read auth token file {path}: {error}"
            ) from error
    host = args.host
    unsafe = False
    tailscale = False
    if args.unsafe_bind is not None:
        host = args.unsafe_bind
        unsafe = True
    if getattr(args, "tailscale", False):
        presence = tailscale_status()
        if not presence.present:
            raise InvalidConfigurationError(
                "--tailscale: no Tailscale address found — is tailscaled running?"
            )
        host = presence.ipv4 or host
        tailscale = True
    explicit_profiles = getattr(args, "profiles_dir", None)
    if explicit_profiles is not None:
        # Persist so serve (systemd) keeps using the same folder without flags.
        save_profiles_directory(args.root or _default_root(), explicit_profiles)
    return AgentConfiguration(
        root=args.root or _default_root(),
        host=host,
        port=args.port,
        auth_token=token,
        unsafe_bind=unsafe,
        tailscale_bind=tailscale,
        allow_unauthenticated=bool(getattr(args, "allow_unauthenticated", False)),
        profiles_dir=explicit_profiles,
    )

def _print_json(payload: dict[str, Any]) -> None:
    print(json.dumps(payload, indent=2, sort_keys=True))

def _run_link(args: argparse.Namespace, configuration: AgentConfiguration) -> int:
    interactive = (
        not args.json
        and not args.yes
        and args.profiles_dir is None
        and sys.stdin.isatty()
        and sys.stdout.isatty()
    )
    if interactive:
        print()
        configuration.profiles_dir = prompt_profiles_directory(
            configuration.root,
            current=configuration.profiles_directory,
        )
    elif args.profiles_dir is not None:
        configuration.profiles_dir = resolve_profiles_directory(
            configuration.root, args.profiles_dir
        )
    configuration.profiles_directory.mkdir(parents=True, exist_ok=True)

    direct_host: str | None = None
    if getattr(args, "tailscale", False):
        presence = tailscale_status()
        if not presence.present:
            raise InvalidConfigurationError(
                "--tailscale: no Tailscale address found — is tailscaled running?"
            )
        direct_host = presence.dns_name or presence.ipv4
    info = build_link_code(configuration.port, direct_host=direct_host)
    info["profiles_dir"] = str(configuration.profiles_directory)
    claims = scan_port_claim_directories(agent_root=configuration.root)
    info["port_claims"] = len(claims)
    info["scan_roots_env"] = SCAN_ROOTS_ENV
    if args.json:
        _print_json(info)
    else:
        print()
        print("Pairing code for Model Switchboard on your Mac:")
        print()
        print(f"  {info['link']}")
        print()
        print(f"Profiles folder: {configuration.profiles_directory}")
        print("Drop one .env/.json per model there (PORT / START_COMMAND / …), then")
        print("Settings → Remote Gateways → Add Remote Gateway → paste the link.")
        print("Every gateway field stays editable on the Mac.")
        print()
        print("Discovery is host-generic: listening model ports + any numeric")
        print("port folders (…/8080/flags.env) under $HOME or")
        print(f"${SCAN_ROOTS_ENV}. Nothing is invented for unknown ports.")
    return 0

def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        configuration = build_configuration(args)
    except AgentError as error:
        sys.stderr.write(f"model-switchboard-agent: {error.message}\n")
        return 2

    service = AgentService(configuration)
    try:
        if args.command == "serve":
            configuration.profiles_directory.mkdir(parents=True, exist_ok=True)
            configuration.run_directory.mkdir(parents=True, exist_ok=True)
            server = make_server(service, verbose=args.verbose)
            service.start_watchdog()
            if configuration.tailscale_bind and configuration.auth_token is None:
                sys.stderr.write(
                    "warning: serving on the tailnet without a bearer token "
                    "(--allow-unauthenticated); anyone on the tailnet can "
                    "start/stop models\n"
                )
            print(f"controller=http://{configuration.host}:{configuration.port}", flush=True)
            print(f"profiles_dir={configuration.profiles_directory}", flush=True)
            try:
                server.serve_forever()
            except KeyboardInterrupt:
                server.shutdown()
            return 0
        if args.command == "status":
            _print_json(service.status_payload(args.profiles or None))
            return 0
        if args.command == "list":
            profiles = service.profiles.load()
            _print_json({
                "profiles": [
                    {
                        "profile": profile.name,
                        "display_name": profile.display_name,
                        "runtime": profile.runtime,
                        "request_model": profile.request_model,
                        "base_url": profile.base_url,
                    }
                    for profile in sorted(profiles.values(), key=lambda p: p.name)
                ],
                "profiles_dir": str(configuration.profiles_directory),
            })
            return 0
        if args.command == "scan-profiles":
            candidates = scan_profile_directories()
            claims = scan_port_claim_directories(agent_root=configuration.root)
            payload = {
                "profiles_dir": str(configuration.profiles_directory),
                "candidates": candidates,
                "port_claims": [
                    {
                        "port": item["port"],
                        "path": item["path"],
                        "display_name": item.get("display_name"),
                        "model_hint": item.get("model_hint"),
                        "runtime_hint": item.get("runtime_hint"),
                    }
                    for item in claims
                ],
                "scan_roots_env": SCAN_ROOTS_ENV,
            }
            if args.json:
                _print_json(payload)
            else:
                print(f"Current profiles folder: {configuration.profiles_directory}")
                if not candidates:
                    print("No launch-looking .env/.json folders found under $HOME.")
                for index, candidate in enumerate(candidates, start=1):
                    print(
                        f"[{index}] {candidate['path']} "
                        f"({candidate['profile_count']}: {', '.join(candidate['files'][:6])})"
                    )
                if claims:
                    print()
                    print("Claimed port folders (numeric dir + launch/flags markers):")
                    for claim in claims:
                        model = claim.get("model_hint") or "—"
                        print(
                            f"  :{claim['port']}  {claim['path']}  "
                            f"({claim.get('runtime_hint') or 'unknown'})  {model}"
                        )
                else:
                    print()
                    print(
                        "No claimed port folders found. Optional: export "
                        f"{SCAN_ROOTS_ENV}=/path/to/scan"
                    )
            return 0
        if args.command in ("scan-ports", "ports"):
            payload = service.ports_payload()
            if args.json:
                _print_json(payload)
            else:
                print("Listening / claimed ports (Ports-style):")
                for entry in payload["ports"]:
                    port = entry["port"]
                    claimed = entry.get("claimed")
                    model = entry.get("model")
                    cmd = (entry.get("command") or "")[:80]
                    flags = []
                    if entry.get("looks_like_model"):
                        flags.append("model-cmd")
                    if claimed:
                        flags.append("claimed")
                    if model and model.get("ready"):
                        flags.append("ready")
                    elif model:
                        flags.append("probe-fail")
                    flag_s = ",".join(flags) if flags else "-"
                    identity = ""
                    if model and model.get("request_model"):
                        identity = str(model["request_model"])
                    elif claimed and claimed.get("model_hint"):
                        identity = str(claimed["model_hint"])
                    print(f"  :{port:<5}  {flag_s:<18}  {identity or cmd or '—'}")
            return 0
        if args.command in ("start", "stop", "restart"):
            if not args.profiles:
                raise UsageError("No profiles selected")
            names = args.profiles
            if names == ["all"]:
                names = sorted(service.profiles.load().keys())
            for name in names:
                if args.command == "stop":
                    service.stop(name, force=bool(args.force))
                else:
                    getattr(service, args.command)(name)
            _print_json(service.action_response())
            return 0
        if args.command in ("switch", "activate"):
            if not args.profiles:
                raise UsageError("No profile selected")
            service.switch_profile(args.profiles[0])
            _print_json(service.action_response())
            return 0
        if args.command in ("stop-all", "kill-all"):
            # kill-all is the nuclear one-liner: always force.
            force = bool(args.force) or args.command == "kill-all"
            service.stop_all(force=force)
            _print_json(service.action_response())
            return 0
        if args.command == "link":
            return _run_link(args, configuration)
    except AgentError as error:
        sys.stderr.write(f"model-switchboard-agent: {error.message}\n")
        return 2 if isinstance(error, (UsageError, InvalidConfigurationError)) else 1
    return 0

if __name__ == "__main__":
    sys.exit(main())


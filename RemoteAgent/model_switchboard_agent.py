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
import traceback
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
    agent_config_path,
    apply_unified_memory_vram,
    canonical_runtime,
    env_flag,
    first_known,
    first_present,
    gpu_metrics_snapshot,
    is_loopback,
    is_placeholder_model_name,
    is_tailscale_ip,
    listener_pid,
    listener_pid_from_inventory,
    load_agent_config,
    missing_local_model_artifacts,
    openai_model_ids_from_entries,
    path_is_dir,
    path_is_regular_file,
    parse_env_profile,
    parse_json_profile,
    parse_llamacpp_slots_tokens,
    parse_prometheus_metric_sum,
    parse_sglang_server_info,
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
    read_uptime_seconds,
    reap_child,
    resolve_model_artifact_fields,
    sample_cpu_percent,
    sample_llm_serving_rates,
    sample_memory,
    sample_network_rates,
    storage_usage,
    _assignment_key_rest,
    _json_object_file,
    _round_tenths,
    _stripped_assignment_line,
    tailscale_health_snapshot,
    terminate_process_tree,
    urlopen_no_redirect,
)
from discovery import (  # noqa: E402
    PORT_CLAIM_DIR_RE,
    PORT_CLAIM_MARKERS,
    clear_listening_tcp_cache,
    command_looks_like_model_server,
    configured_scan_roots,
    discover_live_model_endpoints,
    list_listening_tcp,
    profile_from_claim,
    roots_hinted_by_commands,
    scan_port_claim_directories,
    status_dict_from_discovery,
)

AGENT_VERSION = "2.0.0"

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


@dataclass(frozen=True)
class TailscalePresence:
    """This host's tailnet presence - present / absent / failed (L19).

    Smart-constructor union: the two-optional tuple is gone. A failed or
    absent presence carries no ipv4, and a present presence carries no error -
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

def _run_tailscale(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["tailscale", *args],
        capture_output=True, text=True, timeout=5, check=False,
    )


def _tailscale_presence_from_parsed(parsed: Any) -> TailscalePresence | None:
    self_info = parsed.get("Self") or {}
    ips = _tailscale_ips_from_self(self_info)
    if not ips:
        return None
    return TailscalePresence.present_with(ips[0], _tailscale_dns_from_self(self_info))


def _tailscale_ips_from_self(self_info: dict[str, Any]) -> list[str]:
    return [ip for ip in self_info.get("TailscaleIPs") or [] if is_tailscale_ip(ip)]


def _tailscale_dns_from_self(self_info: dict[str, Any]) -> str | None:
    return (self_info.get("DNSName") or "").rstrip(".") or None


def _tailscale_from_status_json() -> TailscalePresence | None:
    result = _run_tailscale("status", "--json")
    if result.returncode != 0:
        return None
    return _tailscale_presence_from_parsed(json.loads(result.stdout))


def _tailscale_from_ip_v4() -> TailscalePresence | None:
    result = _run_tailscale("ip", "-4")
    if result.returncode != 0:
        return None
    for line in result.stdout.split():
        if is_tailscale_ip(line.strip()):
            return TailscalePresence.present_with(line.strip(), None)
    return None


def _tailscale_failed_or_absent(
    status_failed: str | None, ip_failed: str | None
) -> TailscalePresence:
    if status_failed:
        return TailscalePresence.failed(status_failed)
    if ip_failed:
        return TailscalePresence.failed(ip_failed)
    return TailscalePresence.absent()


def tailscale_status() -> TailscalePresence:
    """Tailnet presence for this host (CLI-backed, no interface sniffing).

    Requires the Tailscale CLI (`tailscale status` or `tailscale ip`). Interface
    scans for any CGNAT address are intentionally not used for bind decisions -
    that could treat a non-tailnet 100.64/10 address as "tailnet-only" and skip
    the normal non-loopback auth rules.
    """
    present, status_failed = _probe_tailscale_status_json()
    if present is not None:
        return present
    present, ip_failed = _probe_tailscale_ip()
    if present is not None:
        return present
    return _tailscale_failed_or_absent(status_failed, ip_failed)


def _probe_tailscale_status_json() -> tuple[TailscalePresence | None, str | None]:
    try:
        return _tailscale_from_status_json(), None
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError) as error:
        return None, f"tailscale status failed: {error}"


def _probe_tailscale_ip() -> tuple[TailscalePresence | None, str | None]:
    try:
        return _tailscale_from_ip_v4(), None
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"tailscale ip failed: {error}"


def _iter_profile_files(directory: Path) -> list[Path]:
    try:
        return sorted(
            (
                path
                for path in directory.iterdir()
                if path.suffix.lower() in (".env", ".json") and not path.name.startswith(".")
            ),
            key=lambda path: path.name.lower(),
        )
    except OSError:
        return []


def _try_profile_from_file(file: Path) -> Profile | None:
    try:
        values = (
            parse_json_profile(file)
            if file.suffix.lower() == ".json"
            else parse_env_profile(file)
        )
        return Profile(name=file.stem, values=values)
    except (AgentError, OSError, ValueError, json.JSONDecodeError) as error:
        sys.stderr.write(f"[profiles] skipping {file.name}: {error}\n")
        return None


def _conflicts_from_endpoint_groups(
    groups: dict[str, list[str]],
) -> dict[str, tuple[str, list[str]]]:
    result: dict[str, tuple[str, list[str]]] = {}
    for endpoint, names in groups.items():
        result.update(_conflicts_for_endpoint(endpoint, names))
    return result


def _conflicts_for_endpoint(
    endpoint: str, names: list[str]
) -> dict[str, tuple[str, list[str]]]:
    if len(names) <= 1:
        return {}
    return {
        name: (endpoint, sorted(n for n in names if n != name))
        for name in sorted(names)
    }


class ProfileRepository:
    def __init__(self, directory: Path):
        self.directory = directory

    def _load_profile_files(self) -> dict[str, Profile]:
        profiles: dict[str, Profile] = {}
        for file in _iter_profile_files(self.directory):
            profile = _try_profile_from_file(file)
            if profile is not None:
                profiles[file.stem] = profile
        return profiles

    def _claim_path_under_directory(self, claim: dict[str, Any], directory: Path) -> bool:
        claim_path = Path(str(claim.get("path") or ""))
        try:
            claim_path.resolve().relative_to(directory)
            return True
        except (ValueError, OSError):
            return False

    def _profile_from_nested_claim(self, claim: dict[str, Any]) -> Profile | None:
        try:
            return profile_from_claim(claim)
        except (AgentError, OSError, TypeError, ValueError) as error:
            sys.stderr.write(f"[profiles] skipping claim {claim.get('path')}: {error}\n")
            return None

    def _resolved_profile_directory(self) -> Path:
        try:
            return self.directory.expanduser().resolve()
        except OSError:
            return self.directory

    def _merge_nested_claims(self, profiles: dict[str, Profile]) -> None:
        directory = self._resolved_profile_directory()
        for claim in scan_port_claim_directories(
            roots=[self.directory],
            agent_root=None,
            listeners=[],
        ):
            if not self._claim_path_under_directory(claim, directory):
                continue
            profile = self._profile_from_nested_claim(claim)
            if profile is None:
                continue
            profiles.setdefault(profile.name, profile)

    def load(self) -> dict[str, Profile]:
        if not path_is_dir(self.directory):
            return {}
        profiles = self._load_profile_files()
        self._merge_nested_claims(profiles)
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
        return _conflicts_from_endpoint_groups(groups)

    def ensure_unique(self, name: str, action: str, profiles: dict[str, Profile]) -> None:
        conflict = self.conflicts(profiles).get(name)
        if conflict:
            endpoint, others = conflict
            raise ProfileConflictError(
                f"Cannot {action} {name}: endpoint {endpoint} is also configured for {', '.join(others)}."
            )

def _adapter_start_command(
    profile: Profile,
    runtime: str,
    host: str,
    port: str,
    model: str,
    model_file: str,
) -> str:
    builder = _ADAPTER_START.get(runtime)
    if builder is not None:
        return builder(profile, host, port, model, model_file)
    return _unsupported_adapter_start(profile, runtime)


def _vllm_start_command(profile: Profile, host: str, port: str, model: str) -> str:
    return (
        f"vllm serve {shlex.quote(model)} --host {shlex.quote(host)} --port {shlex.quote(port)}"
        f" --served-model-name {shlex.quote(profile.server_model_id)}"
    )


def _llamacpp_start_command(profile: Profile, host: str, port: str, model_file: str) -> str:
    if not model_file:
        raise InvalidProfileError(
            f"{profile.name}: llama.cpp launches need MODEL_FILE (or MODEL_PATH) or an explicit START_COMMAND"
        )
    return (
        f"llama-server -m {shlex.quote(model_file)} --host {shlex.quote(host)}"
        f" --port {shlex.quote(port)} -a {shlex.quote(profile.server_model_id)}"
    )


def _sglang_start_command(host: str, port: str, model: str) -> str:
    return (
        f"python3 -m sglang.launch_server --model-path {shlex.quote(model)}"
        f" --host {shlex.quote(host)} --port {shlex.quote(port)}"
    )


def _tgi_start_command(host: str, port: str, model: str) -> str:
    return (
        f"text-generation-launcher --model-id {shlex.quote(model)}"
        f" --hostname {shlex.quote(host)} --port {shlex.quote(port)}"
    )


def _unsupported_adapter_start(profile: Profile, runtime: str) -> str:
    _, _, launch_mode = profile.runtime_spec
    if launch_mode == "external":
        raise UnsupportedError(
            f"{profile.name}: runtime {runtime} is externally managed; the agent only reports its health"
        )
    raise InvalidProfileError(
        f"{profile.name}: no launch template for runtime {runtime}; set START_COMMAND"
    )


_ADAPTER_START = {
    "vllm": lambda profile, host, port, model, model_file: _vllm_start_command(
        profile, host, port, model
    ),
    "llama.cpp": lambda profile, host, port, model, model_file: _llamacpp_start_command(
        profile, host, port, model_file
    ),
    "sglang": lambda profile, host, port, model, model_file: _sglang_start_command(
        host, port, model
    ),
    "tgi": lambda profile, host, port, model, model_file: _tgi_start_command(
        host, port, model
    ),
}


def _explicit_start_command(profile: Profile) -> str:
    return (profile.get("START_COMMAND") or "").strip()


def _start_model_fields(profile: Profile) -> tuple[str, str, str, str]:
    host = first_present(profile.get("HOST"), "127.0.0.1")
    extra = (profile.get("EXTRA_ARGS") or "").strip()
    model = first_present(profile.get("MODEL_PATH"), profile.get("MODEL_REPO"), profile.request_model)
    model_file = first_present(profile.get("MODEL_FILE"), profile.get("MODEL_PATH"), "")
    return host, extra, model, model_file


def _require_managed_start(profile: Profile) -> None:
    if (profile.get("LAUNCH_MODE") or "").lower() == "external":
        raise UnsupportedError(
            f"{profile.name}: externally managed endpoint; set START_COMMAND or a launch claim to start"
        )


def build_start_command(profile: Profile) -> str:
    """Return the shell command that launches this profile's model server."""
    explicit = _explicit_start_command(profile)
    if explicit:
        return explicit
    _require_managed_start(profile)
    host, extra, model, model_file = _start_model_fields(profile)
    command = _adapter_start_command(
        profile, profile.runtime, host, profile.endpoint_port, model, model_file
    )
    return _wrap_start_command(command, extra, (profile.get("VENV") or "").strip())


def _wrap_start_command(command: str, extra: str, venv: str) -> str:
    if extra:
        command = f"{command} {extra}"
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
    mem = sample_memory()
    cpu_percent = sample_cpu_percent()
    gpus, gpu_source, vram_by_pid, proc_names = _gpu_snapshot_fields(gpu)
    apply_unified_memory_vram(gpus, vram_by_pid, mem if isinstance(mem, dict) else None)
    return _assembled_host_metrics(gpu, mem, gpus, gpu_source, proc_names, cpu_percent)


def _copied_gpu_entries(gpu: dict[str, Any]) -> list[dict[str, Any]]:
    return [dict(entry) for entry in (gpu.get("gpus") or [])]


def _gpu_snapshot_fields(gpu: dict[str, Any]) -> tuple[list[dict[str, Any]], str, Any, Any]:
    # Copy GPU dicts so UMA fill does not mutate the nvidia-smi TTL cache.
    return (
        _copied_gpu_entries(gpu),
        gpu.get("source") or "unavailable",
        gpu.get("vram_by_pid") or {},
        gpu.get("process_names") or {},
    )


def _host_uptime_seconds() -> int | None:
    uptime = read_uptime_seconds()
    return round(uptime) if uptime is not None else None


def _assembled_host_metrics(
    gpu: dict[str, Any],
    mem: Any,
    gpus: list[dict[str, Any]],
    gpu_source: str,
    proc_names: dict[Any, Any],
    cpu_percent: Any,
) -> dict[str, Any]:
    return {
        "host": socket.gethostname(),
        "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "cpu_percent": cpu_percent,
        "memory": mem,
        "gpus": gpus,
        "gpu_source": gpu_source,
        "processes": _gpu_process_rows(gpu, proc_names),
        "uptime_seconds": _host_uptime_seconds(),
        "storage": storage_usage("/"),
        "network": sample_network_rates(),
        "tailscale": tailscale_health_snapshot(),
        "agent_version": AGENT_VERSION,
    }


def _gpu_process_rows(gpu: dict[str, Any], proc_names: dict[Any, Any]) -> list[dict[str, Any]]:
    return [
        {
            "pid": pid,
            "vram_mb": round(float(mb) * 10) / 10,
            "name": proc_names.get(pid),
        }
        for pid, mb in sorted((gpu.get("vram_by_pid") or {}).items())
    ]


def _default_root() -> Path:
    return Path.home() / ".local/share/model-switchboard-agent"

def preferred_profiles_directory() -> Path:
    """Visible default: ~/model-profiles (not buried under the agent install root)."""
    return Path.home() / "model-profiles"

try:
    import fcntl  # POSIX advisory locks; unavailable on Windows.
except ImportError:  # pragma: no cover - Windows only
    fcntl = None  # type: ignore[assignment]

def save_agent_config(root: Path, updates: dict[str, Any]) -> Path:
    """Merge *updates* into config.json, cross-process safe.

    SAFETY (multi-writer contract): config.json is written by the running
    agent (set-profiles-dir), the installer (driven by the Mac deployer over
    SSH), and `link` - concurrently across processes. All writers MUST use
    this flock + atomic-replace pattern:
      - flock serializes the read-modify-write between processes (an
        in-process Lock cannot stop two agents/installers).
      - write <path>.tmp then os.replace, so a reader never sees a truncated
        file (a mid-write crash previously left config.json empty and
        silently reset profiles_dir to the default).
    """
    root = root.expanduser()
    root.mkdir(parents=True, exist_ok=True)
    path = agent_config_path(root)
    with open(_agent_config_lock_path(path), "w", encoding="utf-8") as lock_handle:
        _flock_exclusive(lock_handle)
        _merge_locked_agent_config(path, root, updates)
    return path


def _agent_config_lock_path(path: Path) -> Path:
    # NOTE: Path.with_suffix would STRIP the ".json" out of "config.json"
    # (config.json -> config.lock), producing a lock name that does not match
    # the installer's config.json.lock. Build names by concatenation; the
    # installer's writer must keep using exactly these two names.
    return path.parent / (path.name + ".lock")


def _flock_exclusive(lock_handle) -> None:
    if fcntl is not None:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)


def _merge_locked_agent_config(path: Path, root: Path, updates: dict[str, Any]) -> None:
    payload = load_agent_config(root)
    payload.update(updates)
    _write_agent_config_payload(path, payload)


def _write_agent_config_payload(path: Path, payload: dict[str, Any]) -> None:
    temporary = path.parent / (path.name + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, path)
    try:
        path.chmod(0o600)
    except OSError:
        pass

def save_profiles_directory(root: Path, profiles_dir: Path) -> Path:
    resolved = profiles_dir.expanduser().resolve()
    save_agent_config(root, {"profiles_dir": str(resolved)})
    return resolved


def _benchmark_chat_request(profile: Profile, prompt: dict[str, Any]) -> urllib.request.Request:
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
    return urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )


def _benchmark_success_row(
    prompt: dict[str, Any],
    elapsed_s: float,
    completion_tokens: int,
    prompt_tokens: int,
) -> dict[str, Any]:
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


def _benchmark_markdown_row(report: dict[str, Any]) -> str:
    averages = report.get("averages") or {}
    return (
        f"| {report.get('profile')} | {report.get('runtime')} | "
        f"{averages.get('ttft_ms') or '-'} | {averages.get('decode_tokens_per_sec') or '-'} |"
    )


def _benchmark_markdown_table(generated_at: str, reports: list[dict[str, Any]]) -> str:
    lines = [
        "# Model Switchboard Benchmark",
        "",
        f"Generated: {generated_at}",
        "",
        "| Profile | Runtime | TTFT ms | Decode tok/s |",
        "|---|---|---:|---:|",
    ]
    for report in reports:
        lines.append(_benchmark_markdown_row(report))
    return "\n".join(lines) + "\n"


def _status_row_fields(
    profile: Profile,
    *,
    display_name: str,
    label: str,
    tags: Any,
    launch_mode: Any,
    pid: int | None,
    alive: bool,
    ready: bool,
    ready_flag: bool,
    server_ids: list[str],
    rss_mb: Any,
    vram_mb: Any,
    command: Any,
    llm_rates: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        **_status_identity_payload(profile, display_name, label, tags, launch_mode),
        **_status_endpoint_payload(profile),
        **_status_process_payload(
            pid=pid,
            alive=alive,
            ready=ready,
            ready_flag=ready_flag,
            server_ids=server_ids,
            rss_mb=rss_mb,
            vram_mb=vram_mb,
            command=command,
            log_path=profile.log_path,
            origin=profile.origin,
            missing_artifacts=missing_local_model_artifacts(profile.values),
            llm_rates=llm_rates,
        ),
    }


def _status_identity_payload(
    profile: Profile,
    display_name: str,
    label: str,
    tags: Any,
    launch_mode: Any,
) -> dict[str, Any]:
    return {
        "profile": profile.name,
        "display_name": display_name,
        "runtime": profile.runtime,
        "runtime_label": label,
        "runtime_tags": tags if isinstance(tags, list) else profile.runtime_tags,
        "launch_mode": launch_mode,
    }


def _status_endpoint_payload(profile: Profile) -> dict[str, Any]:
    return {
        "host": profile.endpoint_host,
        "port": profile.endpoint_port,
        "base_url": profile.base_url,
        "request_model": profile.request_model,
        "server_model_id": profile.server_model_id,
    }


def _status_process_payload(
    *,
    pid: int | None,
    alive: bool,
    ready: bool,
    ready_flag: bool,
    server_ids: list[str],
    rss_mb: Any,
    vram_mb: Any,
    command: Any,
    log_path: Any,
    origin: Any,
    missing_artifacts: Any,
    llm_rates: dict[str, Any] | None,
) -> dict[str, Any]:
    return {
        "pid": pid,
        "running": alive,
        "ready": ready_flag,
        "server_ids": server_ids if (alive or ready) else [],
        "rss_mb": rss_mb,
        "vram_mb": vram_mb,
        "command": command,
        "log_path": log_path,
        "source": origin,
        "missing_artifacts": missing_artifacts,
        "serving": llm_rates,
    }


def _profile_ports_from_loaded(loaded: dict[str, Any]) -> set[int]:
    profile_ports: set[int] = set()
    for profile in loaded.values():
        try:
            profile_ports.add(int(profile.endpoint_port))
        except (TypeError, ValueError):
            pass
    return profile_ports


def _spawn_environment(profile: Profile, canonical: str) -> dict[str, str]:
    environment = dict(os.environ)
    environment.update(profile.values)
    environment["MODEL_PROFILE"] = canonical
    environment["MODEL_SWITCHBOARD_PROFILE_LOADED"] = "1"
    environment["MODEL_SWITCHBOARD_AGENT"] = "1"
    return environment


def _popen_profile_bash(
    command: str,
    log_handle,
    environment: dict[str, str],
    *,
    canonical: str,
    cwd: Path,
) -> subprocess.Popen[str]:
    try:
        return subprocess.Popen(
            ["/bin/bash", "-lc", command],
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            cwd=cwd,
            env=environment,
            start_new_session=True,
        )
    except OSError as error:
        raise OperationFailedError(f"failed to launch {canonical}: {error}") from error


def _popen_profile(
    profile: Profile,
    command: str,
    environment: dict[str, str],
    *,
    canonical: str,
    cwd: Path,
) -> subprocess.Popen[str]:
    log_path = Path(profile.log_path)
    try:
        log_handle = log_path.open("ab")
    except OSError as error:
        raise OperationFailedError(f"cannot open log {log_path}: {error}") from error
    try:
        return _popen_profile_bash(
            command, log_handle, environment, canonical=canonical, cwd=cwd
        )
    finally:
        log_handle.close()


def _any_iterdir_match(directory: Path, matches) -> bool:
    try:
        for path in directory.iterdir():
            if matches(path):
                return True
    except OSError:
        return False
    return False


def _directory_has_matching_child(directory: Path, matches) -> bool:
    if not path_is_dir(directory):
        return False
    return _any_iterdir_match(directory, matches)


def _directory_has_profile_files(directory: Path) -> bool:
    return _directory_has_matching_child(directory, _is_loadable_profile_filename)


def _is_loadable_profile_filename(path: Path) -> bool:
    if path.suffix.lower() not in (".env", ".json") or path.name.startswith("."):
        return False
    return not path.name.endswith(".example")


def _directory_has_port_claims(directory: Path) -> bool:
    """True when directory has a one-level port-claim child (flags.env / launch.sh / ...)."""
    return _directory_has_matching_child(directory, _is_port_claim_child)


def _is_port_named_dir(path: Path) -> bool:
    try:
        return path_is_dir(path) and bool(PORT_CLAIM_DIR_RE.fullmatch(path.name))
    except OSError:
        return False


def _is_port_claim_child(path: Path) -> bool:
    if not _is_port_named_dir(path):
        return False
    return any(path_is_regular_file(path / marker) for marker in PORT_CLAIM_MARKERS)

def _directory_has_loadable_profiles(directory: Path) -> bool:
    return _directory_has_profile_files(directory) or _directory_has_port_claims(directory)

def _profiles_dir_from_scan_roots(root: Path) -> Path | None:
    """First configured scan_roots entry that already holds port-claim markers."""
    for scan_root in configured_scan_roots(root):
        try:
            resolved = scan_root.expanduser().resolve()
        except OSError:
            continue
        if _directory_has_port_claims(resolved):
            return resolved
    return None

def _configured_profiles_dir(root: Path) -> Path | None:
    configured_raw = load_agent_config(root).get("profiles_dir")
    if isinstance(configured_raw, str) and configured_raw.strip():
        return Path(configured_raw).expanduser().resolve()
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
    return _fallback_profiles_directory(root)


def _maybe_resolve(path: Path, *, resolve: bool) -> Path:
    return path.resolve() if resolve else path


def _loadable_profiles_dir(path: Path | None, *, resolve: bool = False) -> Path | None:
    if path is None or not _directory_has_loadable_profiles(path):
        return None
    return _maybe_resolve(path, resolve=resolve)


def _scan_or_configured_profiles_dir(
    root: Path, configured: Path | None, preferred: Path
) -> Path:
    scan_hit = _profiles_dir_from_scan_roots(root)
    if scan_hit is not None:
        return scan_hit
    return first_present(configured, preferred)


def _fallback_profiles_directory(root: Path) -> Path:
    configured = _configured_profiles_dir(root)
    if hit := _loadable_profiles_dir(configured):
        return hit
    if hit := _loadable_profiles_dir(root.expanduser() / "model-profiles", resolve=True):
        return hit
    preferred = preferred_profiles_directory().resolve()
    if hit := _loadable_profiles_dir(preferred):
        return hit
    return _scan_or_configured_profiles_dir(root, configured, preferred)

def _peek_profile_keys(path: Path) -> set[str]:
    """Best-effort key set for scan scoring - never executes file contents."""
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return set()
    if path.suffix.lower() == ".json":
        return _peek_json_keys(text)
    return _peek_env_keys(text)


def _peek_json_keys(text: str) -> set[str]:
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return set()
    if not isinstance(parsed, dict):
        return set()
    return {str(key) for key in parsed.keys()}


def _peek_env_keys(text: str) -> set[str]:
    keys: set[str] = set()
    for raw_line in text.splitlines():
        key = _env_assignment_key(raw_line)
        if key:
            keys.add(key)
    return keys


def _env_assignment_key(raw_line: str) -> str | None:
    line = _stripped_assignment_line(raw_line)
    if line is None:
        return None
    parsed = _assignment_key_rest(line)
    return parsed[0] if parsed else None


def _live_non_placeholder_model(request: Any) -> Any:
    if request and not str(request).startswith("port-"):
        return request
    return None


def _int_or_word_count(value: Any, text: Any) -> int:
    if isinstance(value, int):
        return value
    return max(1, len(str(text).split()))

def _is_candidate_profile_filename(path: Path) -> bool:
    if path.suffix.lower() not in (".env", ".json") or path.name.startswith("."):
        return False
    return ".example" not in path.name


def looks_like_profile_file(path: Path) -> bool:
    if not _is_candidate_profile_filename(path):
        return False
    keys = _peek_profile_keys(path)
    return bool(keys) and _profile_file_signals(keys)


def _has_model_identity_signal(signals: set[str]) -> bool:
    return bool(signals & {"RUNTIME", "MODEL_FILE", "MODEL_PATH", "MODEL_REPO", "DISPLAY_NAME"})


def _has_launch_signal(signals: set[str]) -> bool:
    return "REQUEST_MODEL" in signals or "START_COMMAND" in signals


def _profile_file_signals(keys: set[str]) -> bool:
    signals = keys & PROFILE_SIGNAL_KEYS
    if _has_launch_signal(signals):
        return True
    if "PORT" in signals or "BASE_URL" in signals:
        return _has_model_identity_signal(signals)
    return False

def _walk_profile_scan(
    directory: Path,
    depth: int,
    max_depth: int,
    tallies: dict[Path, list[str]],
) -> None:
    if depth > max_depth:
        return
    try:
        entries = list(directory.iterdir())
    except OSError:
        return
    for entry in entries:
        _profile_scan_entry(entry, depth, max_depth, tallies)


def _tally_profile_file(entry: Path, tallies: dict[Path, list[str]]) -> None:
    if looks_like_profile_file(entry):
        tallies.setdefault(entry.parent.resolve(), []).append(entry.name)


def _profile_scan_entry(
    entry: Path,
    depth: int,
    max_depth: int,
    tallies: dict[Path, list[str]],
) -> None:
    name = entry.name
    if name in PROFILE_SCAN_SKIP_DIRS:
        return
    try:
        is_dir = entry.is_dir()
    except OSError:
        return
    if is_dir:
        _scan_profile_directory(entry, name, depth, max_depth, tallies)
        return
    _tally_profile_file(entry, tallies)


def _scan_profile_directory(
    entry: Path, name: str, depth: int, max_depth: int, tallies: dict[Path, list[str]]
) -> None:
    if not name.startswith("."):
        _walk_profile_scan(entry, depth + 1, max_depth, tallies)


def _tally_known_profile_dirs(tallies: dict[Path, list[str]]) -> None:
    for extra in (preferred_profiles_directory(), _default_root() / "model-profiles"):
        resolved = _resolved_existing_dir(extra)
        if resolved is None or resolved in tallies:
            continue
        _tally_profile_dir_children(resolved, tallies)


def _resolved_existing_dir(path: Path) -> Path | None:
    try:
        resolved = path.expanduser().resolve()
    except OSError:
        return None
    if not path_is_dir(resolved):
        return None
    return resolved


def _tally_profile_dir_children(directory: Path, tallies: dict[Path, list[str]]) -> None:
    try:
        children = list(directory.iterdir())
    except OSError:
        return
    for path in children:
        if looks_like_profile_file(path):
            tallies.setdefault(directory, []).append(path.name)


def scan_profile_directories(
    home: Path | None = None,
    *,
    max_depth: int = PROFILE_SCAN_MAX_DEPTH,
    limit: int = PROFILE_SCAN_MAX_CANDIDATES,
) -> list[dict[str, Any]]:
    """Find directories that already hold Switchboard-shaped launch .env/.json files.

    Does not invent flags - only groups files an AI or user already wrote
    (often `model.env`, `qwen.env`, …) by parent folder.
    """
    home = (home or Path.home()).expanduser()
    tallies: dict[Path, list[str]] = {}
    _walk_profile_scan(home, 0, max_depth, tallies)
    _tally_known_profile_dirs(tallies)
    return _ranked_profile_scan_results(tallies, limit)


def _ranked_profile_scan_results(
    tallies: dict[Path, list[str]], limit: int
) -> list[dict[str, Any]]:
    ranked = sorted(
        tallies.items(),
        key=lambda item: (-len(item[1]), str(item[0])),
    )
    return [_profile_scan_result(directory, files) for directory, files in ranked[:limit]]


def _profile_scan_result(directory: Path, files: list[str]) -> dict[str, Any]:
    unique_files = sorted(set(files))
    return {
        "path": str(directory),
        "profile_count": len(unique_files),
        "files": unique_files[:12],
    }

def _choose_blank_profiles_directory(
    current: Path,
    candidates: list[dict[str, Any]],
) -> Path:
    if current.exists() or _directory_has_profile_files(current):
        return current
    if candidates:
        return Path(candidates[0]["path"])
    return preferred_profiles_directory()


def _digit_candidate_index(answer: str, candidates: list[dict[str, Any]]) -> int | None:
    if not answer.isdigit() or not candidates:
        return None
    return int(answer)


def _choose_digit_profiles_directory(
    answer: str,
    candidates: list[dict[str, Any]],
) -> Path | None:
    index = _digit_candidate_index(answer, candidates)
    if index is None:
        return None
    if 1 <= index <= len(candidates):
        return Path(candidates[index - 1]["path"])
    raise UsageError(f"No candidate numbered {index}")


def _choose_profiles_directory(
    answer: str,
    current: Path,
    candidates: list[dict[str, Any]],
) -> Path:
    if not answer:
        return _choose_blank_profiles_directory(current, candidates)
    if answer == "0":
        return preferred_profiles_directory()
    if (chosen := _choose_digit_profiles_directory(answer, candidates)) is not None:
        return chosen
    return Path(answer)


def _print_profile_scan_candidates(candidates: list[dict[str, Any]]) -> None:
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


def _print_profiles_directory_prompt(current: Path, candidates: list[dict[str, Any]]) -> None:
    print("Model profiles are plain .env/.json launch files (ports, START_COMMAND, …).")
    print("Switchboard only needs the folder that already holds them - it will not")
    print("author flags for every runtime fork.")
    print()
    print(f"Current profiles folder: {current}")
    if candidates:
        _print_profile_scan_candidates(candidates)
    else:
        _print_empty_profile_scan()
    print()


def _print_empty_profile_scan() -> None:
    print("No launch-looking .env/.json folders found under your home directory.")
    print("  [Enter] keep current / use ~/model-profiles")
    print("  or paste the folder path where your model .env files live")


def _live_item_for_port(live: list[dict[str, Any]], port: int) -> dict[str, Any] | None:
    for item in live:
        try:
            if int(item["port"]) == port:
                return item
        except (KeyError, TypeError, ValueError):
            continue
    return None


def _profile_from_discovered_item(name: str, port: int, item: dict[str, Any]) -> Profile:
    request = str(first_present(item.get("request_model"), f"port-{port}"))
    return Profile(
        name=name,
        values={
            "DISPLAY_NAME": str(first_present(item.get("display_name"), request)),
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


def _digit_ports(items: list[dict[str, Any]]) -> set[int]:
    return {
        int(item["port"])
        for item in items
        if str(item.get("port") or "").isdigit()
    }


def _items_by_digit_port(items: list[dict[str, Any]]) -> dict[int, dict[str, Any]]:
    return {
        int(item["port"]): item
        for item in items
        if str(item.get("port") or "").isdigit()
    }


def _benchmark_loaded_names(
    loaded: dict[str, Any],
    profiles: list[str] | None,
) -> list[str]:
    if not profiles:
        return sorted(loaded.keys())
    names = _names_present_in(loaded, profiles)
    if names:
        return names
    missing = _first_name_absent_from(loaded, profiles)
    if missing:
        raise ProfileNotFoundError(missing)
    return names


def _names_present_in(loaded: dict[str, Any], profiles: list[str]) -> list[str]:
    return [name for name in profiles if name in loaded]


def _first_name_absent_from(loaded: dict[str, Any], profiles: list[str]) -> str | None:
    for name in profiles:
        if name not in loaded:
            return name
    return None


def _openai_model_ids(body: bytes) -> list[str] | None:
    try:
        parsed_body = json.loads(body)
        entries = parsed_body.get("data", [])
    except (json.JSONDecodeError, AttributeError):
        return None
    return openai_model_ids_from_entries(entries)


def _token_is_port_flag(argv: list[str], index: int, token: str, port: str) -> bool:
    if token == f"--port={port}":
        return True
    return token == "--port" and index + 1 < len(argv) and argv[index + 1] == port


def _argv_has_port_flag(argv: list[str], port: str) -> bool:
    return any(
        _token_is_port_flag(argv, index, token, port)
        for index, token in enumerate(argv)
    )


def _foreign_process_command(pid: int) -> str | None:
    if pid == os.getpid():
        return None
    command = (process_command(pid) or "").lower()
    return command or None


def _optional_profile_names(payload: dict[str, Any]) -> list[str] | None:
    selected = payload.get("profiles")
    if selected is None:
        return None
    return _require_string_list(selected, "profiles must be a list of strings")


def _require_string_list(value: Any, message: str) -> list[str]:
    if not isinstance(value, list):
        raise UsageError(message)
    return [_require_nonempty_string(item, message) for item in value]


def _require_nonempty_string(item: Any, message: str) -> str:
    if not isinstance(item, str) or not item:
        raise UsageError(message)
    return item


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
    _print_profiles_directory_prompt(current, candidates)
    chosen = _choose_profiles_directory(
        _read_profiles_folder_answer(reader), current, candidates
    )
    chosen = chosen.expanduser().resolve()
    chosen.mkdir(parents=True, exist_ok=True)
    save_profiles_directory(root, chosen)
    print(f"Using profiles folder: {chosen}")
    return chosen


def _read_profiles_folder_answer(reader: Callable[[str], str]) -> str:
    try:
        return reader("Profiles folder? ").strip()
    except EOFError:
        return ""


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

    def _validate_bind(self, token: str) -> None:
        if self.tailscale_bind:
            self._require_tailscale_bind(token)
            return
        if is_loopback(self.host):
            return
        self._require_unsafe_bind(token)

    def _require_tailscale_bind(self, token: str) -> None:
        if not is_tailscale_ip(self.host):
            raise InvalidConfigurationError(
                f"--tailscale bind resolved a non-Tailscale address: {self.host}"
            )
        if not token and not self.allow_unauthenticated:
            raise InvalidConfigurationError(
                "--tailscale requires a bearer auth token "
                "(--auth-token / --auth-token-file), or pass "
                "--allow-unauthenticated for a personal tailnet"
            )

    def _require_unsafe_bind(self, token: str) -> None:
        if not self.unsafe_bind:
            raise InvalidConfigurationError(
                f"non-loopback agent bind requires --unsafe-bind: {self.host}"
            )
        if not token:
            raise InvalidConfigurationError(
                "non-loopback agent bind requires a bearer auth token"
            )

    def __post_init__(self) -> None:
        token = (self.auth_token or "").strip()
        if token and len(token.encode("utf-8")) < MINIMUM_TOKEN_BYTES:
            raise InvalidConfigurationError(
                f"auth token must be at least {MINIMUM_TOKEN_BYTES} bytes"
            )
        self._validate_bind(token)
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
    in either direction - llama.cpp often returns a full weights path as `id`
    while claim profiles store SERVER_MODEL_ID as the basename (or the
    reverse). Explicit aliases (e.g. REQUEST_MODEL) join the candidate set.
    L23: None (no expected id) NEVER matches - identity must be verifiable.
    Pass ANY_MODEL_ID to accept any non-empty id list explicitly.
    """
    if expected is ANY_MODEL_ID or expected == ANY_MODEL_ID:
        return bool(ids)
    if not expected:
        return False
    return _ids_match_candidates(_expected_id_candidates(expected, aliases), ids)


def _expected_id_candidates(expected: str, aliases: tuple[str, ...]) -> set[str]:
    candidates = {expected}
    for alias in aliases:
        alias_s = (alias or "").strip()
        if alias_s:
            candidates.add(alias_s)
    return candidates


def _ids_match_by_basename(candidates: set[str], ids: list[str]) -> bool:
    id_names = {Path(item).name for item in ids}
    return any(Path(candidate).name in id_names or candidate in id_names for candidate in candidates)


def _ids_match_candidates(candidates: set[str], ids: list[str]) -> bool:
    if candidates & set(ids):
        return True
    return _ids_match_by_basename(candidates, ids)

class AgentService:
    def __init__(self, configuration: AgentConfiguration):
        self.configuration = configuration
        self.profiles = ProfileRepository(configuration.profiles_directory)
        self._mutation_lock = threading.RLock()
        self._watchdog_suppressed_until = 0.0
        self._watchdog_timer: threading.Timer | None = None
        # Profiles started by *this* agent process. Crash-recovery restarts only
        # these - an agent reboot / login never spontaneously loads a model.
        self._supervised: set[str] = set()
        self._benchmark_lock = threading.Lock()
        self._benchmark_running = False

    def _port_from_profile_name(self, name: str) -> int | None:
        if not name.startswith("port-"):
            return None
        try:
            return int(name.removeprefix("port-"))
        except ValueError:
            return None

    def _claim_profile_for_port(self, claims: list[dict[str, Any]], port: int) -> Profile | None:
        for claim in claims:
            try:
                if int(claim["port"]) == port:
                    return profile_from_claim(claim)
            except (KeyError, TypeError, ValueError):
                continue
        return None

    def _discovered_profile_for_port(
        self,
        name: str,
        port: int,
        listeners: list[dict[str, Any]],
    ) -> Profile | None:
        live = discover_live_model_endpoints(
            profile_ports=set(),
            claim_ports={port},
            listeners=listeners,
        )
        item = _live_item_for_port(live, port)
        if item is None:
            return None
        return _profile_from_discovered_item(name, port, item)

    def resolve_profile(self, name: str) -> Profile:
        """Profiles folder first; then claimed port folders (port-N); never invent.

        ``discovered-N`` is a status-only alias for unmanaged listeners. Mapping
        it onto a port-N claim would let API/CLI start a hidden row.
        """
        loaded = self.profiles.load()
        if name in loaded:
            return loaded[name]
        if name.startswith("discovered-"):
            raise ProfileNotFoundError(name)
        resolved = self._resolve_port_named_profile(name)
        if resolved is not None:
            return resolved
        raise ProfileNotFoundError(name)

    def _profile_for_named_port(
        self,
        name: str,
        port: int,
        listeners: list[dict[str, Any]],
    ) -> Profile | None:
        claims = scan_port_claim_directories(
            agent_root=self.configuration.root,
            listeners=listeners,
        )
        return self._claim_profile_for_port(claims, port) or self._discovered_profile_for_port(
            name, port, listeners
        )

    def _resolve_port_named_profile(self, name: str) -> Profile | None:
        port = self._port_from_profile_name(name)
        if port is None:
            return None
        listeners = list_listening_tcp()
        return self._profile_for_named_port(name, port, listeners)

    # -- status ------------------------------------------------------------

    def _status_payload_fields(
        self, statuses: list[dict[str, Any]], benchmark: dict[str, Any]
    ) -> dict[str, Any]:
        return {
            "statuses": statuses,
            "benchmark": benchmark,
            "integrations": [],
            "profiles_dir": str(self.configuration.profiles_directory),
            "controller_root": str(self.configuration.root),
        }

    def _selected_status_names(
        self, loaded: dict[str, Any], selected: list[str] | None
    ) -> list[str]:
        return selected if selected is not None else sorted(loaded.keys())

    def status_payload(self, selected: list[str] | None = None) -> dict[str, Any]:
        """Assemble controller status JSON (profiles + optional full discovery)."""
        loaded = self.profiles.load()
        conflicts = self.profiles.conflicts(loaded)
        names = self._selected_status_names(loaded, selected)
        # One inventory for profile port attribution (no N× socket/lsof) and,
        # when listing everything, claim scan + live discovery.
        listeners = list_listening_tcp()
        statuses, profile_ports = self._status_rows_for_names(
            names, loaded, conflicts, listeners
        )
        if selected is None:
            self._append_discovered_statuses(statuses, loaded, profile_ports, listeners)
        # Ready N/M is derived by Swift (ProfileRuntimeCounts) from board-visible
        # statuses - the single owner. The wire no longer carries counts.
        return self._status_payload_fields(statuses, self.benchmark_status())

    def _append_status_row_port(
        self,
        name: str,
        loaded: dict[str, Any],
        conflicts: dict[str, Any],
        listeners: list[dict[str, Any]],
        statuses: list[dict[str, Any]],
        profile_ports: set[int],
    ) -> None:
        row, port = self._status_row_for_name(name, loaded, conflicts, listeners)
        statuses.append(row)
        if port is not None:
            profile_ports.add(port)

    def _status_rows_for_names(
        self,
        names: list[str],
        loaded: dict[str, Any],
        conflicts: dict[str, Any],
        listeners: list[dict[str, Any]],
    ) -> tuple[list[dict[str, Any]], set[int]]:
        statuses: list[dict[str, Any]] = []
        profile_ports: set[int] = set()
        for name in names:
            self._append_status_row_port(
                name, loaded, conflicts, listeners, statuses, profile_ports
            )
        return statuses, profile_ports

    def _endpoint_port_or_none(self, profile: Profile) -> int | None:
        try:
            return int(profile.endpoint_port)
        except (TypeError, ValueError):
            return None

    def _status_row_for_name(
        self,
        name: str,
        loaded: dict[str, Any],
        conflicts: dict[str, Any],
        listeners: list[dict[str, Any]],
    ) -> tuple[dict[str, Any], int | None]:
        profile = loaded.get(name)
        if profile is None:
            raise ProfileNotFoundError(name)
        row = self.status(
            profile,
            allow_port_fallback=name not in conflicts,
            listeners=listeners,
        )
        return row, self._endpoint_port_or_none(profile)

    def _overlay_live_claim(self, claim: dict[str, Any], live: dict[str, Any]) -> dict[str, Any]:
        merged = dict(claim)
        merged.update(self._live_claim_overlay(claim, live))
        return merged

    def _merge_claim_with_live(self, claim: dict[str, Any], live: dict[str, Any] | None) -> dict[str, Any]:
        if not live:
            return self._empty_claim_status(claim, int(claim["port"]))
        return self._overlay_live_claim(claim, live)

    def _live_claim_overlay(self, claim: dict[str, Any], live: dict[str, Any]) -> dict[str, Any]:
        return {
            "pid": live.get("pid"),
            "command": live.get("command"),
            "ready": live.get("ready"),
            "server_ids": live.get("server_ids"),
            "base_url": live.get("base_url"),
            "runtime": first_known(live.get("runtime"), claim.get("runtime_hint")),
            "request_model": self._live_request_model(claim, live),
            "display_name": claim.get("display_name") or live.get("display_name"),
        }

    def _empty_claim_status(self, claim: dict[str, Any], port: int) -> dict[str, Any]:
        merged = dict(claim)
        merged["ready"] = False
        merged["request_model"] = claim.get("model_hint") or f"port-{port}"
        merged["runtime"] = first_known(claim.get("runtime_hint"))
        return merged

    def _live_request_model(self, claim: dict[str, Any], live: dict[str, Any]) -> Any:
        request = live.get("request_model")
        return _live_non_placeholder_model(request) or claim.get("model_hint") or request

    def _scan_status_claims(
        self,
        loaded: dict[str, Any],
        listeners: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        start_cmds = [profile.get("START_COMMAND") for profile in loaded.values()]
        return scan_port_claim_directories(
            roots=roots_hinted_by_commands(start_cmds) or None,
            agent_root=self.configuration.root,
            listeners=listeners,
        )

    def _append_discovered_statuses(
        self,
        statuses: list[dict[str, Any]],
        loaded: dict[str, Any],
        profile_ports: set[int],
        listeners: list[dict[str, Any]],
    ) -> None:
        claims = self._scan_status_claims(loaded, listeners)
        claim_ports = {int(item["port"]) for item in claims}
        listening = discover_live_model_endpoints(
            profile_ports=profile_ports,
            claim_ports=claim_ports,
            listeners=listeners,
        )
        covered_ports = _digit_ports(statuses)
        listening_by_port = _items_by_digit_port(listening)
        self._append_uncovered_claims(
            statuses, claims, covered_ports, listening_by_port, listeners
        )
        self._append_uncovered_listeners(
            statuses, listening, covered_ports, listeners
        )

    def _append_uncovered_claims(
        self,
        statuses: list[dict[str, Any]],
        claims: list[dict[str, Any]],
        covered_ports: set[int],
        listening_by_port: dict[int, dict[str, Any]],
        listeners: list[dict[str, Any]],
    ) -> None:
        for claim in claims:
            port = int(claim["port"])
            if port in covered_ports:
                continue
            statuses.append(
                status_dict_from_discovery(
                    self._merge_claim_with_live(claim, listening_by_port.get(port)),
                    source="claim",
                    profile_name=f"port-{port}",
                    listeners=listeners,
                )
            )
            covered_ports.add(port)

    def _append_uncovered_listeners(
        self,
        statuses: list[dict[str, Any]],
        listening: list[dict[str, Any]],
        covered_ports: set[int],
        listeners: list[dict[str, Any]],
    ) -> None:
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

    def _ports_inventory_maps(
        self,
        loaded: dict[str, Any],
        listeners: list[dict[str, Any]],
    ) -> tuple[list[dict[str, Any]], dict[int, dict[str, Any]], dict[int, dict[str, Any]]]:
        claims = scan_port_claim_directories(
            agent_root=self.configuration.root,
            listeners=listeners,
        )
        live = discover_live_model_endpoints(
            profile_ports=_profile_ports_from_loaded(loaded),
            claim_ports={int(item["port"]) for item in claims},
            listeners=listeners,
        )
        live_by_port = {int(item["port"]): item for item in live}
        claims_by_port = {int(item["port"]): item for item in claims}
        return claims, live_by_port, claims_by_port

    def ports_payload(self) -> dict[str, Any]:
        """Ports-style inventory: every listener + model probe outcome."""
        loaded = self.profiles.load()
        listeners = list_listening_tcp()
        claims, live_by_port, claims_by_port = self._ports_inventory_maps(loaded, listeners)
        ports = self._ports_from_listeners(listeners, live_by_port, claims_by_port)
        self._append_silent_claims(ports, claims, listeners)
        ports.sort(key=lambda item: int(item["port"]))
        return {
            "ports": ports,
            "profiles_dir": str(self.configuration.profiles_directory),
            "controller_root": str(self.configuration.root),
            "scan_roots_env": SCAN_ROOTS_ENV,
        }

    def _ports_from_listeners(
        self,
        listeners: list[dict[str, Any]],
        live_by_port: dict[int, dict[str, Any]],
        claims_by_port: dict[int, dict[str, Any]],
    ) -> list[dict[str, Any]]:
        ports: list[dict[str, Any]] = []
        for listener in listeners:
            port = int(listener["port"])
            ports.append(
                {
                    "port": port,
                    "pid": listener.get("pid"),
                    "command": listener.get("command"),
                    "bind": listener.get("bind"),
                    "looks_like_model": command_looks_like_model_server(listener.get("command")),
                    "model": live_by_port.get(port),
                    "claimed": claims_by_port.get(port),
                }
            )
        return ports

    def _append_silent_claims(
        self,
        ports: list[dict[str, Any]],
        claims: list[dict[str, Any]],
        listeners: list[dict[str, Any]],
    ) -> None:
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
        payload = _json_object_file(path)
        if payload is None:
            return None
        return self._latest_benchmark_payload(path, payload)

    def _latest_benchmark_payload(self, path: Path, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "generated_at": payload.get("generated_at"),
            "suite": payload.get("suite"),
            "profiles": payload.get("profiles") or [],
            "rows": [
                self._benchmark_summary_row(report)
                for report in payload.get("benchmarks") or []
                if isinstance(report, dict)
            ],
            "json_path": str(path),
            "markdown_path": str(self._benchmark_latest_md()),
        }

    def _benchmark_summary_row(self, report: dict[str, Any]) -> dict[str, Any]:
        averages = report.get("averages") or {}
        return {
            "profile": report.get("profile"),
            "runtime": report.get("runtime"),
            "ttft_ms": averages.get("ttft_ms"),
            "decode_tokens_per_sec": averages.get("decode_tokens_per_sec"),
            "e2e_tokens_per_sec": averages.get("e2e_tokens_per_sec"),
            "rss_mb": report.get("rss_mb"),
            "vram_mb": report.get("vram_mb"),
        }

    def benchmark_status(self) -> dict[str, Any]:
        self._discard_stale_benchmark_pid()
        return self._benchmark_status_payload(self._benchmark_log_path())

    def _benchmark_status_payload(self, log_path: Path) -> dict[str, Any]:
        running = self._benchmark_running
        return {
            "running": running,
            "pid": self._read_benchmark_pid() if running else None,
            "log_path": str(log_path) if log_path.exists() or running else None,
            "latest": self._latest_benchmark_report(),
        }

    def _discard_stale_benchmark_pid(self) -> None:
        # Clear stale pid files left after process crash.
        if not self._benchmark_running and self._benchmark_pid_file().exists():
            self._benchmark_pid_file().unlink(missing_ok=True)

    def _benchmark_target_names(self, profiles: list[str] | None) -> list[str]:
        names = _benchmark_loaded_names(self.profiles.load(), profiles)
        if not names:
            raise UsageError("no profiles available to benchmark")
        return names

    def _begin_benchmark(self) -> None:
        with self._benchmark_lock:
            if self._benchmark_running:
                raise OperationFailedError("benchmark already running")
            self._benchmark_running = True

    def _start_benchmark_worker(
        self,
        profiles: list[str] | None,
        suite: str,
        allow_concurrent: bool,
        keep_running: bool,
    ) -> None:
        names = self._benchmark_target_names(profiles)
        log_path = self._prepare_benchmark_log()
        self._launch_benchmark_thread(
            names,
            suite=suite,
            allow_concurrent=allow_concurrent,
            keep_running=keep_running,
            log_path=log_path,
        )

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
        self._begin_benchmark()
        # From here to the worker start, any failure MUST reset the flag or
        # every future benchmark is rejected with "already running" (the flag
        # is only cleared by the worker's finally or the validation paths).
        try:
            self._start_benchmark_worker(
                profiles, suite, allow_concurrent, keep_running
            )
        except BaseException:
            self._disarm_benchmark()
            raise
        return self.benchmark_status()

    def _disarm_benchmark(self) -> None:
        with self._benchmark_lock:
            self._benchmark_running = False

    def _prepare_benchmark_log(self) -> Path:
        log_path = self._benchmark_log_path()
        log_path.parent.mkdir(parents=True, exist_ok=True)
        log_path.write_text("", encoding="utf-8")
        # Marker pid = this agent process while the worker thread runs.
        self._benchmark_pid_file().write_text(f"{os.getpid()}\n", encoding="utf-8")
        return log_path

    def _launch_benchmark_thread(
        self,
        names: list[str],
        *,
        suite: str,
        allow_concurrent: bool,
        keep_running: bool,
        log_path: Path,
    ) -> None:
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

        threading.Thread(target=worker, name="msw-benchmark", daemon=True).start()

    def _benchmark_log(self, log_path: Path, line: str) -> None:
        try:
            with log_path.open("a", encoding="utf-8") as handle:
                handle.write(line + "\n")
        except OSError:
            pass

    def _wait_until_benchmark_ready(self, name: str, suite: str) -> dict[str, Any]:
        return self._refresh_status_until_ready(
            name, time.time() + (15 if suite == "quick" else 90)
        )

    def _current_profile_status(self, name: str) -> dict[str, Any]:
        return self.status(self.resolve_profile(name))

    def _refresh_status_until_ready(self, name: str, deadline: float) -> dict[str, Any]:
        current = self._current_profile_status(name)
        while time.time() < deadline and not current.get("ready"):
            time.sleep(0.5)
            current = self._current_profile_status(name)
        return current

    def _benchmark_metric_average(
        self, successful: list[dict[str, Any]], key: str
    ) -> float | None:
        vals = [float(row[key]) for row in successful if row.get(key) is not None]
        if not vals:
            return None
        return _round_tenths(sum(vals) / len(vals))

    def _benchmark_averages(self, successful: list[dict[str, Any]]) -> dict[str, float | None]:
        return {
            "ttft_ms": self._benchmark_metric_average(successful, "ttft_ms"),
            "decode_tokens_per_sec": self._benchmark_metric_average(
                successful, "decode_tokens_per_sec"
            ),
            "e2e_tokens_per_sec": self._benchmark_metric_average(
                successful, "e2e_tokens_per_sec"
            ),
        }

    def _empty_benchmark_report(self, name: str, runtime: str, error: str) -> dict[str, Any]:
        return {
            "profile": name,
            "runtime": runtime,
            "rss_mb": None,
            "vram_mb": None,
            "averages": {
                "ttft_ms": None,
                "decode_tokens_per_sec": None,
                "e2e_tokens_per_sec": None,
            },
            "results": [{"error": error}],
        }

    def _stop_benchmark_guest(self, name: str) -> None:
        try:
            self.stop(name, force=True)
        except TypeError:
            try:
                self.stop(name)
            except AgentError:
                pass
        except AgentError:
            pass

    def _write_benchmark_artifacts(
        self,
        names: list[str],
        suite: str,
        reports: list[dict[str, Any]],
    ) -> Path:
        generated_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        latest = self._benchmark_latest_json()
        latest.write_text(
            json.dumps(
                {
                    "generated_at": generated_at,
                    "suite": suite,
                    "profiles": names,
                    "benchmarks": reports,
                },
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        self._benchmark_latest_md().write_text(
            _benchmark_markdown_table(generated_at, reports), encoding="utf-8"
        )
        return latest

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
        for name in names:
            self._benchmark_named_profile(
                name,
                suite=suite,
                prompts=prompts,
                reports=reports,
                allow_concurrent=allow_concurrent,
                keep_running=keep_running,
                log_path=log_path,
            )
        latest = self._write_benchmark_artifacts(names, suite, reports)
        self._benchmark_log(log_path, f"wrote {latest}")

    def _benchmark_named_profile(
        self,
        name: str,
        *,
        suite: str,
        prompts: list[Any],
        reports: list[dict[str, Any]],
        allow_concurrent: bool,
        keep_running: bool,
        log_path: Path,
    ) -> None:
        profile = self._resolved_benchmark_profile(name, log_path)
        if profile is None:
            return
        before = self.status(profile)
        try:
            self._try_benchmark_ready_profile(
                name,
                profile,
                suite=suite,
                before=before,
                prompts=prompts,
                reports=reports,
                allow_concurrent=allow_concurrent,
                log_path=log_path,
            )
        finally:
            self._stop_benchmark_if_guest(name, keep_running, bool(before.get("running")))

    def _stop_benchmark_if_guest(self, name: str, keep_running: bool, was_running: bool) -> None:
        if not keep_running and not was_running:
            self._stop_benchmark_guest(name)

    def _try_benchmark_ready_profile(
        self,
        name: str,
        profile: Profile,
        *,
        suite: str,
        before: dict[str, Any],
        prompts: list[Any],
        reports: list[dict[str, Any]],
        allow_concurrent: bool,
        log_path: Path,
    ) -> None:
        try:
            reports.append(
                self._benchmark_ready_profile(
                    name,
                    profile,
                    suite=suite,
                    before=before,
                    prompts=prompts,
                    allow_concurrent=allow_concurrent,
                    log_path=log_path,
                )
            )
        except AgentError as error:
            self._append_benchmark_error(name, profile, error, reports, log_path)

    def _append_benchmark_error(
        self,
        name: str,
        profile: Profile,
        error: AgentError,
        reports: list[dict[str, Any]],
        log_path: Path,
    ) -> None:
        self._benchmark_log(log_path, f"{name}: {error}")
        reports.append(self._empty_benchmark_report(name, profile.runtime, str(error)))

    def _resolved_benchmark_profile(self, name: str, log_path: Path) -> Profile | None:
        try:
            return self.resolve_profile(name)
        except AgentError as error:
            self._benchmark_log(log_path, f"{name}: resolve failed: {error}")
            return None

    def _benchmark_ready_report(
        self,
        name: str,
        profile: Profile,
        results: list[dict[str, Any]],
        current: dict[str, Any],
    ) -> dict[str, Any]:
        successful = [row for row in results if not row.get("error")]
        return {
            "profile": name,
            "runtime": profile.runtime,
            "rss_mb": current.get("rss_mb"),
            "vram_mb": current.get("vram_mb"),
            "averages": self._benchmark_averages(successful),
            "results": results,
        }

    def _benchmark_ready_profile(
        self,
        name: str,
        profile: Profile,
        *,
        suite: str,
        before: dict[str, Any],
        prompts: list[Any],
        allow_concurrent: bool,
        log_path: Path,
    ) -> dict[str, Any]:
        before = self._ensure_benchmark_ready(
            name, suite=suite, before=before, allow_concurrent=allow_concurrent
        )
        results = self._benchmark_prompt_results(profile, before, prompts)
        successful = [row for row in results if not row.get("error")]
        current = self.status(self.resolve_profile(name))
        self._benchmark_log(log_path, f"{name}: ok rows={len(successful)}/{len(results)}")
        return self._benchmark_ready_report(name, profile, results, current)

    def _benchmark_prompt_results(
        self,
        profile: Profile,
        before: dict[str, Any],
        prompts: list[Any],
    ) -> list[dict[str, Any]]:
        if before.get("ready"):
            return [self._benchmark_one(profile, prompt) for prompt in prompts]
        return [{
            "benchmark": "ready-wait",
            "category": "setup",
            "error": "profile not ready for benchmark",
        }]

    def _ensure_benchmark_ready(
        self,
        name: str,
        *,
        suite: str,
        before: dict[str, Any],
        allow_concurrent: bool,
    ) -> dict[str, Any]:
        if before.get("ready"):
            return before
        if allow_concurrent:
            self.start(name)
        else:
            self.switch_profile(name)
        return self._wait_until_benchmark_ready(name, suite)

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

    def _benchmark_token_counts(self, payload: dict[str, Any], prompt: dict[str, Any]) -> tuple[int, int]:
        choice = (payload.get("choices") or [{}])[0]
        message = choice.get("message") or {}
        content = first_present(message.get("content"), choice.get("text"), "")
        usage = payload.get("usage") or {}
        return (
            _int_or_word_count(usage.get("completion_tokens"), content),
            _int_or_word_count(usage.get("prompt_tokens"), prompt["prompt"]),
        )

    def _benchmark_one(self, profile: Profile, prompt: dict[str, Any]) -> dict[str, Any]:
        """POST /v1/chat/completions on the local endpoint and time TTFT/decode."""
        request = _benchmark_chat_request(profile, prompt)
        started = time.perf_counter()
        try:
            with urlopen_no_redirect(request, 30) as response:
                raw = response.read()
            elapsed_s = max(time.perf_counter() - started, 1e-6)
            payload = json.loads(raw.decode("utf-8"))
            completion_tokens, prompt_tokens = self._benchmark_token_counts(payload, prompt)
            return _benchmark_success_row(
                prompt, elapsed_s, completion_tokens, prompt_tokens
            )
        except Exception as error:  # noqa: BLE001 - surface as row error
            return {
                "benchmark": prompt.get("benchmark"),
                "category": prompt.get("category"),
                "error": str(error),
            }

    def _status_display_name(self, profile: Profile, server_ids: list[str]) -> str:
        display_name = profile.display_name
        if server_ids and (
            display_name.lower() == f"port {profile.endpoint_port}"
            or is_placeholder_model_name(display_name)
        ):
            return Path(server_ids[0]).name
        return display_name

    def _resolve_status_pid(
        self,
        profile: Profile,
        allow_port_fallback: bool,
        listeners: list[dict[str, Any]] | None,
    ) -> tuple[int | None, bool]:
        pid = self._read_pid(profile.name)
        zombie = bool(pid and process_is_zombie(pid))
        pid, zombie = self._clear_dead_status_pid(profile, pid, zombie)
        return self._fallback_status_pid(
            profile, pid, zombie, allow_port_fallback, listeners
        )

    def _fallback_status_pid(
        self,
        profile: Profile,
        pid: int | None,
        zombie: bool,
        allow_port_fallback: bool,
        listeners: list[dict[str, Any]] | None,
    ) -> tuple[int | None, bool]:
        if pid is None and allow_port_fallback:
            return self._adopt_listener_pid(profile, listeners)
        return pid, zombie

    def _is_dead_status_pid(self, pid: int | None, zombie: bool) -> bool:
        return pid is not None and not process_is_alive(pid) and not zombie

    def _clear_dead_status_pid(
        self, profile: Profile, pid: int | None, zombie: bool
    ) -> tuple[int | None, bool]:
        if self._is_dead_status_pid(pid, zombie):
            self._pid_file(profile.name).unlink(missing_ok=True)
            return None, zombie
        return pid, zombie

    def _adopt_listener_pid(
        self,
        profile: Profile,
        listeners: list[dict[str, Any]] | None,
    ) -> tuple[int | None, bool]:
        listener = self._listener_pid_for_profile(profile, listeners)
        if listener is not None and self._process_matches(listener, profile):
            return listener, process_is_zombie(listener)
        return None, False

    def _listener_pid_for_profile(
        self,
        profile: Profile,
        listeners: list[dict[str, Any]] | None,
    ) -> int | None:
        if listeners is not None:
            return listener_pid_from_inventory(profile.endpoint_port, listeners)
        return listener_pid(profile.endpoint_port)

    def _status_listening(
        self,
        profile: Profile,
        listeners: list[dict[str, Any]] | None,
    ) -> bool:
        if listeners is not None:
            return port_listening_from_inventory(profile.endpoint_port, listeners)
        return port_is_listening(profile.endpoint_port)

    def _status_row(
        self,
        profile: Profile,
        *,
        display_name: str,
        pid: int | None,
        zombie: bool,
        alive: bool,
        ready: bool,
        ready_flag: bool,
        server_ids: list[str],
        llm_rates: dict[str, Any] | None,
    ) -> dict[str, Any]:
        label, tags, launch_mode = profile.runtime_spec
        shown_pid, rss_mb, vram_mb, command = self._status_row_process(
            pid, zombie, alive
        )
        return _status_row_fields(
            profile,
            display_name=display_name,
            label=label,
            tags=tags,
            launch_mode=launch_mode,
            pid=shown_pid,
            alive=alive,
            ready=ready,
            ready_flag=ready_flag,
            server_ids=server_ids,
            rss_mb=rss_mb,
            vram_mb=vram_mb,
            command=command,
            llm_rates=llm_rates,
        )

    def _status_row_process(
        self, pid: int | None, zombie: bool, alive: bool
    ) -> tuple[int | None, Any, Any, Any]:
        show_pid = alive or zombie
        rss_mb, vram_mb = self._status_memory(pid, alive)
        return pid if show_pid else None, rss_mb, vram_mb, self._status_command(pid, show_pid)

    def _status_memory(self, pid: int | None, alive: bool) -> tuple[Any, Any]:
        if alive and pid:
            return process_rss_mb(pid), process_vram_mb(pid)
        return None, None

    def _status_command(self, pid: int | None, show_pid: bool) -> str | None:
        if show_pid and pid:
            return process_command(pid)
        return None

    def _status_probe_fields(
        self,
        profile: Profile,
        allow_port_fallback: bool,
        listeners: list[dict[str, Any]] | None,
    ) -> tuple[bool, list[str], int | None, bool, bool, bool]:
        ready, server_ids = self._probe_health(profile)
        pid, zombie = self._resolve_status_pid(profile, allow_port_fallback, listeners)
        alive = self._status_alive(pid, zombie=zombie, ready=ready)
        ready_flag = self._status_ready_flag(profile, ready, alive, listeners)
        return ready, server_ids, pid, zombie, alive, ready_flag

    def status(
        self,
        profile: Profile,
        allow_port_fallback: bool = True,
        *,
        listeners: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        ready, server_ids, pid, zombie, alive, ready_flag = self._status_probe_fields(
            profile, allow_port_fallback, listeners
        )
        return self._status_row(
            profile,
            display_name=self._status_display_name(profile, server_ids),
            pid=pid,
            zombie=zombie,
            alive=alive,
            ready=ready,
            ready_flag=ready_flag,
            server_ids=server_ids,
            llm_rates=self._status_llm_rates(profile, alive, ready_flag),
        )

    def _status_ready_flag(
        self,
        profile: Profile,
        ready: bool,
        alive: bool,
        listeners: list[dict[str, Any]] | None,
    ) -> bool:
        return bool(ready and (alive or self._status_listening(profile, listeners)))

    def _status_llm_rates(
        self, profile: Profile, alive: bool, ready_flag: bool
    ) -> dict[str, Any] | None:
        if not (alive and ready_flag):
            return None
        return sample_llm_serving_rates(
            profile.base_url or "",
            allow_remote=env_flag(os.environ.get("ALLOW_REMOTE_HEALTHCHECK")),
        )

    def _status_alive(self, pid: int | None, *, zombie: bool, ready: bool) -> bool:
        alive = process_is_alive(pid)
        if zombie and not alive and not ready:
            return False
        return alive

    # -- lifecycle ---------------------------------------------------------

    def start(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            # Always key pid files / supervision on the canonical profile name.
            canonical = profile.name
            self._reject_unlaunchable_external(profile, canonical)
            if self._supervise_owned_pid(canonical):
                return
            self._register_start_conflict(profile)
            command = build_start_command(profile)
            if self._adopt_existing_listener(profile, canonical):
                return
            self._spawn_profile(profile, canonical, command)

    def _reject_unlaunchable_external(self, profile: Profile, canonical: str) -> None:
        if not (profile.get("START_COMMAND") or "").strip() and profile.runtime_spec[2] == "external":
            raise UnsupportedError(
                f"{canonical}: discovered endpoint has no launch claim; cannot start from Switchboard"
            )

    def _supervise_owned_pid(self, canonical: str) -> bool:
        # Idempotent only when *this* agent owns a live pid file - not when a
        # foreign listener happens to answer health on the profile port.
        owned_pid = self._read_pid(canonical)
        if owned_pid and process_is_alive(owned_pid):
            self._supervised.add(canonical)
            return True
        return False

    def _register_start_conflict(self, profile: Profile) -> None:
        loaded = dict(self.profiles.load())
        loaded[profile.name] = profile
        self.profiles.ensure_unique(profile.name, "start", loaded)

    def _listening_profile_port(self, profile: Profile) -> str | None:
        port = profile.endpoint_port
        if not port or not port_is_listening(port):
            return None
        return port

    def _adopt_existing_listener(self, profile: Profile, canonical: str) -> bool:
        port = self._listening_profile_port(profile)
        if port is None:
            return False
        listener = listener_pid(port)
        if self._claim_matching_listener(profile, canonical, listener):
            return True
        detail = f" by pid {listener}" if listener else ""
        raise ProfileConflictError(
            f"Cannot start {canonical}: port {port} is already in use{detail}."
        )

    def _claim_matching_listener(
        self, profile: Profile, canonical: str, listener: int | None
    ) -> bool:
        if listener and self._process_matches(listener, profile):
            self._supervised.add(canonical)
            return True
        return False

    def _spawn_profile(self, profile: Profile, canonical: str, command: str) -> None:
        missing = missing_local_model_artifacts(profile.values)
        if missing:
            raise InvalidProfileError(
                f"{canonical}: cannot start; missing model path(s): {', '.join(missing)}"
            )
        environment = _spawn_environment(profile, canonical)
        self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
        process = _popen_profile(
            profile,
            command,
            environment,
            canonical=canonical,
            cwd=profile.working_directory or self.configuration.root,
        )
        self._pid_file(canonical).write_text(f"{process.pid}\n", encoding="utf-8")
        self._supervised.add(canonical)
        clear_listening_tcp_cache()

    def _alive_orphan_pid(self, name: str) -> int | None:
        orphan = self._read_pid(name)
        if orphan and orphan != os.getpid() and process_is_alive(orphan):
            return orphan
        return None

    def _terminate_orphan_model_server(self, orphan: int, force: bool) -> None:
        cmd = process_command(orphan) or ""
        if command_looks_like_model_server(cmd):
            terminate_process_tree(orphan, force=force)

    def _reap_unresolved_pid(self, name: str, force: bool = False) -> None:
        """Pid-file leftover after resolve failed - kill only if it still looks like us."""
        orphan = self._alive_orphan_pid(name)
        if orphan is not None:
            self._terminate_orphan_model_server(orphan, force)
        self._pid_file(name).unlink(missing_ok=True)

    def _trusted_stop_pid(self, profile: Profile, current: dict[str, Any], was_supervised: bool):
        primary_pid = current.get("pid")
        if not primary_pid or self._process_matches(primary_pid, profile):
            return primary_pid
        if self._owned_pid_is_trusted(profile, primary_pid, was_supervised):
            return primary_pid
        return None

    def _owned_pid_is_trusted(self, profile: Profile, primary_pid, was_supervised: bool) -> bool:
        owned = self._owned_alive_pid(profile.name, primary_pid)
        if owned is None:
            return False
        return was_supervised or command_looks_like_model_server(process_command(owned) or "")

    def _owned_alive_pid(self, name: str, primary_pid) -> int | None:
        owned = self._read_pid(name)
        if owned and owned == primary_pid and process_is_alive(owned):
            return owned
        return None

    def _run_stop_command(self, profile: Profile) -> Exception | None:
        stop_command = (profile.get("STOP_COMMAND") or "").strip()
        if not stop_command:
            return None
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
            return error
        return None

    def stop(self, name: str, force: bool = False) -> None:
        with self._mutation_lock:
            self._stop_locked(name, force=force)

    def _stop_locked(self, name: str, force: bool) -> None:
        profile, canonical, current, primary_pid = self._stop_context(name)
        if self._should_skip_stop(current, primary_pid, force):
            self._finish_idle_stop(canonical)
            return
        self._stop_running_profile(profile, canonical, primary_pid, force)

    def _stop_context(
        self, name: str
    ) -> tuple[Profile, str, dict[str, Any], int | None]:
        self._suppress_watchdog()
        profile = self.resolve_profile(name)
        canonical = profile.name
        was_supervised = canonical in self._supervised
        self._supervised.discard(canonical)
        self._clear_active_profile(if_matching=canonical)
        current = self.status(profile)
        return profile, canonical, current, self._trusted_stop_pid(profile, current, was_supervised)

    def _stop_running_profile(
        self,
        profile: Profile,
        canonical: str,
        primary_pid: int | None,
        force: bool,
    ) -> None:
        stop_error = None if force else self._run_stop_command(profile)
        self._apply_stop_processes(profile, primary_pid, force, canonical)
        self._finish_idle_stop(canonical)
        if stop_error is not None and not force:
            raise OperationFailedError(f"STOP_COMMAND failed for {canonical}: {stop_error}")

    def _finish_idle_stop(self, canonical: str) -> None:
        self._pid_file(canonical).unlink(missing_ok=True)
        clear_listening_tcp_cache()

    def _should_skip_stop(self, current: dict[str, Any], primary_pid: int | None, force: bool) -> bool:
        return not current.get("running") and not primary_pid and not force

    def _apply_stop_processes(
        self,
        profile: Profile,
        primary_pid: int | None,
        force: bool,
        canonical: str,
    ) -> None:
        if profile.get("STOP_COMMAND_ONLY") != "1" or force:
            self._terminate_profile_processes(
                profile, primary_pid, force=force
            )
            self._ensure_stopped(profile, primary_pid, force=force, name=canonical)

    def restart(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            loaded = dict(self.profiles.load())
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "restart", loaded)
            self.stop(name)
            self.start(name)

    def _stop_other_managed(self, managed_names: set[str], canonical: str) -> None:
        for other in sorted(managed_names - {canonical}):
            try:
                self.stop(other)
            except ProfileNotFoundError:
                self._reap_unresolved_pid(other)
            except AgentError as error:
                # Keep going so a later idle/missing sibling cannot leave
                # the board with the previous model already killed.
                sys.stderr.write(f"[activate] stop {other}: {error.message}\n")

    def switch_profile(self, name: str) -> None:
        with self._mutation_lock:
            profile = self.resolve_profile(name)
            canonical = profile.name
            loaded = dict(self.profiles.load())
            loaded[profile.name] = profile
            self.profiles.ensure_unique(profile.name, "activate", loaded)
            # Exclusive switch only stops managed profiles / session-supervised
            # claims - never discovered listeners. Do not assemble the full
            # status board (claim walk + live HTTP probes) just to find them.
            managed_names = set(loaded.keys()) | set(self._supervised)
            self._stop_other_managed(managed_names, canonical)
            self.start(canonical)
            self.configuration.run_directory.mkdir(parents=True, exist_ok=True)
            self.configuration.active_profile_file.write_text(f"{canonical}\n", encoding="utf-8")

    def stop_all(self, force: bool = False) -> None:
        with self._mutation_lock:
            # Folder profiles, session-supervised claims, and durable pid files
            # left from a prior agent process (claims survive reboot of the agent).
            names = set(self.profiles.load().keys()) | set(self._supervised) | self._durable_pid_names()
            failures = self._stop_named_profiles(names, force=force)
            # Clear any leftover active marker so a later watchdog cannot revive.
            self.configuration.active_profile_file.unlink(missing_ok=True)
            self._supervised.clear()
            clear_listening_tcp_cache()
            if failures:
                raise OperationFailedError("Failed to stop profiles: " + "; ".join(failures))

    def _durable_pid_names(self) -> set[str]:
        names: set[str] = set()
        try:
            for path in self.configuration.run_directory.glob("*.pid"):
                stem = path.stem
                if stem in {"benchmark", "active-profile"}:
                    continue
                names.add(stem)
        except OSError:
            pass
        return names

    def _stop_named_profiles(self, names: set[str], force: bool) -> list[str]:
        failures: list[str] = []
        for name in sorted(names):
            try:
                # Nested stop also takes the mutation lock (RLock).
                self.stop(name, force=force)
            except ProfileNotFoundError:
                self._reap_unresolved_pid(name, force=force)
            except AgentError as error:
                failures.append(f"{name}: {error.message}")
        return failures

    def run_integration(self, integration: str, action: str) -> None:
        raise UnsupportedError(f"Unsupported integration action: {integration}:{action}")

    # -- doctor ------------------------------------------------------------

    def _doctor_controller(self, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "url": f"http://{self.configuration.host}:{self.configuration.port}",
            "reachable": True,
            "profiles": len(payload["statuses"]),
            "integrations": 0,
        }

    def _doctor_launch_agent(self) -> dict[str, Any]:
        unit = self.configuration.systemd_unit_path
        return {
            "plist_path": str(unit),
            "installed": path_is_regular_file(unit),
            "running": path_is_regular_file(unit),
        }

    def doctor_report(self) -> dict[str, Any]:
        payload = self.status_payload()
        return {
            "controller": self._doctor_controller(payload),
            "launch_agent": self._doctor_launch_agent(),
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

    def _watchdog_foreign_holder(self, profile: Profile) -> bool:
        port = profile.endpoint_port
        if not (port and port_is_listening(port)):
            return False
        listener = listener_pid(port)
        return listener is None or not self._process_matches(listener, profile)

    def _watchdog_restart_one(self, name: str) -> None:
        with self._mutation_lock:
            profile = self._watchdog_profile_to_restart(name)
            if profile is None:
                return
            try:
                self.start(name)
            except AgentError as error:
                sys.stderr.write(f"[watchdog] failed to restart {name}: {error}\n")

    def _watchdog_profile_to_restart(self, name: str) -> Profile | None:
        if not self._watchdog_may_restart(name):
            return None
        return self._watchdog_crashed_supervised(name)

    def _watchdog_crashed_supervised(self, name: str) -> Profile | None:
        profile = self._supervised_profile_or_drop(name)
        if profile is None:
            return None
        if self._watchdog_still_live(profile, name):
            return None
        return profile

    def _watchdog_may_restart(self, name: str) -> bool:
        if time.monotonic() < self._watchdog_suppressed_until:
            return False
        return name in self._supervised

    def _supervised_profile_or_drop(self, name: str) -> Profile | None:
        try:
            return self.resolve_profile(name)
        except AgentError:
            self._supervised.discard(name)
            return None

    def _watchdog_still_live(self, profile: Profile, name: str) -> bool:
        current = self.status(profile)
        if current["ready"] or current["running"]:
            return True
        if self._watchdog_foreign_holder(profile):
            self._supervised.discard(name)
            return True
        return False

    def watchdog_tick(self) -> None:
        """Restart supervised profiles that crashed mid-session only.

        Does *not* read active-profile from disk: that would reload a model on
        every agent/login boot after a prior `switch`. Session supervision is
        the only source of truth for auto-restart.
        """
        if time.monotonic() < self._watchdog_suppressed_until:
            return
        for name in list(self._supervised):
            self._watchdog_restart_one(name)

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

    def _profile_command_markers(self, profile: Profile) -> list[str]:
        return [
            value
            for value in (
                profile.name,
                profile.get("MODEL_ALIAS"),
                profile.request_model,
                profile.server_model_id,
                profile.get("MODEL_PATH"),
                profile.get("MODEL_DIR"),
                profile.get("MODEL_FILE"),
                profile.get("MODEL_REPO"),
                profile.get("START_COMMAND"),
            )
            if value and len(value) >= 4
        ]

    def _command_mentions_port(self, command: str, port: str) -> bool:
        return self._argv_mentions_port(command, port) or bool(
            re.search(rf"(?<!\d):{re.escape(port)}(?!\d)", command)
        )

    def _argv_mentions_port(self, command: str, port: str) -> bool:
        try:
            argv = shlex.split(command)
        except ValueError:
            argv = command.split()
        return _argv_has_port_flag(argv, port)

    def _command_has_profile_marker(self, command: str, profile: Profile) -> bool:
        return any(
            marker.lower() in command for marker in self._profile_command_markers(profile)
        )

    def _command_matches_owned(
        self, pid: int, command: str, profile: Profile
    ) -> bool:
        if self._command_has_profile_marker(command, profile):
            return True
        port = profile.endpoint_port
        if port and self._command_mentions_port(command, port):
            return True
        return self._listener_matches_model_server(pid, command, port)

    def _process_matches(self, pid: int, profile: Profile) -> bool:
        command = _foreign_process_command(pid)
        if command is None:
            return False
        return self._command_matches_owned(pid, command, profile)

    def _listener_matches_model_server(self, pid: int, command: str, port: str) -> bool:
        return (
            command_looks_like_model_server(command)
            and port_is_listening(port)
            and listener_pid(port) == pid
        )

    def _remote_healthcheck_allowed(self) -> bool:
        return (os.environ.get("ALLOW_REMOTE_HEALTHCHECK") or "").lower() in (
            "1", "true", "yes",
        )

    def _healthcheck_url_allowed(self, url: str) -> bool:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False
        return self._remote_healthcheck_allowed() or is_loopback(parsed.hostname or "")

    def _probe_health_body(self, profile: Profile) -> bytes | None:
        if profile.healthcheck_mode == "disabled":
            return None
        url = profile.healthcheck_url
        if not self._healthcheck_url_allowed(url):
            return None
        return self._healthcheck_body(url)

    def _probe_health(self, profile: Profile) -> tuple[bool, list[str]]:
        body = self._probe_health_body(profile)
        if body is None:
            return False, []
        if profile.healthcheck_mode == "http-200":
            return True, []
        return self._health_from_openai_models(profile, body)

    def _healthcheck_body(self, url: str) -> bytes | None:
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urlopen_no_redirect(request, HEALTH_TIMEOUT_SECONDS) as response:
                return response.read()
        except (urllib.error.URLError, OSError, ValueError):
            return None

    def _health_from_openai_models(self, profile: Profile, body: bytes) -> tuple[bool, list[str]]:
        ids = _openai_model_ids(body)
        if ids is None:
            return False, []
        if profile.healthcheck_any_id:
            return bool(ids), ids
        expected = profile.get("HEALTHCHECK_EXPECT_ID") or profile.server_model_id
        matched = openai_model_id_matches(
            expected,
            ids,
            profile.request_model,
            profile.server_model_id,
        )
        return matched, ids

    def _listener_owned_by_profile(
        self,
        listener: int | None,
        primary_pid: int | None,
        self_pid: int,
        profile: Profile,
    ) -> bool:
        return bool(
            listener
            and listener != primary_pid
            and listener != self_pid
            and self._process_matches(listener, profile)
        )

    def _owned_listener_pid(
        self, profile: Profile, primary_pid: int | None, self_pid: int
    ) -> int | None:
        listener = listener_pid(profile.endpoint_port)
        if self._listener_owned_by_profile(listener, primary_pid, self_pid, profile):
            return listener
        return None

    def _terminate_profile_processes(
        self,
        profile: Profile,
        primary_pid: int | None,
        *,
        force: bool = False,
    ) -> None:
        self_pid = os.getpid()
        self._terminate_owned_pid(primary_pid, self_pid=self_pid, force=force)
        # Always re-check the listen port: vLLM may leave EngineCore on the
        # port under a different pid after the launcher shell exits.
        # `force` only strengthens the signal - never skips ownership matching
        # (Swift terminateProfileProcesses always requires processMatches).
        listener = self._owned_listener_pid(profile, primary_pid, self_pid)
        if listener is not None:
            self._terminate_owned_pid(listener, self_pid=self_pid, force=force)

    def _terminate_owned_pid(self, pid: int | None, *, self_pid: int, force: bool) -> None:
        if not pid or pid == self_pid:
            return
        if process_is_zombie(pid):
            reap_child(pid)
            return
        terminate_process_tree(pid, force=force)

    def _wait_or_force_stop(
        self,
        profile: Profile,
        primary_pid: int | None,
        timeout: float,
    ) -> bool:
        if self._wait_until_stopped(profile, primary_pid, timeout=timeout):
            return True
        self._terminate_profile_processes(profile, primary_pid, force=True)
        return self._wait_until_stopped(
            profile,
            primary_pid,
            timeout=FORCE_TERMINATE_TIMEOUT_SECONDS * 2,
        )

    def _ensure_stopped(
        self,
        profile: Profile,
        primary_pid: int | None,
        *,
        force: bool,
        name: str,
    ) -> None:
        timeout = FORCE_TERMINATE_TIMEOUT_SECONDS * 3 if force else STOP_WAIT_SECONDS
        if self._wait_or_force_stop(profile, primary_pid, timeout):
            return
        raise OperationFailedError(
            f"failed to stop {name}: endpoint or process is still alive"
        )

    def _endpoint_released(
        self,
        profile: Profile,
        primary_pid: int | None,
        *,
        final: bool,
    ) -> bool:
        if not port_is_listening(profile.endpoint_port):
            return True
        listeners = list_listening_tcp()
        listener = listener_pid_from_inventory(profile.endpoint_port, listeners)
        if listener is None:
            return True
        if process_is_zombie(listener):
            reap_child(listener)
            return True
        return self._endpoint_foreign_or_unmatched(
            profile, primary_pid, listener, final=final
        )

    def _endpoint_foreign_or_unmatched(
        self,
        profile: Profile,
        primary_pid: int | None,
        listener: int,
        *,
        final: bool,
    ) -> bool:
        if final:
            return not self._process_matches(listener, profile)
        if listener != primary_pid and not self._process_matches(listener, profile):
            return True
        return False

    def _wait_until_stopped(
        self,
        profile: Profile,
        primary_pid: int | None,
        timeout: float = STOP_WAIT_SECONDS,
    ) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self._stop_wait_tick(profile, primary_pid):
                return True
            time.sleep(0.2)
        if process_is_alive(primary_pid):
            return False
        return self._endpoint_released(profile, primary_pid, final=True)

    def _stop_wait_tick(self, profile: Profile, primary_pid: int | None) -> bool:
        if primary_pid:
            reap_child(primary_pid)
        if process_is_alive(primary_pid):
            return False
        return self._endpoint_released(profile, primary_pid, final=False)

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

    def _parsed_content_length(self) -> int | None:
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            return 0
        try:
            length = int(raw_length)
            if length < 0:
                raise ValueError
            return length
        except ValueError:
            self._send_json(*_error_body(400, "invalid_content_length", "invalid Content-Length"))
            self.close_connection = True
            return None

    def _read_body(self) -> bytes | None:
        """Read the request body; None means an error response was already sent."""
        length = self._parsed_content_length()
        if length is None:
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

    def _accept_request(self, path: str) -> bool:
        if path.startswith("/api/") and not self._authorized():
            # The body has not been read yet; drop the connection so an
            # unread payload cannot corrupt a kept-alive request stream.
            self.close_connection = True
            self._send_json(*_error_body(401, "unauthorized", "unauthorized"))
            return False
        return True

    def _read_method_body(self, method: str) -> bytes | None:
        if method != "POST":
            return b""
        return self._read_body()

    def _handle(self, method: str) -> None:
        try:
            self._handle_routed(method)
        except AgentError as error:
            self._send_json(*_error_body(error.http_status, error.code, error.public_message))
        except Exception:  # pragma: no cover - defensive parity with router fallback
            traceback.print_exc()
            self._send_json(*_error_body(500, "internal_error", "internal server error"))

    def _dispatch_accepted(self, method: str, path: str) -> None:
        body = self._read_method_body(method)
        if body is None:
            return
        self._dispatch_routed(method, path, body)

    def _handle_routed(self, method: str) -> None:
        path = urllib.parse.urlparse(self.path).path or "/"
        if not self._accept_request(path):
            return
        self._dispatch_accepted(method, path)

    def _dispatch_routed(self, method: str, path: str, body: bytes) -> None:
        handler = self._route(method, path)
        if handler is None:
            self._send_json(*_error_body(404, "not_found", "not found"))
            return
        self._send_json(200, handler(self._request_object(body or b"")))

    def _route(self, method: str, path: str) -> Callable[[dict[str, Any]], dict[str, Any]] | None:
        service = self.service
        routes: dict[tuple[str, str], Callable[[dict[str, Any]], dict[str, Any]]] = {
            ("GET", "/api/status"): lambda _: service.status_payload(),
            ("GET", "/api/ports"): lambda _: service.ports_payload(),
            ("GET", "/api/doctor"): lambda _: service.doctor_report(),
            ("GET", "/api/benchmark/status"): lambda _: service.benchmark_status(),
            ("GET", "/api/host/metrics"): lambda _: host_metrics_payload(),
            ("GET", "/api/integrations"): lambda _: {
                "integrations": [],
                "profiles_dir": str(service.configuration.profiles_directory),
                "controller_root": str(service.configuration.root),
            },
            ("POST", "/api/start"): self._profile_action(service.start),
            ("POST", "/api/stop"): self._stop_action(service),
            ("POST", "/api/restart"): self._profile_action(service.restart),
            ("POST", "/api/switch"): self._profile_action(service.switch_profile),
            ("POST", "/api/stop-all"): self._stop_all_action(service),
            ("POST", "/api/integrations/run"): self._run_integration_action(service),
            ("POST", "/api/config/profiles-dir"): self._set_profiles_dir_action(service),
            ("POST", "/api/benchmark/start"): self._benchmark_start_action(service),
        }
        return routes.get((method, path))

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

    def _run_integration_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            service.run_integration(
                self._required_string(payload, "integration"),
                payload.get("action", "sync"),
            )
            return service.action_response()
        return handle

    def _set_profiles_dir_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            return service.set_profiles_directory(
                self._required_string(payload, "profiles_dir")
            )
        return handle

    def _benchmark_start_action(
        self, service: "AgentService"
    ) -> Callable[[dict[str, Any]], dict[str, Any]]:
        def handle(payload: dict[str, Any]) -> dict[str, Any]:
            service.start_benchmark(
                profiles=_optional_profile_names(payload),
                suite=str(payload.get("suite") or "quick"),
                allow_concurrent=bool(payload.get("allow_concurrent")),
                keep_running=bool(payload.get("keep_running")),
            )
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
        return _gateway_link(host=direct_host, agent_port=agent_port, name=short_host, mode="direct")
    return _gateway_link(
        host=_ssh_link_host(),
        agent_port=agent_port,
        name=short_host,
        mode="ssh",
        user=getpass.getuser(),
    )


def _ssh_link_host() -> str:
    fqdn = socket.getfqdn()
    if fqdn and "." in fqdn and fqdn != "localhost":
        return fqdn
    return socket.gethostname()


def _gateway_link_authority(host: str, mode: str, user: str) -> str:
    return host if mode == "direct" else f"{urllib.parse.quote(user)}@{host}"


def _gateway_link(
    *,
    host: str,
    agent_port: int,
    name: str,
    mode: str,
    user: str = "",
) -> dict[str, str]:
    authority = _gateway_link_authority(host, mode, user)
    link = (
        "modelswitchboard-gateway://"
        f"{authority}"
        f"?name={urllib.parse.quote(name)}&agent_port={agent_port}&mode={mode}"
    )
    return {
        "user": user,
        "host": host,
        "name": name,
        "agent_port": str(agent_port),
        "mode": mode,
        "link": link,
    }

_CLI_COMMANDS = [
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
]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="model-switchboard-agent",
        description="Model Switchboard remote agent: launch and monitor model servers over the controller HTTP contract.",
    )
    _add_parser_root_arguments(parser)
    _add_parser_bind_arguments(parser)
    _add_parser_cli_arguments(parser)
    return parser


def _add_parser_root_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--version", action="version", version=f"model-switchboard-agent {AGENT_VERSION}")
    parser.add_argument("--root", type=Path, default=None, help="agent root directory (default: ~/.local/share/model-switchboard-agent)")
    parser.add_argument(
        "--profiles-dir",
        type=Path,
        default=None,
        help="folder of model .env/.json profiles (default: ~/model-profiles, or config.json / legacy <root>/model-profiles)",
    )


def _add_parser_bind_arguments(parser: argparse.ArgumentParser) -> None:
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


def _add_parser_cli_arguments(parser: argparse.ArgumentParser) -> None:
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
        choices=_CLI_COMMANDS,
    )
    parser.add_argument("profiles", nargs="*", help="profile names for start/stop/restart/switch")

def _auth_token_from_args(args: argparse.Namespace) -> str:
    token = args.auth_token
    if args.auth_token_file is None:
        return token
    path = args.auth_token_file.expanduser()
    try:
        return path.read_text(encoding="utf-8").strip()
    except OSError as error:
        raise InvalidConfigurationError(
            f"cannot read auth token file {path}: {error}"
        ) from error


def _apply_unsafe_bind(args: argparse.Namespace, host: str) -> tuple[str, bool]:
    if args.unsafe_bind is not None:
        return args.unsafe_bind, True
    return host, False


def _apply_tailscale_bind(args: argparse.Namespace, host: str) -> tuple[str, bool]:
    if not getattr(args, "tailscale", False):
        return host, False
    presence = tailscale_status()
    if not presence.present:
        raise InvalidConfigurationError(
            "--tailscale: no Tailscale address found - is tailscaled running?"
        )
    return presence.ipv4 or host, True


def _bind_from_args(args: argparse.Namespace) -> tuple[str, bool, bool]:
    host, unsafe = _apply_unsafe_bind(args, args.host)
    host, tailscale = _apply_tailscale_bind(args, host)
    return host, unsafe, tailscale


def build_configuration(args: argparse.Namespace) -> AgentConfiguration:
    token = _auth_token_from_args(args)
    host, unsafe, tailscale = _bind_from_args(args)
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


def _stdio_is_tty() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def _link_is_interactive(args: argparse.Namespace) -> bool:
    return (
        not args.json
        and not args.yes
        and args.profiles_dir is None
        and _stdio_is_tty()
    )


def _apply_link_profiles_dir(args: argparse.Namespace, configuration: AgentConfiguration) -> None:
    if _link_is_interactive(args):
        print()
        configuration.profiles_dir = prompt_profiles_directory(
            configuration.root,
            current=configuration.profiles_directory,
        )
        return
    if args.profiles_dir is not None:
        configuration.profiles_dir = resolve_profiles_directory(
            configuration.root, args.profiles_dir
        )


def _link_direct_host(args: argparse.Namespace) -> str | None:
    if not getattr(args, "tailscale", False):
        return None
    presence = tailscale_status()
    if not presence.present:
        raise InvalidConfigurationError(
            "--tailscale: no Tailscale address found - is tailscaled running?"
        )
    return presence.dns_name or presence.ipv4


def _run_link(args: argparse.Namespace, configuration: AgentConfiguration) -> int:
    _apply_link_profiles_dir(args, configuration)
    configuration.profiles_directory.mkdir(parents=True, exist_ok=True)
    direct_host = _link_direct_host(args)
    info = build_link_code(configuration.port, direct_host=direct_host)
    info["profiles_dir"] = str(configuration.profiles_directory)
    claims = scan_port_claim_directories(agent_root=configuration.root)
    info["port_claims"] = len(claims)
    info["scan_roots_env"] = SCAN_ROOTS_ENV
    if args.json:
        _print_json(info)
    else:
        _print_link_human(info, configuration)
    return 0


def _print_link_human(info: dict[str, Any], configuration: AgentConfiguration) -> None:
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

def _cmd_serve(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
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


def _cmd_status(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    _print_json(service.status_payload(args.profiles or None))
    return 0


def _cmd_list(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
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


def _print_scan_candidates(candidates: list[dict[str, Any]]) -> None:
    if not candidates:
        print("No launch-looking .env/.json folders found under $HOME.")
        return
    for index, candidate in enumerate(candidates, start=1):
        print(
            f"[{index}] {candidate['path']} "
            f"({candidate['profile_count']}: {', '.join(candidate['files'][:6])})"
        )


def _print_scan_claims(claims: list[dict[str, Any]]) -> None:
    print()
    print("Claimed port folders (numeric dir + launch/flags markers):")
    for claim in claims:
        model = claim.get("model_hint") or "-"
        print(
            f"  :{claim['port']}  {claim['path']}  "
            f"({claim.get('runtime_hint') or 'unknown'})  {model}"
        )


def _print_scan_no_claims() -> None:
    print()
    print(f"No claimed port folders found. Optional: export {SCAN_ROOTS_ENV}=/path/to/scan")


def _print_scan_profiles(configuration: AgentConfiguration, candidates: list[dict[str, Any]], claims: list[dict[str, Any]]) -> None:
    print(f"Current profiles folder: {configuration.profiles_directory}")
    _print_scan_candidates(candidates)
    if claims:
        _print_scan_claims(claims)
        return
    _print_scan_no_claims()


def _scan_claim_rows(claims: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "port": item["port"],
            "path": item["path"],
            "display_name": item.get("display_name"),
            "model_hint": item.get("model_hint"),
            "runtime_hint": item.get("runtime_hint"),
        }
        for item in claims
    ]


def _cmd_scan_profiles(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    candidates = scan_profile_directories()
    claims = scan_port_claim_directories(agent_root=configuration.root)
    payload = {
        "profiles_dir": str(configuration.profiles_directory),
        "candidates": candidates,
        "port_claims": _scan_claim_rows(claims),
        "scan_roots_env": SCAN_ROOTS_ENV,
    }
    if args.json:
        _print_json(payload)
    else:
        _print_scan_profiles(configuration, candidates, claims)
    return 0


def _port_row_flags(entry: dict[str, Any]) -> str:
    flags = _port_row_flag_parts(entry)
    return ",".join(flags) if flags else "-"


def _port_row_flag_parts(entry: dict[str, Any]) -> list[str]:
    flags: list[str] = []
    if entry.get("looks_like_model"):
        flags.append("model-cmd")
    if entry.get("claimed"):
        flags.append("claimed")
    flags.extend(_port_row_model_flags(entry.get("model")))
    return flags


def _port_row_model_flags(model: Any) -> list[str]:
    if not model:
        return []
    if model.get("ready"):
        return ["ready"]
    return ["probe-fail"]


def _port_row_model_identity(model: Any) -> str | None:
    if model and model.get("request_model"):
        return str(model["request_model"])
    return None


def _port_row_claimed_identity(claimed: Any) -> str | None:
    if claimed and claimed.get("model_hint"):
        return str(claimed["model_hint"])
    return None


def _port_row_fallback_identity(entry: dict[str, Any]) -> str:
    return (entry.get("command") or "")[:80] or "-"


def _port_row_identity(entry: dict[str, Any]) -> str:
    identity = _port_row_model_identity(entry.get("model"))
    if identity is not None:
        return identity
    identity = _port_row_claimed_identity(entry.get("claimed"))
    if identity is not None:
        return identity
    return _port_row_fallback_identity(entry)


def _cmd_ports(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    payload = service.ports_payload()
    if args.json:
        _print_json(payload)
        return 0
    print("Listening / claimed ports (Ports-style):")
    for entry in payload["ports"]:
        print(f"  :{entry['port']:<5}  {_port_row_flags(entry):<18}  {_port_row_identity(entry)}")
    return 0


def _lifecycle_target_names(
    args: argparse.Namespace, service: "AgentService"
) -> list[str]:
    if not args.profiles:
        raise UsageError("No profiles selected")
    names = args.profiles
    if names == ["all"]:
        names = sorted(service.profiles.load().keys())
    return names


def _apply_lifecycle_command(
    service: "AgentService", args: argparse.Namespace, name: str
) -> None:
    if args.command == "stop":
        service.stop(name, force=bool(args.force))
    else:
        getattr(service, args.command)(name)


def _cmd_lifecycle(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    for name in _lifecycle_target_names(args, service):
        _apply_lifecycle_command(service, args, name)
    _print_json(service.action_response())
    return 0


def _cmd_switch(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    if not args.profiles:
        raise UsageError("No profile selected")
    service.switch_profile(args.profiles[0])
    _print_json(service.action_response())
    return 0


def _cmd_stop_all(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    # kill-all is the nuclear one-liner: always force.
    service.stop_all(force=bool(args.force) or args.command == "kill-all")
    _print_json(service.action_response())
    return 0


def _cmd_link(args: argparse.Namespace, configuration: AgentConfiguration, service: "AgentService") -> int:
    return _run_link(args, configuration)


_COMMANDS: dict[str, Callable[[argparse.Namespace, AgentConfiguration, "AgentService"], int]] = {
    "serve": _cmd_serve,
    "status": _cmd_status,
    "list": _cmd_list,
    "scan-profiles": _cmd_scan_profiles,
    "scan-ports": _cmd_ports,
    "ports": _cmd_ports,
    "start": _cmd_lifecycle,
    "stop": _cmd_lifecycle,
    "restart": _cmd_lifecycle,
    "switch": _cmd_switch,
    "activate": _cmd_switch,
    "stop-all": _cmd_stop_all,
    "kill-all": _cmd_stop_all,
    "link": _cmd_link,
}


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        configuration = build_configuration(args)
    except AgentError as error:
        sys.stderr.write(f"model-switchboard-agent: {error.message}\n")
        return 2

    service = AgentService(configuration)
    try:
        return _COMMANDS[args.command](args, configuration, service)
    except AgentError as error:
        sys.stderr.write(f"model-switchboard-agent: {error.message}\n")
        return 2 if isinstance(error, (UsageError, InvalidConfigurationError)) else 1

if __name__ == "__main__":
    sys.exit(main())


from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

from contracts import (
    ControllerActionResponsePayload,
    ControllerIntegrationPayload,
    ControllerStatusPayload,
    ModelProfileStatusPayload,
    ProfileEnv,
    make_action_response_payload,
    make_cached_status_payload,
    make_controller_status_payload,
)
from profile_env import ProfileFormatError, load_profile

from msctl.paths import (
    ACTIVE_PROFILE_PATH,
    BASE,
    FACTORY_SETTINGS_PATH,
    PROFILE_DIR,
    RUN_DIR,
    START_SCRIPT,
    STATUS_CACHE_PATH,
    STOP_ALL_SCRIPT,
    SYNC_SCRIPT,
    _MIN_PID_MARKER_LEN,
)
from msctl.runtimes import canonical_runtime, expand_profile_path, runtime_spec, runtime_tags
from msctl.security import (
    ProfileConflictError,
    is_loopback_host,
    is_safe_healthcheck_url,
    is_active_profile_watchdog_suppressed,
    suppress_active_profile_watchdog,
    with_mutation_lock,
)

def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = True,
    env: ProfileEnv | None = None,
    cwd: pathlib.Path | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
        env=env,
        cwd=cwd,
    )


def profile_paths() -> list[pathlib.Path]:
    return sorted(list(PROFILE_DIR.glob("*.env")) + list(PROFILE_DIR.glob("*.json")))


def load_profiles() -> dict[str, ProfileEnv]:
    profiles: dict[str, ProfileEnv] = {}
    for path in profile_paths():
        try:
            profiles[path.stem] = load_profile(path)
        except ProfileFormatError as exc:
            raise SystemExit(str(exc)) from exc
    return profiles


def require_profile(name: str) -> ProfileEnv:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    return profiles[name]


def pid_path(profile_name: str) -> pathlib.Path:
    return RUN_DIR / f"{profile_name}.pid"


def read_active_profile() -> str | None:
    if not ACTIVE_PROFILE_PATH.exists():
        return None
    name = ACTIVE_PROFILE_PATH.read_text().strip()
    return name or None


def write_active_profile(name: str) -> None:
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    ACTIVE_PROFILE_PATH.write_text(f"{name}\n")


def clear_active_profile(name: str | None = None) -> None:
    if name is None or read_active_profile() == name:
        ACTIVE_PROFILE_PATH.unlink(missing_ok=True)


def log_path(env: ProfileEnv) -> str:
    raw_name = env.get("LOG_ALIAS") or env.get("MODEL_ALIAS") or env["PROFILE_NAME"]
    safe_name = "".join(char if char.isalnum() or char in {"_", ".", "-"} else "_" for char in raw_name)
    return f"/tmp/{safe_name}.log"


def profile_working_directory(env: ProfileEnv) -> pathlib.Path | None:
    raw = env.get("WORKING_DIRECTORY") or env.get("WORKDIR") or ""
    raw = raw.strip()
    return expand_profile_path(raw) if raw else None


def validate_http_url(url: str, *, field: str = "URL") -> str:
    value = url.strip()
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme.lower() not in {"http", "https"} or not parsed.netloc:
        raise ValueError(f"{field} must use http or https")
    return value.rstrip("/")


def url_host_literal(host: str) -> str:
    value = host.strip()
    if ":" in value and not (value.startswith("[") and value.endswith("]")):
        return f"[{value}]"
    return value


def default_client_host(env: ProfileEnv) -> str:
    host = env.get("HOST", "127.0.0.1").strip() or "127.0.0.1"
    if is_loopback_host(host):
        return host
    return "127.0.0.1"


def base_url(env: ProfileEnv) -> str:
    configured = env.get("BASE_URL", "").strip()
    if configured:
        return validate_http_url(configured, field="BASE_URL")
    port = env.get("PORT", "").strip()
    if not port:
        return ""
    return f"http://{url_host_literal(default_client_host(env))}:{port}/v1"


def models_url(env: ProfileEnv) -> str:
    configured = env.get("MODEL_LIST_URL", "").strip()
    if configured:
        return validate_http_url(configured, field="MODEL_LIST_URL")
    url = base_url(env)
    if not url:
        return ""
    return f"{url}/models"


def healthcheck_mode(env: ProfileEnv) -> str:
    return env.get("HEALTHCHECK_MODE", "openai-models").strip().lower()


def healthcheck_url(env: ProfileEnv) -> str:
    configured = env.get("HEALTHCHECK_URL", "").strip()
    if configured:
        return validate_http_url(configured, field="HEALTHCHECK_URL")
    if healthcheck_mode(env) == "openai-models":
        return models_url(env)
    return base_url(env)


def endpoint_host(env: ProfileEnv) -> str:
    if env.get("HOST"):
        return env["HOST"]
    url = base_url(env)
    parsed = urllib.parse.urlparse(url)
    return parsed.hostname or "127.0.0.1"


def endpoint_port(env: ProfileEnv) -> str:
    if env.get("PORT"):
        return env["PORT"]
    url = base_url(env)
    parsed = urllib.parse.urlparse(url)
    return str(parsed.port or "")


def normalized_endpoint_host(host: str) -> str:
    normalized = host.strip().lower().strip("[]")
    if normalized in {"127.0.0.1", "localhost", "::1"}:
        return "localhost"
    return normalized


def endpoint_identity(env: ProfileEnv) -> tuple[str, str] | None:
    port = endpoint_port(env).strip()
    if not port:
        return None
    host = normalized_endpoint_host(endpoint_host(env))
    if not host:
        return None
    return host, port


def profile_endpoint_conflicts(profiles: dict[str, ProfileEnv]) -> dict[str, tuple[str, list[str]]]:
    groups: dict[tuple[str, str], list[str]] = {}
    for name, env in sorted(profiles.items()):
        identity = endpoint_identity(env)
        if not identity:
            continue
        groups.setdefault(identity, []).append(name)

    conflicts: dict[str, tuple[str, list[str]]] = {}
    for (host, port), names in groups.items():
        if len(names) < 2:
            continue
        ordered_names = sorted(names, key=str.lower)
        endpoint = f"{host}:{port}"
        for name in ordered_names:
            conflicts[name] = (endpoint, [other for other in ordered_names if other != name])
    return conflicts


def format_endpoint_conflict(endpoint: str, other_profiles: list[str]) -> str:
    label = "profile" if len(other_profiles) == 1 else "profiles"
    peers = ", ".join(other_profiles)
    return f"endpoint {endpoint} is also configured for {label} {peers}"


def ensure_unique_profile_endpoint(
    name: str,
    profiles: dict[str, ProfileEnv],
    *,
    action: str,
) -> None:
    conflict = profile_endpoint_conflicts(profiles).get(name)
    if not conflict:
        return
    endpoint, other_profiles = conflict
    detail = format_endpoint_conflict(endpoint, other_profiles)
    raise ProfileConflictError(
        f"Cannot {action} {name}: {detail}. Each profile must use a unique HOST:PORT or BASE_URL."
    )


def read_pid(profile_name: str) -> int | None:
    path = pid_path(profile_name)
    if not path.exists():
        return None
    raw = path.read_text().strip()
    if not raw:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def process_alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def child_pids(pid: int) -> list[int]:
    try:
        output = run(["pgrep", "-P", str(pid)]).stdout.strip().splitlines()
    except subprocess.CalledProcessError:
        return []
    children: list[int] = []
    for item in output:
        item = item.strip()
        if item.isdigit():
            children.append(int(item))
    return children


def process_tree_pids(pid: int) -> list[int]:
    seen: set[int] = set()
    ordered: list[int] = []

    def visit(current: int) -> None:
        if current in seen:
            return
        seen.add(current)
        ordered.append(current)
        for child in child_pids(current):
            visit(child)

    visit(pid)
    return ordered


def pid_command(pid: int | None) -> str | None:
    if not pid:
        return None
    try:
        return run(["ps", "-o", "command=", "-p", str(pid)]).stdout.strip() or None
    except subprocess.CalledProcessError:
        return None


def pid_matches_profile(pid: int | None, name: str, env: ProfileEnv) -> bool:
    command = pid_command(pid)
    if not command:
        return False

    normalized_command = command.lower()
    markers = {
        name,
        env.get("PROFILE_NAME"),
        env.get("MODEL_ALIAS"),
        env.get("REQUEST_MODEL"),
        env.get("SERVER_MODEL_ID"),
        env.get("MODEL_PATH"),
        env.get("MODEL_DIR"),
        env.get("MODEL_FILE"),
        env.get("MODEL_REPO"),
    }
    for marker in markers:
        if not marker:
            continue
        value = marker.strip().lower()
        # Short aliases like "v1" / "server" over-match unrelated argv.
        if len(value) < _MIN_PID_MARKER_LEN:
            continue
        if value in normalized_command:
            return True
    return False


def pid_rss_mb(pid: int | None) -> float | None:
    if not pid:
        return None
    try:
        rss_kb = run(["ps", "-o", "rss=", "-p", str(pid)]).stdout.strip()
        if not rss_kb:
            return None
        return round(int(rss_kb) / 1024, 1)
    except (subprocess.CalledProcessError, ValueError):
        return None


def port_listener_pid(port: str) -> int | None:
    if not port:
        return None
    try:
        output = run(["lsof", "-tiTCP:" + port, "-sTCP:LISTEN"]).stdout.strip().splitlines()
    except subprocess.CalledProcessError:
        return None
    for item in output:
        item = item.strip()
        if item.isdigit():
            return int(item)
    return None


def fetch_openai_models(url: str, timeout: float = 1.5) -> list[str]:
    if not url:
        return []
    try:
        url = validate_http_url(url)
    except ValueError:
        return []
    if not is_safe_healthcheck_url(url):
        return []
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- validate_http_url rejects non-http profile URLs before this request.
            payload = json.loads(response.read().decode())
        return [item.get("id", "") for item in payload.get("data", []) if item.get("id")]
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return []


def probe_health(env: ProfileEnv, timeout: float = 1.5) -> tuple[bool, list[str]]:
    mode = healthcheck_mode(env)
    try:
        url = healthcheck_url(env)
    except ValueError:
        return False, []
    if mode == "disabled":
        return False, []
    if url and not is_safe_healthcheck_url(url):
        return False, []
    if mode == "http-200":
        if not url:
            return False, []
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=timeout):  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- healthcheck_url validates explicit profile URLs and generated URLs are loopback http.
                return True, []
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            return False, []
    server_ids = fetch_openai_models(url, timeout=timeout)
    expected = env.get("HEALTHCHECK_EXPECT_ID") or env.get("SERVER_MODEL_ID") or env.get("REQUEST_MODEL")
    if expected:
        return expected in server_ids, server_ids
    return bool(server_ids), server_ids


def status_for_profile(
    name: str,
    env: ProfileEnv,
    *,
    allow_port_fallback: bool = True,
) -> ModelProfileStatusPayload:
    runtime = canonical_runtime(env.get("RUNTIME"))
    spec = runtime_spec(env)
    ready, server_ids = probe_health(env)
    pid = read_pid(name)
    if pid and not process_alive(pid):
        pid_path(name).unlink(missing_ok=True)
        pid = None
    if not pid and allow_port_fallback:
        fallback_pid = port_listener_pid(endpoint_port(env))
        if fallback_pid and (ready or pid_matches_profile(fallback_pid, name, env)):
            pid = fallback_pid
    return {
        "profile": name,
        "display_name": env["DISPLAY_NAME"],
        "runtime": runtime,
        "runtime_label": spec["label"],
        "runtime_tags": runtime_tags(env),
        "launch_mode": spec["launch_mode"],
        "host": endpoint_host(env),
        "port": endpoint_port(env),
        "base_url": base_url(env),
        "request_model": env["REQUEST_MODEL"],
        "server_model_id": env.get("SERVER_MODEL_ID", env["REQUEST_MODEL"]),
        "pid": pid,
        "running": bool(pid and process_alive(pid)),
        "ready": ready,
        "server_ids": server_ids,
        "rss_mb": pid_rss_mb(pid),
        "command": pid_command(pid),
        "log_path": log_path(env),
    }


def status_snapshot(selected: list[str] | None = None) -> list[ModelProfileStatusPayload]:
    profiles = load_profiles()
    conflicts = profile_endpoint_conflicts(profiles)
    names = selected or sorted(profiles)
    return [
        status_for_profile(name, profiles[name], allow_port_fallback=name not in conflicts)
        for name in names
    ]


def status_payload(selected: list[str] | None = None) -> ControllerStatusPayload:
    return make_controller_status_payload(
        statuses=status_snapshot(selected),
        benchmark=benchmark_status(),
        integrations=integration_status(),
        profiles_dir=str(PROFILE_DIR),
        controller_root=str(BASE),
    )


def action_response_from_status(
    payload: ControllerStatusPayload,
    *,
    ok: bool = True,
    error: str | None = None,
) -> ControllerActionResponsePayload:
    return make_action_response_payload(
        statuses=payload["statuses"],
        benchmark=payload["benchmark"],
        integrations=payload["integrations"],
        profiles_dir=payload["profiles_dir"],
        controller_root=payload["controller_root"],
        ok=ok,
        error=error,
    )


def write_status_cache(payload: ControllerStatusPayload) -> None:
    STATUS_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    try:
        STATUS_CACHE_PATH.parent.chmod(0o700)
    except OSError:
        pass
    cache_payload = make_cached_status_payload(
        cached_at=dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        payload=payload,
    )
    temp_path = STATUS_CACHE_PATH.with_suffix(".tmp")
    temp_path.write_text(json.dumps(cache_payload, indent=2, sort_keys=True), encoding="utf-8")
    try:
        temp_path.chmod(0o600)
    except OSError:
        pass
    temp_path.replace(STATUS_CACHE_PATH)


def print_status(selected: list[str] | None = None, *, as_json: bool = False) -> None:
    payload = status_payload(selected)
    statuses = payload["statuses"]
    if as_json:
        print(json.dumps(payload, indent=2))
        return
    print("profile | runtime | state | pid | port | request_model | base_url")
    print("--- | --- | --- | --- | --- | --- | ---")
    for item in statuses:
        if item["ready"]:
            state = "ready"
        elif item["running"]:
            state = "process-only"
        else:
            state = "stopped"
        print(
            " | ".join(
                [
                    item["profile"],
                    item["runtime"],
                    state,
                    str(item["pid"] or "-"),
                    item["port"],
                    item["request_model"],
                    item["base_url"],
                ]
            )
        )


def signal_pid(pid: int, sig: int) -> None:
    try:
        os.kill(pid, sig)
    except ProcessLookupError:
        return
    except OSError:
        return


def signal_process_tree(pid: int, sig: int) -> None:
    try:
        pgid = os.getpgid(pid)
    except ProcessLookupError:
        return
    except OSError:
        pgid = None

    if pgid and pgid != os.getpgrp():
        try:
            os.killpg(pgid, sig)
        except ProcessLookupError:
            return
        except OSError:
            pass

    for item in reversed(process_tree_pids(pid)):
        signal_pid(item, sig)


def terminate_pid(pid: int, *, timeout: float = 12.0) -> None:
    signal_process_tree(pid, signal.SIGTERM)
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return
        time.sleep(0.5)
    signal_process_tree(pid, signal.SIGKILL)


def terminate_profile_processes(name: str, env: ProfileEnv, pid: int | None) -> bool:
    terminated = False
    if pid:
        terminate_pid(pid)
        terminated = True

    # A stale PID file should not leave a model server behind. Only reclaim the
    # listener when the process command clearly belongs to this profile — never
    # kill solely because a health URL returned 200 (shared ports / SSRF).
    listener_pid = port_listener_pid(endpoint_port(env))
    if listener_pid and listener_pid != pid and pid_matches_profile(listener_pid, name, env):
        terminate_pid(listener_pid)
        terminated = True
    return terminated


def wait_for_profile_stopped(name: str, env: ProfileEnv, pid: int | None, *, timeout: float = 8.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        listener_pid = port_listener_pid(endpoint_port(env))
        primary_alive = process_alive(pid)
        # Mirror terminate_profile_processes: only treat a foreign listener as
        # "ours" when the command matches. A shared-port 200 OK must not block stop.
        listener_alive = bool(
            listener_pid
            and (
                listener_pid == pid
                or pid_matches_profile(listener_pid, name, env)
            )
        )
        if not primary_alive and not listener_alive:
            return True
        time.sleep(0.5)
    return False


def run_profile_shell(command: str, env: ProfileEnv) -> subprocess.CompletedProcess[str]:
    merged_env = os.environ.copy()
    merged_env.update(env)
    return run(["bash", "-lc", command], env=merged_env, cwd=profile_working_directory(env))


@with_mutation_lock
def start_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="start")
    env = os.environ.copy()
    env["MODEL_PROFILE"] = name
    result = run(["bash", str(START_SCRIPT)], env=env)
    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)


@with_mutation_lock
def stop_profile(name: str) -> None:
    # Clear desired-active before killing so the crash-recovery watchdog cannot
    # race an intentional stop and bring the profile back up.
    suppress_active_profile_watchdog()
    clear_active_profile(name)
    env = require_profile(name)
    status = status_for_profile(name, env)
    pid = status["pid"]
    stop_command = env.get("STOP_COMMAND", "").strip()
    stop_error: Exception | None = None
    if stop_command:
        try:
            run_profile_shell(stop_command, env)
        except Exception as exc:  # noqa: BLE001
            stop_error = exc
    if not pid:
        terminated = False
        if env.get("STOP_COMMAND_ONLY", "0") != "1":
            terminated = terminate_profile_processes(name, env, None)
            if terminated and not wait_for_profile_stopped(name, env, None):
                raise RuntimeError(f"failed to stop {name}: endpoint or process is still alive")
        pid_path(name).unlink(missing_ok=True)
        if stop_error:
            raise RuntimeError(f"STOP_COMMAND failed for {name}: {stop_error}") from stop_error
        if terminated:
            print(f"[INFO] stopped {name} (stale listener)")
        else:
            print(f"[INFO] {name} already stopped")
        return
    if env.get("STOP_COMMAND_ONLY", "0") != "1":
        terminate_profile_processes(name, env, pid)
        if not wait_for_profile_stopped(name, env, pid):
            raise RuntimeError(f"failed to stop {name}: endpoint or process is still alive")
    pid_path(name).unlink(missing_ok=True)
    if stop_error:
        raise RuntimeError(f"STOP_COMMAND failed for {name}: {stop_error}") from stop_error
    print(f"[INFO] stopped {name} (pid {pid})")


@with_mutation_lock
def restart_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="restart")
    stop_profile(name)
    start_profile(name)


@with_mutation_lock
def stop_all(*, capture_script: bool = False) -> None:
    benchmark_pid = read_pid("benchmark")
    if benchmark_pid:
        terminate_pid(benchmark_pid)
        (RUN_DIR / "benchmark.pid").unlink(missing_ok=True)
    profiles = load_profiles()
    errors: list[str] = []
    for name in sorted(profiles):
        try:
            stop_profile(name)
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{name}: {exc}")
    result = run(["bash", str(STOP_ALL_SCRIPT)], capture=capture_script)
    if capture_script:
        sys.stdout.write(result.stdout)
        if result.stderr:
            sys.stderr.write(result.stderr)
    if errors:
        raise RuntimeError("Failed to stop profiles: " + "; ".join(errors))


def sync_droid() -> None:
    run([sys.executable, str(SYNC_SCRIPT)], capture=False)


def integration_status() -> list[ControllerIntegrationPayload]:
    integrations: list[ControllerIntegrationPayload] = []
    droid_available = SYNC_SCRIPT.exists() and (FACTORY_SETTINGS_PATH.exists() or shutil.which("droid"))
    if droid_available:
        integrations.append(
            {
                "id": "droid",
                "display_name": "Factory Droid",
                "kind": "model_registry",
                "capabilities": ["sync"],
                "sync_label": "Sync Droid",
                "description": "Sync managed local profiles into Factory Droid custom model settings.",
            }
        )
    return integrations


def run_integration_action(integration_id: str, action: str = "sync") -> None:
    if integration_id == "droid" and action == "sync":
        sync_droid()
        return
    raise SystemExit(f"Unsupported integration action: {integration_id}:{action}")


@with_mutation_lock
def switch_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="activate")
    for item in status_snapshot():
        if item["profile"] != name and item["running"]:
            stop_profile(item["profile"])
    start_profile(name)
    write_active_profile(name)


def active_profile_watchdog_once() -> None:
    if is_active_profile_watchdog_suppressed():
        return
    name = read_active_profile()
    if not name:
        return
    profiles = load_profiles()
    env = profiles.get(name)
    if not env:
        clear_active_profile(name)
        return
    status = status_for_profile(name, env)
    if status["ready"] or status["running"]:
        return
    start_profile(name)


def run_active_profile_watchdog(interval: float = 30.0) -> None:
    while True:
        try:
            active_profile_watchdog_once()
        except Exception as exc:  # noqa: BLE001
            print(f"[WARN] active profile watchdog failed: {exc}", file=sys.stderr)
        time.sleep(interval)



#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import shlex
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

BASE = pathlib.Path(__file__).resolve().parent
PROFILE_DIR = BASE / "model-profiles"
RUN_DIR = BASE / "run"
START_SCRIPT = BASE / "start-model-mac.sh"
STOP_ALL_SCRIPT = BASE / "stop-all-models.sh"
SYNC_SCRIPT = BASE / "sync-droid-local-models.py"
BENCH_SCRIPT = BASE / "benchmark-local-models.py"
BENCH_RESULTS_DIR = BASE / "benchmark-results"
DEFAULT_WEB_HOST = "127.0.0.1"
DEFAULT_WEB_PORT = 8877
FACTORY_SETTINGS_PATH = pathlib.Path.home() / ".factory" / "settings.json"
LAUNCH_AGENT_LABEL = "io.modelswitchboard.controller"
LAUNCH_AGENT_PLIST = pathlib.Path.home() / "Library/LaunchAgents" / f"{LAUNCH_AGENT_LABEL}.plist"
STATUS_CACHE_PATH = pathlib.Path.home() / "Library/Caches/io.modelswitchboard/controller-status.json"


HTML_PAGE = """<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>Mac Local Models</title>
  <style>
    :root {
      --bg: #0b1020;
      --panel: #121936;
      --panel-2: #1a2349;
      --text: #edf2ff;
      --muted: #aeb8d6;
      --accent: #7cf0d2;
      --warn: #ffcf66;
      --bad: #ff7d7d;
      --good: #63f29a;
      --line: rgba(255,255,255,0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top left, rgba(124,240,210,0.18), transparent 28%),
        radial-gradient(circle at top right, rgba(91,127,255,0.22), transparent 25%),
        linear-gradient(180deg, #0a0f1d 0%, #0f1730 100%);
      min-height: 100vh;
    }
    .wrap {
      width: min(1180px, calc(100vw - 32px));
      margin: 24px auto 48px;
    }
    .hero {
      display: grid;
      gap: 12px;
      margin-bottom: 18px;
    }
    .hero h1 {
      margin: 0;
      font-size: clamp(28px, 4vw, 46px);
      letter-spacing: -0.04em;
    }
    .hero p {
      margin: 0;
      color: var(--muted);
      max-width: 820px;
      line-height: 1.5;
    }
    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin: 16px 0 22px;
    }
    button {
      background: var(--panel);
      color: var(--text);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 10px 14px;
      cursor: pointer;
      font-weight: 600;
    }
    button:hover { border-color: rgba(124,240,210,0.45); }
    button.primary { background: linear-gradient(135deg, #1a3150, #143b34); }
    button.warn { background: linear-gradient(135deg, #4b3012, #513300); }
    button.bad { background: linear-gradient(135deg, #4d1623, #521515); }
    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin-bottom: 20px;
    }
    .metric, .card {
      background: rgba(18,25,54,0.82);
      border: 1px solid var(--line);
      border-radius: 18px;
      backdrop-filter: blur(10px);
    }
    .metric {
      padding: 14px 16px;
    }
    .metric .label {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      margin-bottom: 6px;
    }
    .metric .value {
      font-size: 28px;
      font-weight: 700;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
      gap: 14px;
    }
    .card {
      padding: 16px;
      display: grid;
      gap: 12px;
    }
    .topline {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
    }
    .title {
      display: grid;
      gap: 4px;
    }
    .title h2 {
      margin: 0;
      font-size: 19px;
      line-height: 1.2;
    }
    .title .meta {
      color: var(--muted);
      font-size: 13px;
    }
    .pill {
      padding: 6px 10px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.04em;
      border: 1px solid transparent;
      white-space: nowrap;
    }
    .pill.running { color: #071910; background: var(--good); }
    .pill.idle { color: #2d2300; background: var(--warn); }
    .pill.dead { color: white; background: var(--bad); }
    .details {
      display: grid;
      gap: 6px;
      font-size: 13px;
      color: var(--muted);
    }
    .details code {
      color: var(--text);
      font-size: 12px;
      word-break: break-all;
    }
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }
    .log {
      font-size: 12px;
      color: var(--muted);
      word-break: break-all;
    }
    .footer {
      margin-top: 18px;
      color: var(--muted);
      font-size: 12px;
    }
  </style>
</head>
<body>
  <div class=\"wrap\">
    <div class=\"hero\">
      <h1>Mac Local Model Control</h1>
      <p>This control plane manages your local `llama.cpp` and `MLX` profiles, tracks real PIDs, and gives you one place to start, switch, benchmark, and stop heavyweight runtimes cleanly. External integrations are optional and only show up when available.</p>
    </div>
    <div class=\"toolbar\">
      <button class=\"primary\" onclick=\"refreshStatus()\">Refresh</button>
      <span id=\"integration-actions\"></span>
      <button onclick=\"startChecked()\">Start Checked</button>
      <button onclick=\"switchChecked()\">Activate Checked</button>
      <button class=\"warn\" onclick=\"stopChecked()\">Stop Checked</button>
      <button onclick=\"runQuickBench()\">Run Quick Bench</button>
      <button class=\"bad\" onclick=\"stopAll()\">Stop All Models</button>
    </div>
    <div class=\"summary\" id=\"summary\"></div>
    <div class=\"grid\" id=\"cards\"></div>
    <div class=\"footer\" id=\"footer\"></div>
  </div>
  <script>
    async function api(path, options = {}) {
      const response = await fetch(path, {
        headers: { 'Content-Type': 'application/json' },
        ...options,
      });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `HTTP ${response.status}`);
      }
      return response.json();
    }

    function checkedProfiles() {
      return Array.from(document.querySelectorAll('input[data-profile]:checked')).map(el => el.dataset.profile);
    }

    async function refreshStatus() {
      const data = await api('/api/status');
      render(data);
    }

    async function postAction(path, payload = {}) {
      try {
        await api(path, { method: 'POST', body: JSON.stringify(payload) });
        await refreshStatus();
      } catch (error) {
        alert(error.message);
      }
    }

    async function stopAll() { await postAction('/api/stop-all'); }
    async function startProfile(name) { await postAction('/api/start', { profile: name }); }
    async function stopProfile(name) { await postAction('/api/stop', { profile: name }); }
    async function restartProfile(name) { await postAction('/api/restart', { profile: name }); }
    async function switchProfile(name) { await postAction('/api/switch', { profile: name }); }
    async function runIntegration(integration, action = 'sync') {
      await postAction('/api/integrations/run', { integration, action });
    }
    async function runQuickBench() {
      const profiles = checkedProfiles();
      await postAction('/api/benchmark/start', { profiles: profiles.length ? profiles : null, suite: 'quick' });
    }
    async function startChecked() {
      const profiles = checkedProfiles();
      if (profiles.length === 0) return;
      await postAction('/api/start-many', { profiles });
    }
    async function switchChecked() {
      const profiles = checkedProfiles();
      if (profiles.length !== 1) {
        alert('Select exactly one profile to activate.');
        return;
      }
      await switchProfile(profiles[0]);
    }
    async function stopChecked() {
      const profiles = checkedProfiles();
      if (profiles.length === 0) return;
      await postAction('/api/stop-many', { profiles });
    }

    function render(data) {
      const statuses = data.statuses || [];
      const running = statuses.filter(item => item.running).length;
      const ready = statuses.filter(item => item.ready).length;
      const total = statuses.length;
      const benchmark = data.benchmark || {};
      const integrations = data.integrations || [];
      const runtimeCounts = statuses.reduce((acc, item) => {
        acc[item.runtime] = (acc[item.runtime] || 0) + 1;
        return acc;
      }, {});

      document.getElementById('integration-actions').innerHTML = integrations
        .filter(item => item.capabilities.includes('sync'))
        .map(item => `<button onclick="runIntegration('${item.id}', 'sync')">${item.sync_label || ('Sync ' + item.display_name)}</button>`)
        .join('');

      document.getElementById('summary').innerHTML = `
        <div class=\"metric\"><div class=\"label\">Profiles</div><div class=\"value\">${total}</div></div>
        <div class=\"metric\"><div class=\"label\">Running</div><div class=\"value\">${running}</div></div>
        <div class=\"metric\"><div class=\"label\">Healthy Endpoints</div><div class=\"value\">${ready}</div></div>
        <div class=\"metric\"><div class=\"label\">Runtimes</div><div class=\"value\">${Object.entries(runtimeCounts).map(([k, v]) => `${k}:${v}`).join(' ')}</div></div>
        <div class=\"metric\"><div class=\"label\">Benchmark</div><div class=\"value\">${benchmark.running ? 'RUNNING' : (benchmark.latest ? benchmark.latest.suite : 'idle')}</div></div>
        <div class=\"metric\"><div class=\"label\">Integrations</div><div class=\"value\">${integrations.length || 0}</div></div>
      `;

      document.getElementById('cards').innerHTML = statuses.map(item => {
        const stateClass = item.ready ? 'running' : (item.running ? 'idle' : 'dead');
        const stateText = item.running ? 'RUNNING' : 'NOT RUNNING';
        return `
          <div class=\"card\">
            <div class=\"topline\">
              <div class=\"title\">
                <h2><label><input type=\"checkbox\" data-profile=\"${item.profile}\"> ${item.display_name}</label></h2>
                <div class=\"meta\">${item.profile} • ${item.runtime} • ${item.request_model}</div>
              </div>
              <div class=\"pill ${stateClass}\">${stateText}</div>
            </div>
            <div class=\"details\">
              <div>Base URL: <code>${item.base_url}</code></div>
              <div>Port: <code>${item.host}:${item.port}</code></div>
              <div>PID: <code>${item.pid || 'none'}</code> • RSS: <code>${item.rss_mb ? item.rss_mb + ' MB' : 'n/a'}</code></div>
              <div>Server IDs: <code>${(item.server_ids || []).join(', ') || 'n/a'}</code></div>
            </div>
            <div class=\"actions\">
              <button class=\"primary\" onclick=\"switchProfile('${item.profile}')\">Activate</button>
              <button onclick=\"startProfile('${item.profile}')\">Start</button>
              <button class=\"warn\" onclick=\"stopProfile('${item.profile}')\">Stop</button>
              <button onclick=\"restartProfile('${item.profile}')\">Restart</button>
              <button onclick=\"window.open('${item.base_url.replace('/v1', '/v1/models')}', '_blank')\">Open /v1/models</button>
              <button onclick=\"postAction('/api/benchmark/start', { profiles: ['${item.profile}'], suite: 'quick' })\">Bench</button>
            </div>
            <div class=\"log\">Log: ${item.log_path}</div>
          </div>
        `;
      }).join('');

      document.getElementById('footer').textContent = `Updated ${new Date().toLocaleString()} • managed by modelctl.py`;
    }

    refreshStatus();
    setInterval(refreshStatus, 5000);
  </script>
</body>
</html>
"""


def run(cmd: list[str], *, check: bool = True, capture: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
        env=env,
    )


def load_env_profile(path: pathlib.Path) -> dict[str, str]:
    data = subprocess.check_output(
        ["bash", "-lc", f"set -a; source {shlex.quote(str(path))}; env -0"],
        text=False,
    )
    env: dict[str, str] = {}
    for item in data.decode().split("\0"):
        if not item or "=" not in item:
            continue
        key, value = item.split("=", 1)
        env[key] = value
    env["PROFILE_NAME"] = path.stem
    return env


def load_json_profile(path: pathlib.Path) -> dict[str, str]:
    raw = json.loads(path.read_text())
    if not isinstance(raw, dict):
        raise SystemExit(f"Profile JSON must be an object: {path}")
    env: dict[str, str] = {}
    for key, value in raw.items():
        if value is None:
            env[key] = ""
        elif isinstance(value, bool):
            env[key] = "1" if value else "0"
        else:
            env[key] = str(value)
    env["PROFILE_NAME"] = path.stem
    return env


def load_profile(path: pathlib.Path) -> dict[str, str]:
    if path.suffix == ".json":
        return load_json_profile(path)
    return load_env_profile(path)


def profile_paths() -> list[pathlib.Path]:
    return sorted(list(PROFILE_DIR.glob("*.env")) + list(PROFILE_DIR.glob("*.json")))


def load_profiles() -> dict[str, dict[str, str]]:
    return {path.stem: load_profile(path) for path in profile_paths()}


def require_profile(name: str) -> dict[str, str]:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    return profiles[name]


def pid_path(profile_name: str) -> pathlib.Path:
    return RUN_DIR / f"{profile_name}.pid"


def log_path(env: dict[str, str]) -> str:
    return f"/tmp/{env.get('MODEL_ALIAS', env['PROFILE_NAME'])}.log"


def base_url(env: dict[str, str]) -> str:
    configured = env.get("BASE_URL", "").strip()
    if configured:
        return configured.rstrip("/")
    port = env.get("PORT", "").strip()
    if not port:
        return ""
    return f"http://{env.get('HOST', '127.0.0.1')}:{port}/v1"


def models_url(env: dict[str, str]) -> str:
    configured = env.get("MODEL_LIST_URL", "").strip()
    if configured:
        return configured
    url = base_url(env)
    if not url:
        return ""
    return f"{url}/models"


def healthcheck_mode(env: dict[str, str]) -> str:
    return env.get("HEALTHCHECK_MODE", "openai-models").strip().lower()


def healthcheck_url(env: dict[str, str]) -> str:
    configured = env.get("HEALTHCHECK_URL", "").strip()
    if configured:
        return configured
    if healthcheck_mode(env) == "openai-models":
        return models_url(env)
    return base_url(env)


def endpoint_host(env: dict[str, str]) -> str:
    if env.get("HOST"):
        return env["HOST"]
    url = base_url(env)
    parsed = urllib.parse.urlparse(url)
    return parsed.hostname or "127.0.0.1"


def endpoint_port(env: dict[str, str]) -> str:
    if env.get("PORT"):
        return env["PORT"]
    url = base_url(env)
    parsed = urllib.parse.urlparse(url)
    return str(parsed.port or "")


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


def pid_command(pid: int | None) -> str | None:
    if not pid:
        return None
    try:
        return run(["ps", "-o", "command=", "-p", str(pid)]).stdout.strip() or None
    except subprocess.CalledProcessError:
        return None


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
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode())
        return [item.get("id", "") for item in payload.get("data", []) if item.get("id")]
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, json.JSONDecodeError):
        return []


def probe_health(env: dict[str, str], timeout: float = 1.5) -> tuple[bool, list[str]]:
    mode = healthcheck_mode(env)
    url = healthcheck_url(env)
    if mode == "disabled":
        return False, []
    if mode == "http-200":
        if not url:
            return False, []
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=timeout):
                return True, []
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            return False, []
    server_ids = fetch_openai_models(url, timeout=timeout)
    expected = env.get("HEALTHCHECK_EXPECT_ID") or env.get("SERVER_MODEL_ID") or env.get("REQUEST_MODEL")
    if expected:
        return expected in server_ids, server_ids
    return bool(server_ids), server_ids


def status_for_profile(name: str, env: dict[str, str]) -> dict[str, Any]:
    pid = read_pid(name)
    if pid and not process_alive(pid):
        pid_path(name).unlink(missing_ok=True)
        pid = None
    if not pid:
        pid = port_listener_pid(endpoint_port(env))
    ready, server_ids = probe_health(env)
    return {
        "profile": name,
        "display_name": env["DISPLAY_NAME"],
        "runtime": env.get("RUNTIME", "llama.cpp"),
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


def status_snapshot(selected: list[str] | None = None) -> list[dict[str, Any]]:
    profiles = load_profiles()
    names = selected or sorted(profiles)
    return [status_for_profile(name, profiles[name]) for name in names]


def status_payload(selected: list[str] | None = None) -> dict[str, Any]:
    return {
        "statuses": status_snapshot(selected),
        "benchmark": benchmark_status(),
        "integrations": integration_status(),
    }


def write_status_cache(payload: dict[str, Any]) -> None:
    STATUS_CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)
    cache_payload = {
        "cached_at": dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z"),
        **payload,
    }
    temp_path = STATUS_CACHE_PATH.with_suffix(".tmp")
    temp_path.write_text(json.dumps(cache_payload, indent=2, sort_keys=True), encoding="utf-8")
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



def start_profile(name: str) -> None:
    require_profile(name)
    env = os.environ.copy()
    env["MODEL_PROFILE"] = name
    result = run(["bash", str(START_SCRIPT)], env=env)
    sys.stdout.write(result.stdout)
    if result.stderr:
        sys.stderr.write(result.stderr)



def terminate_pid(pid: int, *, timeout: float = 12.0) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not process_alive(pid):
            return
        time.sleep(0.5)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        return



def stop_profile(name: str) -> None:
    env = require_profile(name)
    status = status_for_profile(name, env)
    pid = status["pid"]
    if not pid:
        pid_path(name).unlink(missing_ok=True)
        print(f"[INFO] {name} already stopped")
        return
    terminate_pid(pid)
    pid_path(name).unlink(missing_ok=True)
    print(f"[INFO] stopped {name} (pid {pid})")



def restart_profile(name: str) -> None:
    stop_profile(name)
    start_profile(name)



def stop_all() -> None:
    run(["bash", str(STOP_ALL_SCRIPT)], capture=False)



def sync_droid() -> None:
    run([sys.executable, str(SYNC_SCRIPT)], capture=False)


def integration_status() -> list[dict[str, Any]]:
    integrations: list[dict[str, Any]] = []
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


def switch_profile(name: str) -> None:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    for item in status_snapshot():
        if item["profile"] != name and item["running"]:
            stop_profile(item["profile"])
    start_profile(name)


def latest_benchmark_report() -> dict[str, Any] | None:
    latest_json = BENCH_RESULTS_DIR / "latest.json"
    latest_md = BENCH_RESULTS_DIR / "latest.md"
    if not latest_json.exists():
        return None
    try:
        payload = json.loads(latest_json.read_text())
    except json.JSONDecodeError:
        return None
    rows = []
    for item in payload.get("benchmarks", []):
        avg = item.get("averages", {})
        rows.append(
            {
                "profile": item.get("profile"),
                "runtime": item.get("runtime"),
                "ttft_ms": avg.get("ttft_ms"),
                "decode_tokens_per_sec": avg.get("decode_tokens_per_sec"),
                "e2e_tokens_per_sec": avg.get("e2e_tokens_per_sec"),
                "rss_mb": item.get("rss_mb"),
            }
        )
    return {
        "generated_at": payload.get("generated_at"),
        "suite": payload.get("suite"),
        "profiles": payload.get("profiles", []),
        "rows": rows,
        "json_path": str(latest_json),
        "markdown_path": str(latest_md),
    }


def benchmark_pid_path() -> pathlib.Path:
    return RUN_DIR / "benchmark.pid"


def benchmark_log_path() -> pathlib.Path:
    return pathlib.Path("/tmp/model-benchmark.log")


def benchmark_status() -> dict[str, Any]:
    pid = read_pid("benchmark")
    alive = bool(pid and process_alive(pid))
    if pid and not alive:
        benchmark_pid_path().unlink(missing_ok=True)
        pid = None
    return {
        "running": alive,
        "pid": pid,
        "log_path": str(benchmark_log_path()),
        "latest": latest_benchmark_report(),
    }


def start_benchmark(
    profiles: list[str] | None = None,
    *,
    suite: str = "quick",
    allow_concurrent: bool = False,
    keep_running: bool = False,
) -> dict[str, Any]:
    current = benchmark_status()
    if current["running"]:
        return current
    selected = profiles or ["all"]
    cmd = [sys.executable, str(BENCH_SCRIPT), "--suite", suite, "--profiles", *selected]
    if allow_concurrent:
        cmd.append("--allow-concurrent")
    if keep_running:
        cmd.append("--keep-running")
    RUN_DIR.mkdir(parents=True, exist_ok=True)
    with open(benchmark_log_path(), "ab", buffering=0) as log_fp, open(os.devnull, "rb") as stdin_fp:
        proc = subprocess.Popen(
            cmd,
            stdin=stdin_fp,
            stdout=log_fp,
            stderr=log_fp,
            start_new_session=True,
            close_fds=True,
        )
    benchmark_pid_path().write_text(f"{proc.pid}\n")
    return benchmark_status()


def detect_model_root(env: dict[str, str]) -> pathlib.Path:
    local_model_root = BASE / "../models"
    candidates = [
        env.get("MODEL_ROOT"),
        env.get("MODEL_ROOT_HINT"),
        str(local_model_root),
        str(pathlib.Path.home() / "AI/models"),
    ]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).is_dir():
            return pathlib.Path(candidate)
    return pathlib.Path(local_model_root)


def resolve_llama_server_bin() -> str | None:
    candidates = [
        os.environ.get("LLAMA_SERVER_BIN"),
        str(BASE / "runtime/llama.cpp-apple/build/bin/llama-server"),
        "/opt/homebrew/bin/llama-server",
        "/usr/local/bin/llama-server",
        "/opt/homebrew/bin/llama.cpp-server",
        "/usr/local/bin/llama.cpp-server",
        str(pathlib.Path.home() / "Developer/llama.cpp/build/bin/llama-server"),
        str(pathlib.Path.home() / "Developer/llama.cpp/build/bin/llama.cpp-server"),
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("llama-server") or shutil.which("llama.cpp-server")


def resolve_mlx_server_bin() -> str | None:
    candidates = [
        os.environ.get("MLX_SERVER_BIN"),
        str(BASE / ".venv-mlx-lm/bin/mlx_lm.server"),
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return shutil.which("mlx_lm.server")


def model_path_for_profile(env: dict[str, str]) -> pathlib.Path | None:
    if env.get("MODEL_PATH"):
        return pathlib.Path(env["MODEL_PATH"])
    if env.get("MODEL_FILE"):
        return detect_model_root(env) / env["MODEL_FILE"]
    return None


def launch_agent_status() -> dict[str, Any]:
    try:
        output = run(["launchctl", "list"], check=False).stdout
    except Exception:  # noqa: BLE001
        output = ""
    running = LAUNCH_AGENT_LABEL in output
    return {"plist_path": str(LAUNCH_AGENT_PLIST), "installed": LAUNCH_AGENT_PLIST.exists(), "running": running}


def controller_status() -> dict[str, Any]:
    url = f"http://{DEFAULT_WEB_HOST}:{DEFAULT_WEB_PORT}/api/status"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=1.5) as response:
            payload = json.loads(response.read().decode())
        return {
            "url": url,
            "reachable": True,
            "profiles": len(payload.get("statuses", [])),
            "integrations": len(payload.get("integrations", [])),
        }
    except Exception:  # noqa: BLE001
        return {"url": url, "reachable": False, "profiles": 0, "integrations": 0}


def diagnose_profile(name: str, env: dict[str, str]) -> dict[str, Any]:
    runtime = env.get("RUNTIME", "llama.cpp")
    errors: list[str] = []
    warnings: list[str] = []

    if not env.get("DISPLAY_NAME"):
        errors.append("missing DISPLAY_NAME")
    if not env.get("REQUEST_MODEL"):
        errors.append("missing REQUEST_MODEL")

    if runtime == "llama.cpp":
        if not resolve_llama_server_bin():
            errors.append("llama-server not found")
        model_path = model_path_for_profile(env)
        if not model_path:
            errors.append("missing MODEL_PATH or MODEL_FILE")
        elif not model_path.exists():
            errors.append(f"model file not found: {model_path}")
    elif runtime == "mlx":
        if not resolve_mlx_server_bin():
            errors.append("mlx_lm.server not found")
        model_dir = env.get("MODEL_DIR")
        model_repo = env.get("MODEL_REPO")
        if model_dir:
            if not pathlib.Path(model_dir).exists():
                errors.append(f"MODEL_DIR not found: {model_dir}")
        elif not model_repo:
            errors.append("missing MODEL_DIR or MODEL_REPO")
    elif runtime in {"custom", "command"}:
        if not env.get("START_COMMAND"):
            errors.append("missing START_COMMAND")
        if healthcheck_mode(env) != "disabled" and not healthcheck_url(env):
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    else:
        warnings.append(f"runtime '{runtime}' has no adapter-specific validation yet")

    if not base_url(env):
        warnings.append("base_url is empty; endpoint open action will be disabled")
    if healthcheck_mode(env) == "disabled":
        warnings.append("healthcheck disabled; ready state cannot be verified")

    try:
        live = status_for_profile(name, env)
    except Exception as exc:  # noqa: BLE001
        live = {
            "running": False,
            "ready": False,
            "pid": None,
            "base_url": base_url(env),
            "error": str(exc),
        }
        errors.append(f"status probe failed: {exc}")

    return {
        "profile": name,
        "display_name": env.get("DISPLAY_NAME", name),
        "runtime": runtime,
        "errors": errors,
        "warnings": warnings,
        "running": live.get("running", False),
        "ready": live.get("ready", False),
        "pid": live.get("pid"),
        "base_url": live.get("base_url", base_url(env)),
    }


def doctor_report() -> dict[str, Any]:
    profiles = load_profiles()
    diagnostics = [diagnose_profile(name, env) for name, env in sorted(profiles.items())]
    return {
        "controller": controller_status(),
        "launch_agent": launch_agent_status(),
        "integrations": integration_status(),
        "profiles_dir": str(PROFILE_DIR),
        "profiles": diagnostics,
    }


def print_doctor(report: dict[str, Any]) -> None:
    controller = report["controller"]
    launch_agent = report["launch_agent"]
    print("component | status | details")
    print("--- | --- | ---")
    print(
        f"controller | {'ok' if controller['reachable'] else 'warn'} | "
        f"{controller['url']} • profiles={controller['profiles']} • integrations={controller['integrations']}"
    )
    print(
        f"launch-agent | {'ok' if launch_agent['installed'] else 'warn'} | "
        f"installed={launch_agent['installed']} running={launch_agent['running']} • {launch_agent['plist_path']}"
    )
    print(f"profiles-dir | ok | {report['profiles_dir']}")
    for item in report["profiles"]:
        if item["errors"]:
            state = "error"
        elif item["warnings"]:
            state = "warn"
        else:
            state = "ok"
        details = [
            f"{item['display_name']} ({item['runtime']})",
            f"running={item['running']}",
            f"ready={item['ready']}",
            f"pid={item['pid'] or '-'}",
            item["base_url"] or "base_url=n/a",
        ]
        if item["errors"]:
            details.append("errors=" + "; ".join(item["errors"]))
        if item["warnings"]:
            details.append("warnings=" + "; ".join(item["warnings"]))
        print(f"profile:{item['profile']} | {state} | {' • '.join(details)}")


class DashboardHandler(BaseHTTPRequestHandler):
    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body: str, status: int = 200) -> None:
        raw = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0:
            return {}
        payload = self.rfile.read(length).decode()
        return json.loads(payload) if payload else {}

    def do_GET(self) -> None:
        if self.path in {"/", "/index.html"}:
            self._send_html(HTML_PAGE)
            return
        if self.path == "/api/status":
            payload = status_payload()
            write_status_cache(payload)
            self._send_json(payload)
            return
        if self.path == "/api/benchmark/status":
            self._send_json(benchmark_status())
            return
        if self.path == "/api/integrations":
            self._send_json({"integrations": integration_status()})
            return
        self._send_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:
        try:
            payload = self._read_json()
            if self.path == "/api/start":
                start_profile(payload["profile"])
            elif self.path == "/api/stop":
                stop_profile(payload["profile"])
            elif self.path == "/api/restart":
                restart_profile(payload["profile"])
            elif self.path == "/api/switch":
                switch_profile(payload["profile"])
            elif self.path == "/api/start-many":
                for name in payload.get("profiles", []):
                    start_profile(name)
            elif self.path == "/api/stop-many":
                for name in payload.get("profiles", []):
                    stop_profile(name)
            elif self.path == "/api/stop-all":
                stop_all()
            elif self.path == "/api/sync-droid":
                sync_droid()
            elif self.path == "/api/integrations/run":
                run_integration_action(payload["integration"], payload.get("action", "sync"))
            elif self.path == "/api/benchmark/start":
                status = start_benchmark(
                    payload.get("profiles"),
                    suite=payload.get("suite", "quick"),
                    allow_concurrent=bool(payload.get("allow_concurrent", False)),
                    keep_running=bool(payload.get("keep_running", False)),
                )
                response_payload = {
                    "ok": True,
                    "benchmark": status,
                    "statuses": status_snapshot(),
                    "integrations": integration_status(),
                }
                write_status_cache(
                    {
                        "statuses": response_payload["statuses"],
                        "benchmark": response_payload["benchmark"],
                        "integrations": response_payload["integrations"],
                    }
                )
                self._send_json(response_payload)
                return
            else:
                self._send_json({"error": "not found"}, status=404)
                return
        except Exception as exc:  # noqa: BLE001
            self._send_json({"error": str(exc)}, status=500)
            return
        payload = {
            "ok": True,
            "statuses": status_snapshot(),
            "benchmark": benchmark_status(),
            "integrations": integration_status(),
        }
        write_status_cache(
            {
                "statuses": payload["statuses"],
                "benchmark": payload["benchmark"],
                "integrations": payload["integrations"],
            }
        )
        self._send_json(payload)

    def log_message(self, fmt: str, *args: Any) -> None:
        return



def serve_web(host: str, port: int) -> None:
    server = ThreadingHTTPServer((host, port), DashboardHandler)
    print(f"dashboard=http://{host}:{port}")
    server.serve_forever()



def resolve_selected(args: argparse.Namespace) -> list[str] | None:
    if not getattr(args, "profiles", None):
        return None
    if args.profiles == ["all"]:
        return sorted(load_profiles())
    return args.profiles



def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Control local llama.cpp and MLX profiles")
    sub = parser.add_subparsers(dest="command", required=True)

    status_cmd = sub.add_parser("status", help="Show status for profiles")
    status_cmd.add_argument("profiles", nargs="*", default=[])
    status_cmd.add_argument("--json", action="store_true")

    list_cmd = sub.add_parser("list", help="List profiles")
    list_cmd.add_argument("--json", action="store_true")

    start_cmd = sub.add_parser("start", help="Start one or more profiles")
    start_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")

    stop_cmd = sub.add_parser("stop", help="Stop one or more profiles")
    stop_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")

    restart_cmd = sub.add_parser("restart", help="Restart one or more profiles")
    restart_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")

    switch_cmd = sub.add_parser("switch", help="Stop other running profiles and start the selected one")
    switch_cmd.add_argument("profile", help="Profile name")

    bench_cmd = sub.add_parser("benchmark", help="Run the benchmark harness")
    bench_cmd.add_argument("profiles", nargs="*", default=["all"], help="Profile names or 'all'")
    bench_cmd.add_argument("--suite", choices=["quick", "coding"], default="quick")
    bench_cmd.add_argument("--allow-concurrent", action="store_true")
    bench_cmd.add_argument("--keep-running", action="store_true")
    bench_cmd.add_argument("--background", action="store_true")

    doctor_cmd = sub.add_parser("doctor", help="Validate profiles, controller, and launch agent")
    doctor_cmd.add_argument("--json", action="store_true")

    sub.add_parser("integrations", help="List optional backend integrations")
    integration_cmd = sub.add_parser("run-integration", help="Run an action on an optional integration")
    integration_cmd.add_argument("integration", help="Integration id")
    integration_cmd.add_argument("--action", default="sync", help="Integration action to run")

    sub.add_parser("sync-droid", help="Sync profile endpoints into Droid settings")
    sub.add_parser("stop-all", help="Stop every managed model process")

    web_cmd = sub.add_parser("serve-web", help="Serve the local model dashboard")
    web_cmd.add_argument("--host", default=DEFAULT_WEB_HOST)
    web_cmd.add_argument("--port", type=int, default=DEFAULT_WEB_PORT)

    return parser



def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "list":
        profiles = load_profiles()
        rows = [
            {
                "profile": name,
                "display_name": env["DISPLAY_NAME"],
                "runtime": env.get("RUNTIME", "llama.cpp"),
                "request_model": env["REQUEST_MODEL"],
                "base_url": base_url(env),
            }
            for name, env in sorted(profiles.items())
        ]
        if args.json:
            print(json.dumps({"profiles": rows}, indent=2))
        else:
            print("profile | runtime | displayName | request_model | base_url")
            print("--- | --- | --- | --- | ---")
            for row in rows:
                print(
                    " | ".join(
                        [
                            row["profile"],
                            row["runtime"],
                            row["display_name"],
                            row["request_model"],
                            row["base_url"],
                        ]
                    )
                )
        return

    if args.command == "status":
        print_status(resolve_selected(args), as_json=args.json)
        return

    if args.command == "sync-droid":
        sync_droid()
        return

    if args.command == "integrations":
        print(json.dumps({"integrations": integration_status()}, indent=2))
        return

    if args.command == "run-integration":
        run_integration_action(args.integration, args.action)
        return

    if args.command == "stop-all":
        stop_all()
        return

    if args.command == "serve-web":
        serve_web(args.host, args.port)
        return

    if args.command == "doctor":
        report = doctor_report()
        if args.json:
            print(json.dumps(report, indent=2))
        else:
            print_doctor(report)
        return

    if args.command == "switch":
        switch_profile(args.profile)
        return

    if args.command == "benchmark":
        selected = None if args.profiles == ["all"] else args.profiles
        if args.background:
            print(json.dumps(start_benchmark(
                selected,
                suite=args.suite,
                allow_concurrent=args.allow_concurrent,
                keep_running=args.keep_running,
            ), indent=2))
            return
        cmd = [sys.executable, str(BENCH_SCRIPT), "--suite", args.suite, "--profiles", *(selected or ["all"])]
        if args.allow_concurrent:
            cmd.append("--allow-concurrent")
        if args.keep_running:
            cmd.append("--keep-running")
        run(cmd, capture=False)
        return

    selected = resolve_selected(args)
    if not selected:
        raise SystemExit("No profiles selected")

    for name in selected:
        if args.command == "start":
            start_profile(name)
        elif args.command == "stop":
            stop_profile(name)
        elif args.command == "restart":
            restart_profile(name)


if __name__ == "__main__":
    main()

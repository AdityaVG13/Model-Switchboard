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


HTML_PAGE = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Model Switchboard Dashboard</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0f1218;
      --panel: #171c24;
      --panel-soft: #1f2530;
      --line: rgba(255, 255, 255, 0.08);
      --line-strong: rgba(255, 255, 255, 0.14);
      --text: #f3f5f7;
      --muted: #a7b0bc;
      --good: #69d18f;
      --warn: #f0c06b;
      --bad: #ef7d7d;
      --accent: #8bb8ff;
      --accent-strong: #5e94f0;
      --shadow: 0 18px 48px rgba(0, 0, 0, 0.26);
      --radius: 18px;
      --radius-sm: 12px;
    }

    * { box-sizing: border-box; }

    body {
      margin: 0;
      min-height: 100vh;
      background: linear-gradient(180deg, #0d1015 0%, #11151d 100%);
      color: var(--text);
      font-family: "SF Pro Text", "Inter", system-ui, sans-serif;
    }

    button,
    code {
      font: inherit;
    }

    code {
      font-family: "SF Mono", "JetBrains Mono", monospace;
    }

    .shell {
      width: min(1040px, calc(100vw - 32px));
      margin: 20px auto 28px;
      display: grid;
      gap: 16px;
    }

    .panel {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: var(--radius);
      box-shadow: var(--shadow);
    }

    .header {
      display: flex;
      align-items: start;
      justify-content: space-between;
      gap: 16px;
      padding: 20px 22px;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      margin-bottom: 8px;
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.12em;
      text-transform: uppercase;
    }

    .eyebrow::before {
      content: "";
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: var(--accent);
    }

    h1 {
      margin: 0 0 6px;
      font-size: 30px;
      line-height: 1.05;
      letter-spacing: -0.03em;
    }

    .header p,
    .muted {
      margin: 0;
      color: var(--muted);
      line-height: 1.5;
      font-size: 14px;
    }

    .heartbeat {
      color: var(--muted);
      font-size: 13px;
      white-space: nowrap;
    }

    .toolbar,
    .section,
    .footer {
      padding: 16px 18px;
    }

    .toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
    }

    .summary {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
    }

    .stat {
      padding: 14px 16px;
      background: var(--panel-soft);
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
    }

    .stat .label {
      color: var(--muted);
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      margin-bottom: 8px;
    }

    .stat .value {
      font-size: 24px;
      font-weight: 700;
      letter-spacing: -0.03em;
    }

    .stat .subvalue {
      margin-top: 6px;
      color: var(--muted);
      font-size: 13px;
    }

    .section-header {
      display: flex;
      justify-content: space-between;
      gap: 12px;
      align-items: start;
      margin-bottom: 12px;
    }

    .section-header h2 {
      margin: 0;
      font-size: 18px;
    }

    .integration-actions,
    .card-actions {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
    }

    .cards {
      display: grid;
      gap: 12px;
    }

    .card {
      padding: 16px;
      background: var(--panel-soft);
      border: 1px solid var(--line);
      border-radius: var(--radius-sm);
      display: grid;
      gap: 12px;
    }

    .card-top {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: start;
    }

    .card-title {
      margin: 0 0 4px;
      font-size: 21px;
      line-height: 1.15;
    }

    .card-meta,
    .card-endpoint,
    .card-inspect {
      color: var(--muted);
      font-size: 14px;
      line-height: 1.45;
    }

    .badge {
      display: inline-flex;
      align-items: center;
      padding: 5px 10px;
      border-radius: 999px;
      font-size: 12px;
      font-weight: 700;
      letter-spacing: 0.04em;
      text-transform: uppercase;
      white-space: nowrap;
    }

    .badge.running {
      background: rgba(105, 209, 143, 0.16);
      color: var(--good);
    }

    .badge.booting {
      background: rgba(240, 192, 107, 0.16);
      color: var(--warn);
    }

    .badge.offline {
      background: rgba(239, 125, 125, 0.16);
      color: var(--bad);
    }

    button {
      appearance: none;
      border: 1px solid var(--line-strong);
      background: #262d39;
      color: var(--text);
      border-radius: 10px;
      padding: 9px 13px;
      cursor: pointer;
      transition: background 0.14s ease, border-color 0.14s ease;
    }

    button:hover {
      background: #2d3645;
      border-color: rgba(255, 255, 255, 0.22);
    }

    button:disabled {
      opacity: 0.5;
      cursor: default;
    }

    button.primary {
      background: rgba(94, 148, 240, 0.18);
      border-color: rgba(94, 148, 240, 0.46);
    }

    button.warn {
      background: rgba(239, 125, 125, 0.12);
      border-color: rgba(239, 125, 125, 0.36);
    }

    .footer {
      display: flex;
      flex-wrap: wrap;
      gap: 10px 18px;
      color: var(--muted);
      font-size: 13px;
    }

    @media (max-width: 720px) {
      .shell {
        width: calc(100vw - 18px);
        margin: 10px auto 18px;
      }

      .header,
      .toolbar,
      .section,
      .footer {
        padding: 14px;
      }

      .card-top,
      .section-header,
      .header {
        flex-direction: column;
      }

      h1 {
        font-size: 24px;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <section class="panel header">
      <div>
        <div class="eyebrow">Model Switchboard Dashboard</div>
        <h1>Local model control plane</h1>
        <p>Compact browser view for the same actions exposed in the menu bar. No oversized hero, no selection deck, no extra drag.</p>
      </div>
      <div class="heartbeat" id="heartbeat">Refreshing controller state...</div>
    </section>

    <section class="panel toolbar">
      <button class="primary" id="refresh-button">Refresh</button>
      <button id="bench-all-button">Quick Bench All</button>
      <button class="warn" id="stop-all-button">Stop All</button>
    </section>

    <section class="summary" id="summary"></section>

    <section class="panel section" id="integrations-section" hidden>
      <div class="section-header">
        <h2>Optional integrations</h2>
        <div class="muted" id="integration-summary"></div>
      </div>
      <div class="integration-actions" id="integration-actions"></div>
    </section>

    <section class="panel section">
      <div class="section-header">
        <h2>Profiles</h2>
        <div class="muted" id="profile-summary"></div>
      </div>
      <div class="cards" id="cards"></div>
    </section>

    <section class="panel footer" id="footer"></section>
  </main>

  <script>
    const REFRESH_INTERVAL_MS = 5000;
    const heartbeatEl = document.getElementById('heartbeat');
    const summaryEl = document.getElementById('summary');
    const integrationsSectionEl = document.getElementById('integrations-section');
    const integrationSummaryEl = document.getElementById('integration-summary');
    const integrationActionsEl = document.getElementById('integration-actions');
    const profileSummaryEl = document.getElementById('profile-summary');
    const cardsEl = document.getElementById('cards');
    const footerEl = document.getElementById('footer');
    const refreshButton = document.getElementById('refresh-button');
    const benchAllButton = document.getElementById('bench-all-button');
    const stopAllButton = document.getElementById('stop-all-button');

    function escapeHTML(value) {
      return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    function statusTone(item) {
      if (item.ready) return 'running';
      if (item.running) return 'booting';
      return 'offline';
    }

    function statusLabel(item) {
      if (item.ready) return 'Running';
      if (item.running) return 'Starting';
      return 'Not Running';
    }

    function formatMemory(value) {
      if (value === null || value === undefined || value === '') return 'n/a';
      return `${Number(value).toFixed(1)} MB`;
    }

    function metric(label, value, subvalue = '') {
      return `
        <article class="panel stat">
          <div class="label">${escapeHTML(label)}</div>
          <div class="value">${escapeHTML(value)}</div>
          <div class="subvalue">${escapeHTML(subvalue)}</div>
        </article>
      `;
    }

    function suiteLabel(value) {
      if (!value) return 'Idle';
      return String(value)
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .replace(/\b\w/g, (char) => char.toUpperCase());
    }

    async function api(path, options = {}) {
      const response = await fetch(path, {
        headers: { 'Content-Type': 'application/json' },
        ...options,
      });
      if (!response.ok) {
        throw new Error((await response.text()) || `HTTP ${response.status}`);
      }
      return response.json();
    }

    async function postAction(path, payload = {}) {
      try {
        heartbeatEl.textContent = 'Executing action...';
        await api(path, { method: 'POST', body: JSON.stringify(payload) });
        await refreshStatus();
      } catch (error) {
        heartbeatEl.textContent = `Action failed: ${error.message}`;
        alert(error.message);
      }
    }

    function renderSummary(data) {
      const statuses = data.statuses || [];
      const running = statuses.filter(item => item.running).length;
      const ready = statuses.filter(item => item.ready).length;
      const benchmark = data.benchmark || {};
      const latest = benchmark.latest || {};

      summaryEl.innerHTML = [
        metric('Ready', `${ready}/${statuses.length}`, `${running} process${running === 1 ? '' : 'es'} live`),
        metric('Benchmark', benchmark.running ? 'Running' : suiteLabel(latest.suite), latest.generated_at ? new Date(latest.generated_at).toLocaleTimeString() : 'No recent benchmark'),
        metric('Profiles folder', statuses.length ? 'Live' : 'Waiting', data.profiles_dir || 'not reported'),
      ].join('');

      profileSummaryEl.textContent = `${statuses.length} profiles • auto-refresh ${REFRESH_INTERVAL_MS / 1000}s`;
    }

    function renderIntegrations(integrations) {
      const syncable = (integrations || []).filter(item => (item.capabilities || []).includes('sync'));
      integrationsSectionEl.hidden = syncable.length === 0;
      if (syncable.length === 0) {
        integrationActionsEl.innerHTML = '';
        integrationSummaryEl.textContent = '';
        return;
      }

      integrationActionsEl.innerHTML = syncable.map(item => `
        <button data-integration="${escapeHTML(item.id)}" data-integration-action="sync">${escapeHTML(item.sync_label || ('Sync ' + item.display_name))}</button>
      `).join('');
      integrationSummaryEl.textContent = syncable.map(item => item.description || item.display_name).join(' ');
    }

    function renderCards(data) {
      const statuses = [...(data.statuses || [])].sort((a, b) => {
        if (a.ready !== b.ready) return Number(b.ready) - Number(a.ready);
        if (a.running !== b.running) return Number(b.running) - Number(a.running);
        return a.display_name.localeCompare(b.display_name);
      });

      cardsEl.innerHTML = statuses.map(item => {
        const tone = statusTone(item);
        const openUrl = item.base_url ? `${item.base_url.replace(/\/$/, '')}/models` : '';
        const runtime = item.runtime || 'unknown';
        const pid = item.pid || 'none';
        return `
          <article class="card">
            <div class="card-top">
              <div>
                <h3 class="card-title">${escapeHTML(item.display_name)}</h3>
                <div class="card-meta">${escapeHTML(runtime)} • ${escapeHTML(statusLabel(item))}</div>
                <div class="card-endpoint"><code>${escapeHTML(item.base_url || 'no endpoint')}</code></div>
              </div>
              <span class="badge ${tone}">${escapeHTML(statusLabel(item))}</span>
            </div>
            <div class="card-inspect">Profile: <code>${escapeHTML(item.profile)}</code> • Request model: <code>${escapeHTML(item.request_model || 'n/a')}</code> • PID: <code>${escapeHTML(pid)}</code> • RSS: <code>${escapeHTML(formatMemory(item.rss_mb))}</code></div>
            <div class="card-actions">
              <button class="primary" data-action="switch" data-profile="${escapeHTML(item.profile)}">Activate</button>
              <button data-action="start" data-profile="${escapeHTML(item.profile)}">Start</button>
              <button class="warn" data-action="stop" data-profile="${escapeHTML(item.profile)}">Stop</button>
              <button data-action="restart" data-profile="${escapeHTML(item.profile)}">Restart</button>
              <button data-action="bench" data-profile="${escapeHTML(item.profile)}">Bench</button>
              <button ${openUrl ? `data-action="open" data-url="${escapeHTML(openUrl)}"` : 'disabled'}>Open /v1/models</button>
            </div>
          </article>
        `;
      }).join('');
    }

    function renderFooter(data) {
      const benchmark = data.benchmark || {};
      const latest = benchmark.latest || {};
      footerEl.innerHTML = `
        <div><strong>Controller:</strong> ${escapeHTML(window.location.origin)}</div>
        <div><strong>Profiles:</strong> ${escapeHTML(data.profiles_dir || 'not reported')}</div>
        <div><strong>Benchmark:</strong> ${escapeHTML(benchmark.running ? 'Running' : suiteLabel(latest.suite))}</div>
      `;
    }

    function render(data) {
      renderSummary(data);
      renderIntegrations(data.integrations || []);
      renderCards(data);
      renderFooter(data);
      heartbeatEl.textContent = 'Controller online';
    }

    async function refreshStatus() {
      try {
        refreshButton.disabled = true;
        heartbeatEl.textContent = 'Refreshing controller state...';
        const data = await api('/api/status');
        render(data);
      } catch (error) {
        heartbeatEl.textContent = `Refresh failed: ${error.message}`;
      } finally {
        refreshButton.disabled = false;
      }
    }

    integrationActionsEl.addEventListener('click', async (event) => {
      const button = event.target.closest('button[data-integration]');
      if (!button) return;
      await postAction('/api/integrations/run', {
        integration: button.dataset.integration,
        action: button.dataset.integrationAction || 'sync',
      });
    });

    cardsEl.addEventListener('click', async (event) => {
      const button = event.target.closest('button[data-action]');
      if (!button) return;
      const action = button.dataset.action;
      const profile = button.dataset.profile;
      const url = button.dataset.url;

      if (action === 'open' && url) {
        window.open(url, '_blank', 'noopener,noreferrer');
        return;
      }
      if (action === 'start') await postAction('/api/start', { profile });
      if (action === 'stop') await postAction('/api/stop', { profile });
      if (action === 'restart') await postAction('/api/restart', { profile });
      if (action === 'switch') await postAction('/api/switch', { profile });
      if (action === 'bench') await postAction('/api/benchmark/start', { suite: 'quick', profiles: [profile] });
    });

    refreshButton.addEventListener('click', () => refreshStatus());
    benchAllButton.addEventListener('click', () => postAction('/api/benchmark/start', { suite: 'quick' }));
    stopAllButton.addEventListener('click', () => postAction('/api/stop-all'));

    refreshStatus();
    setInterval(refreshStatus, REFRESH_INTERVAL_MS);
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
        "profiles_dir": str(PROFILE_DIR),
        "controller_root": str(BASE),
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
        "controller_root": str(BASE),
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
            self._send_json(
                {
                    "integrations": integration_status(),
                    "profiles_dir": str(PROFILE_DIR),
                    "controller_root": str(BASE),
                }
            )
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
                    "profiles_dir": str(PROFILE_DIR),
                    "controller_root": str(BASE),
                }
                write_status_cache(
                    {
                        "statuses": response_payload["statuses"],
                        "benchmark": response_payload["benchmark"],
                        "integrations": response_payload["integrations"],
                        "profiles_dir": response_payload["profiles_dir"],
                        "controller_root": response_payload["controller_root"],
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
            "profiles_dir": str(PROFILE_DIR),
            "controller_root": str(BASE),
        }
        write_status_cache(
            {
                "statuses": payload["statuses"],
                "benchmark": payload["benchmark"],
                "integrations": payload["integrations"],
                "profiles_dir": payload["profiles_dir"],
                "controller_root": payload["controller_root"],
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
    bench_cmd.add_argument("--suite", choices=["quick", "local", "context", "coding"], default="quick")
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

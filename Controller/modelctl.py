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
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Model Switchboard Dashboard</title>
  <style>
    :root {
      --bg-0: #0a0d12;
      --bg-1: #11161d;
      --bg-2: #1a2029;
      --panel: rgba(17, 22, 29, 0.82);
      --panel-strong: rgba(22, 28, 37, 0.92);
      --line: rgba(255, 244, 222, 0.08);
      --line-strong: rgba(255, 244, 222, 0.16);
      --text: #f3ecdf;
      --muted: #b7ae9c;
      --soft: #8a857a;
      --accent: #85d5c2;
      --accent-strong: #4eb79d;
      --accent-warm: #d9a973;
      --good: #7fdda6;
      --warn: #f2c06f;
      --bad: #ec8a87;
      --shadow: 0 22px 80px rgba(0, 0, 0, 0.34);
      --radius-xl: 28px;
      --radius-lg: 22px;
      --radius-md: 16px;
      --radius-sm: 12px;
    }

    * { box-sizing: border-box; }

    html {
      color-scheme: dark;
      scroll-behavior: smooth;
    }

    body {
      margin: 0;
      min-height: 100vh;
      color: var(--text);
      background:
        radial-gradient(circle at 0% 0%, rgba(133, 213, 194, 0.16), transparent 28%),
        radial-gradient(circle at 100% 0%, rgba(217, 169, 115, 0.12), transparent 24%),
        linear-gradient(180deg, #090c11 0%, #0d1219 44%, #121821 100%);
      font-family: "SF Pro Text", "Inter", "Segoe UI", sans-serif;
    }

    body::before {
      content: "";
      position: fixed;
      inset: 0;
      pointer-events: none;
      background-image: linear-gradient(rgba(255,255,255,0.018) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.018) 1px, transparent 1px);
      background-size: 32px 32px;
      mask-image: linear-gradient(180deg, rgba(255,255,255,0.18), transparent 80%);
      opacity: 0.34;
    }

    button,
    input,
    code {
      font: inherit;
    }

    code {
      font-family: "SF Mono", "JetBrains Mono", "Roboto Mono", monospace;
    }

    .shell {
      width: min(1380px, calc(100vw - 40px));
      margin: 28px auto 48px;
      position: relative;
      z-index: 1;
    }

    .masthead {
      margin-bottom: 20px;
      animation: rise 420ms ease both;
    }

    .eyebrow-row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      margin-bottom: 14px;
    }

    .eyebrow {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 8px 12px;
      border-radius: 999px;
      background: rgba(255,255,255,0.04);
      border: 1px solid var(--line);
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
      background: linear-gradient(135deg, var(--accent), var(--accent-warm));
      box-shadow: 0 0 0 6px rgba(133, 213, 194, 0.08);
    }

    .heartbeat {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      color: var(--soft);
      font-size: 13px;
    }

    .heartbeat::before {
      content: "";
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: var(--good);
      box-shadow: 0 0 0 0 rgba(127, 221, 166, 0.55);
      animation: pulse 2.2s ease infinite;
    }

    .masthead-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.5fr) minmax(300px, 0.8fr);
      gap: 18px;
      align-items: stretch;
    }

    .headline,
    .hero-panel,
    .command-deck,
    .metric,
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      box-shadow: var(--shadow);
      backdrop-filter: blur(18px);
    }

    .headline {
      border-radius: var(--radius-xl);
      padding: 28px 30px 30px;
      overflow: hidden;
      position: relative;
    }

    .headline::after {
      content: "";
      position: absolute;
      inset: auto -80px -80px auto;
      width: 240px;
      height: 240px;
      border-radius: 999px;
      background: radial-gradient(circle, rgba(133, 213, 194, 0.16), transparent 68%);
      filter: blur(8px);
    }

    .headline h1 {
      margin: 0 0 12px;
      max-width: 10ch;
      font-family: "Iowan Old Style", "Palatino Linotype", "Book Antiqua", Georgia, serif;
      font-size: clamp(42px, 7vw, 76px);
      line-height: 0.94;
      letter-spacing: -0.05em;
      font-weight: 700;
    }

    .headline p {
      margin: 0;
      max-width: 66ch;
      color: var(--muted);
      line-height: 1.62;
      font-size: 15px;
    }

    .hero-panel {
      border-radius: var(--radius-xl);
      padding: 24px;
      display: grid;
      gap: 18px;
      align-content: start;
      background:
        linear-gradient(180deg, rgba(22, 28, 37, 0.95), rgba(15, 20, 28, 0.9)),
        radial-gradient(circle at top right, rgba(217, 169, 115, 0.16), transparent 42%);
    }

    .hero-kicker {
      color: var(--soft);
      text-transform: uppercase;
      letter-spacing: 0.16em;
      font-size: 11px;
      font-weight: 700;
    }

    .hero-stat {
      font-size: clamp(28px, 3.2vw, 42px);
      font-weight: 700;
      letter-spacing: -0.04em;
    }

    .hero-copy {
      color: var(--muted);
      line-height: 1.55;
      font-size: 14px;
    }

    .hero-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }

    .hero-cell {
      padding: 12px 14px;
      border-radius: var(--radius-md);
      background: rgba(255,255,255,0.035);
      border: 1px solid rgba(255,255,255,0.05);
    }

    .hero-cell .label {
      font-size: 11px;
      color: var(--soft);
      text-transform: uppercase;
      letter-spacing: 0.12em;
      margin-bottom: 6px;
    }

    .hero-cell .value {
      font-size: 20px;
      font-weight: 700;
      letter-spacing: -0.03em;
    }

    .command-deck {
      border-radius: var(--radius-xl);
      padding: 18px;
      display: grid;
      grid-template-columns: repeat(3, minmax(0, 1fr));
      gap: 14px;
      margin-bottom: 18px;
      animation: rise 520ms ease both;
      animation-delay: 60ms;
    }

    .deck-group {
      min-height: 100%;
      padding: 14px;
      border-radius: var(--radius-lg);
      background: rgba(255,255,255,0.028);
      border: 1px solid rgba(255,255,255,0.05);
      display: grid;
      gap: 12px;
      align-content: start;
    }

    .deck-label,
    .section-label {
      color: var(--soft);
      text-transform: uppercase;
      letter-spacing: 0.14em;
      font-size: 11px;
      font-weight: 700;
    }

    .deck-buttons,
    .integration-actions,
    .actions {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
    }

    button {
      appearance: none;
      border: 1px solid rgba(255,255,255,0.08);
      background: linear-gradient(180deg, rgba(255,255,255,0.05), rgba(255,255,255,0.025));
      color: var(--text);
      padding: 10px 14px;
      border-radius: 999px;
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0.01em;
      cursor: pointer;
      transition: transform 140ms ease, border-color 140ms ease, background 180ms ease, color 180ms ease;
    }

    button:hover {
      transform: translateY(-1px);
      border-color: rgba(133, 213, 194, 0.4);
      background: linear-gradient(180deg, rgba(133, 213, 194, 0.08), rgba(255,255,255,0.04));
    }

    button:disabled {
      opacity: 0.46;
      cursor: not-allowed;
      transform: none;
    }

    button.primary {
      background: linear-gradient(135deg, rgba(133, 213, 194, 0.18), rgba(78, 183, 157, 0.24));
      border-color: rgba(133, 213, 194, 0.28);
    }

    button.warn {
      background: linear-gradient(135deg, rgba(242, 192, 111, 0.16), rgba(170, 111, 38, 0.18));
      border-color: rgba(242, 192, 111, 0.24);
    }

    button.bad {
      background: linear-gradient(135deg, rgba(236, 138, 135, 0.18), rgba(148, 55, 70, 0.18));
      border-color: rgba(236, 138, 135, 0.24);
    }

    .deck-note {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.45;
    }

    .summary-grid {
      display: grid;
      grid-template-columns: repeat(6, minmax(0, 1fr));
      gap: 12px;
      margin-bottom: 18px;
      animation: rise 620ms ease both;
      animation-delay: 110ms;
    }

    .metric {
      border-radius: var(--radius-lg);
      padding: 16px 16px 18px;
      position: relative;
      overflow: hidden;
    }

    .metric::before {
      content: "";
      position: absolute;
      inset: 0 0 auto 0;
      height: 2px;
      background: linear-gradient(90deg, rgba(133, 213, 194, 0.05), rgba(133, 213, 194, 0.75), rgba(217, 169, 115, 0.16));
    }

    .metric .label {
      color: var(--soft);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.14em;
      margin-bottom: 10px;
    }

    .metric .value {
      font-size: clamp(26px, 3vw, 34px);
      font-weight: 700;
      letter-spacing: -0.04em;
      line-height: 1;
      margin-bottom: 6px;
    }

    .metric .subvalue {
      color: var(--muted);
      font-size: 13px;
      line-height: 1.4;
    }

    .profiles-header {
      display: flex;
      justify-content: space-between;
      align-items: end;
      gap: 14px;
      margin: 28px 0 14px;
      animation: rise 680ms ease both;
      animation-delay: 150ms;
    }

    .profiles-header h2 {
      margin: 6px 0 0;
      font-size: clamp(24px, 3vw, 34px);
      letter-spacing: -0.04em;
    }

    .profiles-copy {
      color: var(--muted);
      font-size: 14px;
      line-height: 1.55;
      max-width: 64ch;
    }

    .profile-meta {
      text-align: right;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.45;
    }

    .profile-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(360px, 1fr));
      gap: 14px;
    }

    .card {
      border-radius: var(--radius-lg);
      padding: 16px;
      display: grid;
      gap: 14px;
      animation: rise 540ms ease both;
      transform-origin: center top;
      transition: transform 180ms ease, border-color 180ms ease, background 180ms ease;
    }

    .card:hover {
      transform: translateY(-2px);
      border-color: rgba(255,255,255,0.12);
      background: var(--panel-strong);
    }

    .card.ready {
      box-shadow: 0 22px 80px rgba(0,0,0,0.34), inset 0 1px 0 rgba(127, 221, 166, 0.06);
    }

    .card.booting {
      box-shadow: 0 22px 80px rgba(0,0,0,0.34), inset 0 1px 0 rgba(242, 192, 111, 0.07);
    }

    .card.offline {
      box-shadow: 0 22px 80px rgba(0,0,0,0.34), inset 0 1px 0 rgba(236, 138, 135, 0.05);
    }

    .card-top {
      display: grid;
      grid-template-columns: auto minmax(0, 1fr);
      gap: 14px;
      align-items: start;
    }

    .selector {
      display: inline-grid;
      place-items: center;
      width: 28px;
      height: 28px;
      margin-top: 2px;
      border-radius: 999px;
      background: rgba(255,255,255,0.04);
      border: 1px solid rgba(255,255,255,0.06);
    }

    .selector input {
      width: 15px;
      height: 15px;
      accent-color: var(--accent-strong);
      cursor: pointer;
    }

    .identity {
      min-width: 0;
      display: grid;
      gap: 8px;
    }

    .identity-row {
      display: flex;
      align-items: start;
      justify-content: space-between;
      gap: 12px;
    }

    .identity h3 {
      margin: 0;
      font-size: 20px;
      line-height: 1.18;
      letter-spacing: -0.03em;
    }

    .meta-row,
    .runtime-strip {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 8px;
      color: var(--muted);
      font-size: 12px;
    }

    .runtime-tag,
    .model-chip,
    .server-chip {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 10px;
      border-radius: 999px;
      border: 1px solid rgba(255,255,255,0.08);
      background: rgba(255,255,255,0.04);
      color: var(--text);
      font-size: 12px;
    }

    .model-chip {
      width: fit-content;
      max-width: 100%;
      color: var(--muted);
    }

    .state-pill {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 7px 10px;
      border-radius: 999px;
      font-size: 11px;
      font-weight: 800;
      letter-spacing: 0.12em;
      text-transform: uppercase;
      white-space: nowrap;
      border: 1px solid transparent;
    }

    .state-pill::before {
      content: "";
      width: 8px;
      height: 8px;
      border-radius: 999px;
      background: currentColor;
      box-shadow: 0 0 0 5px color-mix(in srgb, currentColor 14%, transparent);
    }

    .state-pill.ready {
      color: var(--good);
      background: rgba(127, 221, 166, 0.10);
      border-color: rgba(127, 221, 166, 0.22);
    }

    .state-pill.booting {
      color: var(--warn);
      background: rgba(242, 192, 111, 0.10);
      border-color: rgba(242, 192, 111, 0.2);
    }

    .state-pill.offline {
      color: var(--bad);
      background: rgba(236, 138, 135, 0.10);
      border-color: rgba(236, 138, 135, 0.2);
    }

    .detail-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px;
    }

    .detail {
      padding: 12px;
      border-radius: var(--radius-md);
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.05);
      min-width: 0;
    }

    .detail-label {
      display: block;
      color: var(--soft);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      margin-bottom: 7px;
    }

    .detail code,
    .trace-grid code {
      display: block;
      color: var(--text);
      font-size: 12px;
      line-height: 1.55;
      word-break: break-word;
    }

    .trace {
      border-top: 1px solid rgba(255,255,255,0.05);
      padding-top: 12px;
    }

    .trace summary {
      cursor: pointer;
      color: var(--muted);
      font-size: 13px;
      font-weight: 600;
      list-style: none;
    }

    .trace summary::-webkit-details-marker {
      display: none;
    }

    .trace-grid {
      margin-top: 12px;
      display: grid;
      gap: 10px;
    }

    .trace-grid > div {
      padding: 10px 12px;
      border-radius: var(--radius-md);
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.05);
    }

    .trace-grid span {
      display: block;
      color: var(--soft);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.12em;
      margin-bottom: 6px;
    }

    .footer {
      margin-top: 18px;
      padding: 12px 4px 0;
      display: flex;
      justify-content: space-between;
      gap: 12px;
      color: var(--soft);
      font-size: 12px;
    }

    .footer strong {
      color: var(--muted);
      font-weight: 700;
    }

    @keyframes rise {
      from {
        opacity: 0;
        transform: translateY(10px);
      }
      to {
        opacity: 1;
        transform: translateY(0);
      }
    }

    @keyframes pulse {
      0% { box-shadow: 0 0 0 0 rgba(127, 221, 166, 0.55); }
      70% { box-shadow: 0 0 0 8px rgba(127, 221, 166, 0); }
      100% { box-shadow: 0 0 0 0 rgba(127, 221, 166, 0); }
    }

    @media (max-width: 1080px) {
      .masthead-grid,
      .command-deck,
      .summary-grid {
        grid-template-columns: 1fr;
      }

      .summary-grid {
        grid-template-columns: repeat(2, minmax(0, 1fr));
      }
    }

    @media (max-width: 720px) {
      .shell {
        width: min(100vw - 20px, 100%);
        margin: 16px auto 32px;
      }

      .headline,
      .hero-panel,
      .command-deck,
      .card {
        border-radius: 20px;
      }

      .headline {
        padding: 22px 20px 24px;
      }

      .hero-panel,
      .command-deck,
      .card {
        padding: 18px;
      }

      .eyebrow-row,
      .profiles-header,
      .footer,
      .identity-row {
        flex-direction: column;
        align-items: start;
      }

      .summary-grid,
      .detail-grid,
      .hero-grid {
        grid-template-columns: 1fr;
      }

      .profile-grid {
        grid-template-columns: 1fr;
      }
    }
  </style>
</head>
<body>
  <div class="shell">
    <header class="masthead">
      <div class="eyebrow-row">
        <div class="eyebrow">Model Switchboard Dashboard</div>
        <div class="heartbeat" id="heartbeat">Controller online</div>
      </div>
      <div class="masthead-grid">
        <section class="headline">
          <h1>Operate local models like infrastructure, not guesswork.</h1>
          <p>Start, activate, benchmark, and stop heavyweight runtimes from one control surface. The dashboard is deliberately operational: clear state, clean selection flows, minimal noise, and enough detail to make fast decisions without dropping into terminal history.</p>
        </section>
        <aside class="hero-panel">
          <div>
            <div class="hero-kicker">Control plane</div>
            <div class="hero-stat" id="hero-stat">Idle</div>
          </div>
          <div class="hero-copy" id="hero-copy">Auto-refresh every 5 seconds. Integrations only appear when the backend exposes them.</div>
          <div class="hero-grid" id="hero-grid"></div>
        </aside>
      </div>
    </header>

    <section class="command-deck">
      <div class="deck-group">
        <div class="deck-label">Global Control</div>
        <div class="deck-buttons">
          <button class="primary" id="refresh-button">Refresh</button>
          <button id="bench-all-button">Quick Bench All</button>
          <button class="bad" id="stop-all-button">Stop All</button>
        </div>
        <div class="deck-note">Use bulk actions for clean operator loops. The dashboard does not try to be chat UI.</div>
      </div>

      <div class="deck-group">
        <div class="deck-label">Selection</div>
        <div class="deck-buttons">
          <button id="start-checked-button">Start Checked</button>
          <button class="primary" id="activate-checked-button">Activate Checked</button>
          <button class="warn" id="stop-checked-button">Stop Checked</button>
          <button id="clear-selection-button">Clear Selection</button>
        </div>
        <div class="deck-note" id="selection-summary">No profiles selected.</div>
      </div>

      <div class="deck-group">
        <div class="deck-label">Integrations</div>
        <div class="integration-actions" id="integration-actions"></div>
        <div class="deck-note" id="integration-summary">No optional integrations exposed by the controller.</div>
      </div>
    </section>

    <section class="summary-grid" id="summary"></section>

    <section class="profiles-header">
      <div>
        <div class="section-label">Managed Profiles</div>
        <h2>Runtime lanes</h2>
        <div class="profiles-copy">Healthy endpoints surface first. Booting processes remain visible so you can tell the difference between a dead model and one that is still coming up.</div>
      </div>
      <div class="profile-meta" id="profile-meta"></div>
    </section>

    <section class="profile-grid" id="cards"></section>
    <footer class="footer" id="footer"></footer>
  </div>

  <script>
    const REFRESH_INTERVAL_MS = 5000;
    const selectedProfiles = new Set();
    let latestPayload = { statuses: [], benchmark: null, integrations: [] };

    const cardsEl = document.getElementById('cards');
    const summaryEl = document.getElementById('summary');
    const integrationActionsEl = document.getElementById('integration-actions');
    const integrationSummaryEl = document.getElementById('integration-summary');
    const heartbeatEl = document.getElementById('heartbeat');
    const heroStatEl = document.getElementById('hero-stat');
    const heroCopyEl = document.getElementById('hero-copy');
    const heroGridEl = document.getElementById('hero-grid');
    const selectionSummaryEl = document.getElementById('selection-summary');
    const profileMetaEl = document.getElementById('profile-meta');
    const footerEl = document.getElementById('footer');

    const refreshButton = document.getElementById('refresh-button');
    const benchAllButton = document.getElementById('bench-all-button');
    const stopAllButton = document.getElementById('stop-all-button');
    const startCheckedButton = document.getElementById('start-checked-button');
    const activateCheckedButton = document.getElementById('activate-checked-button');
    const stopCheckedButton = document.getElementById('stop-checked-button');
    const clearSelectionButton = document.getElementById('clear-selection-button');

    function escapeHTML(value) {
      return String(value ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
    }

    function formatMemory(value) {
      if (value === null || value === undefined || value === '') return 'n/a';
      return `${Number(value).toFixed(1)} MB`;
    }

    function formatNumber(value, digits = 1) {
      if (value === null || value === undefined || Number.isNaN(Number(value))) return 'n/a';
      return Number(value).toFixed(digits);
    }

    function runtimeLabel(runtime) {
      if (!runtime) return 'unknown';
      if (runtime === 'llama.cpp') return 'llama.cpp';
      if (runtime === 'mlx') return 'MLX';
      return runtime;
    }

    function statusTone(item) {
      if (item.ready) return 'ready';
      if (item.running) return 'booting';
      return 'offline';
    }

    function statusLabel(item) {
      if (item.ready) return 'Healthy';
      if (item.running) return 'Booting';
      return 'Not Running';
    }

    function checkedProfiles() {
      return Array.from(selectedProfiles);
    }

    function syncSelection(statuses) {
      const available = new Set((statuses || []).map(item => item.profile));
      for (const profile of Array.from(selectedProfiles)) {
        if (!available.has(profile)) selectedProfiles.delete(profile);
      }
    }

    function updateSelectionUI() {
      const profiles = checkedProfiles();
      const count = profiles.length;
      startCheckedButton.disabled = count === 0;
      stopCheckedButton.disabled = count === 0;
      activateCheckedButton.disabled = count !== 1;
      clearSelectionButton.disabled = count === 0;

      if (count === 0) {
        selectionSummaryEl.textContent = 'No profiles selected.';
      } else if (count === 1) {
        selectionSummaryEl.textContent = `1 profile selected: ${profiles[0]}. Activate uses the selected profile and stops other running profiles first.`;
      } else {
        selectionSummaryEl.textContent = `${count} profiles selected. Start and Stop operate in bulk; Activate remains single-target by design.`;
      }
    }

    function heroCells({ total, running, ready, benchmark, integrations }) {
      const benchmarkText = benchmark?.running
        ? 'Running now'
        : (benchmark?.latest?.suite ? `${benchmark.latest.suite} suite ready` : 'Idle');
      return [
        { label: 'Profiles', value: total },
        { label: 'Healthy', value: ready },
        { label: 'Running', value: running },
        { label: 'Benchmark', value: benchmarkText },
      ].map(item => `
        <div class="hero-cell">
          <div class="label">${escapeHTML(item.label)}</div>
          <div class="value">${escapeHTML(item.value)}</div>
        </div>
      `).join('');
    }

    function metric(label, value, subvalue = '') {
      return `
        <div class="metric">
          <div class="label">${escapeHTML(label)}</div>
          <div class="value">${escapeHTML(value)}</div>
          <div class="subvalue">${escapeHTML(subvalue)}</div>
        </div>
      `;
    }

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

    async function refreshStatus() {
      try {
        refreshButton.disabled = true;
        heartbeatEl.textContent = 'Refreshing controller state...';
        const data = await api('/api/status');
        latestPayload = data;
        render(data);
      } catch (error) {
        heartbeatEl.textContent = `Refresh failed: ${error.message}`;
      } finally {
        refreshButton.disabled = false;
      }
    }

    async function runQuickBench(profiles = null) {
      await postAction('/api/benchmark/start', { profiles, suite: 'quick' });
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
      await postAction('/api/switch', { profile: profiles[0] });
    }

    async function stopChecked() {
      const profiles = checkedProfiles();
      if (profiles.length === 0) return;
      await postAction('/api/stop-many', { profiles });
    }

    function renderIntegrations(integrations) {
      if (!integrations.length) {
        integrationActionsEl.innerHTML = '';
        integrationSummaryEl.textContent = 'No optional integrations exposed by the controller.';
        return;
      }

      integrationActionsEl.innerHTML = integrations
        .filter(item => (item.capabilities || []).includes('sync'))
        .map(item => `
          <button data-integration="${escapeHTML(item.id)}" data-integration-action="sync">${escapeHTML(item.sync_label || ('Sync ' + item.display_name))}</button>
        `)
        .join('');

      integrationSummaryEl.textContent = integrations.map(item => item.description || item.display_name).join(' ');
    }

    function renderSummary(data) {
      const statuses = [...(data.statuses || [])].sort((a, b) => {
        if (a.ready !== b.ready) return Number(b.ready) - Number(a.ready);
        if (a.running !== b.running) return Number(b.running) - Number(a.running);
        return a.display_name.localeCompare(b.display_name);
      });
      const benchmark = data.benchmark || {};
      const integrations = data.integrations || [];
      const total = statuses.length;
      const running = statuses.filter(item => item.running).length;
      const ready = statuses.filter(item => item.ready).length;
      const busiest = statuses.reduce((best, item) => (item.rss_mb || 0) > (best.rss_mb || 0) ? item : best, {});
      const fastest = (benchmark.latest?.rows || []).reduce((best, item) => {
        return (item.decode_tokens_per_sec || 0) > (best.decode_tokens_per_sec || 0) ? item : best;
      }, {});
      const runtimeCounts = Object.entries(statuses.reduce((acc, item) => {
        const key = runtimeLabel(item.runtime);
        acc[key] = (acc[key] || 0) + 1;
        return acc;
      }, {})).map(([key, value]) => `${key}: ${value}`).join(' • ') || 'No runtimes loaded';

      summaryEl.innerHTML = [
        metric('Profiles', total, `${running} running • ${ready} healthy`),
        metric('Benchmark', benchmark.running ? 'Running' : (benchmark.latest?.suite || 'Idle'), benchmark.latest?.generated_at ? `Latest at ${new Date(benchmark.latest.generated_at).toLocaleTimeString()}` : 'No benchmark in flight'),
        metric('Fastest Decode', fastest.decode_tokens_per_sec ? `${formatNumber(fastest.decode_tokens_per_sec, 2)} tok/s` : 'n/a', fastest.profile || 'No benchmark rows yet'),
        metric('Highest RSS', busiest.rss_mb ? formatMemory(busiest.rss_mb) : 'n/a', busiest.display_name || 'No live process'),
        metric('Runtimes', Object.keys(statuses.reduce((acc, item) => { acc[item.runtime] = true; return acc; }, {})).length || 0, runtimeCounts),
        metric('Integrations', integrations.length || 0, integrations.length ? integrations.map(item => item.display_name).join(' • ') : 'No optional hooks'),
      ].join('');

      heroStatEl.textContent = benchmark.running ? 'Benchmark in flight' : (ready > 0 ? `${ready} healthy endpoint${ready === 1 ? '' : 's'}` : 'No healthy endpoints');
      heroCopyEl.textContent = benchmark.running
        ? 'Quick benchmark is currently active. Leave the board open if you want live status and endpoint health to converge while the run completes.'
        : 'Auto-refresh every 5 seconds. Integrations only appear when the backend exposes them, and bulk actions stay disabled until selection exists.';
      heroGridEl.innerHTML = heroCells({ total, running, ready, benchmark, integrations });
      profileMetaEl.textContent = `${total} profiles • ${running} running • ${ready} healthy • auto-refresh ${REFRESH_INTERVAL_MS / 1000}s`;
    }

    function renderCards(data) {
      const statuses = [...(data.statuses || [])].sort((a, b) => {
        if (a.ready !== b.ready) return Number(b.ready) - Number(a.ready);
        if (a.running !== b.running) return Number(b.running) - Number(a.running);
        return a.display_name.localeCompare(b.display_name);
      });
      syncSelection(statuses);

      cardsEl.innerHTML = statuses.map((item, index) => {
        const tone = statusTone(item);
        const openUrl = item.base_url ? `${item.base_url.replace(/\/$/, '')}/models` : '';
        const serverIds = (item.server_ids || []).length ? item.server_ids.map(serverId => `<span class="server-chip">${escapeHTML(serverId)}</span>`).join(' ') : '<span class="server-chip">n/a</span>';
        return `
          <article class="card ${tone}" style="animation-delay:${index * 45}ms">
            <div class="card-top">
              <label class="selector">
                <input type="checkbox" data-profile="${escapeHTML(item.profile)}" ${selectedProfiles.has(item.profile) ? 'checked' : ''}>
              </label>
              <div class="identity">
                <div class="identity-row">
                  <div>
                    <h3>${escapeHTML(item.display_name)}</h3>
                    <div class="meta-row">
                      <span class="runtime-tag">${escapeHTML(runtimeLabel(item.runtime))}</span>
                      <span>${escapeHTML(item.profile)}</span>
                    </div>
                  </div>
                  <span class="state-pill ${tone}">${escapeHTML(statusLabel(item))}</span>
                </div>
                <div class="model-chip">${escapeHTML(item.request_model)}</div>
              </div>
            </div>

            <div class="detail-grid">
              <div class="detail">
                <span class="detail-label">Endpoint</span>
                <code>${escapeHTML(item.base_url || 'n/a')}</code>
              </div>
              <div class="detail">
                <span class="detail-label">Port</span>
                <code>${escapeHTML(`${item.host}:${item.port}`)}</code>
              </div>
              <div class="detail">
                <span class="detail-label">Process</span>
                <code>PID ${escapeHTML(item.pid || 'none')} • RSS ${escapeHTML(formatMemory(item.rss_mb))}</code>
              </div>
              <div class="detail">
                <span class="detail-label">Server IDs</span>
                <div class="runtime-strip">${serverIds}</div>
              </div>
            </div>

            <div class="actions">
              <button class="primary" data-action="switch" data-profile="${escapeHTML(item.profile)}">Activate</button>
              <button data-action="start" data-profile="${escapeHTML(item.profile)}">Start</button>
              <button class="warn" data-action="stop" data-profile="${escapeHTML(item.profile)}">Stop</button>
              <button data-action="restart" data-profile="${escapeHTML(item.profile)}">Restart</button>
              <button data-action="bench" data-profile="${escapeHTML(item.profile)}">Bench</button>
              <button ${openUrl ? `data-action="open" data-url="${escapeHTML(openUrl)}"` : 'disabled'}>Open /v1/models</button>
            </div>

            <details class="trace">
              <summary>Inspect runtime</summary>
              <div class="trace-grid">
                <div>
                  <span>Log path</span>
                  <code>${escapeHTML(item.log_path || 'n/a')}</code>
                </div>
                <div>
                  <span>Resolved command</span>
                  <code>${escapeHTML(item.command || 'not running')}</code>
                </div>
              </div>
            </details>
          </article>
        `;
      }).join('');

      updateSelectionUI();
    }

    function renderFooter(data) {
      const integrations = data.integrations || [];
      const benchmark = data.benchmark || {};
      const profilesDir = data.profiles_dir || 'not reported';
      footerEl.innerHTML = `
        <div><strong>Controller:</strong> ${escapeHTML(window.location.origin)}</div>
        <div><strong>Profiles:</strong> ${escapeHTML(profilesDir)}</div>
        <div><strong>Benchmark:</strong> ${escapeHTML(benchmark.running ? 'running' : (benchmark.latest?.suite || 'idle'))}</div>
        <div><strong>Integrations:</strong> ${escapeHTML(integrations.length ? integrations.map(item => item.display_name).join(', ') : 'none')}</div>
      `;
    }

    function render(data) {
      renderIntegrations(data.integrations || []);
      renderSummary(data);
      renderCards(data);
      renderFooter(data);
      heartbeatEl.textContent = 'Controller online';
    }

    integrationActionsEl.addEventListener('click', async (event) => {
      const button = event.target.closest('button[data-integration]');
      if (!button) return;
      await postAction('/api/integrations/run', {
        integration: button.dataset.integration,
        action: button.dataset.integrationAction || 'sync',
      });
    });

    cardsEl.addEventListener('change', (event) => {
      const checkbox = event.target.closest('input[data-profile]');
      if (!checkbox) return;
      if (checkbox.checked) {
        selectedProfiles.add(checkbox.dataset.profile);
      } else {
        selectedProfiles.delete(checkbox.dataset.profile);
      }
      updateSelectionUI();
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
      if (action === 'bench') await runQuickBench([profile]);
    });

    refreshButton.addEventListener('click', () => refreshStatus());
    benchAllButton.addEventListener('click', () => runQuickBench(null));
    stopAllButton.addEventListener('click', () => postAction('/api/stop-all'));
    startCheckedButton.addEventListener('click', () => startChecked());
    activateCheckedButton.addEventListener('click', () => switchChecked());
    stopCheckedButton.addEventListener('click', () => stopChecked());
    clearSelectionButton.addEventListener('click', () => {
      selectedProfiles.clear();
      cardsEl.querySelectorAll('input[data-profile]').forEach((checkbox) => {
        checkbox.checked = false;
      });
      updateSelectionUI();
    });

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

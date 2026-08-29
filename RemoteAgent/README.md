# Model Switchboard Remote Agent

This stdlib-only Python 3.10+ agent (`model_switchboard_agent.py`,
`agent_core.py`, and `discovery.py`) lets the Mac app control Linux/Unix model hosts. It uses the
macOS controller's HTTP contract and `.env` / `.json` profiles.

## Install

In **Settings → Remote Gateways → Add Remote Gateway**, enter `user` + `host`
and click **Install Agent on Host**. The app pushes bundled modules over SSH
and installs the service; the remote downloads nothing. Manual, no-checkout:

```bash
curl -fsSL https://raw.githubusercontent.com/AdityaVG13/Model-Switchboard/main/RemoteAgent/install-remote-agent.sh | bash
```

Repo checkout:

```bash
git clone https://github.com/AdityaVG13/Model-Switchboard.git
cd Model-Switchboard/RemoteAgent
./install-remote-agent.sh
```

Re-run the same method to update. Installation uses
`~/.local/share/model-switchboard-agent/`, creates `~/model-profiles/` with
sample templates, and enables a systemd user service when available. Run
`loginctl enable-linger $USER` to keep it running after logout.

Add one profile per model server to `~/model-profiles/` (or any folder you
point the agent at), e.g.:

```bash
# llama31-8b.env
DISPLAY_NAME="Llama 3.1 8B (vLLM)"
RUNTIME=vllm
REQUEST_MODEL=meta-llama/Llama-3.1-8B-Instruct
PORT=8001
EXTRA_ARGS="--max-model-len 8192"
```

`model-switchboard-agent link` scans `$HOME` for Switchboard-shaped `.env` /
`.json`, confirms or accepts another folder, persists it, and prints pairing.
Non-interactive: `--profiles-dir /path --yes`. The installer also accepts
`--profiles-dir`; use `MODEL_SWITCHBOARD_PROFILES_DIR` in the environment.

Built-in launch templates: `vllm`, `llama.cpp` (`llama-server`), `sglang`,
`tgi`. Anything else works via `START_COMMAND=...` / `STOP_COMMAND=...`.
Daemon-style runtimes (`ollama`, LiteLLM, …) are monitored health-only.

## Connect from the Mac

The installer prints a pairing code; regenerate it with `link`:

```
modelswitchboard-gateway://user@host?name=spark&agent_port=8877
```

Paste it into **Settings → Remote Gateways → Add Remote Gateway**. It prefills
editable fields; the gateway gets a named panel section.

- **SSH tunnel (recommended).** The agent binds `127.0.0.1` only; the app
  opens `ssh -N -L` to it using your existing SSH keys/agent (`BatchMode`;
  passwords are never handled; connect once from Terminal first so the host
  key is trusted). Running models' ports are forwarded automatically, so
  copied endpoint URLs work directly on the Mac. The agent does not open
  ports on the network.
- **Tailscale.** If both machines are on your tailnet, skip tunnels entirely:

  ```bash
  ./install-remote-agent.sh --tailscale
  # or: model-switchboard-agent serve --tailscale --auth-token-file ~/.config/model-switchboard-agent.token
  ```

  The agent binds only the host's Tailscale address (WireGuard-encrypted,
  tailnet-only, never the open LAN), **requires a bearer token by default**,
  and prints a **direct** pairing code using its MagicDNS name
  (`modelswitchboard-gateway://spark.tail1234.ts.net?…&mode=direct`).
  Paste the link **and** the generated token into the Mac gateway form.
  You are then connected as a Direct URL gateway with no SSH involved.

  Personal tailnet opt-out (anyone on the tailnet can start/stop models):

  ```bash
  ./install-remote-agent.sh --tailscale --allow-unauthenticated
  ```

  Model server ports follow the same rule: set `HOST=0.0.0.0` (or the
  Tailscale IP) in profiles you want to reach from the Mac, since there is no
  tunnel to forward loopback ports.

- **Direct URL (plain LAN).** For a trusted LAN without Tailscale, run the
  agent bound to the network. This **requires** a bearer token of at least
  16 bytes, exactly like the macOS controller:

  ```bash
  openssl rand -hex 24 > ~/.config/model-switchboard-agent.token
  chmod 600 ~/.config/model-switchboard-agent.token
  model-switchboard-agent serve --unsafe-bind 0.0.0.0 \
      --auth-token-file ~/.config/model-switchboard-agent.token
  ```

  Paste the same token into the gateway's token field on the Mac (it is
  stored in your keychain).

## CLI

The agent doubles as a CLI on the remote host:

```bash
model-switchboard-agent list
model-switchboard-agent status --json
model-switchboard-agent switch llama31-8b
model-switchboard-agent stop-all
model-switchboard-agent stop-all --force   # SIGKILL if a graceful stop stalls
model-switchboard-agent kill-all          # nuclear: force-stop every profile
```

### Models vs the agent

The systemd agent is always on; launched models are child processes. Closing
a terminal or logging out does **not** stop them. After `stop`, `stop-all`, or
`kill-all`, `nvidia-smi` should show no model process. Large vLLM unloads can
take ~90s; use `--force` / `kill-all` if one hangs.

## Contract

Same routes, auth rules, status codes, and JSON field names as the macOS
controller (see `SETUP.md` → "Controller API contract"): `/api/status`,
`/api/doctor`, `/api/start`, `/api/stop`, `/api/restart`, `/api/switch`,
`/api/stop-all`. Benchmarks and integrations are macOS-controller features;
the agent answers those endpoints with structured "unsupported" responses.

```bash
# Native Swift conformance; the real agent is the system under test.
swift test --filter RemoteAgentConformanceTests
```

## Discovery (host-generic)

The agent does **not** invent models or assume a host layout (no hard-coded
`/data/launch`, no fixed product ports). On each `/api/status` it merges:

1. **Profiles:** `.env` / `.json` in the profiles folder (start/stop/manage).
2. **Listening ports:** Ports.app-style inventory (`ss`/`lsof`) plus short probes
   of `/health` and `/v1/models` when the process cmdline looks like a model
   server (or the port is already claimed).
3. **Claimed port folders:** any directory named like a TCP port (`8080`,
   `9123`, …) that contains `flags.env` / `launch.sh` / `ctrl.sh` / … under
   `$HOME`, paths hinted by live process argv, or extra roots from:

   - env: `MODEL_SWITCHBOARD_SCAN_ROOTS=/path/a:/path/b`
   - config: `~/.local/share/model-switchboard-agent/config.json` → `"scan_roots": ["…"]`

Identity comes from `/v1/models`, process argv (`-m`, `vllm serve …`), or
flags keys that already exist. It never fabricates an HF repo name.

```bash
model-switchboard-agent ports          # listening + claims
model-switchboard-agent scan-profiles  # profile folders + port claims
curl -sS -H "Authorization: Bearer $TOKEN" http://HOST:8877/api/ports | jq .
```

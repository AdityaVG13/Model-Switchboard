# Model Switchboard Remote Agent

Launch and monitor model servers on any Linux/Unix host — a DGX box, a lab
workstation, a home server — from the Model Switchboard menu bar app on your
Mac.

The agent is a **single Python file with zero dependencies** (Python 3.10+,
stdlib only). It speaks the exact same HTTP contract as the macOS controller,
reads the same `model-profiles/*.env|*.json` profile format, and is what the
app's **remote gateways** feature talks to.

## Install

**Nothing to download on the remote host.** In Model Switchboard on your Mac:
**Settings → Remote Gateways → Add Remote Gateway**, enter `user` + `host`,
and click **Install Agent on Host** — the app pushes the bundled single-file
agent over your own SSH connection and sets up its service.

Prefer to run something yourself in your existing SSH session? One line, no
checkout:

```bash
curl -fsSL https://raw.githubusercontent.com/AdityaVG13/Model-Switchboard/main/RemoteAgent/install-remote-agent.sh | bash
```

Or from a repo checkout:

```bash
git clone https://github.com/AdityaVG13/Model-Switchboard.git
cd Model-Switchboard/RemoteAgent
./install-remote-agent.sh
```

The installer puts the agent under `~/.local/share/model-switchboard-agent/`,
creates a visible **`~/model-profiles/`** folder for launch `.env` / `.json`
files (with sample templates), and (when systemd is present) enables a user
service that keeps it running. Run `loginctl enable-linger $USER` so the
service survives logout.

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

Already have launch files somewhere else (AI setups often drop `model.env`
next to the model)? Run `model-switchboard-agent link` — it scans your home
directory for Switchboard-shaped `.env` / `.json` files, asks you to confirm
a folder (or paste another path), saves it, then prints the pairing code.
Non-interactive: `--profiles-dir /path --yes`.

Built-in launch templates: `vllm`, `llama.cpp` (`llama-server`), `sglang`,
`tgi`. Anything else works via `START_COMMAND=...` / `STOP_COMMAND=...`.
Daemon-style runtimes (`ollama`, LiteLLM, …) are monitored health-only.

## Connect from the Mac

The installer ends by printing a **pairing code** (get it again anytime with
`model-switchboard-agent link`):

```
modelswitchboard-gateway://user@host?name=spark&agent_port=8877
```

In Model Switchboard: **Settings → Remote Gateways → Add Remote Gateway**,
paste the code, and the form prefills — every field stays editable. The
gateway's models then appear in the main panel under its own named section.

- **SSH tunnel (recommended).** The agent binds `127.0.0.1` only; the app
  opens `ssh -N -L` to it using your existing SSH keys/agent (`BatchMode` —
  passwords are never handled; connect once from Terminal first so the host
  key is trusted). Running models' ports are forwarded automatically, so
  copied endpoint URLs work directly on the Mac. Zero ports exposed.
- **Tailscale.** If both machines are on your tailnet, skip tunnels entirely:

  ```bash
  ./install-remote-agent.sh --tailscale
  # or: model-switchboard-agent serve --tailscale --auth-token-file ~/.config/model-switchboard-agent.token
  ```

  The agent binds only the host's Tailscale address (WireGuard-encrypted,
  tailnet-only — never the open LAN), **requires a bearer token by default**,
  and prints a **direct** pairing code using its MagicDNS name
  (`modelswitchboard-gateway://spark.tail1234.ts.net?…&mode=direct`).
  Paste the link **and** the generated token into the Mac gateway form — you
  are connected as a Direct URL gateway with no SSH involved.

  Personal tailnet opt-out (anyone on the tailnet can start/stop models):

  ```bash
  ./install-remote-agent.sh --tailscale --allow-unauthenticated
  ```

  Model server ports follow the same rule: set `HOST=0.0.0.0` (or the
  Tailscale IP) in profiles you want to reach from the Mac, since there is no
  tunnel to forward loopback ports.

- **Direct URL (plain LAN).** For a trusted LAN without Tailscale, run the
  agent bound to the network — this **requires** a bearer token of at least
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

The **agent** is an always-on controller (systemd user unit). A **model** is a
child process the agent launched (vLLM, llama.cpp, …). Closing a terminal or
logging out does **not** stop models — only `stop` / `stop-all` / `kill-all`
does. After a successful stop, `nvidia-smi` should show no model process (large
vLLM unloads can take up to ~90s; use `--force` / `kill-all` if it hangs).

One-liner to free the GPU from models managed by switchboard:

```bash
model-switchboard-agent kill-all
```

## Contract

Same routes, auth rules, status codes, and JSON field names as the macOS
controller (see `SETUP.md` → "Controller API contract"): `/api/status`,
`/api/doctor`, `/api/start`, `/api/stop`, `/api/restart`, `/api/switch`,
`/api/stop-all`. Benchmarks and integrations are macOS-controller features;
the agent answers those endpoints with structured "unsupported" responses.

Tests: `python3 -m unittest discover -s RemoteAgent/tests -p 'test_*.py'` —
includes conformance cases shared with the reference controller.

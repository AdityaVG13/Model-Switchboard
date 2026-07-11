from __future__ import annotations

from msctl.doctor import doctor_capabilities, doctor_health_payload, tool_version
from msctl.paths import (
    CLI_COMMAND_ALIASES,
    CLI_CONTRACT_VERSION,
    CLI_EXIT_CODES,
    CLI_GLOBAL_ALIASES,
    CLI_SCHEMA_VERSION,
)
from msctl.profiles import load_profiles

def modelctl_command_contracts() -> list[dict[str, object]]:
    return [
        {
            "name": "capabilities",
            "aliases": ["--capabilities"],
            "mutates": False,
            "json": True,
            "purpose": "Return the machine-readable CLI contract.",
            "examples": ["./Controller/modelctl.py capabilities --json"],
        },
        {
            "name": "robot-docs",
            "aliases": ["docs", "--robot-docs", "--robot-help"],
            "mutates": False,
            "json": False,
            "purpose": "Print paste-ready agent guidance.",
            "examples": ["./Controller/modelctl.py robot-docs guide"],
        },
        {
            "name": "triage",
            "aliases": ["--robot-triage"],
            "mutates": False,
            "json": True,
            "purpose": "Return health, recommended commands, and next actions in one call.",
            "examples": ["./Controller/modelctl.py triage --json", "./Controller/modelctl.py --robot-triage"],
        },
        {
            "name": "doctor",
            "aliases": ["diagnose", "validate"],
            "mutates": "only with --fix",
            "json": True,
            "purpose": "Diagnose profiles, controller reachability, LaunchAgent state, and safe repairs.",
            "examples": [
                "./Controller/modelctl.py doctor --json",
                "./Controller/modelctl.py diagnose --json",
                "./Controller/modelctl.py doctor --dry-run --fix --json",
            ],
        },
        {
            "name": "health",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "Alias for doctor health.",
            "examples": ["./Controller/modelctl.py health --json"],
        },
        {
            "name": "status",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "Show profile runtime status.",
            "examples": ["./Controller/modelctl.py status --json"],
        },
        {
            "name": "list",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "List configured profiles.",
            "examples": ["./Controller/modelctl.py list --json"],
        },
        {
            "name": "integrations",
            "aliases": [],
            "mutates": False,
            "json": True,
            "purpose": "List optional backend integrations.",
            "examples": ["./Controller/modelctl.py integrations"],
        },
        {
            "name": "start",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Start one or more profiles.",
            "examples": [
                "./Controller/modelctl.py start qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py start qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py doctor --json",
        },
        {
            "name": "stop",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Stop one or more profiles.",
            "examples": [
                "./Controller/modelctl.py stop qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py stop qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "restart",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Restart one or more profiles.",
            "examples": [
                "./Controller/modelctl.py restart qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py restart qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "switch",
            "aliases": ["activate"],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Stop other running profiles and start the selected profile.",
            "examples": [
                "./Controller/modelctl.py switch qwen35-a3b --dry-run --json",
                "./Controller/modelctl.py switch qwen35-a3b --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "benchmark",
            "aliases": [],
            "mutates": "starts benchmark workers unless --background is omitted and the harness exits inline",
            "json": "with --background",
            "purpose": "Run the benchmark harness.",
            "safe_alternative": "./Controller/modelctl.py triage --json",
        },
        {
            "name": "stop-all",
            "aliases": [],
            "mutates": True,
            "json": True,
            "dry_run": True,
            "purpose": "Stop every managed model process.",
            "examples": [
                "./Controller/modelctl.py stop-all --dry-run --json",
                "./Controller/modelctl.py stop-all --json",
            ],
            "safe_alternative": "./Controller/modelctl.py status --json",
        },
        {
            "name": "serve-web",
            "aliases": [],
            "mutates": "starts a local HTTP server",
            "json": False,
            "purpose": "Serve the local controller JSON API used by the menu bar app (no browser UI).",
            "safe_alternative": "./Controller/modelctl.py doctor --json",
        },
    ]


def modelctl_capabilities() -> dict[str, object]:
    return {
        "schema_version": CLI_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "contract_version": CLI_CONTRACT_VERSION,
        "default_probe": "./Controller/modelctl.py triage --json",
        "offline_first": True,
        "commands": modelctl_command_contracts(),
        "aliases": {**CLI_COMMAND_ALIASES, **CLI_GLOBAL_ALIASES},
        "exit_codes": CLI_EXIT_CODES,
        "env_vars": [
            "MODEL_SWITCHBOARD_URL",
            "MODEL_SWITCHBOARD_APP_PATH",
            "MODEL_SWITCHBOARD_VARIANT",
            "SOURCE_DATE_EPOCH",
            "NO_COLOR",
            "CI",
            "TERM",
        ],
        "stdout_stderr_contract": {
            "stdout": "requested human or JSON data only",
            "stderr": "usage errors, diagnostics, and actionable hints",
        },
        "doctor": doctor_capabilities(),
    }


def modelctl_triage_payload() -> dict[str, object]:
    profiles = load_profiles()
    health = doctor_health_payload()
    recommendations = [
        {
            "id": "inspect-contract",
            "command": "./Controller/modelctl.py capabilities --json",
            "reason": "Discover commands, aliases, mutability, JSON support, and exit codes.",
        },
        {
            "id": "read-agent-guide",
            "command": "./Controller/modelctl.py robot-docs guide",
            "reason": "Get paste-ready usage guidance without opening external docs.",
        },
    ]
    if not health["healthy"]:
        recommendations.insert(
            0,
            {
                "id": "diagnose-findings",
                "command": "./Controller/modelctl.py doctor --json",
                "reason": "Structured findings are present; inspect exact evidence and remediation.",
            },
        )
    if health["auto_fixable_count"]:
        recommendations.insert(
            1,
            {
                "id": "preview-safe-fix",
                "command": "./Controller/modelctl.py doctor --dry-run --fix --json",
                "reason": "Preview reversible fixes before changing local state.",
            },
        )
    return {
        "schema_version": CLI_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "health": health,
        "profiles": {
            "count": len(profiles),
            "names": sorted(profiles),
        },
        "commands": [
            "./Controller/modelctl.py status --json",
            "./Controller/modelctl.py list --json",
            "./Controller/modelctl.py doctor --json",
            "./Controller/modelctl.py capabilities --json",
            "./Controller/modelctl.py robot-docs guide",
        ],
        "recommendations": recommendations,
        "exit_codes": CLI_EXIT_CODES,
    }


def print_modelctl_triage(payload: dict[str, object]) -> None:
    health = payload["health"]
    profiles = payload["profiles"]
    print(f"healthy={str(health['healthy']).lower()} findings={health['finding_count']}")
    print(f"profiles={profiles['count']}")
    for recommendation in payload["recommendations"]:
        print(f"next | {recommendation['id']} | {recommendation['command']}")


def modelctl_robot_docs(topic: str = "guide") -> str:
    if topic != "guide":
        raise ValueError(f"unknown robot-docs topic {topic!r}; use `./Controller/modelctl.py robot-docs guide`")
    return "\n".join(
        [
            "Model Switchboard modelctl robot docs",
            "",
            "First commands to try:",
            "- `./Controller/modelctl.py triage --json` returns health, profile names, recommended commands, and exit codes.",
            "- `./Controller/modelctl.py capabilities --json` returns the machine-readable CLI contract.",
            "- `./Controller/modelctl.py doctor --json` returns structured findings with evidence and remediation.",
            "- `./Controller/modelctl.py status --json` returns live profile status.",
            "- `./Controller/modelctl.py list --json` returns configured profiles.",
            "",
            "Intent aliases:",
            "- `./Controller/modelctl.py diagnose --json` is accepted as `doctor --json`.",
            "- `./Controller/modelctl.py health --json` is accepted as `doctor health --json`.",
            "- `./Controller/modelctl.py --robot-triage` is accepted as `triage --json`.",
            "- `./Controller/modelctl.py --capabilities` is accepted as `capabilities --json`.",
            "",
            "Mutation safety:",
            "- `start`, `stop`, `restart`, `switch`, `benchmark --background`, `stop-all`, and `serve-web` mutate local runtime state.",
            "- `serve-web` exposes only `/api/*` JSON routes for the menu bar app; it does not serve a browser dashboard.",
            "- Use `status --json`, `doctor --json`, or `triage --json` before mutating when you need a safe probe.",
            "- Use `start|stop|restart|switch <profile> --dry-run --json` or `stop-all --dry-run --json` to preview profile mutations.",
            "- Use `--json` on applied profile mutations to receive a stable envelope with plan, captured output, errors, and post-action status.",
            "- Use `doctor --dry-run --fix --json` before `doctor --fix --json`.",
            "",
            "Output contract:",
            "- JSON commands print data to stdout.",
            "- Usage errors and hints print to stderr and exit 64.",
            "- Diagnostic findings exit non-zero so agents can branch deterministically.",
        ]
    )

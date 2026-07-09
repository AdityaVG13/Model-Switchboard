from __future__ import annotations

import pathlib
import re
import threading

# Controller/ is the package parent (this file lives in Controller/msctl/).
BASE = pathlib.Path(__file__).resolve().parent.parent
PROJECT_ROOT = BASE.parent
PROFILE_DIR = BASE / "model-profiles"
RUN_DIR = BASE / "run"
ACTIVE_PROFILE_PATH = RUN_DIR / "active-profile"
START_SCRIPT = BASE / "start-model-mac.sh"
STOP_ALL_SCRIPT = BASE / "stop-all-models.sh"
SYNC_SCRIPT = BASE / "sync-droid-local-models.py"
BENCH_SCRIPT = BASE / "benchmark-local-models.py"
BENCH_RESULTS_DIR = BASE / "benchmark-results"

DEFAULT_WEB_HOST = "127.0.0.1"


DEFAULT_WEB_PORT = 8877


MIN_AUTH_TOKEN_BYTES = 16


MAX_JSON_BODY_BYTES = 64 * 1024


FACTORY_SETTINGS_PATH = pathlib.Path.home() / ".factory" / "settings.json"


LAUNCH_AGENT_LABEL = "io.modelswitchboard.controller"


LAUNCH_AGENT_PLIST = pathlib.Path.home() / "Library/LaunchAgents" / f"{LAUNCH_AGENT_LABEL}.plist"


STATUS_CACHE_PATH = pathlib.Path.home() / "Library/Caches/io.modelswitchboard/controller-status.json"


CLI_CONTRACT_VERSION = "1.0"


CLI_SCHEMA_VERSION = "1"


DOCTOR_CONTRACT_VERSION = "1.0"


DOCTOR_SCHEMA_VERSION = "1"


DOCTOR_ARTIFACT_DIR = PROJECT_ROOT / ".doctor"
DOCTOR_RUNS_DIR = DOCTOR_ARTIFACT_DIR / "runs"
DOCTOR_LATEST_PATH = DOCTOR_ARTIFACT_DIR / "latest"


CLI_EXIT_CODES = {
    "0": "success",
    "1": "operation failed or diagnostic findings are present",
    "2": "safety block or partially applied repair",
    "3": "tool environment error or rollback failure",
    "4": "unsafe state refused",
    "5": "conflict or concurrency loss",
    "64": "usage error",
}


CLI_COMMAND_ALIASES = {
    "activate": ["switch"],
    "diagnose": ["doctor"],
    "validate": ["doctor"],
    "health": ["doctor", "health"],
    "docs": ["robot-docs", "guide"],
    "robot-help": ["robot-docs", "guide"],
}


CLI_GLOBAL_ALIASES = {
    "--capabilities": ["capabilities", "--json"],
    "--robot-docs": ["robot-docs", "guide"],
    "--robot-help": ["robot-docs", "guide"],
    "--robot-triage": ["triage", "--json"],
}


CLI_COMMAND_NAMES = [
    "status",
    "list",
    "start",
    "stop",
    "restart",
    "switch",
    "activate",
    "benchmark",
    "doctor",
    "diagnose",
    "health",
    "capabilities",
    "robot-docs",
    "triage",
    "integrations",
    "run-integration",
    "stop-all",
    "serve-web",
]


CLI_KNOWN_FLAGS = [
    "--allow-concurrent",
    "--auth-token",
    "--auth-token-file",
    "--background",
    "--dry-run",
    "--fix",
    "--help",
    "--host",
    "--json",
    "--keep-running",
    "--no-strict",
    "--plan",
    "--port",
    "--run-id",
    "--suite",
    "--unsafe-bind",
]


MUTATION_LOCK = threading.RLock()


_WATCHDOG_SUPPRESS_UNTIL = 0.0


_MIN_PID_MARKER_LEN = 4


DOCTOR_RUN_ID_PATTERN = re.compile(r"^[A-Za-z0-9._-]+$")


ALLOW_REMOTE_HEALTHCHECK_ENV = "ALLOW_REMOTE_HEALTHCHECK"


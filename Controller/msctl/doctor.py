from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

from contracts import (
    ControllerHeartbeatPayload,
    DoctorReportPayload,
    LaunchAgentStatusPayload,
    ProfileDiagnosticPayload,
    ProfileEnv,
)

from msctl.paths import (
    BASE,
    DEFAULT_WEB_HOST,
    DEFAULT_WEB_PORT,
    DOCTOR_ARTIFACT_DIR,
    DOCTOR_CONTRACT_VERSION,
    DOCTOR_LATEST_PATH,
    DOCTOR_RUNS_DIR,
    DOCTOR_SCHEMA_VERSION,
    LAUNCH_AGENT_LABEL,
    LAUNCH_AGENT_PLIST,
    PROFILE_DIR,
    PROJECT_ROOT,
)
from msctl.profiles import (
    base_url,
    endpoint_identity,
    healthcheck_mode,
    integration_status,
    load_profiles,
    profile_endpoint_conflicts,
    status_for_profile,
)
from msctl.runtimes import (
    adapter_model_source,
    canonical_runtime,
    executable_configured,
    executable_not_found_message,
    model_path_for_profile,
    resolve_llama_server_bin,
    resolve_mlx_server_bin,
    resolve_vllm_mlx_server_bin,
    runtime_spec,
    runtime_tags,
)
from msctl.security import sanitize_doctor_run_id

def launch_agent_status() -> LaunchAgentStatusPayload:
    try:
        output = run(["launchctl", "list"], check=False).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        print(f"warn: failed to read launchctl status: {exc}", file=sys.stderr)
        output = ""
    running = LAUNCH_AGENT_LABEL in output
    return {"plist_path": str(LAUNCH_AGENT_PLIST), "installed": LAUNCH_AGENT_PLIST.exists(), "running": running}


def controller_status() -> ControllerHeartbeatPayload:
    url = f"http://{DEFAULT_WEB_HOST}:{DEFAULT_WEB_PORT}/api/status"
    request = urllib.request.Request(url, headers={"Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=1.5) as response:  # nosemgrep: python.lang.security.audit.dynamic-urllib-use-detected.dynamic-urllib-use-detected -- controller_status probes the fixed loopback controller URL.
            payload = json.loads(response.read().decode())
        return {
            "url": url,
            "reachable": True,
            "profiles": len(payload.get("statuses", [])),
            "integrations": len(payload.get("integrations", [])),
        }
    except (
        urllib.error.URLError,
        urllib.error.HTTPError,
        TimeoutError,
        json.JSONDecodeError,
        UnicodeDecodeError,
    ):
        return {"url": url, "reachable": False, "profiles": 0, "integrations": 0}


def utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def utc_stamp() -> str:
    return utc_now().strftime("%Y%m%dT%H%M%SZ")


def tool_version() -> str:
    version_path = PROJECT_ROOT / "VERSION"
    try:
        return version_path.read_text(encoding="utf-8").strip() or "unknown"
    except OSError:
        return "unknown"


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def sha256_path(path: pathlib.Path) -> str | None:
    if not path.exists() or path.is_dir():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def doctor_run_id(label: str = "doctor") -> str:
    stamp = utc_stamp()
    seed = f"{PROJECT_ROOT}:{stamp}:{label}:{os.getpid()}"
    return f"{stamp}__{hashlib.sha256(seed.encode('utf-8')).hexdigest()[:8]}"


def doctor_run_dir(run_id: str) -> pathlib.Path:
    safe_id = sanitize_doctor_run_id(run_id)
    run_dir = (DOCTOR_RUNS_DIR / safe_id).resolve()
    runs_root = DOCTOR_RUNS_DIR.resolve()
    if run_dir != runs_root and runs_root not in run_dir.parents:
        raise ValueError("doctor run id escapes runs directory")
    return run_dir


def write_json_atomic(path: pathlib.Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temp_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    temp_path.replace(path)


def append_jsonl(path: pathlib.Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def update_doctor_latest(run_dir: pathlib.Path) -> None:
    DOCTOR_ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    tmp = DOCTOR_ARTIFACT_DIR / f".latest.{os.getpid()}.tmp"
    tmp.unlink(missing_ok=True)
    os.symlink(f"runs/{run_dir.name}", tmp)
    tmp.replace(DOCTOR_LATEST_PATH)


def doctor_finding(
    *,
    finding_id: str,
    severity: str,
    subsystem: str,
    message: str,
    evidence: str,
    remediation: str,
    auto_fixable: bool = False,
    fixer: str | None = None,
) -> dict[str, object]:
    return {
        "id": finding_id,
        "severity": severity,
        "subsystem": subsystem,
        "message": message,
        "evidence": evidence,
        "remediation": remediation,
        "auto_fixable": auto_fixable,
        "fixer": fixer,
        "online_required": False,
    }


def profile_finding_id(profile: str, kind: str, message: str) -> str:
    slug = "".join(char.lower() if char.isalnum() else "-" for char in profile).strip("-") or "profile"
    digest = sha256_text(f"{profile}:{kind}:{message}")[:8]
    return f"fm-profile-{slug}-{kind}-{digest}"


def doctor_findings(report: DoctorReportPayload) -> list[dict[str, object]]:
    findings: list[dict[str, object]] = []
    profiles_dir = pathlib.Path(report["profiles_dir"])
    if not profiles_dir.exists():
        findings.append(
            doctor_finding(
                finding_id="fm-profiles-dir-missing",
                severity="P1",
                subsystem="profiles",
                message="profiles directory is missing",
                evidence=str(profiles_dir),
                remediation="./Controller/modelctl.py doctor --fix",
                auto_fixable=True,
                fixer="create-profiles-dir",
            )
        )
    elif not profiles_dir.is_dir():
        findings.append(
            doctor_finding(
                finding_id="fm-profiles-dir-not-directory",
                severity="P0",
                subsystem="profiles",
                message="profiles path exists but is not a directory",
                evidence=str(profiles_dir),
                remediation="Move the file aside, then run ./Controller/modelctl.py doctor --fix",
            )
        )
    controller = report["controller"]
    if not controller["reachable"]:
        findings.append(
            doctor_finding(
                finding_id="fm-controller-unreachable",
                severity="P2",
                subsystem="controller",
                message="controller API is not reachable",
                evidence=controller["url"],
                remediation="bash ./Controller/install-model-switchboard-controller.sh",
            )
        )
    launch_agent = report["launch_agent"]
    if not launch_agent["installed"]:
        findings.append(
            doctor_finding(
                finding_id="fm-launch-agent-not-installed",
                severity="P2",
                subsystem="launch-agent",
                message="controller LaunchAgent is not installed",
                evidence=launch_agent["plist_path"],
                remediation="./Controller/install-model-switchboard-controller.sh",
            )
        )
    elif not launch_agent["running"]:
        findings.append(
            doctor_finding(
                finding_id="fm-launch-agent-not-running",
                severity="P2",
                subsystem="launch-agent",
                message="controller LaunchAgent is installed but not running",
                evidence=launch_agent["plist_path"],
                remediation="launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.modelswitchboard.controller.plist",
            )
        )
    for profile in report["profiles"]:
        for message in profile["errors"]:
            findings.append(
                doctor_finding(
                    finding_id=profile_finding_id(profile["profile"], "error", message),
                    severity="P1",
                    subsystem="profile",
                    message=message,
                    evidence=f"profile={profile['profile']} base_url={profile['base_url'] or 'n/a'}",
                    remediation=f"Edit {PROFILE_DIR / (profile['profile'] + '.env')} or run ./Controller/modelctl.py doctor explain {profile_finding_id(profile['profile'], 'error', message)}",
                )
            )
        for message in profile["warnings"]:
            findings.append(
                doctor_finding(
                    finding_id=profile_finding_id(profile["profile"], "warning", message),
                    severity="P3",
                    subsystem="profile",
                    message=message,
                    evidence=f"profile={profile['profile']} base_url={profile['base_url'] or 'n/a'}",
                    remediation=f"Review {PROFILE_DIR / (profile['profile'] + '.env')}",
                )
            )
    return findings


def doctor_next_steps(findings: list[dict[str, object]]) -> list[str]:
    if not findings:
        return ["No findings. Re-run with --json for machine-readable status."]
    steps = ["Run ./Controller/modelctl.py doctor --json for structured findings."]
    if any(finding.get("auto_fixable") for finding in findings):
        steps.append("Preview safe repairs with ./Controller/modelctl.py doctor --dry-run --fix --json.")
        steps.append("Apply safe repairs with ./Controller/modelctl.py doctor --fix --json.")
    steps.append("Use ./Controller/modelctl.py doctor explain <finding-id> for evidence and remediation.")
    return steps


def write_doctor_run_artifact(payload: object, *, run_id: str, command: str) -> pathlib.Path:
    run_dir = doctor_run_dir(run_id)
    run_dir.mkdir(parents=True, exist_ok=True)
    write_json_atomic(
        run_dir / "report.json",
        {
            "command": command,
            "generated_at": utc_now().isoformat().replace("+00:00", "Z"),
            "payload": payload,
        },
    )
    update_doctor_latest(run_dir)
    return run_dir


def doctor_capabilities() -> dict[str, object]:
    return {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "doctor_contract_version": DOCTOR_CONTRACT_VERSION,
        "default_command": "diagnose",
        "offline_default": True,
        "subcommands": ["diagnose", "health", "capabilities", "robot-docs", "explain", "undo"],
        "detectors": [
            {"id": "profiles-dir", "subsystem": "profiles", "online_required": False},
            {"id": "controller-api", "subsystem": "controller", "online_required": False},
            {"id": "launch-agent", "subsystem": "launch-agent", "online_required": False},
            {"id": "profile-config", "subsystem": "profile", "online_required": False},
        ],
        "fixers": [
            {
                "id": "create-profiles-dir",
                "description": "Create the controller model-profiles directory when it is absent.",
                "writes_to": [str(PROFILE_DIR)],
                "undo": True,
            }
        ],
        "write_scopes": [str(PROFILE_DIR), str(DOCTOR_ARTIFACT_DIR)],
        "artifacts": {
            "runs_dir": str(DOCTOR_RUNS_DIR),
            "latest": str(DOCTOR_LATEST_PATH),
            "actions_jsonl": "actions.jsonl",
            "backups_dir": "backups/",
        },
        "exit_codes": {
            "0": "healthy, fix complete, or undo complete",
            "1": "findings present in diagnose mode",
            "2": "fix partially applied",
            "3": "fix failed and rolled back",
            "4": "refused unsafe state",
            "5": "concurrency lost",
            "64": "usage error",
        },
        "env_vars": ["MODEL_SWITCHBOARD_URL", "MODEL_SWITCHBOARD_APP_PATH", "MODEL_SWITCHBOARD_VARIANT"],
    }


def doctor_health_payload() -> dict[str, object]:
    report = doctor_report()
    findings = report["findings"]
    return {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "healthy": not findings,
        "finding_count": len(findings),
        "auto_fixable_count": sum(1 for finding in findings if finding.get("auto_fixable")),
        "controller_reachable": report["controller"]["reachable"],
        "launch_agent_installed": report["launch_agent"]["installed"],
        "launch_agent_running": report["launch_agent"]["running"],
    }


def doctor_robot_docs() -> str:
    capabilities = doctor_capabilities()
    exit_codes = capabilities["exit_codes"]
    return "\n".join(
        [
            "Model Switchboard doctor robot docs",
            "",
            "Safe defaults:",
            "- `doctor` and `doctor diagnose` do not modify profile/controller state.",
            "- `doctor --fix` only applies fixers declared by `doctor capabilities --json`.",
            "- `doctor --dry-run --fix --json` prints the planned actions first.",
            "- `doctor undo <run-id>` reverses recorded fix actions from `.doctor/runs/<run-id>/actions.jsonl`.",
            "- Network probes are not used by this doctor.",
            "",
            "Primary commands:",
            "- `./Controller/modelctl.py doctor --json`",
            "- `./Controller/modelctl.py doctor health --json`",
            "- `./Controller/modelctl.py doctor capabilities --json`",
            "- `./Controller/modelctl.py doctor --dry-run --fix --json`",
            "- `./Controller/modelctl.py doctor explain <finding-id> --json`",
            "- `./Controller/modelctl.py doctor undo <run-id> --json`",
            "",
            "Exit codes:",
            *[f"- {code}: {meaning}" for code, meaning in exit_codes.items()],
        ]
    )


def doctor_mutate_create_directory(path: pathlib.Path, *, run_dir: pathlib.Path, dry_run: bool = False) -> dict[str, object]:
    before_exists = path.exists()
    before_hash = sha256_path(path)
    action = {
        "action": "create_directory",
        "path": str(path),
        "before_exists": before_exists,
        "before_hash": before_hash,
        "after_exists": before_exists,
        "after_hash": before_hash,
        "dry_run": dry_run,
    }
    if before_exists:
        action["status"] = "skipped_already_exists"
        return action
    if dry_run:
        action["status"] = "planned"
        return action
    path.mkdir(parents=True, exist_ok=True)
    action["after_exists"] = path.exists()
    action["after_hash"] = sha256_path(path)
    action["status"] = "applied"
    append_jsonl(run_dir / "actions.jsonl", action)
    return action


def doctor_fix(*, dry_run: bool = False, run_id: str | None = None) -> tuple[dict[str, object], int]:
    before = doctor_report()
    run_id = run_id or doctor_run_id("fix")
    run_dir = doctor_run_dir(run_id)
    run_dir.mkdir(parents=True, exist_ok=True)
    actions: list[dict[str, object]] = []
    for finding in before["findings"]:
        if finding.get("fixer") == "create-profiles-dir":
            actions.append(doctor_mutate_create_directory(PROFILE_DIR, run_dir=run_dir, dry_run=dry_run))
    after = before if dry_run else doctor_report()
    payload = {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "run_id": run_id,
        "dry_run": dry_run,
        "actions_taken": sum(1 for action in actions if action.get("status") == "applied"),
        "actions": actions,
        "healthy": after["healthy"],
        "findings": after["findings"],
        "next_steps": doctor_next_steps(after["findings"]),
    }
    write_doctor_run_artifact(payload, run_id=run_id, command="fix")
    if dry_run:
        return payload, 0 if not actions else 1
    if payload["actions_taken"] == 0 and before["findings"]:
        return payload, 1
    return payload, 0 if after["healthy"] else 2


def doctor_undo(run_id: str, *, strict: bool = True) -> tuple[dict[str, object], int]:
    run_dir = doctor_run_dir(run_id)
    actions_path = run_dir / "actions.jsonl"
    if not actions_path.exists():
        return {
            "schema_version": DOCTOR_SCHEMA_VERSION,
            "run_id": run_id,
            "ok": False,
            "error": "actions.jsonl not found",
            "strict": strict,
        }, 4
    actions = [json.loads(line) for line in actions_path.read_text(encoding="utf-8").splitlines() if line.strip()]
    undone: list[dict[str, object]] = []
    quarantine = run_dir / "quarantine"
    for action in reversed(actions):
        if action.get("action") != "create_directory" or action.get("before_exists"):
            continue
        path = pathlib.Path(str(action["path"]))
        item: dict[str, object] = {"action": "undo_create_directory", "path": str(path)}
        if not path.exists():
            item["status"] = "skipped_missing"
            undone.append(item)
            continue
        if any(path.iterdir()):
            item["status"] = "refused_non_empty_directory"
            undone.append(item)
            if strict:
                return {
                    "schema_version": DOCTOR_SCHEMA_VERSION,
                    "run_id": run_id,
                    "ok": False,
                    "strict": strict,
                    "undone": undone,
                    "error": "refused to undo non-empty created directory",
                }, 4
            continue
        quarantine.mkdir(parents=True, exist_ok=True)
        target = quarantine / f"{path.name}.{sha256_text(str(path))[:8]}"
        path.replace(target)
        item["status"] = "quarantined"
        item["quarantine_path"] = str(target)
        undone.append(item)
    payload = {"schema_version": DOCTOR_SCHEMA_VERSION, "run_id": run_id, "ok": True, "strict": strict, "undone": undone}
    write_doctor_run_artifact(payload, run_id=doctor_run_id("undo"), command=f"undo {run_id}")
    return payload, 0


def explain_doctor_finding(finding_id: str) -> tuple[dict[str, object], int]:
    report = doctor_report()
    for finding in report["findings"]:
        if finding["id"] == finding_id:
            return {
                "schema_version": DOCTOR_SCHEMA_VERSION,
                "finding": finding,
                "capabilities": {
                    "fixer": finding.get("fixer"),
                    "auto_fixable": finding.get("auto_fixable"),
                    "online_required": finding.get("online_required"),
                },
                "next_steps": doctor_next_steps([finding]),
            }, 0
    return {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "error": "finding not present in current doctor report",
        "finding_id": finding_id,
        "known_findings": [finding["id"] for finding in report["findings"]],
    }, 1


def diagnose_profile(
    name: str,
    env: ProfileEnv,
    *,
    endpoint_conflict: tuple[str, list[str]] | None = None,
) -> ProfileDiagnosticPayload:
    runtime = canonical_runtime(env.get("RUNTIME"))
    spec = runtime_spec(env)
    launch_mode = spec["launch_mode"]
    errors: list[str] = []
    warnings: list[str] = []
    profile_base_url = ""
    url_config_error = False

    try:
        profile_base_url = base_url(env)
    except ValueError as exc:
        errors.append(str(exc))
        url_config_error = True

    health_url = ""
    health_url_error = False
    if healthcheck_mode(env) != "disabled":
        try:
            health_url = healthcheck_url(env)
        except ValueError as exc:
            message = str(exc)
            if message not in errors:
                errors.append(message)
            health_url_error = True
            url_config_error = True

    if not env.get("DISPLAY_NAME"):
        errors.append("missing DISPLAY_NAME")
    if not env.get("REQUEST_MODEL"):
        errors.append("missing REQUEST_MODEL")

    if launch_mode == "external":
        if healthcheck_mode(env) != "disabled" and not health_url and not health_url_error:
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    elif runtime == "llama.cpp":
        if not resolve_llama_server_bin(env):
            errors.append(executable_not_found_message("llama-server", "SERVER_BIN", "LLAMA_SERVER_BIN"))
        model_path = model_path_for_profile(env)
        if not model_path:
            errors.append(
                "missing MODEL_PATH or MODEL_FILE with a model root "
                "(MODEL_ROOT, MODEL_ROOT_HINT, ~/AI/models, or ../models)"
            )
        elif not model_path.exists():
            errors.append(f"model file not found: {model_path}")
    elif runtime == "mlx":
        if not resolve_mlx_server_bin(env):
            errors.append(executable_not_found_message("mlx_lm.server", "SERVER_BIN", "MLX_SERVER_BIN"))
        model_dir = env.get("MODEL_DIR")
        model_repo = env.get("MODEL_REPO")
        if model_dir:
            if not pathlib.Path(model_dir).exists():
                errors.append(f"MODEL_DIR not found: {model_dir}")
        elif not model_repo:
            errors.append("missing MODEL_DIR or MODEL_REPO")
    elif runtime == "rvllm-mlx":
        server_bin = env.get("SERVER_BIN")
        if not server_bin:
            errors.append("missing SERVER_BIN")
        elif not pathlib.Path(server_bin).exists():
            errors.append(f"SERVER_BIN not found: {server_bin}")
        elif not os.access(server_bin, os.X_OK):
            errors.append(f"SERVER_BIN is not executable: {server_bin}")
        model_dir = env.get("MODEL_DIR")
        if not model_dir:
            errors.append("missing MODEL_DIR")
        elif not pathlib.Path(model_dir).exists():
            errors.append(f"MODEL_DIR not found: {model_dir}")
    elif runtime == "vllm-mlx":
        if not resolve_vllm_mlx_server_bin(env):
            errors.append(executable_not_found_message("vllm-mlx", "SERVER_BIN", "VLLM_MLX_BIN"))
        model_source = adapter_model_source(env)
        if not model_source:
            errors.append("missing MODEL_REPO, MODEL_ID, MODEL_DIR, MODEL_PATH, or MODEL_FILE for vllm-mlx")
        elif env.get("MODEL_DIR") and not pathlib.Path(env["MODEL_DIR"]).exists():
            errors.append(f"MODEL_DIR not found: {env['MODEL_DIR']}")
    elif runtime == "ollama":
        if not executable_configured(env, "SERVER_BIN", "OLLAMA_BIN") and not shutil.which("ollama"):
            errors.append("ollama not found")
    elif runtime in {"vllm", "sglang", "tgi"}:
        if not adapter_model_source(env):
            errors.append(f"missing MODEL_REPO, MODEL_ID, MODEL_DIR, MODEL_PATH, or MODEL_FILE for {runtime}")
        if runtime == "tgi":
            if not executable_configured(env, "SERVER_BIN", "TGI_SERVER_BIN") and not shutil.which("text-generation-launcher"):
                errors.append("text-generation-launcher not found")
        elif not executable_configured(env, "PYTHON_BIN") and not shutil.which("python3") and not shutil.which("python"):
            errors.append(f"python not found for {runtime}")
    elif runtime == "llama-cpp-python":
        model_source = adapter_model_source(env)
        if not model_source:
            errors.append("missing MODEL_PATH or MODEL_FILE for llama-cpp-python")
        elif not pathlib.Path(model_source).exists():
            errors.append(f"model file not found: {model_source}")
        if not executable_configured(env, "PYTHON_BIN") and not shutil.which("python3") and not shutil.which("python"):
            errors.append("python not found for llama-cpp-python")
    elif runtime == "command":
        if not env.get("START_COMMAND"):
            errors.append("missing START_COMMAND")
        if healthcheck_mode(env) != "disabled" and not health_url and not health_url_error:
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    elif env.get("START_COMMAND"):
        if healthcheck_mode(env) != "disabled" and not health_url and not health_url_error:
            errors.append("missing BASE_URL or HEALTHCHECK_URL")
    elif env.get("SERVER_BIN"):
        if not pathlib.Path(env["SERVER_BIN"]).exists():
            errors.append(f"SERVER_BIN not found: {env['SERVER_BIN']}")
        elif not os.access(env["SERVER_BIN"], os.X_OK):
            errors.append(f"SERVER_BIN is not executable: {env['SERVER_BIN']}")
        if not env.get("SERVER_ARGS_JSON"):
            errors.append("missing SERVER_ARGS_JSON for generic SERVER_BIN runtime")
    else:
        warnings.append(f"runtime '{runtime}' has no adapter-specific validation; use START_COMMAND or SERVER_BIN with SERVER_ARGS_JSON")

    if not profile_base_url:
        warnings.append("base_url is empty; endpoint health checks may fail")
    if healthcheck_mode(env) == "disabled":
        warnings.append("healthcheck disabled; ready state cannot be verified")
    if endpoint_conflict:
        endpoint, other_profiles = endpoint_conflict
        errors.append(f"duplicate {format_endpoint_conflict(endpoint, other_profiles)}")

    if url_config_error:
        live = {
            "running": False,
            "ready": False,
            "pid": None,
            "base_url": profile_base_url,
        }
    else:
        try:
            live = status_for_profile(name, env, allow_port_fallback=endpoint_conflict is None)
        except Exception as exc:  # noqa: BLE001
            live = {
                "running": False,
                "ready": False,
                "pid": None,
                "base_url": profile_base_url,
                "error": str(exc),
            }
            errors.append(f"status probe failed: {exc}")

    return {
        "profile": name,
        "display_name": env.get("DISPLAY_NAME", name),
        "runtime": runtime,
        "runtime_label": spec["label"],
        "runtime_tags": runtime_tags(env),
        "launch_mode": spec["launch_mode"],
        "errors": errors,
        "warnings": warnings,
        "running": live.get("running", False),
        "ready": live.get("ready", False),
        "pid": live.get("pid"),
        "base_url": live.get("base_url", profile_base_url),
    }


def doctor_report() -> DoctorReportPayload:
    profiles = load_profiles()
    conflicts = profile_endpoint_conflicts(profiles)
    diagnostics = [
        diagnose_profile(name, env, endpoint_conflict=conflicts.get(name))
        for name, env in sorted(profiles.items())
    ]
    report = {
        "schema_version": DOCTOR_SCHEMA_VERSION,
        "doctor_contract_version": DOCTOR_CONTRACT_VERSION,
        "tool_version": tool_version(),
        "generated_at": utc_now().isoformat().replace("+00:00", "Z"),
        "controller": controller_status(),
        "launch_agent": launch_agent_status(),
        "integrations": integration_status(),
        "profiles_dir": str(PROFILE_DIR),
        "controller_root": str(BASE),
        "profiles": diagnostics,
    }
    findings = doctor_findings(report)
    report["healthy"] = not findings
    report["findings"] = findings
    report["next_steps"] = doctor_next_steps(findings)
    return report


def print_doctor(report: DoctorReportPayload) -> None:
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
            f"{item['display_name']} ({item['runtime_label']})",
            f"launch={item['launch_mode']}",
            f"tags={','.join(item['runtime_tags']) or '-'}",
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
    findings = report.get("findings", [])
    print(f"doctor | {'ok' if not findings else 'warn'} | findings={len(findings)} contract={DOCTOR_CONTRACT_VERSION}")
    for step in report.get("next_steps", []):
        print(f"next | info | {step}")


def print_doctor_health(payload: dict[str, object]) -> None:
    print("component | status | details")
    print("--- | --- | ---")
    print(
        "doctor | "
        f"{'ok' if payload['healthy'] else 'warn'} | "
        f"findings={payload['finding_count']} auto_fixable={payload['auto_fixable_count']}"
    )
    print(f"controller | {'ok' if payload['controller_reachable'] else 'warn'} | reachable={payload['controller_reachable']}")
    print(
        "launch-agent | "
        f"{'ok' if payload['launch_agent_installed'] and payload['launch_agent_running'] else 'warn'} | "
        f"installed={payload['launch_agent_installed']} running={payload['launch_agent_running']}"
    )



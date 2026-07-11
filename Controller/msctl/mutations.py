from __future__ import annotations

import argparse
import contextlib
import io
import json

from contracts import ProfileEnv
from msctl.doctor import tool_version, utc_now
from msctl.paths import ACTIVE_PROFILE_PATH, CLI_SCHEMA_VERSION, START_SCRIPT, STOP_ALL_SCRIPT
from msctl.profiles import (
    base_url,
    ensure_unique_profile_endpoint,
    load_profiles,
    read_pid,
    require_profile,
    restart_profile,
    start_profile,
    status_for_profile,
    status_payload,
    status_snapshot,
    stop_all,
    stop_profile,
    switch_profile,
)
from msctl.security import ProfileConflictError


def resolve_selected(args: argparse.Namespace) -> list[str] | None:
    if not getattr(args, "profiles", None):
        return None
    if args.profiles == ["all"]:
        return sorted(load_profiles())
    return args.profiles

def mutation_action(
    action: str,
    *,
    profile: str | None = None,
    mutates: bool = True,
    command: list[str] | None = None,
    details: dict[str, object] | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "action": action,
        "mutates": mutates,
    }
    if profile:
        payload["profile"] = profile
    if command:
        payload["command"] = command
    if details:
        payload["details"] = details
    return payload


def plan_start_profile(name: str, profiles: dict[str, ProfileEnv] | None = None) -> dict[str, object]:
    profiles = profiles or load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="start")
    env = profiles[name]
    return mutation_action(
        "start-profile",
        profile=name,
        command=["bash", str(START_SCRIPT)],
        details={
            "environment": {"MODEL_PROFILE": name},
            "runtime": env.get("RUNTIME", "llama.cpp"),
            "base_url": base_url(env),
            "request_model": env.get("REQUEST_MODEL"),
        },
    )


def plan_stop_profile(name: str) -> dict[str, object]:
    env = require_profile(name)
    status = status_for_profile(name, env)
    stop_command = env.get("STOP_COMMAND", "").strip()
    return mutation_action(
        "stop-profile",
        profile=name,
        details={
            "pid": status.get("pid"),
            "running": bool(status.get("running")),
            "ready": bool(status.get("ready")),
            "stop_command": stop_command or None,
            "stop_command_only": env.get("STOP_COMMAND_ONLY", "0") == "1",
            "will_clear_active_profile": True,
        },
    )


def plan_restart_profile(name: str, profiles: dict[str, ProfileEnv] | None = None) -> dict[str, object]:
    profiles = profiles or load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="restart")
    return mutation_action(
        "restart-profile",
        profile=name,
        details={
            "steps": [
                plan_stop_profile(name),
                plan_start_profile(name, profiles),
            ]
        },
    )


def plan_switch_profile(name: str) -> dict[str, object]:
    profiles = load_profiles()
    if name not in profiles:
        raise SystemExit(f"Unknown profile: {name}")
    ensure_unique_profile_endpoint(name, profiles, action="activate")
    running_others = sorted(
        item["profile"] for item in status_snapshot() if item["profile"] != name and item["running"]
    )
    steps = [
        *[
            mutation_action(
                "stop-running-profile",
                profile=profile,
                details={"reason": f"switch activates {name} exclusively"},
            )
            for profile in running_others
        ],
        plan_start_profile(name, profiles),
        mutation_action("write-active-profile", profile=name, details={"path": str(ACTIVE_PROFILE_PATH)}),
    ]
    return mutation_action(
        "switch-profile",
        profile=name,
        details={
            "stop_first": running_others,
            "steps": steps,
        },
    )


def plan_stop_all() -> dict[str, object]:
    profiles = load_profiles()
    benchmark_pid = read_pid("benchmark")
    steps = []
    if benchmark_pid:
        steps.append(mutation_action("stop-benchmark", details={"pid": benchmark_pid}))
    steps.extend(mutation_action("stop-profile", profile=name) for name in sorted(profiles))
    steps.append(mutation_action("run-stop-all-script", command=["bash", str(STOP_ALL_SCRIPT)]))
    return mutation_action(
        "stop-all",
        details={
            "benchmark_pid": benchmark_pid,
            "profiles": sorted(profiles),
            "steps": steps,
        },
    )


def mutating_plan_for_args(args: argparse.Namespace) -> list[dict[str, object]]:
    if args.command == "switch":
        return [plan_switch_profile(args.profile)]
    if args.command == "stop-all":
        return [plan_stop_all()]
    selected = resolve_selected(args)
    if not selected:
        if getattr(args, "dry_run", False) and getattr(args, "profiles", None) == ["all"]:
            return [mutation_action(f"{args.command}-all", details={"profiles": [], "steps": []})]
        raise SystemExit("No profiles selected")
    if args.command == "start":
        profiles = load_profiles()
        return [plan_start_profile(name, profiles) for name in selected]
    if args.command == "stop":
        return [plan_stop_profile(name) for name in selected]
    if args.command == "restart":
        profiles = load_profiles()
        return [plan_restart_profile(name, profiles) for name in selected]
    raise SystemExit(f"Unsupported mutating command: {args.command}")


def mutation_envelope(
    args: argparse.Namespace,
    *,
    dry_run: bool,
    plan: list[dict[str, object]],
    ok: bool = True,
    results: list[dict[str, object]] | None = None,
    error: dict[str, object] | None = None,
) -> dict[str, object]:
    payload: dict[str, object] = {
        "schema_version": CLI_SCHEMA_VERSION,
        "tool": "modelctl.py",
        "tool_version": tool_version(),
        "command": args.command,
        "dry_run": dry_run,
        "status": "planned" if dry_run else ("applied" if ok else "failed"),
        "ok": ok,
        "generated_at": utc_now().isoformat().replace("+00:00", "Z"),
        "plan": plan,
        "results": results or [],
    }
    if error:
        payload["error"] = error
    if not dry_run and ok:
        payload["status_after"] = status_payload()
    return payload


def print_mutation_plan(envelope: dict[str, object]) -> None:
    print(f"plan {envelope['command']} dry_run={str(envelope['dry_run']).lower()}")
    for item in envelope["plan"]:
        profile = f" {item['profile']}" if item.get("profile") else ""
        print(f"- {item['action']}{profile}")
        details = item.get("details")
        if isinstance(details, dict):
            steps = details.get("steps")
            if isinstance(steps, list):
                for step in steps:
                    step_profile = f" {step['profile']}" if step.get("profile") else ""
                    print(f"  - {step['action']}{step_profile}")


def mutation_exit_code(exc: BaseException) -> int:
    if isinstance(exc, ProfileConflictError):
        return 5
    if isinstance(exc, SystemExit) and isinstance(exc.code, int):
        return exc.code
    return 1


def mutation_error_payload(exc: BaseException) -> dict[str, object]:
    if isinstance(exc, ProfileConflictError):
        code = "profile_conflict"
    elif isinstance(exc, SystemExit):
        code = "usage_error" if isinstance(exc.code, int) and exc.code == 64 else "user_input_error"
    else:
        code = "operation_failed"
    return {
        "code": code,
        "message": str(exc),
    }


def execute_mutating_args(args: argparse.Namespace) -> None:
    if args.command == "switch":
        switch_profile(args.profile)
        return
    if args.command == "stop-all":
        stop_all(capture_script=True)
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
        else:
            raise SystemExit(f"Unsupported mutating command: {args.command}")


def capture_mutating_execution(args: argparse.Namespace) -> tuple[list[dict[str, object]], BaseException | None]:
    stdout = io.StringIO()
    stderr = io.StringIO()
    try:
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            execute_mutating_args(args)
    except (Exception, SystemExit) as exc:  # noqa: BLE001
        return [
            {
                "ok": False,
                "stdout": stdout.getvalue().splitlines(),
                "stderr": stderr.getvalue().splitlines(),
            }
        ], exc
    return [
        {
            "ok": True,
            "stdout": stdout.getvalue().splitlines(),
            "stderr": stderr.getvalue().splitlines(),
        }
    ], None


def handle_mutating_command(args: argparse.Namespace) -> int:
    as_json = bool(getattr(args, "json", False))
    dry_run = bool(getattr(args, "dry_run", False))
    try:
        plan = mutating_plan_for_args(args)
    except (Exception, SystemExit) as exc:  # noqa: BLE001
        if not as_json:
            raise
        payload = mutation_envelope(
            args,
            dry_run=dry_run,
            plan=[],
            ok=False,
            error=mutation_error_payload(exc),
        )
        print(json.dumps(payload, indent=2))
        return mutation_exit_code(exc)

    if dry_run:
        payload = mutation_envelope(args, dry_run=True, plan=plan)
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            print_mutation_plan(payload)
        return 0

    if as_json:
        results, error = capture_mutating_execution(args)
        payload = mutation_envelope(
            args,
            dry_run=False,
            plan=plan,
            ok=error is None,
            results=results,
            error=mutation_error_payload(error) if error else None,
        )
        print(json.dumps(payload, indent=2))
        return 0 if error is None else mutation_exit_code(error)

    execute_mutating_args(args)
    return 0

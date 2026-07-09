from __future__ import annotations

import argparse
import difflib
import json
import sys

from msctl.agent_contracts import (
    modelctl_capabilities,
    modelctl_robot_docs,
    modelctl_triage_payload,
    print_modelctl_triage,
)
from msctl.benchmarks import start_benchmark
from msctl.doctor import (
    doctor_capabilities,
    doctor_fix,
    doctor_health_payload,
    doctor_report,
    doctor_robot_docs,
    doctor_undo,
    explain_doctor_finding,
    print_doctor,
    print_doctor_health,
    write_doctor_run_artifact,
)
from msctl.mutations import handle_mutating_command
from msctl.paths import (
    CLI_COMMAND_ALIASES,
    CLI_COMMAND_NAMES,
    CLI_GLOBAL_ALIASES,
    CLI_KNOWN_FLAGS,
    DEFAULT_WEB_HOST,
    DEFAULT_WEB_PORT,
    PROFILE_DIR,
)
from msctl.profiles import (
    integration_status,
    load_profiles,
    print_status,
    run_integration_action,
    status_payload,
    write_status_cache,
)
from msctl.security import resolve_auth_token
from msctl.web import serve_web

def closest_cli_token(value: str, choices: list[str]) -> str | None:
    matches = difflib.get_close_matches(value, choices, n=1, cutoff=0.58)
    return matches[0] if matches else None


def normalize_cli_argv(argv: list[str]) -> list[str]:
    if not argv:
        return argv
    first = argv[0]
    if first in CLI_GLOBAL_ALIASES:
        return [*CLI_GLOBAL_ALIASES[first], *argv[1:]]
    if first in CLI_COMMAND_ALIASES:
        return [*CLI_COMMAND_ALIASES[first], *argv[1:]]
    return argv


def cli_usage_hint(prog: str, message: str) -> str:
    hint_parts: list[str] = []
    if "invalid choice:" in message:
        attempted = message.split("invalid choice:", 1)[1].split("(", 1)[0].strip().strip("'\"")
        suggestion = closest_cli_token(attempted, CLI_COMMAND_NAMES)
        if suggestion:
            hint_parts.append(f"did you mean: `{prog} {suggestion}`")
    if "unrecognized arguments:" in message:
        unknown = message.split("unrecognized arguments:", 1)[1].strip().split()[0]
        suggestion = closest_cli_token(unknown, CLI_KNOWN_FLAGS)
        if suggestion:
            hint_parts.append(f"did you mean: `{prog} {suggestion}`")
    hint_parts.append(f"inspect machine-readable commands with `{prog} capabilities --json`")
    return "\n".join(f"hint: {hint}" for hint in hint_parts)


class AgentArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        self.exit(64, f"{self.prog}: usage error: {message}\n{cli_usage_hint(self.prog, message)}\n")


def resolve_selected(args: argparse.Namespace) -> list[str] | None:
    if not getattr(args, "profiles", None):
        return None
    if args.profiles == ["all"]:
        return sorted(load_profiles())
    return args.profiles


def build_parser() -> argparse.ArgumentParser:
    parser = AgentArgumentParser(description="Control local llama.cpp and MLX profiles", allow_abbrev=False)
    sub = parser.add_subparsers(dest="command", required=True, parser_class=AgentArgumentParser)

    status_cmd = sub.add_parser("status", help="Show status for profiles")
    status_cmd.add_argument("profiles", nargs="*", default=[])
    status_cmd.add_argument("--json", action="store_true")

    list_cmd = sub.add_parser("list", help="List profiles")
    list_cmd.add_argument("--json", action="store_true")

    start_cmd = sub.add_parser("start", help="Start one or more profiles")
    start_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")
    start_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    start_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    stop_cmd = sub.add_parser("stop", help="Stop one or more profiles")
    stop_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")
    stop_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    stop_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    restart_cmd = sub.add_parser("restart", help="Restart one or more profiles")
    restart_cmd.add_argument("profiles", nargs="+", help="Profile names or 'all'")
    restart_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    restart_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    switch_cmd = sub.add_parser("switch", help="Stop other running profiles and start the selected one")
    switch_cmd.add_argument("profile", help="Profile name")
    switch_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    switch_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    bench_cmd = sub.add_parser("benchmark", help="Run the benchmark harness")
    bench_cmd.add_argument("profiles", nargs="*", default=["all"], help="Profile names or 'all'")
    bench_cmd.add_argument("--suite", choices=["quick", "local", "context", "coding"], default="quick")
    bench_cmd.add_argument("--allow-concurrent", action="store_true")
    bench_cmd.add_argument("--keep-running", action="store_true")
    bench_cmd.add_argument("--background", action="store_true")

    capabilities_cmd = sub.add_parser("capabilities", help="Describe the machine-readable CLI contract")
    capabilities_cmd.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    robot_docs_cmd = sub.add_parser("robot-docs", help="Print agent-facing CLI usage docs")
    robot_docs_cmd.add_argument("topic", nargs="?", default="guide", choices=["guide"])

    triage_cmd = sub.add_parser("triage", help="Print one-call agent triage")
    triage_cmd.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    doctor_cmd = sub.add_parser("doctor", help="Validate profiles, controller, and launch agent")
    doctor_cmd.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    doctor_cmd.add_argument("--fix", action="store_true", help="Apply safe, reversible repairs")
    doctor_cmd.add_argument("--dry-run", action="store_true", help="Show the repair plan without mutating state")
    doctor_cmd.add_argument("--run-id", help="Override the doctor run id for artifacts")
    doctor_sub = doctor_cmd.add_subparsers(dest="doctor_command")
    doctor_diagnose = doctor_sub.add_parser("diagnose", help="Run diagnostics (default)")
    doctor_diagnose.add_argument("--json", action="store_true")
    doctor_diagnose.add_argument("--fix", action="store_true")
    doctor_diagnose.add_argument("--dry-run", action="store_true")
    doctor_diagnose.add_argument("--run-id")
    doctor_health = doctor_sub.add_parser("health", help="Print a compact health summary")
    doctor_health.add_argument("--json", action="store_true")
    doctor_capabilities = doctor_sub.add_parser("capabilities", help="Describe doctor capabilities")
    doctor_capabilities.add_argument("--json", action="store_true")
    doctor_robot_docs_cmd = doctor_sub.add_parser("robot-docs", help="Print agent-facing doctor usage docs")
    doctor_robot_docs_cmd.add_argument("topic", nargs="?", default="guide", choices=["guide"])
    doctor_explain = doctor_sub.add_parser("explain", help="Explain a current finding")
    doctor_explain.add_argument("finding_id")
    doctor_explain.add_argument("--json", action="store_true")
    doctor_undo_cmd = doctor_sub.add_parser("undo", help="Undo a recorded doctor fix run")
    doctor_undo_cmd.add_argument("run_id")
    doctor_undo_cmd.add_argument("--json", action="store_true")
    doctor_undo_cmd.add_argument("--no-strict", action="store_true", help="Continue past non-critical undo refusals")

    sub.add_parser("integrations", help="List optional backend integrations")
    integration_cmd = sub.add_parser("run-integration", help="Run an action on an optional integration")
    integration_cmd.add_argument("integration", help="Integration id")
    integration_cmd.add_argument("--action", default="sync", help="Integration action to run")

    stop_all_cmd = sub.add_parser("stop-all", help="Stop every managed model process")
    stop_all_cmd.add_argument("--json", action="store_true", help="Print a structured result envelope")
    stop_all_cmd.add_argument("--dry-run", "--plan", action="store_true", help="Print the action plan without mutating")

    web_cmd = sub.add_parser(
        "serve-web",
        help="Serve the local controller JSON API for the menu bar app (no browser UI)",
    )
    web_cmd.add_argument("--host", default=None)
    web_cmd.add_argument("--unsafe-bind", metavar="HOST", help="Bind a non-loopback host; requires an auth token")
    web_cmd.add_argument("--port", type=int, default=DEFAULT_WEB_PORT)
    web_cmd.add_argument("--auth-token")
    web_cmd.add_argument("--auth-token-file")

    return parser


def handle_doctor(args: argparse.Namespace) -> int:
    doctor_command = args.doctor_command or "diagnose"
    as_json = bool(getattr(args, "json", False))
    if doctor_command == "capabilities":
        payload = doctor_capabilities()
        print(json.dumps(payload, indent=2) if as_json else json.dumps(payload, indent=2))
        return 0
    if doctor_command == "robot-docs":
        print(doctor_robot_docs())
        return 0
    if doctor_command == "health":
        payload = doctor_health_payload()
        write_doctor_run_artifact(payload, run_id=doctor_run_id("health"), command="health")
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            print_doctor_health(payload)
        return 0 if payload["healthy"] else 1
    if doctor_command == "explain":
        payload, code = explain_doctor_finding(args.finding_id)
        if as_json:
            print(json.dumps(payload, indent=2))
        elif code == 0:
            finding = payload["finding"]
            print(f"{finding['id']}: {finding['message']}")
            print(f"evidence: {finding['evidence']}")
            print(f"remediation: {finding['remediation']}")
        else:
            print(f"finding not present: {args.finding_id}", file=sys.stderr)
        return code
    if doctor_command == "undo":
        payload, code = doctor_undo(args.run_id, strict=not args.no_strict)
        if as_json:
            print(json.dumps(payload, indent=2))
        elif payload.get("ok"):
            print(f"undone {args.run_id}: {len(payload.get('undone', []))} actions")
        else:
            print(f"undo failed for {args.run_id}: {payload.get('error')}", file=sys.stderr)
        return code
    if args.fix:
        payload, code = doctor_fix(dry_run=bool(args.dry_run), run_id=args.run_id)
        if as_json:
            print(json.dumps(payload, indent=2))
        else:
            mode = "planned" if args.dry_run else "applied"
            print(f"doctor fix {mode}: actions={payload['actions_taken']} run_id={payload['run_id']}")
            for action in payload["actions"]:
                print(f"action | {action['status']} | {action['action']} {action['path']}")
        return code
    report = doctor_report()
    run_id = args.run_id or doctor_run_id("diagnose")
    write_doctor_run_artifact(report, run_id=run_id, command="diagnose")
    if as_json:
        print(json.dumps(report, indent=2))
    else:
        print_doctor(report)
    return 0 if report["healthy"] else 1


def main() -> None:
    parser = build_parser()
    args = parser.parse_args(normalize_cli_argv(sys.argv[1:]))

    if args.command == "capabilities":
        payload = modelctl_capabilities()
        print(json.dumps(payload, indent=2) if args.json else json.dumps(payload, indent=2))
        return

    if args.command == "robot-docs":
        print(modelctl_robot_docs(args.topic))
        return

    if args.command == "triage":
        payload = modelctl_triage_payload()
        if args.json:
            print(json.dumps(payload, indent=2))
        else:
            print_modelctl_triage(payload)
        return

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

    if args.command == "integrations":
        print(json.dumps({"integrations": integration_status()}, indent=2))
        return

    if args.command == "run-integration":
        run_integration_action(args.integration, args.action)
        return

    if args.command == "stop-all":
        code = handle_mutating_command(args)
        if code:
            raise SystemExit(code)
        return

    if args.command == "serve-web":
        host = args.unsafe_bind or args.host or DEFAULT_WEB_HOST
        auth_token = resolve_auth_token(args.auth_token, args.auth_token_file)
        serve_web(host, args.port, unsafe_bind=bool(args.unsafe_bind), auth_token=auth_token)
        return

    if args.command == "doctor":
        code = handle_doctor(args)
        if code:
            raise SystemExit(code)
        return

    if args.command == "switch":
        code = handle_mutating_command(args)
        if code:
            raise SystemExit(code)
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

    code = handle_mutating_command(args)
    if code:
        raise SystemExit(code)



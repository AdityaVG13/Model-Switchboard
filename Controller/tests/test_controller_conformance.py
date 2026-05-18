from __future__ import annotations

import contextlib
import difflib
import http.client
import importlib.util
import json
import os
import re
import sys
import threading
import unittest
from pathlib import Path
from typing import Any
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
MODULE_PATH = ROOT / "modelctl.py"
SPEC = importlib.util.spec_from_file_location("modelctl", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

CONFORMANCE_DIR = ROOT / "tests" / "conformance"
CASES_PATH = CONFORMANCE_DIR / "fixtures" / "controller_api_cases.json"
REPORT_PATH = CONFORMANCE_DIR / "REPORT.md"
SPEC_SOURCE = "`Controller/modelctl.py`, `Controller/contracts.py`, `Sources/ModelSwitchboardCore/ControllerClient.swift`"
UPDATE_GOLDENS = {"1", "true", "yes"}


def load_cases() -> list[dict[str, Any]]:
    return json.loads(CASES_PATH.read_text())


def updating_goldens() -> bool:
    return os.environ.get("UPDATE_GOLDENS", "").lower() in UPDATE_GOLDENS


def canonicalize_golden_text(text: str) -> str:
    text = text.replace("\r\n", "\n").replace("\r", "\n").replace("\\", "/")
    text = re.sub(r"/Users/[^/\n]+/", "/HOME/", text)
    text = re.sub(r"/home/[^/\n]+/", "/HOME/", text)
    lines = [line.rstrip() for line in text.split("\n")]
    return "\n".join(lines).rstrip() + "\n"


def assert_golden(testcase: unittest.TestCase, golden_path: Path, actual: str) -> None:
    actual = canonicalize_golden_text(actual)
    if updating_goldens():
        golden_path.parent.mkdir(parents=True, exist_ok=True)
        golden_path.write_text(actual)
        return
    expected = canonicalize_golden_text(golden_path.read_text())
    actual_path = golden_path.with_suffix(golden_path.suffix + ".actual")
    actual_path.unlink(missing_ok=True)
    if actual == expected:
        return
    actual_path.write_text(actual)
    diff = "\n".join(
        difflib.unified_diff(
            expected.splitlines(),
            actual.splitlines(),
            fromfile=str(golden_path),
            tofile=str(actual_path),
            lineterm="",
        )
    )
    testcase.fail(
        f"golden mismatch: {golden_path}\n{diff}\n"
        f"Update intentionally with UPDATE_GOLDENS=1 uv run python3 -m unittest Controller.tests.test_controller_conformance "
        f"then review git diff {golden_path.parent}"
    )


def benchmark_payload() -> dict[str, object]:
    return {
        "running": False,
        "pid": None,
        "log_path": str(ROOT / "run" / "logs" / "benchmark.log"),
        "latest": None,
    }


def status_payload() -> dict[str, object]:
    return {
        "statuses": [],
        "benchmark": benchmark_payload(),
        "integrations": [],
        "profiles_dir": str(ROOT / "model-profiles"),
        "controller_root": str(ROOT),
    }


def integration_payload() -> list[dict[str, object]]:
    return [
        {
            "id": "droid",
            "display_name": "Factory Droid",
            "kind": "optional",
            "capabilities": ["sync"],
            "sync_label": "Sync",
            "description": "Sync local model profiles into Factory Droid.",
        }
    ]


def value_at(payload: Any, path: str) -> Any:
    value = payload
    for part in path.split("."):
        value = value[part]
    return value


def arrange_case(case: dict[str, Any]) -> tuple[contextlib.ExitStack, dict[str, mock.Mock]]:
    stack = contextlib.ExitStack()
    mocks: dict[str, mock.Mock] = {}
    arrange = case.get("arrange", "none")
    if arrange == "none":
        return stack, mocks
    if arrange in {"status_ok", "start_profile_ok", "stop_all_ok", "integration_run", "benchmark_start"}:
        mocks["status_payload"] = stack.enter_context(mock.patch.object(MODULE, "status_payload", return_value=status_payload()))
        mocks["write_status_cache"] = stack.enter_context(mock.patch.object(MODULE, "write_status_cache"))
    if arrange == "status_ok":
        return stack, mocks
    if arrange == "integrations_ok":
        mocks["integration_status"] = stack.enter_context(mock.patch.object(MODULE, "integration_status", return_value=integration_payload()))
        return stack, mocks
    if arrange == "start_profile_ok":
        mocks["start_profile"] = stack.enter_context(mock.patch.object(MODULE, "start_profile"))
        return stack, mocks
    if arrange == "stop_all_ok":
        mocks["stop_all"] = stack.enter_context(mock.patch.object(MODULE, "stop_all"))
        return stack, mocks
    if arrange == "unknown_profile":
        mocks["start_profile"] = stack.enter_context(
            mock.patch.object(MODULE, "start_profile", side_effect=SystemExit("Unknown profile: missing-profile"))
        )
        return stack, mocks
    if arrange == "profile_conflict":
        mocks["switch_profile"] = stack.enter_context(
            mock.patch.object(MODULE, "switch_profile", side_effect=MODULE.ProfileConflictError("endpoint conflict"))
        )
        return stack, mocks
    if arrange == "integration_run":
        mocks["run_integration_action"] = stack.enter_context(mock.patch.object(MODULE, "run_integration_action"))
        return stack, mocks
    if arrange == "benchmark_start":
        mocks["start_benchmark"] = stack.enter_context(mock.patch.object(MODULE, "start_benchmark", return_value=benchmark_payload()))
        return stack, mocks
    raise AssertionError(f"unknown conformance arrangement: {arrange}")


def assert_expected_calls(testcase: unittest.TestCase, case: dict[str, Any], mocks: dict[str, mock.Mock]) -> None:
    arrange = case.get("arrange", "none")
    if arrange == "start_profile_ok":
        mocks["start_profile"].assert_called_once_with("qwen35-a3b")
    elif arrange == "stop_all_ok":
        if case["expected"]["status"] == 200:
            mocks["stop_all"].assert_called_once_with()
        else:
            mocks["stop_all"].assert_not_called()
    elif arrange == "unknown_profile":
        mocks["start_profile"].assert_called_once_with("missing-profile")
    elif arrange == "profile_conflict":
        mocks["switch_profile"].assert_called_once_with("qwen35-a3b")
    elif arrange == "integration_run":
        mocks["run_integration_action"].assert_called_once_with("droid", "sync")
    elif arrange == "benchmark_start":
        mocks["start_benchmark"].assert_called_once_with(
            ["qwen35-a3b"],
            suite="quick",
            allow_concurrent=True,
            keep_running=False,
        )
    testcase.assertNotIn("skip", case, "conformance cases must use XFAIL metadata, not skip")


def send_request(server: http.server.HTTPServer, request: dict[str, Any]) -> tuple[int, dict[str, str], bytes]:
    body = None
    headers = dict(request.get("headers", {}))
    if "json" in request:
        body = json.dumps(request["json"]).encode()
        headers.setdefault("Content-Type", "application/json")
    elif "raw_body" in request:
        body = str(request["raw_body"]).encode()
    connection = http.client.HTTPConnection("127.0.0.1", server.server_port, timeout=2)
    try:
        connection.putrequest(request["method"], request["path"])
        for key, value in headers.items():
            if key.lower() != "content-length":
                connection.putheader(key, str(value))
        if "content_length" in request:
            connection.putheader("Content-Length", str(request["content_length"]))
        elif body is not None:
            connection.putheader("Content-Length", str(len(body)))
        connection.endheaders()
        if body is not None:
            connection.send(body)
        response = connection.getresponse()
        raw = response.read()
        return response.status, dict(response.getheaders()), raw
    finally:
        connection.close()


def generate_report(cases: list[dict[str, Any]]) -> str:
    sections: dict[str, dict[str, int]] = {}
    for case in cases:
        stats = sections.setdefault(case["section"], {"must": 0, "should": 0, "tested": 0, "passing": 0, "divergent": 0})
        level = case["level"].lower()
        if level == "must":
            stats["must"] += 1
        elif level == "should":
            stats["should"] += 1
        stats["tested"] += 1
        stats["passing"] += 1
    lines = [
        "# Controller API Conformance Report",
        "",
        f"Specification source: {SPEC_SOURCE}",
        "",
        "| Section | MUST | SHOULD | Tested | Passing | Divergent | Score |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    must_total = 0
    must_passing = 0
    for section in sorted(sections):
        stats = sections[section]
        must_total += stats["must"]
        must_passing += stats["must"]
        score = (stats["passing"] / stats["tested"]) * 100
        lines.append(
            f"| {section} | {stats['must']}/{stats['must']} | {stats['should']}/{stats['should']} | "
            f"{stats['tested']} | {stats['passing']} | {stats['divergent']} | {score:.1f}% |"
        )
    lines.extend(["", f"MUST score: {must_passing}/{must_total}.", ""])
    return "\n".join(lines)


class ControllerAPIConformanceTests(unittest.TestCase):
    def run_case(self, case: dict[str, Any]) -> None:
        server = MODULE.ThreadingHTTPServer(("127.0.0.1", 0), MODULE.DashboardHandler)
        if token := case.get("server_auth_token"):
            server.auth_token = token
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        stack, mocks = arrange_case(case)
        try:
            with stack:
                status, headers, raw_body = send_request(server, case["request"])
                self.assertEqual(status, case["expected"]["status"], case["id"])
                content_type = headers.get("Content-Type", "")
                parsed = None
                if "application/json" in content_type:
                    parsed = json.loads(raw_body.decode())
                expected = case["expected"]
                if "body_contains" in expected:
                    self.assertIn(expected["body_contains"], raw_body.decode())
                for path, expected_value in expected.get("json_path_equals", {}).items():
                    self.assertIsNotNone(parsed, case["id"])
                    self.assertEqual(value_at(parsed, path), expected_value, case["id"])
                type_map = {"list": list, "dict": dict, "str": str, "bool": bool}
                for path, expected_type in expected.get("json_path_types", {}).items():
                    self.assertIsNotNone(parsed, case["id"])
                    self.assertIsInstance(value_at(parsed, path), type_map[expected_type], case["id"])
                for path, suffix in expected.get("json_path_suffix", {}).items():
                    self.assertIsNotNone(parsed, case["id"])
                    self.assertTrue(str(value_at(parsed, path)).endswith(suffix), case["id"])
                assert_expected_calls(self, case, mocks)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_controller_api_conformance_cases(self) -> None:
        for case in load_cases():
            with self.subTest(case=case["id"]):
                self.assertIn(case["level"], {"MUST", "SHOULD", "MAY"})
                self.run_case(case)

    def test_controller_api_compliance_report_is_current(self) -> None:
        assert_golden(self, REPORT_PATH, generate_report(load_cases()))


if __name__ == "__main__":
    unittest.main()

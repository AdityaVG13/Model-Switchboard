from __future__ import annotations

import importlib.util
import io
import json
import random
import re
import string
import sys
import tempfile
import unittest
import urllib.parse
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
MODULE_PATH = ROOT / "modelctl.py"
SPEC = importlib.util.spec_from_file_location("modelctl", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
PROFILE_ENV_PATH = ROOT / "profile_env.py"
PROFILE_ENV_SPEC = importlib.util.spec_from_file_location("profile_env_fuzz", PROFILE_ENV_PATH)
assert PROFILE_ENV_SPEC and PROFILE_ENV_SPEC.loader
PROFILE_ENV = importlib.util.module_from_spec(PROFILE_ENV_SPEC)
PROFILE_ENV_SPEC.loader.exec_module(PROFILE_ENV)

FUZZ_SEED = 0x5EED_2026
KEY_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
FUZZ_DIR = Path(__file__).with_name("fuzz")


def valid_key(rng: random.Random) -> str:
    first = rng.choice(string.ascii_letters + "_")
    rest = "".join(rng.choice(string.ascii_letters + string.digits + "_") for _ in range(rng.randrange(0, 24)))
    return f"{first}{rest}"


def maybe_key(rng: random.Random) -> str:
    if rng.random() < 0.75:
        return valid_key(rng)
    return rng.choice(
        [
            "",
            "1BAD",
            "BAD-KEY",
            "BAD.KEY",
            "BAD KEY",
            "BAD/KEY",
            "export",
            "NAME[]",
            "$NAME",
        ]
    )


def env_value(rng: random.Random, marker: Path) -> str:
    interesting = [
        "",
        "plain",
        "value with spaces",
        "http://127.0.0.1:8080/v1",
        "https://localhost:9443/v1/models",
        "file:///etc/passwd",
        f"$(touch {marker})",
        f"`touch {marker}`",
        f"; touch {marker}",
        "${HOME}/models/model.gguf",
        "#not-a-comment-when-quoted",
        "value # inline comment",
        "[]",
        '{"data":[{"id":"model"}]}',
        "127.0.0.1",
        "::1",
        "0.0.0.0",
    ]
    if rng.random() < 0.65:
        return rng.choice(interesting)
    alphabet = string.ascii_letters + string.digits + " _./:-[]{}$`()'\"#;,&?=%\t"
    return "".join(rng.choice(alphabet) for _ in range(rng.randrange(0, 80)))


def env_assignment_value(rng: random.Random, marker: Path) -> str:
    value = env_value(rng, marker)
    style = rng.choice(["raw", "single", "double", "broken_single", "broken_double"])
    if style == "single":
        return "'" + value.replace("'", "'\"'\"'") + "'"
    if style == "double":
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if style == "broken_single":
        return "'" + value
    if style == "broken_double":
        return '"' + value
    return value


def env_profile_text(rng: random.Random, marker: Path) -> str:
    shell_statements = [
        "source ~/.zshrc",
        "unset MODEL_PATH",
        f"touch {marker}",
        "alias ll='ls -la'",
        "if true; then echo no; fi",
    ]
    lines: list[str] = []
    for _ in range(rng.randrange(1, 18)):
        line_type = rng.choice(["assignment", "assignment", "assignment", "comment", "blank", "shell"])
        if line_type == "comment":
            lines.append("# " + env_value(rng, marker))
            continue
        if line_type == "blank":
            lines.append(" " * rng.randrange(0, 4))
            continue
        if line_type == "shell":
            lines.append(rng.choice(shell_statements))
            continue
        prefix = "export " if rng.random() < 0.35 else ""
        spacing = " " * rng.randrange(0, 3)
        lines.append(f"{prefix}{spacing}{maybe_key(rng)}{spacing}={spacing}{env_assignment_value(rng, marker)}")
    return "\n".join(lines) + "\n"


def json_value(rng: random.Random, depth: int = 0) -> object:
    if depth >= 2:
        return rng.choice([None, True, False, rng.randrange(-1000, 1000), env_value(rng, Path("/tmp/noop"))])
    kind = rng.choice(["none", "bool", "int", "str", "list", "dict"])
    if kind == "none":
        return None
    if kind == "bool":
        return rng.choice([True, False])
    if kind == "int":
        return rng.randrange(-100000, 100000)
    if kind == "str":
        return env_value(rng, Path("/tmp/noop"))
    if kind == "list":
        return [json_value(rng, depth + 1) for _ in range(rng.randrange(0, 5))]
    return {valid_key(rng): json_value(rng, depth + 1) for _ in range(rng.randrange(0, 5))}


def expected_json_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (list, dict)):
        return json.dumps(value)
    return str(value)


def json_profile_payload(rng: random.Random) -> tuple[str, dict[str, object] | None]:
    if rng.random() < 0.15:
        return rng.choice(["", "{", "[1, 2", '{"BAD-KEY":']), None
    if rng.random() < 0.18:
        raw_non_object = rng.choice([None, True, False, 42, "profile", [1, 2, 3]])
        return json.dumps(raw_non_object), None
    raw: dict[str, object] = {}
    for _ in range(rng.randrange(1, 14)):
        raw[maybe_key(rng)] = json_value(rng)
    return json.dumps(raw), raw


def url_candidate(rng: random.Random) -> str:
    scheme = rng.choice(["http", "https", "HTTP", "HTTPS", "file", "ftp", "gopher", "javascript", ""])
    if scheme == "javascript":
        return "javascript:alert(1)"
    if not scheme:
        return rng.choice(["", "localhost:8080", "//127.0.0.1:8080/v1", "/tmp/model", "model"])
    netloc = rng.choice(
        [
            "",
            "127.0.0.1",
            "localhost",
            "0.0.0.0",
            "[::1]",
            "example.com",
            "user:pass@example.com",
            "bad host",
        ]
    )
    port = rng.choice(["", ":80", ":8080", ":65536", ":bad"])
    path = rng.choice(["", "/", "/v1", "/v1/models", "/with space", "/%2fetc%2fpasswd"])
    return f"{scheme}://{netloc}{port}{path}"


def is_http_url(value: str) -> bool:
    parsed = urllib.parse.urlparse(value.strip())
    return parsed.scheme.lower() in {"http", "https"} and bool(parsed.netloc)


def request_body_case(rng: random.Random) -> tuple[bytes, str]:
    if rng.random() < 0.12:
        return b"\xff\xfe\xfa", "3"
    if rng.random() < 0.12:
        return rng.choice([b"", b"{", b"[1, 2", b"not-json"]), str(rng.randrange(0, 8))
    if rng.random() < 0.12:
        body = json.dumps(rng.choice([None, True, False, 1, "x", ["profile"]])).encode()
    else:
        raw: dict[str, object] = {}
        for key in [
            "profile",
            "profiles",
            "integration",
            "action",
            "suite",
            "allow_concurrent",
            "keep_running",
            "ignored",
        ]:
            if rng.random() < 0.6:
                if key == "profiles":
                    raw[key] = rng.choice(
                        [
                            [env_value(rng, Path("/tmp/noop")) for _ in range(rng.randrange(0, 5))],
                            [env_value(rng, Path("/tmp/noop")), 1],
                            "not-a-list",
                        ]
                    )
                elif key in {"allow_concurrent", "keep_running"}:
                    raw[key] = rng.choice([True, False, "true", 1, None])
                else:
                    raw[key] = rng.choice([env_value(rng, Path("/tmp/noop")), 1, None, [], {}])
        body = json.dumps(raw).encode("utf-8")
    length = rng.choice(
        [
            str(len(body)),
            str(max(0, len(body) - rng.randrange(0, min(len(body), 5) + 1))),
            str(len(body) + rng.randrange(1, 5)),
            "invalid",
            "-1",
            str(MODULE.MAX_JSON_BODY_BYTES + 1),
        ]
    )
    return body, length


def read_json_request(body: bytes, content_length: str) -> dict[str, object]:
    handler = object.__new__(MODULE.DashboardHandler)
    handler.headers = {"Content-Length": content_length}
    handler.rfile = io.BytesIO(body)
    return MODULE.DashboardHandler._read_json(handler)


class ProfileFuzzingTests(unittest.TestCase):
    def assert_profile_env_shape(self, env: dict[str, str], profile_name: str) -> None:
        self.assertEqual(env["PROFILE_NAME"], profile_name)
        for key, value in env.items():
            self.assertRegex(key, KEY_PATTERN)
            self.assertIsInstance(value, str)

    def test_committed_seed_corpus_replays(self) -> None:
        for path in sorted((FUZZ_DIR / "corpus" / "profile_env").glob("*.env")):
            with self.subTest(path=path.name):
                if ".invalid." in path.name:
                    with self.assertRaises(MODULE.ProfileFormatError):
                        MODULE.load_env_profile(path)
                    continue
                self.assert_profile_env_shape(MODULE.load_env_profile(path), path.stem)
        for path in sorted((FUZZ_DIR / "corpus" / "profile_json").glob("*.json")):
            with self.subTest(path=path.name):
                if ".invalid." in path.name:
                    with self.assertRaises(MODULE.ProfileFormatError):
                        MODULE.load_json_profile(path)
                    continue
                self.assert_profile_env_shape(MODULE.load_json_profile(path), path.stem)

    def test_env_profile_parser_fuzz_cases_are_declarative(self) -> None:
        rng = random.Random(FUZZ_SEED)
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            for case in range(260):
                marker = tmp / f"executed-{case}"
                profile = tmp / f"env_case_{case}.env"
                profile.write_text(env_profile_text(rng, marker), encoding="utf-8")
                with self.subTest(seed=FUZZ_SEED, case=case):
                    try:
                        env = MODULE.load_env_profile(profile)
                    except MODULE.ProfileFormatError:
                        self.assertFalse(marker.exists())
                        continue
                    self.assertFalse(marker.exists())
                    self.assertEqual(env, MODULE.load_env_profile(profile))
                    self.assert_profile_env_shape(env, profile.stem)
                    for line in PROFILE_ENV.shell_exports(env).splitlines():
                        self.assertRegex(line, r"^export [A-Za-z_][A-Za-z0-9_]*=")

    def test_json_profile_parser_fuzz_cases_normalize_values(self) -> None:
        rng = random.Random(FUZZ_SEED ^ 0xA11CE)
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            for case in range(220):
                payload, raw = json_profile_payload(rng)
                profile = tmp / f"json_case_{case}.json"
                profile.write_text(payload, encoding="utf-8")
                with self.subTest(seed=FUZZ_SEED, case=case):
                    try:
                        env = MODULE.load_json_profile(profile)
                    except MODULE.ProfileFormatError:
                        continue
                    self.assertIsNotNone(raw)
                    assert raw is not None
                    self.assertEqual(env, MODULE.load_json_profile(profile))
                    self.assert_profile_env_shape(env, profile.stem)
                    for key, value in raw.items():
                        if key != "PROFILE_NAME":
                            self.assertEqual(env[key], expected_json_value(value))

    def test_profile_url_fuzz_cases_never_resolve_to_non_http_urls(self) -> None:
        rng = random.Random(FUZZ_SEED ^ 0xC0FFEE)
        for case in range(240):
            env: dict[str, str] = {}
            if rng.random() < 0.55:
                env["BASE_URL"] = url_candidate(rng)
            else:
                env["HOST"] = rng.choice(["127.0.0.1", "localhost", "0.0.0.0", "::1", "[::1]", "example.com"])
                env["PORT"] = rng.choice(["", "80", "8080", "bad", "65536"])
            if rng.random() < 0.35:
                env["MODEL_LIST_URL"] = url_candidate(rng)
            if rng.random() < 0.35:
                env["HEALTHCHECK_URL"] = url_candidate(rng)
            if rng.random() < 0.25:
                env["HEALTHCHECK_MODE"] = rng.choice(["openai-models", "http", "disabled", "custom"])

            with self.subTest(seed=FUZZ_SEED, case=case, env=env):
                for func in (MODULE.base_url, MODULE.models_url, MODULE.healthcheck_url):
                    try:
                        value = func(env)
                    except ValueError as exc:
                        self.assertIn("must use http or https", str(exc))
                        continue
                    if value:
                        parsed = urllib.parse.urlparse(value)
                        self.assertIn(parsed.scheme.lower(), {"http", "https"})
                        self.assertTrue(parsed.netloc)

    def test_fetch_openai_models_fuzz_cases_do_not_open_non_http_urls(self) -> None:
        rng = random.Random(FUZZ_SEED ^ 0xBAD5EED)
        candidates = [url_candidate(rng) for _ in range(260)]
        with mock.patch.object(MODULE.urllib.request, "urlopen") as urlopen:
            for case, candidate in enumerate(candidates):
                if is_http_url(candidate):
                    continue
                with self.subTest(seed=FUZZ_SEED, case=case, url=candidate):
                    self.assertEqual(MODULE.fetch_openai_models(candidate), [])
            urlopen.assert_not_called()

    def test_dashboard_json_request_fuzz_cases_return_typed_requests(self) -> None:
        rng = random.Random(FUZZ_SEED ^ 0xDAD)
        allowed_keys = {"profile", "profiles", "integration", "action", "suite", "allow_concurrent", "keep_running"}
        for case in range(260):
            body, content_length = request_body_case(rng)
            with self.subTest(seed=FUZZ_SEED, case=case, content_length=content_length):
                try:
                    request = read_json_request(body, content_length)
                except MODULE.ControllerAPIError as exc:
                    self.assertIn(exc.status, {400, 413})
                    self.assertTrue(exc.code)
                    continue
                self.assertLessEqual(set(request), allowed_keys)
                for key in {"profile", "integration", "action", "suite"} & set(request):
                    self.assertIsInstance(request[key], str)
                if "profiles" in request:
                    self.assertIsInstance(request["profiles"], list)
                    self.assertTrue(request["profiles"])
                    self.assertTrue(all(isinstance(item, str) for item in request["profiles"]))
                for key in {"allow_concurrent", "keep_running"} & set(request):
                    self.assertIsInstance(request[key], bool)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import re
import shlex
import sys
from typing import Any


_KEY_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
ProfileEnv = dict[str, str]


class ProfileFormatError(ValueError):
    """Raised when a profile file is not declarative key/value data."""


def _location(path: pathlib.Path, line_number: int | None = None) -> str:
    if line_number is None:
        return str(path)
    return f"{path}:{line_number}"


def _validate_key(key: str, path: pathlib.Path, line_number: int | None = None) -> str:
    normalized = key.strip()
    if not _KEY_PATTERN.fullmatch(normalized):
        raise ProfileFormatError(
            f"{_location(path, line_number)}: invalid profile key {key!r}; "
            "expected an environment-style name like MODEL_PATH"
        )
    return normalized


def _json_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, (list, dict)):
        return json.dumps(value)
    return str(value)


def _strip_inline_comment(value: str) -> str:
    return re.sub(r"\s+#.*$", "", value).strip()


def _parse_env_value(raw_value: str, path: pathlib.Path, line_number: int) -> str:
    value = raw_value.strip()
    if not value:
        return ""
    if value[0] in {"'", '"'}:
        try:
            tokens = shlex.split(value, comments=True, posix=True)
        except ValueError as exc:
            raise ProfileFormatError(f"{_location(path, line_number)}: invalid quoted value: {exc}") from exc
        if len(tokens) != 1:
            raise ProfileFormatError(
                f"{_location(path, line_number)}: quoted values must resolve to exactly one value"
            )
        return tokens[0]
    return _strip_inline_comment(value)


def _parse_env_line(raw_line: str, path: pathlib.Path, line_number: int) -> tuple[str, str] | None:
    line = raw_line.strip()
    if not line or line.startswith("#"):
        return None
    if line.startswith("export "):
        line = line[len("export ") :].lstrip()
    if "=" not in line:
        raise ProfileFormatError(
            f"{_location(path, line_number)}: expected KEY=value; profile files are not shell scripts"
        )
    key, raw_value = line.split("=", 1)
    return _validate_key(key, path, line_number), _parse_env_value(raw_value, path, line_number)


def load_env_profile(path: pathlib.Path) -> ProfileEnv:
    env: ProfileEnv = {}
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        parsed = _parse_env_line(raw_line, path, line_number)
        if parsed is None:
            continue
        key, value = parsed
        env[key] = value
    env["PROFILE_NAME"] = path.stem
    return env


def load_json_profile(path: pathlib.Path) -> ProfileEnv:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ProfileFormatError(f"{path}: invalid JSON profile: {exc}") from exc
    if not isinstance(raw, dict):
        raise ProfileFormatError(f"Profile JSON must be an object: {path}")
    env: ProfileEnv = {}
    for key, value in raw.items():
        env[_validate_key(str(key), path)] = _json_value(value)
    env["PROFILE_NAME"] = path.stem
    return env


def load_profile(path: pathlib.Path) -> ProfileEnv:
    if path.suffix == ".json":
        return load_json_profile(path)
    return load_env_profile(path)


def shell_exports(env: ProfileEnv) -> str:
    return "\n".join(f"export {key}={shlex.quote(value)}" for key, value in env.items())


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("usage: profile_env.py <profile.env|profile.json>", file=sys.stderr)
        return 2
    try:
        print(shell_exports(load_profile(pathlib.Path(args[0]))))
    except (OSError, ProfileFormatError) as exc:
        print(f"profile_env.py: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

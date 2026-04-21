#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import re
import sys


SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
README_BADGE_RE = re.compile(r"version-(\d+\.\d+\.\d+)-blue")
PROJECT_VERSION_RE = re.compile(
    r"^(\s+)(MARKETING_VERSION|CURRENT_PROJECT_VERSION):\s+\d+\.\d+\.\d+$",
    re.MULTILINE,
)


def parse_version(raw: str) -> tuple[int, int, int]:
    match = SEMVER_RE.fullmatch(raw.strip())
    if not match:
        raise ValueError(f"invalid semantic version: {raw!r}")
    return tuple(int(part) for part in match.groups())


def render_version(parts: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in parts)


def next_version(current: str, target: str) -> str:
    major, minor, patch = parse_version(current)
    if target == "major":
        return render_version((major + 1, 0, 0))
    if target == "minor":
        return render_version((major, minor + 1, 0))
    if target == "patch":
        return render_version((major, minor, patch + 1))
    parse_version(target)
    return target


def replace_project_versions(text: str, version: str) -> str:
    def repl(match: re.Match[str]) -> str:
        indent, key = match.groups()
        return f"{indent}{key}: {version}"

    updated, count = PROJECT_VERSION_RE.subn(repl, text)
    if count < 2:
        raise ValueError("project.yml is missing MARKETING_VERSION or CURRENT_PROJECT_VERSION")
    return updated


def replace_readme_badge(text: str, version: str) -> str:
    updated, count = README_BADGE_RE.subn(f"version-{version}-blue", text, count=1)
    if count != 1:
        raise ValueError("README.md version badge not found")
    return updated


def insert_changelog_entry(text: str, version: str, entry_date: str) -> str:
    header = f"## [{version}]"
    if header in text:
        raise ValueError(f"CHANGELOG.md already contains {header}")

    entry = (
        f"{header} - {entry_date}\n\n"
        "### Added\n"
        "- TBD\n\n"
        "### Changed\n"
        "- TBD\n\n"
        "### Fixed\n"
        "- TBD\n\n"
    )

    first_entry = text.find("\n## [")
    if first_entry == -1:
        return text.rstrip() + "\n\n" + entry
    return text[: first_entry + 1] + entry + text[first_entry + 1 :]


def write_text(path: pathlib.Path, contents: str) -> None:
    path.write_text(contents, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Bump Model Switchboard release version")
    parser.add_argument("target", help="patch, minor, major, or an explicit x.y.z version")
    parser.add_argument("--date", default=dt.date.today().isoformat(), help="changelog entry date (YYYY-MM-DD)")
    parser.add_argument(
        "--root",
        default=str(pathlib.Path(__file__).resolve().parents[1]),
        help="repository root to update",
    )
    args = parser.parse_args()

    try:
        dt.date.fromisoformat(args.date)
    except ValueError as exc:
        raise SystemExit(f"invalid --date value: {args.date}") from exc

    root = pathlib.Path(args.root).resolve()
    version_path = root / "VERSION"
    project_path = root / "project.yml"
    readme_path = root / "README.md"
    changelog_path = root / "CHANGELOG.md"

    for path in (version_path, project_path, readme_path, changelog_path):
        if not path.is_file():
            raise SystemExit(f"missing required file: {path}")

    current_version = version_path.read_text(encoding="utf-8").strip()
    try:
        new_version = next_version(current_version, args.target)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    project_text = project_path.read_text(encoding="utf-8")
    readme_text = readme_path.read_text(encoding="utf-8")
    changelog_text = changelog_path.read_text(encoding="utf-8")

    try:
        updated_project = replace_project_versions(project_text, new_version)
        updated_readme = replace_readme_badge(readme_text, new_version)
        updated_changelog = insert_changelog_entry(changelog_text, new_version, args.date)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc

    write_text(version_path, f"{new_version}\n")
    write_text(project_path, updated_project)
    write_text(readme_path, updated_readme)
    write_text(changelog_path, updated_changelog)

    print(f"old_version={current_version}")
    print(f"new_version={new_version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

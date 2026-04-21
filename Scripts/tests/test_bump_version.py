from __future__ import annotations

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts" / "bump-version.py"


def write_fixture_repo(root: Path) -> None:
    (root / "VERSION").write_text("1.0.4\n", encoding="utf-8")
    (root / "project.yml").write_text(
        textwrap.dedent(
            """\
            settings:
              base:
                MARKETING_VERSION: 1.0.4
                CURRENT_PROJECT_VERSION: 1.0.4
            """
        ),
        encoding="utf-8",
    )
    (root / "README.md").write_text(
        "[![Version](https://img.shields.io/badge/version-1.0.4-blue?style=for-the-badge)](VERSION)\n",
        encoding="utf-8",
    )
    (root / "CHANGELOG.md").write_text(
        textwrap.dedent(
            """\
            # Changelog

            All notable changes to this project are documented in this file.

            ## [1.0.4] - 2026-04-20

            ### Fixed
            - Existing entry.
            """
        ),
        encoding="utf-8",
    )


class BumpVersionTests(unittest.TestCase):
    def test_patch_bump_updates_repo_files_and_scaffolds_changelog(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir)
            write_fixture_repo(repo)

            result = subprocess.run(
                ["python3", str(SCRIPT), "patch", "--date", "2026-04-21", "--root", str(repo)],
                text=True,
                capture_output=True,
                check=True,
            )

            self.assertIn("old_version=1.0.4", result.stdout)
            self.assertIn("new_version=1.0.5", result.stdout)
            self.assertEqual((repo / "VERSION").read_text(encoding="utf-8").strip(), "1.0.5")
            self.assertIn("MARKETING_VERSION: 1.0.5", (repo / "project.yml").read_text(encoding="utf-8"))
            self.assertIn("CURRENT_PROJECT_VERSION: 1.0.5", (repo / "project.yml").read_text(encoding="utf-8"))
            self.assertIn("version-1.0.5-blue", (repo / "README.md").read_text(encoding="utf-8"))
            changelog = (repo / "CHANGELOG.md").read_text(encoding="utf-8")
            self.assertIn("## [1.0.5] - 2026-04-21", changelog)
            self.assertIn("### Added\n- TBD", changelog)
            self.assertIn("## [1.0.4] - 2026-04-20", changelog)

    def test_explicit_version_refuses_duplicate_changelog_entry(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir)
            write_fixture_repo(repo)

            result = subprocess.run(
                ["python3", str(SCRIPT), "1.0.4", "--root", str(repo)],
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("CHANGELOG.md already contains ## [1.0.4]", result.stderr)


if __name__ == "__main__":
    unittest.main()

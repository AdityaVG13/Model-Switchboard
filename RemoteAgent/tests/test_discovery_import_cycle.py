"""discovery.py must not import the agent (the old sys.modules alias cycle)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

AGENT_DIR = Path(__file__).resolve().parents[1]
if str(AGENT_DIR) not in sys.path:
    sys.path.insert(0, str(AGENT_DIR))


class DiscoveryImportCycleTests(unittest.TestCase):
    def test_discovery_source_does_not_import_the_agent(self) -> None:
        source = (AGENT_DIR / "discovery.py").read_text(encoding="utf-8")
        self.assertNotIn("from model_switchboard_agent", source)
        self.assertNotIn("import model_switchboard_agent", source)
        self.assertIn("from agent_core import", source)

    def test_importing_discovery_does_not_load_the_agent(self) -> None:
        for name in ("discovery", "agent_core", "model_switchboard_agent"):
            sys.modules.pop(name, None)
        import discovery  # noqa: F401

        self.assertIn("agent_core", sys.modules)
        self.assertNotIn("model_switchboard_agent", sys.modules)

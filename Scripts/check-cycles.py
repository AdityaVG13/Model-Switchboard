#!/usr/bin/env python3
from __future__ import annotations

import ast
import json
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]


def tarjan_cycles(graph: dict[str, set[str]]) -> list[list[str]]:
    index = 0
    indices: dict[str, int] = {}
    lowlink: dict[str, int] = {}
    stack: list[str] = []
    on_stack: set[str] = set()
    sccs: list[list[str]] = []

    def strongconnect(node: str) -> None:
        nonlocal index
        indices[node] = index
        lowlink[node] = index
        index += 1
        stack.append(node)
        on_stack.add(node)

        for neighbor in graph.get(node, set()):
            if neighbor not in indices:
                strongconnect(neighbor)
                lowlink[node] = min(lowlink[node], lowlink[neighbor])
            elif neighbor in on_stack:
                lowlink[node] = min(lowlink[node], indices[neighbor])

        if lowlink[node] == indices[node]:
            component: list[str] = []
            while stack:
                popped = stack.pop()
                on_stack.remove(popped)
                component.append(popped)
                if popped == node:
                    break
            sccs.append(component)

    for node in sorted(graph):
        if node not in indices:
            strongconnect(node)

    cycles = [sorted(comp) for comp in sccs if len(comp) > 1]
    for node, neighbors in graph.items():
        if node in neighbors:
            cycles.append([node])

    return sorted(cycles, key=lambda c: (len(c), c))


def parse_spm_target_graph() -> dict[str, set[str]]:
    cmd = ["swift", "package", "describe", "--type", "json"]
    proc = subprocess.run(
        cmd,
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    data = json.loads(proc.stdout)
    graph: dict[str, set[str]] = {}

    target_names = {target["name"] for target in data.get("targets", [])}
    for target in data.get("targets", []):
        name = target["name"]
        deps = {
            dep for dep in target.get("target_dependencies", []) if dep in target_names
        }
        graph[name] = deps

    return graph


def parse_xcode_target_graph() -> dict[str, set[str]]:
    project_yml = ROOT / "project.yml"
    lines = project_yml.read_text().splitlines()

    graph: dict[str, set[str]] = {}
    in_targets = False
    current_target: str | None = None
    in_dependencies = False

    target_decl = re.compile(r"^  ([A-Za-z0-9_+.-]+):\s*$")
    target_dep = re.compile(r"^      - target:\s*([A-Za-z0-9_+.-]+)\s*$")

    for line in lines:
        if line.startswith("targets:"):
            in_targets = True
            continue

        if in_targets and re.match(r"^[A-Za-z]", line):
            # Exited the top-level targets block.
            in_targets = False
            current_target = None
            in_dependencies = False

        if not in_targets:
            continue

        target_match = target_decl.match(line)
        if target_match:
            current_target = target_match.group(1)
            graph.setdefault(current_target, set())
            in_dependencies = False
            continue

        if current_target is None:
            continue

        if line.startswith("    dependencies:"):
            in_dependencies = True
            continue

        if in_dependencies:
            # End dependency parsing when sibling target keys resume.
            if line.startswith("    ") and not line.startswith("      ") and line.strip():
                in_dependencies = False

        if in_dependencies:
            dep_match = target_dep.match(line)
            if dep_match:
                graph[current_target].add(dep_match.group(1))

    # Keep only known local targets.
    known = set(graph)
    return {name: {d for d in deps if d in known} for name, deps in graph.items()}


def parse_swift_module_graph() -> dict[str, set[str]]:
    sources_root = ROOT / "Sources"
    modules = {p.name for p in sources_root.iterdir() if p.is_dir()}
    graph: dict[str, set[str]] = {module: set() for module in modules}

    import_re = re.compile(r"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*)")

    for module in modules:
        module_dir = sources_root / module
        for swift_file in module_dir.rglob("*.swift"):
            for line in swift_file.read_text().splitlines():
                match = import_re.match(line)
                if not match:
                    continue
                imported = match.group(1)
                if imported in modules and imported != module:
                    graph[module].add(imported)

    return graph


def parse_python_module_graph() -> dict[str, set[str]]:
    controller_dir = ROOT / "Controller"
    modules = {path.stem: path for path in controller_dir.glob("*.py")}
    graph: dict[str, set[str]] = {name: set() for name in modules}

    for module, path in modules.items():
        tree = ast.parse(path.read_text(), filename=str(path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    top = alias.name.split(".")[0]
                    if top in modules and top != module:
                        graph[module].add(top)
            elif isinstance(node, ast.ImportFrom):
                if not node.module:
                    continue
                top = node.module.split(".")[0]
                if top in modules and top != module:
                    graph[module].add(top)

    return graph


def print_graph(title: str, graph: dict[str, set[str]]) -> None:
    print(f"\n{title}")
    for node in sorted(graph):
        neighbors = ", ".join(sorted(graph[node])) or "(none)"
        print(f"  {node} -> {neighbors}")


def ensure_acyclic(name: str, graph: dict[str, set[str]]) -> bool:
    cycles = tarjan_cycles(graph)
    if cycles:
        print(f"\n{name}: CYCLES DETECTED")
        for cyc in cycles:
            print(f"  cycle: {' -> '.join(cyc)}")
        return False

    print(f"\n{name}: no cycles")
    return True


def main() -> int:
    graphs: list[tuple[str, dict[str, set[str]]]] = [
        ("Swift module import graph", parse_swift_module_graph()),
        ("Swift SPM target dependency graph", parse_spm_target_graph()),
        ("Swift Xcode target dependency graph", parse_xcode_target_graph()),
        ("Python controller module import graph", parse_python_module_graph()),
    ]

    ok = True
    for label, graph in graphs:
        print_graph(label, graph)
        ok = ensure_acyclic(label, graph) and ok

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

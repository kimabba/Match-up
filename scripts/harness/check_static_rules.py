#!/usr/bin/env python3
"""Cheap repository rules that prevent harness/rule drift."""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ROOT_RULE_LIMITS = {
    "AGENTS.md": 100,
    "CLAUDE.md": 80,
}

REQUIRED_RULE_DOCS = [
    "docs/rules/README.md",
    "docs/rules/PROJECT_CONTEXT.md",
    "docs/rules/CODING_RULES.md",
    "docs/rules/DOMAIN_RULES.md",
    "docs/rules/FRONTEND_RULES.md",
    "docs/rules/BACKEND_RULES.md",
    "docs/rules/DATABASE_RULES.md",
    "docs/rules/SECURITY_RULES.md",
    "docs/rules/SPEED_GUN_RULES.md",
    "docs/rules/HARNESS.md",
]

FORBIDDEN_ROOT_HEADINGS = [
    "## Project Overview",
    "## Tech Stack",
    "## Architecture",
    "## Environment Variables",
    "## Operational Notes",
]


def fail(message: str) -> None:
    print(f"❌ {message}", file=sys.stderr)
    raise SystemExit(1)


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        fail(f"missing required file: {relative}")
    return path.read_text(encoding="utf-8")


def check_root_file_lengths() -> None:
    for relative, limit in ROOT_RULE_LIMITS.items():
        text = read(relative)
        lines = text.splitlines()
        if len(lines) > limit:
            fail(f"{relative} is {len(lines)} lines; keep it <= {limit} lines and move detail into docs/rules/")
        for heading in FORBIDDEN_ROOT_HEADINGS:
            if heading in text:
                fail(f"{relative} contains long-form heading {heading!r}; move this content into docs/rules/")
        print(f"✓ {relative}: {len(lines)} lines <= {limit}")


def check_required_rule_docs() -> None:
    for relative in REQUIRED_RULE_DOCS:
        read(relative)
    print(f"✓ required rule docs present: {len(REQUIRED_RULE_DOCS)}")


def check_agents_rule_links() -> None:
    agents = read("AGENTS.md")
    missing = [relative for relative in REQUIRED_RULE_DOCS[1:] if f"`{relative}`" not in agents]
    if missing:
        fail("AGENTS.md load-on-demand map is missing: " + ", ".join(missing))
    print("✓ AGENTS.md references load-on-demand rule docs")


def check_github_templates() -> None:
    required = [
        ".github/pull_request_template.md",
        ".github/ISSUE_TEMPLATE/bug_report.yml",
        ".github/ISSUE_TEMPLATE/feature_task.yml",
        ".github/ISSUE_TEMPLATE/harness_task.yml",
        ".github/workflows/harness.yml",
    ]
    for relative in required:
        read(relative)
    print(f"✓ GitHub collaboration files present: {len(required)}")


def check_no_shell_background_wrappers_in_harness() -> None:
    run_all = read("scripts/harness/run_all.sh")
    if re.search(r"\b(nohup|disown|setsid)\b", run_all):
        fail("scripts/harness/run_all.sh should stay foreground and CI-friendly")
    print("✓ harness script is foreground/CI-friendly")


def main() -> int:
    check_root_file_lengths()
    check_required_rule_docs()
    check_agents_rule_links()
    check_github_templates()
    check_no_shell_background_wrappers_in_harness()
    print("✅ static repository rules passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

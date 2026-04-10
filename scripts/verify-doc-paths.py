#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Verify repo paths cited in navigation docs (deterministic, v1).

Allowlisted sources:
  - docs/DEVELOPER_MAP.md
  - docs/agent-stubs/*.md

Extracts each backtick-wrapped segment. Resolves to a filesystem path when the
segment matches one of the rules below; otherwise the segment is skipped (e.g.
~/.osaurus, bare filenames like ToolRegistry.swift, prose).

Rules:
  - Starts with Packages/  -> repo root
  - Starts with App/ or equals App -> repo root
  - Equals osaurus.xcworkspace -> repo root
  - Starts with a known OsaurusCore top-level dir -> Packages/OsaurusCore/<segment>

See docs/superpowers/specs/2026-04-11-doc-integrity-automation-design.md
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

ALLOWLIST_FILES = [REPO / "docs" / "DEVELOPER_MAP.md"]
_STUB_DIR = REPO / "docs" / "agent-stubs"
if _STUB_DIR.is_dir():
    ALLOWLIST_FILES.extend(sorted(_STUB_DIR.glob("*.md")))

# OsaurusCore immediate children that appear in stubs/map as repo-relative segments.
_CORE_TOP_LEVEL = (
    "Services",
    "Tools",
    "Managers",
    "Models",
    "Storage",
    "Identity",
    "Work",
    "Networking",
    "Views",
    "Utils",
)

_CORE_PREFIX = re.compile(rf"^({'|'.join(_CORE_TOP_LEVEL)})(/|$)")


def _iter_backtick_segments(text: str):
    for m in re.finditer(r"`([^`]+)`", text):
        yield m.group(1).strip()


def resolve_segment(seg: str) -> Path | None:
    s = seg.strip().rstrip("/")
    if not s or s.startswith("http") or s.startswith("~"):
        return None
    # Skip markdown link targets and obvious non-paths
    if " " in s or "\n" in s:
        return None
    if s.startswith("Packages/"):
        return REPO.joinpath(*s.split("/"))
    if s.startswith("App/") or s == "App":
        return REPO.joinpath(*s.split("/"))
    if s == "osaurus.xcworkspace":
        return REPO / s
    if _CORE_PREFIX.match(s):
        return REPO.joinpath("Packages", "OsaurusCore", *s.split("/"))
    return None


def main() -> int:
    errors: list[str] = []
    for fpath in ALLOWLIST_FILES:
        if not fpath.is_file():
            errors.append(f"Allowlisted file missing: {fpath.relative_to(REPO)}")
            continue
        text = fpath.read_text(encoding="utf-8")
        seen: set[str] = set()
        for seg in _iter_backtick_segments(text):
            if seg in seen:
                continue
            seen.add(seg)
            target = resolve_segment(seg)
            if target is None:
                continue
            if not target.exists():
                try:
                    rel = target.relative_to(REPO)
                except ValueError:
                    rel = target
                errors.append(f"{fpath.relative_to(REPO)}: missing `{seg}` -> {rel}")

    if errors:
        print("verify-doc-paths: failed:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1
    print("verify-doc-paths: OK", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

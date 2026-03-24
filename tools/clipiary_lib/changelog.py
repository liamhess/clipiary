from __future__ import annotations

import re
from datetime import date
from pathlib import Path

from .common import ToolError, write_text

CHANGELOG_FILE = "CHANGELOG.md"
UNRELEASED_HEADING = "## [Unreleased]"
VERSION_HEADING_RE = re.compile(r"^## \[(\d+\.\d+\.\d+)\]")


def _changelog_path(root: Path) -> Path:
    return root / CHANGELOG_FILE


def extract_version_notes(root: Path, version: str) -> str:
    """Return the release notes for *version* from CHANGELOG.md.

    Extracts everything between ``## [version]`` and the next ``## [`` heading
    (or end of file).  Raises ``ToolError`` when the section is missing or
    empty.
    """
    path = _changelog_path(root)
    if not path.exists():
        raise ToolError(f"{CHANGELOG_FILE} not found — create one with an [Unreleased] section")

    text = path.read_text(encoding="utf-8")
    pattern = re.compile(
        rf"^## \[{re.escape(version)}\].*?\n(.*?)(?=^## \[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        raise ToolError(f"No changelog section found for version {version}")

    notes = match.group(1).strip()
    if not notes:
        raise ToolError(f"Changelog section for version {version} is empty")

    return notes + "\n"


def stamp_release(root: Path, version: str, *, dry_run: bool = False) -> None:
    """Rename ``[Unreleased]`` to ``[version] - today`` and add a fresh ``[Unreleased]`` section."""
    path = _changelog_path(root)
    if not path.exists():
        raise ToolError(f"{CHANGELOG_FILE} not found — create one with an [Unreleased] section")

    text = path.read_text(encoding="utf-8")
    if UNRELEASED_HEADING not in text:
        raise ToolError(f"{CHANGELOG_FILE} has no {UNRELEASED_HEADING} section")

    today = date.today().isoformat()
    stamped_heading = f"## [{version}] - {today}"
    new_text = text.replace(
        UNRELEASED_HEADING,
        f"{UNRELEASED_HEADING}\n\n{stamped_heading}",
        1,
    )
    write_text(path, new_text, dry_run=dry_run)

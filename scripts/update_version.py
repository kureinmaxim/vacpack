#!/usr/bin/env python3
"""Keep Vacpack's version in sync across the repository.

Source of truth: project.yml (MARKETING_VERSION and VACPACK_RELEASE_DATE).

  python3 scripts/update_version.py status
  python3 scripts/update_version.py bump patch|minor|major [--release-date DD.MM.YYYY] [--dry-run]
  python3 scripts/update_version.py sync [X.Y.Z] [--release-date DD.MM.YYYY] [--dry-run]

Standard library only. See VERSION_MANAGEMENT.md.
"""

from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional, Tuple

ROOT = Path(__file__).resolve().parents[1]
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")
DATE_FORMAT = "%d.%m.%Y"

Found = Tuple[Optional[str], Optional[str]]  # (version, release date) found in a file


def parse_date(value: str) -> dt.date:
    return dt.datetime.strptime(value, DATE_FORMAT).date()


def iso(release_date: str) -> str:
    return parse_date(release_date).isoformat()


def replace_one(pattern: str, value: str, text: str, path: str) -> str:
    """Replaces exactly one match with its group 1 (the prefix to keep) followed by `value`.

    A missing line means the file was reformatted by hand.
    """
    new, count = re.subn(pattern, lambda match: match.group(1) + value, text, count=1, flags=re.MULTILINE)
    if count == 0:
        raise RuntimeError(f"Could not update {path}: no line matches {pattern!r}")
    return new


def first(pattern: str, text: str) -> Optional[str]:
    match = re.search(pattern, text, flags=re.MULTILINE)
    return match.group(1) if match else None


# MARK: Tracked files


def read_source(text: str, _expected: str) -> Found:
    return first(r'^\s*MARKETING_VERSION:\s*"([^"]*)"', text), first(r'^\s*VACPACK_RELEASE_DATE:\s*"([^"]*)"', text)


def write_source(text: str, version: str, date: str) -> str:
    path = "project.yml"
    text = replace_one(r'^(\s*MARKETING_VERSION:\s*)"[^"]*"', f'"{version}"', text, path)
    return replace_one(r'^(\s*VACPACK_RELEASE_DATE:\s*)"[^"]*"', f'"{date}"', text, path)


def read_kit(text: str, _expected: str) -> Found:
    return first(r'static let number = "([^"]*)"', text), first(r'static let releaseDate = "([^"]*)"', text)


def write_kit(text: str, version: str, date: str) -> str:
    path = "Version.swift"
    text = replace_one(r'(static let number = )"[^"]*"', f'"{version}"', text, path)
    return replace_one(r'(static let releaseDate = )"[^"]*"', f'"{date}"', text, path)


def read_readme(text: str, _expected: str) -> Found:
    match = re.search(r"^\*\*Version:\*\* `([^`]+)`, released (\S+?) ·", text, flags=re.MULTILINE)
    return (match.group(1), match.group(2)) if match else (None, None)


def write_readme(text: str, version: str, date: str) -> str:
    line = f"`{version}`, released {date} · [changelog](CHANGELOG.md) · [how versions are managed](VERSION_MANAGEMENT.md)"
    return replace_one(r"^(\*\*Version:\*\* ).*$", line, text, "README.md")


def read_changelog(text: str, expected: str) -> Found:
    date = first(rf"^## \[{re.escape(expected)}\] - (\d{{4}}-\d{{2}}-\d{{2}})$", text)
    if date is None:
        return None, None
    return expected, dt.date.fromisoformat(date).strftime(DATE_FORMAT)


def write_changelog(text: str, version: str, date: str) -> str:
    heading = rf"^(## )\[{re.escape(version)}\] - .*$"
    if re.search(heading, text, flags=re.MULTILINE):
        return replace_one(heading, f"[{version}] - {iso(date)}", text, "CHANGELOG.md")
    # A new version takes the notes collected under Unreleased; a fresh Unreleased goes on top.
    return replace_one(r"^(## )\[Unreleased\]$", f"[Unreleased]\n\n## [{version}] - {iso(date)}", text, "CHANGELOG.md")


@dataclass
class Target:
    label: str
    path: str
    read: Callable[[str, str], Found]
    write: Callable[[str, str, str], str]

    @property
    def file(self) -> Path:
        return ROOT / self.path


SOURCE = Target("source", "project.yml", read_source, write_source)
TARGETS = [
    SOURCE,
    Target("kit", "Packages/CompressorKit/Sources/CompressorKit/Version.swift", read_kit, write_kit),
    Target("readme", "README.md", read_readme, write_readme),
    Target("changelog", "CHANGELOG.md", read_changelog, write_changelog),
]


# MARK: Commands


def source_version() -> Tuple[str, str]:
    version, date = SOURCE.read(SOURCE.file.read_text(encoding="utf-8"), "")
    if version is None or not SEMVER.match(version):
        raise SystemExit(f"project.yml: MARKETING_VERSION {version!r} is not MAJOR.MINOR.PATCH")
    if date is None:
        raise SystemExit("project.yml: VACPACK_RELEASE_DATE is missing")
    parse_date(date)
    return version, date


def bumped(version: str, level: str) -> str:
    major, minor, patch = (int(part) for part in version.split("."))
    if level == "major":
        return f"{major + 1}.0.0"
    if level == "minor":
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


def status() -> int:
    version, date = source_version()
    print(f"Source version:      {version}")
    print(f"Source release date: {date}\n")
    drifted = False
    width = max(len(target.path) for target in TARGETS)
    for target in TARGETS:
        if not target.file.exists():
            found, mark = (None, None), "MISSING FILE"
        else:
            found = target.read(target.file.read_text(encoding="utf-8"), version)
            mark = "OK" if found == (version, date) else ("MISSING" if found == (None, None) else "DIFF")
        drifted = drifted or mark != "OK"
        shown = f"{found[0] or '-'}  {found[1] or '-'}"
        print(f"{target.label:<10} {target.path:<{width}}  {shown:<22} {mark}")
    if drifted:
        print("\nOut of sync: run `python3 scripts/update_version.py sync` (keeps the source version and date).")
    return 1 if drifted else 0


def apply(version: str, date: str, dry_run: bool) -> int:
    print(f"Target version:      {version}")
    print(f"Target release date: {date}\n")
    is_new_version = version != source_version()[0]
    # Build every new file first, so a line that cannot be found leaves the repository untouched.
    changes = []
    for target in TARGETS:
        old = target.file.read_text(encoding="utf-8")
        new = target.write(old, version, date)
        if new != old:
            changes.append((target, new))
    for target, new in changes:
        if dry_run:
            print(f"Would update {target.path}")
        else:
            # Keep repository line endings stable when bumping a version on Windows too.
            with target.file.open("w", encoding="utf-8", newline="\n") as output:
                output.write(new)
            print(f"Updated {target.path}")
    if not changes:
        print("Everything is already in sync.")
    elif not dry_run and is_new_version:
        print("\nNext: write the notes under this version in CHANGELOG.md, run scripts/check.sh, commit.")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="update_version.py", description="Keep Vacpack's version in sync. Source of truth: project.yml."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("status", help="show every tracked file; exit 1 if any is out of sync")

    def add_write_flags(command: argparse.ArgumentParser) -> None:
        command.add_argument("--release-date", metavar="DD.MM.YYYY", help="release date (default: today)")
        command.add_argument("--dry-run", action="store_true", help="show what would change, write nothing")

    bump = commands.add_parser("bump", help="next semantic version, release date today")
    bump.add_argument("level", choices=["patch", "minor", "major"])
    add_write_flags(bump)
    sync = commands.add_parser("sync", help="set X.Y.Z, or re-apply the source version and date to every file")
    sync.add_argument("version", nargs="?", metavar="X.Y.Z")
    add_write_flags(sync)
    args = parser.parse_args(argv)

    if args.command == "status":
        return status()
    if args.release_date is not None:
        try:
            parse_date(args.release_date)
        except ValueError:
            parser.error(f"--release-date {args.release_date!r} is not DD.MM.YYYY")
    today = dt.date.today().strftime(DATE_FORMAT)
    current, current_date = source_version()
    if args.command == "bump":
        return apply(bumped(current, args.level), args.release_date or today, args.dry_run)
    if args.version is None:
        return apply(current, args.release_date or current_date, args.dry_run)
    if not SEMVER.match(args.version):
        parser.error(f"{args.version!r} is not MAJOR.MINOR.PATCH")
    return apply(args.version, args.release_date or today, args.dry_run)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except RuntimeError as error:
        sys.exit(f"error: {error}")

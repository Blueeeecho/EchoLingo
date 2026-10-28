#!/usr/bin/env python3
"""Check tracked publication inputs without reading local-only working notes."""

import argparse
from pathlib import Path, PurePosixPath
import re
import subprocess


PRIVATE_DIRS = {
    ".codex-plans", ".codex", ".claude", ".cursor", ".internal",
    "work", "test-results", "playwright-report", "__pycache__",
}
PRIVATE_DOCS = {
    "api-configuration-design.zh-CN.md", "bob-research.zh-CN.md",
    "implementation-plan.md", "local-preview.zh-CN.md",
    "official-website.zh-CN.md", "release-notes.zh-CN.md",
    "review-notes.md", "roadmap.zh-CN.md", "status.md", "test-report.md",
    "ui-notes.md", "windows-selection-github-recheck-20261028.zh-CN.md",
    "windows-selection-native-context-research.zh-CN.md", "windows-test-plan.zh-CN.md",
}
CONTENT_RULES = {
    "local user path": re.compile(
        r"/" + r"Users/[^\s/]+/|/var" + r"/folders/|"
        r"[A-Z]:[\\/]{1,2}Users[\\/]{1,2}[^\\/\s]+[\\/]"
    ),
    "credential-like value": re.compile(
        r"sk-" + r"[A-Za-z0-9_-]{32,}|gh[pousr]_[A-Za-z0-9]{30,}|"
        r"github_pat_[A-Za-z0-9_]{40,}|-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"
    ),
}


def private_path(name):
    path = PurePosixPath(name)
    if any(part in PRIVATE_DIRS for part in path.parts):
        return True
    if path.name in {"AGENTS.md", "PROJECT.md"}:
        return True
    if path.parts[:2] == ("docs", "validation"):
        return True
    if path.parts[:2] == ("docs", "harmonyos-pc"):
        return True
    return path.parent == PurePosixPath("docs") and (
        path.name in PRIVATE_DOCS or path.name.startswith("harmonyos-")
    )


def check(root):
    names = subprocess.check_output(
        ["git", "ls-files", "--cached", "-z"], cwd=root
    ).decode("utf-8").split("\0")
    failures = []
    for name in filter(None, names):
        if private_path(name):
            failures.append((name, "internal development file"))
            continue
        # Inspect the staged blob, so an unstaged edit cannot conceal staged data.
        data = subprocess.check_output(["git", "show", ":" + name], cwd=root)
        if b"\0" in data:
            continue
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            continue
        for label, pattern in CONTENT_RULES.items():
            if pattern.search(text):
                failures.append((name, label))
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parent.parent)
    failures = check(parser.parse_args().repo)
    if failures:
        for name, reason in failures:
            # Never print matched contents or credential values.
            print(f"{name}: {reason}")
        return 1
    print("Repository publication check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

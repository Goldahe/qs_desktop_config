#!/usr/bin/env python3
"""Regression: active Quickshell windows and popups must not expose close-X controls."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
production = [
    path for path in root.rglob("*.qml")
    if "backups" not in path.parts
    and "tests" not in path.parts
    and ".bak" not in path.name
]
violations = [
    str(path.relative_to(root))
    for path in production
    if 'text: "×"' in path.read_text()
]
assert not violations, f"close-X controls remain in: {', '.join(violations)}"

print("PASS: active Quickshell windows and popups contain no close-X controls")

#!/usr/bin/env python3
from pathlib import Path

path = Path("Sources/AgenTM5N/Views/KnowledgeLibraryView.swift")
text = path.read_text(encoding="utf-8")

replacements = [
    (
        "  private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {",
        "  private func perform(_ operation: @MainActor () async throws -> Void) async {",
    ),
    (
        "          .foregroundStyle(document.isEnabled ? .secondary : .orange)",
        "          .foregroundStyle(document.isEnabled ? Color.secondary : Color.orange)",
    ),
]

for old, new in replacements:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"guard failed for {old!r}: expected 1 occurrence, found {count}")
    text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")

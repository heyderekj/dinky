#!/usr/bin/env python3
"""Mechanical String(localized:) wrapping for PreferencesView.swift (Tier-1 localization)."""
import re
from pathlib import Path

PATH = Path(__file__).resolve().parents[1] / "Dinky" / "PreferencesView.swift"
C = "Settings UI."


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> None:
    c = PATH.read_text(encoding="utf-8")

    c = re.sub(
        r'Toggle\("((?:[^"\\]|\\.)*)",\s*isOn:',
        lambda m: f'Toggle(String(localized: "{esc(m.group(1))}", comment: "{C}"), isOn:',
        c,
    )
    c = re.sub(
        r'Picker\("((?:[^"\\]|\\.)*)",\s*selection:',
        lambda m: f'Picker(String(localized: "{esc(m.group(1))}", comment: "{C}"), selection:',
        c,
    )
    c = re.sub(
        r'Section\("((?:[^"\\]|\\.)*)"\)\s*\{',
        lambda m: f'Section(String(localized: "{esc(m.group(1))}", comment: "{C}")) {{',
        c,
    )
    c = re.sub(
        r'TextField\("((?:[^"\\]|\\.)*)",\s*text:',
        lambda m: f'TextField(String(localized: "{esc(m.group(1))}", comment: "{C}"), text:',
        c,
    )
    c = re.sub(
        r'Button\("((?:[^"\\]|\\.)*)",\s*role:',
        lambda m: f'Button(String(localized: "{esc(m.group(1))}", comment: "{C}"), role:',
        c,
    )
    c = re.sub(
        r'Button\("((?:[^"\\]|\\.)*)"\)\s*\{',
        lambda m: f'Button(String(localized: "{esc(m.group(1))}", comment: "{C}")) {{',
        c,
    )
    c = re.sub(
        r'Label\("((?:[^"\\]|\\.)*)",\s*systemImage:',
        lambda m: f'Label(String(localized: "{esc(m.group(1))}", comment: "{C}"), systemImage:',
        c,
    )
    c = re.sub(
        r'PreferencesRelatedTabLink\(title: "((?:[^"\\]|\\.)*)",\s*tab:',
        lambda m: f'PreferencesRelatedTabLink(title: String(localized: "{esc(m.group(1))}", comment: "{C}"), tab:',
        c,
    )

    # Text("...") before .font on next line (various indent)
    c = re.sub(
        r'Text\("((?:[^"\\]|\\.)*)"\)\s*\n\s*\.font',
        lambda m: f'Text(String(localized: "{esc(m.group(1))}", comment: "{C}"))\n                    .font',
        c,
    )
    # Text("...").tag(
    c = re.sub(
        r'Text\("((?:[^"\\]|\\.)*)"\)\.tag\(',
        lambda m: f'Text(String(localized: "{esc(m.group(1))}", comment: "{C}")).tag(',
        c,
    )
    # Text("...") \n .foregroundStyle(.secondary) without .font first
    c = re.sub(
        r'Text\("((?:[^"\\]|\\.)*)"\)\s*\n\s*\.foregroundStyle\(\.secondary\)',
        lambda m: f'Text(String(localized: "{esc(m.group(1))}", comment: "{C}"))\n                    .foregroundStyle(.secondary)',
        c,
    )

    # Section headers: } header: {\n                Text("
    c = re.sub(
        r'\}\s*header:\s*\{\s*\n\s*Text\("((?:[^"\\]|\\.)*)"\)\s*\n\s*\}',
        lambda m: f'}} header: {{\n                Text(String(localized: "{esc(m.group(1))}", comment: "{C}"))\n            }}',
        c,
    )

    # confirmationDialog title string
    c = re.sub(
        r'\.confirmationDialog\(\s*\n\s*"((?:[^"\\]|\\.)*)",\s*\n\s*isPresented:',
        lambda m: f'.confirmationDialog(\n            String(localized: "{esc(m.group(1))}", comment: "{C}"),\n            isPresented:',
        c,
    )
    # confirmationDialog message Text
    c = re.sub(
        r'\}\s*message:\s*\{\s*\n\s*Text\("((?:[^"\\]|\\.)*)"\)\s*\n\s*\}',
        lambda m: f'}} message: {{\n            Text(String(localized: "{esc(m.group(1))}", comment: "{C}"))\n        }}',
        c,
    )

    # Footer Text with only .font(.caption)
    c = re.sub(
        r'footer:\s*\{\s*\n\s*Text\("((?:[^"\\]|\\.)*)"\)\s*\n\s*\.font\(\.caption\)',
        lambda m: f'footer: {{\n                Text(String(localized: "{esc(m.group(1))}", comment: "{C}"))\n                    .font(.caption)',
        c,
    )

    PATH.write_text(c, encoding="utf-8")


if __name__ == "__main__":
    main()

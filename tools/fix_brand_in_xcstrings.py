#!/usr/bin/env python3
"""Fix MT brand-name leaks in Localizable.xcstrings.

Restores literal "Dinky" wherever a translator transliterated or translated it.
Also handles a few well-known lone-word MT mistakes.
"""
import json
import re
from pathlib import Path

CAT = Path(__file__).resolve().parent.parent / "Dinky" / "Localizable.xcstrings"

# Unambiguous transliterations of the literal brand "Dinky" per locale.
# Only applied to translations of source keys that already contain "Dinky".
BRAND_PATTERNS = {
    "ja": [r"ディンキー", r"ディンキ"],
    "ko": [r"딩키", r"딘키"],
    "ru": [r"Динки"],
    "zh-Hans": [r"丁基", r"丁奇", r"极小"],
    "zh-Hant": [r"丁基", r"丁奇", r"極小"],
    "es": [r"\bMono\b", r"\bPequeña\b(?= ayuda)", r"\bPequeño\b"],
    "fr": [r"\bMignon\b"],
    "nl": [r"\bDink\b"],
    "de": [r"\bMickrig\b"],
    "it": [r"\bPiccolo\b"],
    "tr": [r"\bMinik\b", r"\bUfak\b"],
}

# Per-key, per-locale targeted overrides for unambiguous fixes.
OVERRIDES = {
    ("Help", "de"): "Hilfe",
    ("Help", "es"): "Ayuda",
    ("Help", "fr"): "Aide",
    ("Help", "it"): "Aiuto",
    ("Help", "nl"): "Help",
    ("Help", "pt-BR"): "Ajuda",
    ("Help", "ru"): "Справка",
    ("Help", "tr"): "Yardım",
    ("Clear", "de"): "Löschen",
    ("Clear", "es"): "Borrar",
    ("Clear", "fr"): "Effacer",
    ("Clear", "it"): "Cancella",
    ("Clear", "nl"): "Wissen",
    ("Clear", "pt-BR"): "Limpar",
    ("Clear", "ru"): "Очистить",
    ("Clear", "tr"): "Temizle",
    ("Clear", "ja"): "クリア",
    ("Clear", "ko"): "지우기",
    ("Clear", "zh-Hans"): "清除",
    ("Clear", "zh-Hant"): "清除",
    ("Behavior", "ja"): "動作",
    ("Behavior", "ko"): "동작",
    ("Behavior", "zh-Hans"): "行为",
    ("Behavior", "zh-Hant"): "行為",
    # "What's New" key family
    ("What’s New…", "zh-Hans"): "新功能…",
    ("What’s New…", "zh-Hant"): "新功能…",
    ("What’s New…", "de"): "Neuigkeiten…",
}


def fix_brand(text: str, loc: str) -> str:
    """Replace any locale-specific brand mistranslations with literal 'Dinky'."""
    if not text:
        return text
    out = text
    for pat in BRAND_PATTERNS.get(loc, []):
        out = re.sub(pat, "Dinky", out)
    # Collapse double spaces from word swaps.
    out = re.sub(r"  +", " ", out).strip()
    return out


def main():
    data = json.loads(CAT.read_text())
    fixes = 0
    for key, entry in data.get("strings", {}).items():
        locs = entry.get("localizations", {})
        key_has_brand = "Dinky" in key
        for loc, payload in locs.items():
            su = payload.get("stringUnit")
            if not su:
                continue
            original = su.get("value", "")
            new = fix_brand(original, loc) if key_has_brand else original
            override = OVERRIDES.get((key, loc))
            if override is not None:
                new = override
            if new != original:
                su["value"] = new
                fixes += 1
                print(f"  [{loc}] {key!r}\n    - {original!r}\n    + {new!r}")
    CAT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"\nApplied {fixes} fixes.")


if __name__ == "__main__":
    main()

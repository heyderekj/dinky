#!/usr/bin/env python3
"""Add Tier-1 locale stringUnit entries to Localizable.xcstrings (key = English source).

By default only fills locales a string is missing, so existing (and hand-corrected) translations stay.
  python3 tools/fill_xcstrings_translations.py                 # fill gaps
  python3 tools/fill_xcstrings_translations.py --all           # re-translate everything
  python3 tools/fill_xcstrings_translations.py --keys "Scale" "Compress as JPEG"
Strings that fail to translate are left untouched and reported; the script exits 1 if any failed.
Run `xcodebuild -exportLocalizations -project Dinky.xcodeproj -localizationPath /tmp/loc -exportLanguage en`
first so new strings from the code are in the catalog.
"""
from __future__ import annotations

import argparse
import json
import re
import pathlib
import sys
import time

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("pip install deep-translator", file=sys.stderr)
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATH = ROOT / "Dinky" / "Localizable.xcstrings"

LANGS = {
    "de": "de",
    "es": "es",
    "fr": "fr",
    "it": "it",
    "ja": "ja",
    "ko": "ko",
    "nl": "nl",
    "pt-BR": "pt",
    "ru": "ru",
    "tr": "tr",
    "zh-Hans": "zh-CN",
    "zh-Hant": "zh-TW",
}


def protect_tokens(s: str) -> tuple[str, list[str]]:
    parts: list[str] = []

    def grab(pattern: str, text: str) -> str:
        def repl(m):
            parts.append(m.group(0))
            return f"⟦{len(parts) - 1}⟧"

        return re.sub(pattern, repl, text)

    s = grab(r"%(?:\d+\$)?(?:\.\d+)?[dfus@]|%lld", s)
    s = grab(r"\\\([^)]*\)", s)
    return s, parts


def restore_tokens(s: str, parts: list[str]) -> str:
    for i, p in enumerate(parts):
        s = s.replace(f"⟦{i}⟧", p)
    return s


def translate_one(translator: GoogleTranslator, text: str) -> str | None:
    """Translated text, or None when every attempt failed (rate limit, network)."""
    if not text.strip():
        return text
    for attempt in range(3):
        try:
            return translator.translate(text)
        except Exception:
            time.sleep(0.4 * (attempt + 1))
    return None


def translate_all(texts: list[str], tgt: str, chunk: int = 25) -> list[str | None]:
    translator = GoogleTranslator(source="en", target=tgt)
    out: list[str | None] = []
    for i in range(0, len(texts), chunk):
        batch = texts[i : i + chunk]
        try:
            res = translator.translate_batch(batch)
            time.sleep(0.15)
        except Exception:
            res = []
        if len(res) != len(batch):
            res = [translate_one(translator, t) for t in batch]
        out.extend(res)
    return out


def save(doc: dict) -> None:
    """Write in Xcode's own format (` : ` separators, empty entries on three lines) so diffs stay small."""
    text = json.dumps(doc, ensure_ascii=False, indent=2, separators=(",", " : "))
    text = re.sub(r" : \{\}", " : {\n\n    }", text)
    PATH.write_text(text, encoding="utf-8")  # Xcode writes no trailing newline


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="re-translate locales that already have a value")
    ap.add_argument("--keys", nargs="+", help="only these English keys")
    args = ap.parse_args()

    doc = json.loads(PATH.read_text(encoding="utf-8"))
    strings = doc.get("strings", {})
    keys = [
        k for k in strings
        if k.strip()
        and strings[k].get("extractionState") != "stale"
        and strings[k].get("shouldTranslate", True)
        and (not args.keys or k in args.keys)
    ]
    failed: list[tuple[str, str]] = []

    for xc, gt in LANGS.items():
        todo = [k for k in keys if args.all or xc not in strings[k].get("localizations", {})]
        if not todo:
            continue
        print(f"-> {xc}: {len(todo)} strings", file=sys.stderr, flush=True)
        protected = [protect_tokens(k) for k in todo]
        trs = translate_all([p for p, _ in protected], gt)
        for k, tr, (_, ph) in zip(todo, trs, protected):
            if not isinstance(tr, str):
                failed.append((xc, k))
                continue
            loc = strings[k].setdefault("localizations", {})
            loc[xc] = {"stringUnit": {"state": "translated", "value": restore_tokens(tr, ph)}}
        save(doc)

    if failed:
        print(f"✗ {len(failed)} translations failed (left untranslated); run again later:", file=sys.stderr)
        for xc, k in failed[:20]:
            print(f"   {xc}: {k}", file=sys.stderr)
        sys.exit(1)
    print(f"Done {PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()

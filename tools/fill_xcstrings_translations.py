#!/usr/bin/env python3
"""Add Tier-1 locale stringUnit entries to Localizable.xcstrings (key = English source)."""
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


def translate_one(translator: GoogleTranslator, text: str) -> str:
    if not text.strip():
        return text
    for attempt in range(3):
        try:
            return translator.translate(text)
        except Exception:
            time.sleep(0.4 * (attempt + 1))
    return text


def translate_all(texts: list[str], tgt: str, chunk: int = 25) -> list[str]:
    translator = GoogleTranslator(source="en", target=tgt)
    out: list[str] = []
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
    PATH.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    doc = json.loads(PATH.read_text(encoding="utf-8"))
    strings = doc.get("strings", {})
    keys = [k for k in strings if k.strip()]
    print(f"{len(keys)} keys", file=sys.stderr)

    protected: list[str] = []
    ph_parts: list[list[str]] = []
    for k in keys:
        p, ph = protect_tokens(k)
        protected.append(p)
        ph_parts.append(ph)

    for xc, gt in LANGS.items():
        print(f"-> {xc}", file=sys.stderr, flush=True)
        trs = translate_all(protected, gt)
        for k, tr, ph in zip(keys, trs, ph_parts):
            val = restore_tokens(tr if isinstance(tr, str) else k, ph)
            loc = strings[k].setdefault("localizations", {})
            loc[xc] = {"stringUnit": {"state": "translated", "value": val}}
        doc["strings"] = strings
        save(doc)
        print(f"  saved ({xc})", file=sys.stderr, flush=True)

    print(f"Done {PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()

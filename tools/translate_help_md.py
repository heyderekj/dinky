#!/usr/bin/env python3
"""Translate Resources/*/Help.md from English (en.lproj) to Tier-1 locales."""
import pathlib
import sys
import time

try:
    from deep_translator import GoogleTranslator
except ImportError:
    print("pip install deep-translator", file=sys.stderr)
    sys.exit(1)

ROOT = pathlib.Path(__file__).resolve().parents[1] / "Dinky" / "Resources"
SRC = ROOT / "en.lproj" / "Help.md"

LANGS = {
    "de.lproj": "de",
    "es.lproj": "es",
    "fr.lproj": "fr",
    "it.lproj": "it",
    "ja.lproj": "ja",
    "ko.lproj": "ko",
    "nl.lproj": "nl",
    "pt-BR.lproj": "pt",
    "ru.lproj": "ru",
    "tr.lproj": "tr",
    "zh-Hans.lproj": "zh-CN",
    "zh-Hant.lproj": "zh-TW",
}


def translate_text(text: str, tgt: str) -> str:
    if not text.strip():
        return text
    lines = text.split("\n")
    out: list[str] = []
    buf: list[str] = []
    for line in lines:
        if line.strip() == "" or line.startswith("#") or line.startswith("---"):
            if buf:
                chunk = "\n".join(buf)
                try:
                    t = GoogleTranslator(source="en", target=tgt).translate(chunk)
                    time.sleep(0.12)
                except Exception:
                    t = chunk
                out.append(t)
                buf = []
            out.append(line)
        else:
            buf.append(line)
    if buf:
        chunk = "\n".join(buf)
        try:
            t = GoogleTranslator(source="en", target=tgt).translate(chunk)
        except Exception:
            t = chunk
        out.append(t)
    return "\n".join(out)


def main() -> None:
    en = SRC.read_text(encoding="utf-8")
    for folder, code in LANGS.items():
        dest = ROOT / folder / "Help.md"
        print(folder, file=sys.stderr, flush=True)
        dest.write_text(translate_text(en, code), encoding="utf-8")
    print("Done", file=sys.stderr)


if __name__ == "__main__":
    main()

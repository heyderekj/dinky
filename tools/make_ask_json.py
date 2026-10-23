#!/usr/bin/env python3
"""Builds site/ask.json: what the site's Spotlight answers are grounded in (functions/api/ask.js).

Reads the homepage FAQ (.faq-item > .faq-q + .faq-a), gives each item a stable id (and writes that id onto the
item in site/index.html, so answers can link to it), and adds the app's English Help.md as extra context.
Run it again whenever the FAQ or Help changes:  python3 tools/make_ask_json.py
"""
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APPS = {
    'dinky': dict(app='Dinky', line='Dinky makes files smaller.', help='Dinky/Resources/en.lproj/Help.md',
                  voice='Friendly, plain and a little cheeky about making files small. Keep it light; never oversell.'),
    'binky': dict(app='Binky', line='Binky sorts your files.', help='Binky/Resources/en.lproj/Help.md',
                  voice='Warm, plain and a bit playful about mess and calm. Keep it light; never oversell.'),
}
# Which app this repo is, from its Xcode project (the folder name differs in worktrees and clones).
cfg = next(c for c in APPS.values() if (ROOT / f'{c["app"]}.xcodeproj').exists())
page_path = ROOT / 'site' / 'index.html'
page = page_path.read_text()


def text(fragment: str) -> str:
    fragment = re.sub(r'<button[^>]*>.*?</button>', '', fragment, flags=re.S)
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', '', fragment))).strip()


def slug(q: str) -> str:
    return 'faq-' + re.sub(r'[^a-z0-9]+', '-', q.lower()).strip('-')[:60].rstrip('-')


faq = []
def tag(m: re.Match) -> str:
    open_tag, body = m.group(1), m.group(2)
    q = text(re.search(r'<(h3|summary) class="faq-q"[^>]*>(.*?)</\1>', body, re.S).group(2))
    a = text(re.search(r'<p class="faq-a"[^>]*>(.*?)</p>', body, re.S).group(1))
    # Keep an id the page already uses (other links point at it); otherwise make one from the question.
    existing = re.search(r'\sid="([^"]+)"', open_tag)
    fid = existing.group(1) if existing else slug(q)
    faq.append({'id': fid, 'q': q, 'a': a})
    if not existing:
        open_tag = open_tag.replace('class="faq-item', f'id="{fid}" class="faq-item', 1)
    return open_tag + body


# FAQ items are <div> (older pages) or <details> with a <summary> question (family design).
page = re.sub(r'(<(?:div|details) (?:id="[^"]*" )?class="faq-item[^"]*"[^>]*>)(.*?</p>\s*)(?=</(?:div|details)>)', tag, page, flags=re.S)
page_path.write_text(page)

# The compare pages (site/compare/<tool>/), so "how does it compare?" has real answers. Title, summary and
# the main text up to "More comparisons", trimmed.
compare = []
for cpage in sorted((ROOT / 'site' / 'compare').glob('*/index.html')):
    src = cpage.read_text()
    h1 = re.search(r'<h1[^>]*>(.*?)</h1>', src, re.S)
    if not h1:
        continue
    body = re.sub(r'<(script|style|nav|header|footer)\b.*?</\1>', ' ', src, flags=re.S)
    body = text(body)
    title = text(h1.group(1))
    start = body.find(title)
    main = body[start + len(title):] if start >= 0 else body
    main = main.split('More comparisons')[0].strip()
    compare.append({'name': title, 'url': f'/compare/{cpage.parent.name}/', 'text': main[:700]})

version = (re.search(r'\bv(\d+\.\d+\.\d+)\b', page) or [None, ''])[1]
help_md = (ROOT / cfg['help']).read_text() if (ROOT / cfg['help']).exists() else ''
data = {
    'app': cfg['app'], 'line': cfg['line'], 'version': version, 'email': 'derek@testamentmade.com',
    'voice': cfg['voice'], 'faq': faq, 'compare': compare, 'more': help_md,
}
(ROOT / 'site' / 'ask.json').write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n')
print(f"{cfg['app']}: {len(faq)} FAQ items, {len(compare)} comparisons, help {len(help_md)} chars, v{version}", file=sys.stderr)

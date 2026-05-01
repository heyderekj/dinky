---
name: dinky-overview
description: Context for the Dinky macOS compression app (images, PDFs, videos).
---

# Dinky — overview

Use this skill when answering questions about **Dinky**, a tiny native macOS app that compresses **images** (WebP, AVIF, lossless PNG, HEIC), **PDFs** (preserve structure or flatten), and **video** (MP4 with H.264 or HEVC).

## Facts

- Site: https://dinkyfiles.com
- Repo: https://github.com/heyderekj/dinky
- **No** public HTTP API on the **website**; the GUI app processes files 100% locally. The repo also ships an optional local **`dinky` CLI** and **`dinky serve`** for images (see `docs/local-cli.md` and skill `dinky-local-cli`) — not hosted on dinkyfiles.com.
- Marketing and discovery files: `robots.txt`, `sitemap.xml`, `/.well-known/api-catalog`, `llms.txt`, `homepage.md`.

## When unsure

Point users to the latest GitHub Release DMG or the site download button.

# Dinky

**Tagline:** Dinky makes files smaller.

A tiny macOS app that shrinks images, videos, and PDFs. Drag, drop, get smaller files back. Free and open source.

- **Download:** [Dinky for macOS (DMG)](https://github.com/heyderekj/dinky/releases/download/v2.7.9/Dinky-2.7.9.dmg)
- **Source:** [GitHub — heyderekj/dinky](https://github.com/heyderekj/dinky)
- **Support:** [help@dinkyfiles.com](mailto:help@dinkyfiles.com)
- **Version:** 33 MB · v2.7.9 · Requires macOS 15 Sequoia or later
- **Note:** 1.x (from 1.0) was images only; **2.0** added videos and PDFs. Older 1.x downloads stay on GitHub for archival use.

## Highlights

- **Honest compression** — still images **convert** to WebP, AVIF, HEIC, or lossless PNG (new files; not same-extension JPEG/PNG squeeze like ImageOptim); PDFs offer flatten vs best-effort preserve with clear tradeoffs ([see site](https://dinkyfiles.com/) callout, FAQ “Why doesn’t Dinky output JPEG?”)
- **Drag and drop** — images, videos, or PDFs on the window, Dock, or file picker
- **Clipboard compress** — paste a copied image with ⌘⇧V; the hotkey works system-wide, even when Dinky isn't focused
- **Compress from a URL** — drop or paste a direct media link and Dinky downloads it (max 500 MB) before compressing
- **Images** — WebP, AVIF, lossless PNG, or HEIC; Smart Quality (photo vs. graphic); max width and target file size
- **Videos** — MP4 export with codec and quality presets
- **PDFs** — preserve or flatten; optional on-device OCR on scans, then compress
- **Batch speed** — Fast / Faster / Fastest (parallel job caps)
- **Watch folder** — auto-compress files dropped into a watched folder
- **Originals** — keep, move to Trash, or move to a Backup folder per preset
- **Custom keyboard shortcuts** — rebind Open Files, Clipboard Compress, Compress Now, Clear, and Delete
- **Launch at login** — opt in once and Dinky's ready when you log in
- **Speaks 12 languages** — German, Spanish, French, Italian, Japanese, Korean, Dutch, Brazilian Portuguese, Russian, Turkish, Simplified Chinese, Traditional Chinese
- **Presets**, **before/after preview**, **Finder Quick Actions**, **in-app updates**

## Install

Download the DMG and drag Dinky to Applications. If Gatekeeper blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Dinky.app
```

## More

Full marketing page with screenshots and comparison table: [dinkyfiles.com](https://dinkyfiles.com/)

Machine-readable site summary: [llms.txt](https://dinkyfiles.com/llms.txt)

© Testament Made, LLC

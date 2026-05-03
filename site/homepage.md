# Dinky

**Tagline:** Dinky makes files smaller.

A tiny macOS app that shrinks images, videos, audio, and PDFs. Drag, drop, get smaller files back. Free and open source.

- **Download:** [Dinky for macOS (DMG)](https://github.com/heyderekj/dinky/releases/download/v2.11.1/Dinky-2.11.1.dmg) — or install with [Homebrew](https://brew.sh): `brew tap heyderekj/dinky https://github.com/heyderekj/dinky` then `brew install --cask dinky`
- **Source:** [GitHub — heyderekj/dinky](https://github.com/heyderekj/dinky)
- **Support:** [help@dinkyfiles.com](mailto:help@dinkyfiles.com)
- **Version:** 33 MB · v2.11.1 · Requires macOS 15 Sequoia or later
- **Note:** 1.x (from 1.0) was images only; **2.0** added videos and PDFs. **2.10** added audio compression and an optional video FPS cap. Older 1.x downloads stay on GitHub for archival use.

## Highlights

- **Honest compression** — still images **convert** to WebP, AVIF, HEIC, or lossless PNG (new files; not same-extension JPEG/PNG squeeze like ImageOptim); PDFs offer flatten vs best-effort preserve with clear tradeoffs ([comparison pages](https://dinkyfiles.com/compare/imageoptim/) cover ImageOptim, TinyPNG, HandBrake, Acrobat, and more)
- **Drag and drop** — images, videos, audio, or PDFs on the window, Dock, or file picker
- **Clipboard compress** — paste a copied image with ⌘⇧V; the hotkey works system-wide, even when Dinky isn't focused
- **Compress from a URL** — drop or paste a direct media link and Dinky downloads it (max 500 MB) before compressing
- **Images** — WebP, AVIF, lossless PNG, or HEIC; Smart Quality (photo vs. graphic); max width and target file size
- **Videos** — MP4 export with codec and quality presets; optional FPS cap
- **Audio** — AAC (M4A), ALAC, WAV, AIFF, FLAC, MP3; cross-convert via macOS `afconvert`; MP3 encode via bundled LAME
- **PDFs** — preserve or flatten; optional on-device OCR on scans, then compress
- **Batch speed** — Fast / Faster / Fastest (parallel job caps)
- **Watch folder** — auto-compress files dropped into a watched folder
- **Originals** — keep, move to Trash, or move to a Backup folder per preset
- **Custom keyboard shortcuts** — rebind Open Files, Clipboard Compress, Compress Now, Clear, and Delete
- **CLI + local API (pro users)** — optional `dinky` CLI and `dinky serve` loopback endpoint for scripts and AI agents
- **Launch at login** — opt in once and Dinky's ready when you log in
- **Speaks 12 languages** — German, Spanish, French, Italian, Japanese, Korean, Dutch, Brazilian Portuguese, Russian, Turkish, Simplified Chinese, Traditional Chinese
- **Presets**, **before/after preview**, **Finder Quick Actions**, **in-app updates**

## Install

**Download & install:** grab the installer from GitHub Releases and drag Dinky into Applications.

**Homebrew:** if you use [Homebrew](https://brew.sh), run:

```bash
brew tap heyderekj/dinky https://github.com/heyderekj/dinky
brew install --cask dinky
```

To upgrade later: `brew update && brew upgrade --cask dinky`.

**Gatekeeper:** if macOS blocks the first launch, use **System Settings → Privacy & Security → Open Anyway**, or:

```bash
xattr -dr com.apple.quarantine /Applications/Dinky.app
```

## More

Full marketing page with screenshots and comparison table: [dinkyfiles.com](https://dinkyfiles.com/)

Comparison pages — Images: [ImageOptim](https://dinkyfiles.com/compare/imageoptim/), [Optimage](https://dinkyfiles.com/compare/optimage/), [TinyPNG](https://dinkyfiles.com/compare/tinypng/), [Squoosh](https://dinkyfiles.com/compare/squoosh/), [Preview](https://dinkyfiles.com/compare/preview/). Video: [HandBrake](https://dinkyfiles.com/compare/handbrake/), [Compressor](https://dinkyfiles.com/compare/compressor/), [Permute](https://dinkyfiles.com/compare/permute/), [FFmpeg](https://dinkyfiles.com/compare/ffmpeg/), [QuickTime](https://dinkyfiles.com/compare/quicktime/). PDF: [Acrobat](https://dinkyfiles.com/compare/adobe-acrobat/), [Preview](https://dinkyfiles.com/compare/preview/), [PDF Squeezer](https://dinkyfiles.com/compare/pdf-squeezer/), [Smallpdf](https://dinkyfiles.com/compare/smallpdf/). All-in-one (images, video, audio & PDF): [Clop](https://dinkyfiles.com/compare/clop/), [Picmal](https://dinkyfiles.com/compare/picmal/).

Machine-readable site summary: [llms.txt](https://dinkyfiles.com/llms.txt)

© Testament Made, LLC

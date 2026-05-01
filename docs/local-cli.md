# Dinky `dinky` CLI and local service (images, video, PDF)

Dinky’s compression pipeline is available as a **local** command-line tool and an optional **loopback HTTP** server. There is still **no public cloud API**; everything runs on the Mac with explicit file paths you supply.

**Source layout:** Swift package at `DinkyCoreImage/` in this repo. Library targets: `DinkyCoreShared`, `DinkyCoreImage`, `DinkyCoreVideo`, `DinkyCorePDF`, `DinkyCLILib` (CLI + JSON). Product executable: `dinky`.

## Building

```bash
cd DinkyCoreImage
swift build -c release
# Binary: .build/release/dinky
```

**Tools directory (`DINKY_BIN`):** same resolution order as before:

1. `DINKY_BIN` — directory containing `cwebp`, `avifenc`, `oxipng` (required for **images** and for discovering **qpdf** next to them).
2. `bin` next to the `dinky` binary.
3. Homebrew: `/opt/homebrew/bin` or `/usr/local/bin`.

Place an executable **`qpdf`** in that same directory for best **PDF preserve-mode** behavior (matches `Dinky.app` Resources). Optional sibling **`lib/`** holds dylibs; `DYLD_LIBRARY_PATH` is set to include that folder and `/opt/homebrew/lib` when qpdf runs.

**Video** compression uses AVFoundation only — no external encoders.

## Exit codes (all subcommands)

| Code | Meaning |
|------|--------|
| `0` | All inputs processed successfully |
| `1` | Parse error, missing tools, no inputs, or at least one file failed |

---

## Images — `dinky compress-image`

```text
dinky compress-image <file>... [options]
```

`dinky compress` is a **deprecated** alias (prints a warning); use `compress-image`.

### Flags (images)

- `-f, --format` `auto|webp|avif|png|heic` (default: `auto`)
- `-o, --output-dir` — output directory (default: next to each input, or from preset save location)
- `-w, --max-width` — max width in pixels
- `--max-size-kb` — target max file size (KB)
- `-q, --quality` `0...100` — disables smart quality when set
- `--smart-quality` / `--no-smart-quality`
- `--content-hint` `auto|photo|graphic|mixed`
- `--strip-metadata` / `--no-strip-metadata`
- `-j, --parallel` — concurrency (default: 3)
- `--collision-style` / `--collision-pattern` — collision naming
- `--json` — machine-readable output
- **Presets:** `--preset "Name"`, `--preset-id <UUID>`, `--preset-file <path>` — same resolution order as below; CLI flags override preset fields; preset **scope** must include **images**.

### JSON schema — `dinky.image.compress/1.0.0`

Root: `schema`, `success`, `results[]`.

Each result: `input`, `output`, `originalBytes`, `outputBytes`, `savingsPercent`, `detectedContent`, `error`.

---

## Video — `dinky compress-video`

```text
dinky compress-video <file>... [options]
```

### Flags (video)

- `-q, --quality` `low|medium|high|lossless` — `low` maps to balanced tier; `lossless` to high tier
- `--codec` `h264|hevc` (ProRes is not supported)
- `--remove-audio` / `--keep-audio`
- `--max-height` — max output height (lines)
- `--smart-quality` / `--no-smart-quality`
- `-o`, `--output-dir`, `--json`, `--collision-style`, `--collision-pattern`
- **Presets:** same trio as images; scope must include **videos**.

### JSON schema — `dinky.video.compress/1.0.0`

Each result adds: `durationSeconds`, `effectiveCodec`, `isHDR`, `videoContentType`.

---

## PDF — `dinky compress-pdf`

```text
dinky compress-pdf <file>... [options]
```

Requires the same **`DINKY_BIN`** resolution as images so the CLI can find **qpdf** when needed (flatten mode can still run without qpdf; preserve mode falls back to PDFKit if qpdf is missing).

### Flags (PDF)

- `--mode` `preserve|flatten`
- `-q, --quality` `smallest|low|medium|high`
- `--grayscale` / `--no-grayscale`
- `--strip-metadata` / `--no-strip-metadata`
- `--resolution-downsample` / `--no-resolution-downsample` (preserve mode)
- `--target-kb` — soft cap (tries lower-quality steps in flatten chain)
- `--preserve-experimental` `none|stripStructure|strongerImages|maximum` (+ short aliases: `strip`, `stronger`, `max`)
- `--smart-quality` / `--no-smart-quality`
- `--auto-grayscale-mono` / `--no-auto-grayscale-mono`
- `-o`, `--output-dir`, `--json`, collision flags
- **Presets:** same; scope must include **pdfs**.

### JSON schema — `dinky.pdf.compress/1.0.0`

Each result: `input`, `output`, `originalBytes`, `outputBytes`, `savingsPercent`, `mode` (`preserve` | `flatten`), `qpdfStepUsed`, `appliedDownsampling`, `error`.

---

## OCR — `dinky ocr` (optional)

Searchable PDF layer via Vision (same engine as the app’s OCR path):

```text
dinky ocr <pdf>... [--languages en-US,fr] [-o dir] [--json]
```

---

## Presets (shared)

Resolution order for the presets JSON **array**:

1. `--preset-file`
2. `$DINKY_PRESETS_PATH`
3. `~/.config/dinky/presets.json`
4. `UserDefaults(suiteName: "com.dinky.app")` key `savedPresetsData` (GUI presets)

Lookup: `--preset "Name"` (exact, then case-insensitive) or `--preset-id`.

**Custom save folders** stored only as app security-scoped bookmarks require **`-o`** unless `presetCustomFolderPath` has a plain path string.

Ignored in CLI: watch-folder fields, “open folder when done”, notification toggles.

---

## `dinky serve` (local HTTP)

Default port **17381**. Prefer **`127.0.0.1`** in clients.

| Method | Path | Notes |
|--------|------|--------|
| `GET` | `/v1/health` | `{"ok":true,"schema":"dinky.image.serve/1.0.0"}` |
| `POST` | `/v1/compress` | Image body (existing); response `dinky.image.compress/1.0.0` |
| `POST` | `/v1/video/compress` | Video options JSON; response `dinky.video.compress/1.0.0` |
| `POST` | `/v1/pdf/compress` | PDF options JSON; response `dinky.pdf.compress/1.0.0` |

HTTP **200** if all files OK, **422** if any failed (image/video/PDF). **503** if `DINKY_BIN` missing for PDF handler.

### Example: image POST

```json
{
  "inputPaths": ["/path/to/photo.png"],
  "format": "webp",
  "outputDir": "/path/to/out",
  "quality": 80,
  "smartQuality": false,
  "stripMetadata": true
}
```

### Example: video POST

```json
{
  "inputPaths": ["/path/to/clip.mov"],
  "outputDir": "/path/to/out",
  "quality": "medium",
  "codec": "hevc",
  "removeAudio": false,
  "maxHeight": 1080,
  "smartQuality": true
}
```

### Example: PDF POST

```json
{
  "inputPaths": ["/path/to/doc.pdf"],
  "outputDir": "/path/to/out",
  "mode": "flatten",
  "quality": "medium",
  "smartQuality": true,
  "stripMetadata": true
}
```

---

## Security model

- No upload to a hosted Dinky API.
- Only files you pass are read; output paths are under your control.
- Prefer loopback and explicit paths for agents/scripts.

---

## Developer tools — `dinky make-fixtures`

**Local testing only**: generates valid sample **images**, **videos**, and **PDFs** under a folder you choose (default `./.dinky-fixtures/<ISO8601-timestamp>/`, with `:` replaced for path safety). Writes `manifest.json` (`schema: dinky.fixtures.manifest/1.0.0`) listing each file, size, and notes (including skips when an encoder is missing).

```text
dinky make-fixtures [--output-dir <path>] [--types images,video,pdf] [--count 1..20] [--seed <u64>] [--overwrite] [--json]
```

- **Images:** PNG, JPEG, TIFF, BMP, HEIC via ImageIO; WebP and AVIF when `cwebp` / `avifenc` resolve via `DINKY_BIN` (same as compress-image).
- **Video:** Short synthetic H.264 clips (`.mov` and `.mp4`) via `AVAssetWriter`.
- **PDF:** Core Text “text-heavy” page and a raster-heavy “scan-like” page via Core Graphics.

Use `--json` to print the manifest to stdout after writing.

---

## Roadmap / follow-ups

- Loopback-only bind option for `serve`, request size caps, structured errors.
- `dinky preset list|export` and JSON schema for presets.
- Optional bundled tiny media fixtures for CI video smoke tests.

---

## Testing

```bash
cd DinkyCoreImage
swift test
```

Some PDF smoke tests **skip** when a blank one-page PDF cannot be shrunk further in a given OS configuration.

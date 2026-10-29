# Welcome

Dinky makes files dinky. Drop something in, get a smaller version out — same look, less weight.

It works on **images** (JPEG, PNG, WebP, AVIF, HEIC/HEIF, TIFF, BMP), **videos** (MP4, MOV, M4V), **PDFs**, and **audio** (MP3, M4A, WAV, AIFF, FLAC).

Everything happens on your Mac. Nothing is uploaded.

---

## Quick start

1. Drag a file, a folder, or a pile of them onto Dinky's window.
2. Watch the count go down. No questions asked — it just compresses.
3. Find the smaller copies next to the originals (default), in your Downloads folder, or in a folder you choose.

Want a say before each batch? Set **Start compressing** to **Ask first** in **Settings → Ways to Compress**.

That's it. The defaults are good. Read on if you want to bend them to your will.

---

## Ways to compress

You don't have to open the app first. Pick whichever fits how you work.

- **Drag & drop** files or whole folders onto the Dinky window or the Dock icon.
- **Floating dropzone** — start dragging files anywhere and a little dropzone pops into a screen corner. Drop on it to compress without opening the window. (See *Floating dropzone* below.)
- **Hide from Dock** — **Settings → Startup & Dock** (requires **Open at login**) keeps Dinky running without a Dock icon or App Switcher entry (Dock-icon drops need this off).
- **Open Files…** — `{{SK_OPEN_FILES}}` to pick files or folders from a sheet.
- **Paste** — `⌘V` or `{{SK_PASTE}}` compresses **files** copied in Finder (images, videos, PDFs, audio — all of them, not just the first) or **raw image** data (screenshots, browser copies). Pasted images are saved to your Downloads folder as *Pasted image …*.
- **Right-click in Finder → Services → Compress with Dinky** — works on selections of any size.
- **Watch a folder** — Dinky compresses anything new that lands in it. (See *Watch folders* below.)
- **Quick Action** — assign a keyboard shortcut to "Compress with Dinky" in System Settings → Keyboard → Keyboard Shortcuts → Services.

---

## Where files go

Set this once in **Settings → Output**.

- **Same folder as original** *(default)* — keeps things tidy and local.
- **Downloads folder** — good if you process a lot from email or messages.
- **Custom folder…** — point Dinky anywhere.

### Filenames

- **Append "-dinky"** *(default)* — `photo.jpg` becomes `photo-dinky.jpg`. Originals are safe.
- **Replace original** — overwrites the file. Combine with *Move originals to trash* in **General** if you want one clean file at the end.
- **Custom suffix** — for the workflow tinkerers. Use what suits your filing system.

> **Pro tip:** Presets can override save location and filename per rule. Use that for things like "screenshots → `~/Desktop/web/`, replace original".

---

## Sidebar & formats

The sidebar on the right of the main window is where you tell Dinky **what** to make.

### Simple sidebar (default)

Three plain-language choices: **Image**, **Video**, **PDF**. Pick one per category and drop. Dinky figures out a sensible encoder, quality, and size.

**Still images:** Dinky **converts** to WebP, AVIF, lossless PNG, HEIC, or JPEG — new files with that extension. **Auto** picks AVIF for most photos and WebP for graphics, never JPEG; turn off **Auto** in the full sidebar or use **Settings → Presets** to lock one format.

### Full sidebar

Toggle **Settings → General → Use simple sidebar** off (or flip individual sections on) to expose every control:

- **Images** — format (Auto, WebP, AVIF, lossless PNG, HEIC, or JPEG), content hint (photo / illustration / screenshot), max width, scale by percentage, max file size. With **Smart quality** off and a fixed format, you also get AVIF chroma, lossless WebP, or optimized PNG options in the sidebar.
- **Videos** — codec family (H.264 / HEVC / AV1), quality tier, strip audio.
- **PDFs** — preserve text & links, or flatten to images for the smallest possible file.

---

## Smart quality

When **Smart quality** is on (default for new presets), Dinky inspects each file and picks settings for it:

- Images get an encoder tuned to their content (busy photo vs. graphic — UI, illustration, logo, screenshot), including AVIF chroma subsampling and WebP near-lossless when appropriate.
- Videos get a tier based on resolution and source bitrate, then nudged for content type — screen recordings and animation / motion graphics move up a tier so text and edges stay readable. Camera footage is identified from EXIF make/model so it isn't over-protected. HDR sources (Dolby Vision, HDR10, HLG) are exported with HEVC to preserve color and highlight detail; H.264 would silently flatten them to SDR.
- PDFs get a tier based on document complexity and whether they're text-first or image-heavy. **Preserve text** uses Smart quality to try several **qpdf** passes when Experimental preserve is off, then PDFKit if needed. **Smallest file (flatten)** can turn on **Auto-grayscale monochrome scans** (in the preset) so black-and-white scans use grayscale without enabling **Grayscale PDF** for everything.

Turn it off in any preset under **Compression** when you want a fixed quality tier (Balanced / High for video, Low / Medium / High for PDFs) — useful for batches that need predictable results.

---

## Presets

Presets are saved combinations of settings. Build one for each repeating task.

Examples that work well:

- **Web hero images** — WebP, max width 1920, append `-web`.
- **Client deliverables** — WebP, max width 2560, replace original, save to `~/Deliverables/`.
- **Screen recordings** — H.264 Balanced, strip audio.
- **Scanned PDFs** — flatten, medium quality, grayscale.

Create them in **Settings → Presets**. Each can:

- Apply to all media or just one type (Image / Video / PDF).
- Use its own save location and filename rule.
- Watch its own folder *(see below)*.
- Strip metadata, sanitize filenames, open the output folder when done.

Switch the active preset from the sidebar at any time.

---

## Watch folders

Drop files into a folder and let Dinky handle them in the background.

- **Global watch** — *Settings → Watch → Global*. Uses whatever the sidebar is currently set to. Good for an "incoming" or screenshot folder.
- **Per-preset watch** — each preset can also watch its own folder with its own rules. Independent of the sidebar — change the sidebar all you want, the preset still does its thing.

> **Pro tip:** Combine "screen recordings folder" + a preset that strips audio and re-encodes to H.264 Balanced. Hit `⌘⇧5`, screen-record, hit stop — Dinky has a small file ready before you reach the Finder.

---

## Floating dropzone

Turn it on in **Settings → Ways to Compress → Floating dropzone**, and pick its corner there.

- **Drag files anywhere** — from Finder, Mail, your browser's downloads — and a small dropzone tucks into the corner. It grows as you get close.
- **Drop on the big target** to use your current preset. To use another one, sweep across the **preset track** along the bottom — the highlight follows you — then let go there or anywhere on the target.
- **Watch it shrink.** When it's done you'll see how much you saved. **Drag any result straight out** into another app, or click it to show it in Finder.
- Drops here skip the confirmation sheet and manual mode — dropping *is* the go button. Hold `⌥` while dropping to compress files Dinky would normally skip.

---

## Manual mode

Set **Start compressing** to **Wait for Compress Now** in **Settings → Ways to Compress** when you want full control.

Files dropped in won't auto-compress. Right-click any row to pick a format on the spot, use **File → Compress Now** (`{{SK_COMPRESS_NOW}}`) when the queue is ready, or change settings in the sidebar first. Useful when one batch contains very different files.

---

## Keyboard shortcuts

You’ll find the same list in **Settings → Shortcuts** so you don’t have to dig through this page.

| Shortcut | Action |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Open files… |
| `{{SK_PASTE}}` | Clipboard Compress |
| `⌘V` | Paste files or images to compress |
| `Space` | Quick Look the selected results |
| `⌘C` | Copy the selected results (paste them straight into Finder, Mail, Figma…) |
| `⌘Z` | Undo the last batch |
| `{{SK_COMPRESS_NOW}}` | Compress Now (runs the queue — especially useful in Manual mode) |
| `{{SK_CLEAR_ALL}}` | Clear All |
| `{{SK_TOGGLE_SIDEBAR}}` | Toggle format sidebar |
| `{{SK_DELETE}}` | Delete selected rows |
| `{{SK_SETTINGS}}` | Settings |
| `{{SK_HELP}}` | This Help window |

Add your own for *Compress with Dinky* in **System Settings → Keyboard → Keyboard Shortcuts → Services**.

---

## Shortcuts app

Dinky registers a **Compress Images** action for the Shortcuts app. Use it to pipe Finder files or other actions through Dinky with a chosen format — same engine as in-app compression (respects Settings for smart quality, resize, and metadata).

---

## Privacy & safety

- Everything runs **locally**. No uploads, no telemetry, no account.
- **Crash reports** are only sent if *you* choose to — via the post-crash prompt, the "Report a Bug…" menu, or the error detail sheet. If you've opted into macOS diagnostic sharing in System Settings, Apple also delivers anonymised crash data to Dinky on your behalf via MetricKit, with no additional data leaving your Mac.
- The encoders (`cwebp`, `avifenc`, `oxipng`, plus Apple's built-in PDF and AVFoundation video pipelines) ship inside the app and read your files directly.
- Originals are kept by default. *Move originals to trash after compressing* is opt-in, in **Settings → General**.
- *Skip if savings below* (2% by default) protects already-lean files from being re-encoded for nothing.
- *Strip metadata* in any preset removes EXIF, GPS, camera info, and color profiles. Worth it before publishing photos to the web.

---

## Troubleshooting

**A file came out larger than the original.**
Dinky keeps the original instead. You'll see *"Couldn't make this one any smaller. Keeping the original."* in the row.

**A file was skipped.**
It was already very small (under your *Skip if savings below* threshold). Choose *Compress Anyway* from the row's menu to try it regardless.

**A file couldn't be compressed.**
The row says so, and the batch summary opens to show what went wrong. Right-click the row to try again with a different format or quality.

**I dropped files and nothing happened.**
Dinky only takes images, videos, PDFs and audio. The bar at the bottom says which files it skipped.

**A video is taking a long time.**
Video re-encoding is CPU-heavy. The *Batch speed* setting in **Settings → Compression** controls how many files run at once — set it to **Gentle** if your Mac is doing other things.

**My PDF lost text selection / hyperlinks.**
You used *Smallest file (flatten pages)*. Switch the preset's PDF output to *Preserve text (best-effort size)* and re-run. Flatten is for reliable smaller files; preserve keeps text and links when optimization actually reduces size.

**Right-click "Compress with Dinky" isn't showing up.**
Open Dinky once after installing so macOS registers the Service. If it still doesn't appear, enable it in **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**.

**When should I pick JPEG?**
When something on the other end can't open WebP or AVIF — some older apps (FileMaker, for one) and upload forms still want a `.jpg`. Pick **JPEG** in the sidebar, or right-click a file and choose **Compress as JPEG**. Transparent areas turn white, since JPEG has no transparency. Otherwise WebP or AVIF will get you a smaller file at the same quality.

**How do I make images half the size?**
Turn on **Scale** in the full sidebar (or in a preset) and pick 25%, 50%, or 75%, or type any percentage up to 100%. Width and height shrink together, so portrait and landscape images keep their shape. If **Max width** is on too, it still applies after scaling.

---

## Get in touch

- Site: [dinkyfiles.com](https://dinkyfiles.com)
- Code & issues: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- Email: [derek@testamentmade.com](mailto:derek@testamentmade.com)

Built by Derek Castelli. Suggestions, bugs, and "could it also do…" are all welcome.

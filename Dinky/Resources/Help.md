# Welcome

Dinky makes files dinky. Drop something in, get a smaller version out — same look, less weight.

It works on **images** (JPEG, PNG, WebP, AVIF, HEIC/HEIF, TIFF, BMP), **videos** (MP4, MOV, M4V), and **PDFs**.

Everything happens on your Mac. Nothing is uploaded.

---

## Quick start

1. Drag a file (or a pile of them) onto Dinky's window.
2. Watch the count go down.
3. Find the smaller copies next to the originals (default), in your Downloads folder, or in a folder you choose.

That's it. The defaults are good. Read on if you want to bend them to your will.

---

## Ways to compress

You don't have to open the app first. Pick whichever fits how you work.

- **Drag & drop** onto the Dinky window or the Dock icon.
- **Open Files…** — `{{SK_OPEN_FILES}}` to pick from a sheet.
- **Clipboard Compress** — `{{SK_PASTE}}` pastes a supported **file** copied in Finder (images, videos, PDFs) or **raw image** data (PNG/TIFF from screenshots or browsers).
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

### Full sidebar

Toggle **Settings → General → Use simple sidebar** off (or flip individual sections on) to expose every control:

- **Images** — format (Auto, WebP, AVIF, lossless PNG, or HEIC), content hint (photo / illustration / screenshot), max width, max file size.
- **Videos** — codec family (H.264 / HEVC / AV1), quality tier, strip audio.
- **PDFs** — **Smallest file (flatten pages)** is the default for real size savings; **Preserve text (best-effort size)** keeps structure when qpdf/PDFKit can actually shrink the file.

---

## Smart quality

When **Smart quality** is on (default for new presets), Dinky inspects each file and picks settings for it:

- Images get an encoder tuned to their content (busy photo vs. graphic — UI, illustration, logo, screenshot).
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

## Manual mode

Turn on **Settings → General → Manual mode** when you want full control.

Files dropped in won't auto-compress. Right-click any row to pick a format on the spot, use **File → Compress Now** (`{{SK_COMPRESS_NOW}}`) when the queue is ready, or change settings in the sidebar first. Useful when one batch contains very different files.

---

## Keyboard shortcuts

You’ll find the same list in **Settings → Shortcuts** so you don’t have to dig through this page.

| Shortcut | Action |
| --- | --- |
| `{{SK_OPEN_FILES}}` | Open files… |
| `{{SK_PASTE}}` | Clipboard Compress |
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
- **Crash reports** are off by default and never sent automatically. If something goes wrong, the post-crash prompt, the "Report a Bug…" menu, and the error detail sheet pre-fill an email or GitHub issue with version + macOS info — *you* still have to hit Send.
- **Apple crash diagnostics** (MetricKit) are opt-in. Turn on **Settings → General → Privacy → Share crash diagnostics with Dinky** to let Apple deliver anonymous crash and hang reports to Dinky **on your Mac**. The data only leaves your device if you choose to attach it to an email or GitHub issue. Requires *Share with App Developers* under System Settings → Privacy & Security → Analytics & Improvements.
- The encoders (`cwebp`, `avifenc`, `oxipng`, bundled `qpdf` on the preserve-PDF path, plus PDFKit/ImageIO for flatten and AVFoundation for video) ship inside the app and read your files directly.
- Originals are kept by default. *Move originals to trash after compressing* is opt-in, in **Settings → General**.
- *Skip if savings below* (off by default) protects already-lean files from being re-encoded for nothing.
- *Strip metadata* in any preset removes EXIF, GPS, camera info, and color profiles. Worth it before publishing photos to the web.

---

## Troubleshooting

**A file came out larger than the original.**
Dinky keeps the original instead. You'll see *"Couldn't make this one any smaller. Keeping the original."* in the row.

**A file was skipped.**
Either it was already very small (under your *Skip if savings below* threshold), or the encoder couldn't read it. Click the row for details.

**A video is taking a long time.**
Video re-encoding is CPU-heavy. The *Batch speed* setting in **Settings → General** controls how many files run at once — drop it to **Fast** if your Mac is doing other things.

**My PDF lost text selection / hyperlinks.**
You used *Smallest file (flatten pages)*. Switch the preset's PDF output to *Preserve text (best-effort size)* and re-run. Flatten is for reliable smaller files; preserve keeps text and links when optimization actually reduces size.

**Right-click "Compress with Dinky" isn't showing up.**
Open Dinky once after installing so macOS registers the Service. If it still doesn't appear, enable it in **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**.

**Finder’s “Open With” lists two Dinkys (two different versions).**
macOS shows one line per **Dinky.app** path it knows about. If you upgraded via **Homebrew**, run `brew cleanup dinky` so old versions are removed from Caskroom. Otherwise, in Terminal run `mdfind 'kMDItemCFBundleIdentifier == "com.dinky.app"'` to see every copy on disk and delete extras (for example an old app left in Downloads).

**Why doesn't Dinky output JPEG?**
WebP and AVIF are strictly better than JPEG — same visual quality, smaller file, and supported everywhere that matters. If your platform requires a `.jpg`, try WebP first; it's accepted almost universally now. If you hit a place that genuinely rejects it, get in touch and let us know.

---

## Get in touch

- Site: [dinkyfiles.com](https://dinkyfiles.com)
- Code & issues: [github.com/heyderekj/dinky](https://github.com/heyderekj/dinky)
- Email: [help@dinkyfiles.com](mailto:help@dinkyfiles.com)

Built by Derek Castelli. Suggestions, bugs, and "could it also do…" are all welcome.

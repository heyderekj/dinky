# Dinky

A small macOS utility that compresses images. Drop files in, get smaller ones back.

Supports JPG, PNG, WebP, and AVIF. Outputs WebP or AVIF depending on your preference. Strips metadata, respects max dimensions and file size targets, and saves next to the original by default.

## About the developer

[Derek Castelli](https://www.heyderekj.com) is a full-time freelance web designer working primarily in Webflow and Figma. Image compression is a constant part of the job — every site build involves optimizing photos for fast load times, and doing that by hand in a browser or through a bloated app gets old fast. Dinky came out of that frustration.

## Features

- **Drag and drop** — drop images straight onto the window, or use the file picker
- **Format conversion** — outputs WebP or AVIF, where the real savings happen
- **Max width** — resize on the way out with common web presets or a custom value
- **Max file size** — binary-searches the quality level to hit an exact KB/MB target
- **Batch compression** — multiple files compress concurrently, live results as they finish
- **Show in Finder** — jump straight to any compressed file from the results list
- **Finder-like selection** — click, cmd+click, shift+click, double-click to open, drag to anywhere
- **Destination** — save next to the original or pick a custom folder
- **Performance** — Stroll (one at a time) or Sprint (all cores)
- **Notifications** — get a tap when a batch finishes, with messaging that varies by count and time
- **Advanced** — strip metadata, sanitize filenames for web, open output folder automatically, move originals to trash
- **Quirky idle animation** — three choreographed card-drop variants that loop then hold until you come back
- 4.1 MB. Appropriately dinky.

### What others don't do

- **Actually changes the format** — ImageOptim squeezes your JPEG and hands it back as a JPEG. Dinky converts to WebP or AVIF, which is where 30–80% of the real savings live. Optimage does this too, but costs money and weighs 62 MB.
- **Results you can act on** — most compression apps give you a done screen you can't do anything with. Dinky's results list works like Finder: select files, drag them somewhere else, double-click to open, right-click to remove individual items.
- **Notifications with a personality** — other apps either don't notify at all or send a generic "Done." Dinky's notification changes based on how many files you compressed and how long it took. Small things, but they add up.
- **Free, open source, and tiny** — Optimage is $69. ImageOptim is free but lossless only. Dinky is free, open source, converts formats, and fits in a fraction of the space either of them takes up.

## Why it exists

Optimage crashed. Instead of finding a replacement, I figured it was a good excuse to build my own — this was my first macOS app.

I liked [Squoosh](https://github.com/GoogleChromeLabs/squoosh) but didn't want to be in a browser every time I needed to compress something. I wanted something that lived on my Mac, stayed out of the way, and just worked.

## How it differs from ImageOptim and Optimage

ImageOptim is lossless only — it makes your JPEG or PNG smaller without changing the format. Optimage does lossy and lossless but also mostly keeps you in the source format. Both are good at what they do.

Dinky takes a different approach: it converts to WebP or AVIF. That format change is where most of the real savings come from — often 30–80% smaller than a JPEG or PNG at the same visual quality. If you're putting images on the web or into a CMS and you're still working with JPEGs and PNGs, converting the format matters more than squeezing the existing one.

## How it works

Built entirely in Swift and SwiftUI for macOS 26 (Tahoe). No Electron, no web views, no third-party UI frameworks. The whole app is 4.1 MB, which feels appropriate for something called Dinky.

Compression runs through a native `actor`-based service that shells out to platform image tools, keeping the main thread free. Multiple files compress concurrently up to the core count of the machine. Output quality is tuned automatically to hit the target file size if one is set.

The sidebar stores preferences via `@AppStorage`. The results list updates live as each file finishes. Error details are tappable. The idle animation on the drop zone runs through three choreographed variants then holds — portrait, landscape, and wide cards dragged in by a pinch cursor from whatever corner the window is closest to.

The app registers as an "Open with" handler and exposes a Finder Quick Action so you can compress without opening the app manually.

## Built with

- SwiftUI (macOS 26)
- AppKit for window and event integration
- `actor` concurrency model for compression
- `@AppStorage` / `UserDefaults` for preferences
- `NSServices` for Finder integration
- Claude for most of the code

## Compression engines

Dinky is a native front-end for these open-source CLI tools, which do the actual work:

- [cwebp](https://developers.google.com/speed/webp) — Google's WebP encoder (BSD)
- [avifenc](https://github.com/AOMediaCodec/libavif) — Alliance for Open Media's AVIF encoder (BSD)
- [cjpeg](https://github.com/mozilla/mozjpeg) — Mozilla's MozJPEG (MPL/BSD)
- [oxipng](https://github.com/shssoichiro/oxipng) — lossless PNG optimizer in Rust (MIT)

## Install

Download the DMG and drag Dinky to Applications.

Since the app isn't notarized, macOS will block it on first launch. To get past this, go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. That's a one-time step — it opens normally after that.

Or run this in Terminal:
```bash
xattr -dr com.apple.quarantine /Applications/Dinky.app
```

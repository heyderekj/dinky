# Dinky

A small macOS utility that compresses images. Drop files in, get smaller ones back.

Supports JPG, PNG, WebP, and AVIF. Outputs WebP or AVIF depending on your preference. Strips metadata, respects max dimensions and file size targets, and saves next to the original by default.

## Why it exists

Optimage crashed. Instead of finding a replacement, I figured it was a good excuse to build my own — this was my first macOS app.

I liked [Squoosh](https://github.com/GoogleChromeLabs/squoosh) but didn't want to be in a browser every time I needed to compress something. I wanted something that lived on my Mac, stayed out of the way, and just worked.

## How it differs from ImageOptim and Optimage

ImageOptim is lossless only — it makes your JPEG or PNG smaller without changing the format. Optimage does lossy and lossless but also mostly keeps you in the source format. Both are good at what they do.

Dinky takes a different approach: it converts to WebP or AVIF. That format change is where most of the real savings come from — often 30–80% smaller than a JPEG or PNG at the same visual quality. If you're putting images on the web or into a CMS and you're still working with JPEGs and PNGs, converting the format matters more than squeezing the existing one.

## How it works

Built entirely in Swift and SwiftUI for macOS 26 (Tahoe). No Electron, no web views, no third-party UI frameworks.

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

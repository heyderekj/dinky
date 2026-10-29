# Compression Binaries

Place arm64 macOS CLI binaries here. Dinky expects them at:

```
Dinky.app/Contents/Resources/bin/
├── cjpeg      ← MozJPEG
├── cwebp      ← libwebp / Google WebP
├── oxipng     ← OxiPNG
├── avifenc    ← libavif
└── qpdf       ← QPDF (preserve-mode structural optimize; needs `lib/*.dylib` — see below)
```

After placing binaries, make them executable:
```bash
chmod +x bin/cjpeg bin/cwebp bin/oxipng bin/avifenc
```

Then remove quarantine (required for unsigned binaries on macOS):
```bash
xattr -d com.apple.quarantine bin/cjpeg bin/cwebp bin/oxipng bin/avifenc
```

---

## Download links (arm64 / Apple Silicon)

### cjpeg (MozJPEG)
Build from source or grab a prebuilt binary from:
- https://github.com/mozilla/mozjpeg/releases
- Homebrew: `brew install mozjpeg` → binary at `/opt/homebrew/opt/mozjpeg/bin/cjpeg`

### cwebp (WebP)
- https://developers.google.com/speed/webp/download
- Homebrew: `brew install webp` → binary at `/opt/homebrew/bin/cwebp`

### oxipng
- https://github.com/shssoichiro/oxipng/releases
- Grab `oxipng-*-aarch64-apple-darwin.tar.gz`
- Homebrew: `brew install oxipng`

### avifenc (libavif)
- https://github.com/AOMediaCodec/libavif/releases
- Homebrew: `brew install libavif` → binary at `/opt/homebrew/bin/avifenc`

---

## Quick setup via Homebrew

```bash
brew install mozjpeg webp oxipng libavif

cp /opt/homebrew/opt/mozjpeg/bin/cjpeg  bin/
cp /opt/homebrew/bin/cwebp               bin/
cp /opt/homebrew/bin/oxipng             bin/
cp /opt/homebrew/bin/avifenc            bin/

chmod +x bin/*
xattr -d com.apple.quarantine bin/* 2>/dev/null || true
```

### qpdf (PDF structure / streams)

Homebrew’s `qpdf` links to `libqpdf`, `jpeg-turbo`, and `openssl@3`. After copying the binary into `bin/`, copy the dylibs into `../lib/` and fix loader paths (Apple Silicon example):

```bash
brew install qpdf
cp /opt/homebrew/bin/qpdf bin/
cp /opt/homebrew/opt/qpdf/lib/libqpdf.*.dylib ../lib/
cp /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib ../lib/

chmod +x bin/qpdf
install_name_tool -change @rpath/libqpdf.30.dylib @loader_path/lib/libqpdf.30.3.2.dylib bin/qpdf
# Xcode copies `bin/qpdf` into the app bundle’s `Resources/` root, so use `@loader_path/lib/…` (same folder as `cwebp`), not `../lib`.
# Point libqpdf at vendored libjpeg + libcrypto (see `otool -L` on your copies).
# libqpdf shares `lib/libjpeg.8.dylib` with cwebp/avifenc; don't vendor a second libjpeg.
install_name_tool -change <libqpdf's libjpeg path> @loader_path/libjpeg.8.dylib ../lib/libqpdf.30.3.2.dylib
```

Then re-sign in Xcode’s “Re-sign bundled binaries” phase (or `codesign -s - --force` on `qpdf` and each dylib).

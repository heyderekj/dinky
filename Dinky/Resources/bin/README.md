# Compression Binaries

Place universal macOS CLI binaries here. Dinky expects them at:

```
Dinky.app/Contents/Resources/bin/
├── cjpeg      ← MozJPEG
├── cwebp      ← libwebp / Google WebP
├── oxipng     ← OxiPNG
├── avifenc    ← libavif
└── qpdf       ← QPDF (preserve-mode structural optimize; needs `lib/*.dylib` — see below)
```

The Xcode project copies these executables into `Dinky.app/Contents/Resources/`
and copies `Dinky/Resources/lib/` to `Dinky.app/Contents/Resources/lib/`.
Release builds should therefore keep both the executables and every bundled
dylib as universal `arm64 x86_64` Mach-O files.

After placing binaries, make them executable:
```bash
chmod +x bin/cjpeg bin/cwebp bin/oxipng bin/avifenc
```

Then remove quarantine (required for unsigned binaries on macOS):
```bash
xattr -d com.apple.quarantine bin/cjpeg bin/cwebp bin/oxipng bin/avifenc
```

---

## Universal helper refresh

Run this from the repo root to rebuild the checked-in helper payload from the
current arm64 slices plus Intel Homebrew bottles:

```bash
tools/vendor_universal_binaries.sh
```

The script downloads public Homebrew bottle blobs into `build/`, extracts the
x86_64 slices, patches their install names/rpaths to Dinky's bundle layout, and
combines them with the checked-in arm64 slices via `lipo`.

To inspect the result:

```bash
for f in Dinky/Resources/bin/{cwebp,avifenc,oxipng,qpdf,lame} Dinky/Resources/lib/*.dylib; do
  echo "$f: $(lipo -archs "$f")"
done
```

---

## Download links

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
cp /opt/homebrew/opt/jpeg-turbo/lib/libjpeg.*.dylib ../lib/
cp /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib ../lib/

chmod +x bin/qpdf
install_name_tool -change @rpath/libqpdf.30.dylib @loader_path/lib/libqpdf.30.3.2.dylib bin/qpdf
# Xcode copies `bin/qpdf` into the app bundle’s `Resources/` root, so use `@loader_path/lib/…` (same folder as `cwebp`), not `../lib`.
# Point libqpdf at vendored libjpeg + libcrypto (see `otool -L` on your copies).
```

Then re-sign in Xcode’s “Re-sign bundled binaries” phase (or `codesign -s - --force` on `qpdf` and each dylib).

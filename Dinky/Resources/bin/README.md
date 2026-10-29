# Compression Binaries

Xcode copies these into the app bundle's `Contents/Resources/` root. Every encoder is a single
static arm64 binary that links only system libraries (`libSystem`, `libz`, `libc++`, `libiconv`),
so there is no `lib/` folder of dylibs to ship or re-point.

| Binary    | Version | Built from | Notes |
|-----------|---------|------------|-------|
| `cwebp`   | libwebp 1.6.0 | source | Reads PNG/JPEG/WebP only (no TIFF). Dinky decodes every other input to PNG first. |
| `avifenc` | libavif 1.4.1 + libaom 3.13.3 | source | aom encoder only: no AV1 decoder, no dav1d, no VMAF/Butteraugli tuning, no SVE kernels. `-O3`. 10-bit (`--depth 10`) supported. |
| `oxipng`  | 10.1.0 | crates.io | No zopfli (Dinky never passes `--zopfli`); `--threads` works. |
| `qpdf`    | 12.3.2 | source | Native crypto instead of OpenSSL. `--optimize-images` uses the static libjpeg-turbo. |
| `lame`    | 3.100 | Homebrew | Unchanged. |

Shared static deps: libjpeg-turbo 3.1.4.1, libpng 1.6.57 (zlib comes from macOS).
These are the same versions the 2.16 bundle shipped as Homebrew dylibs, and the encodes are
byte-for-byte identical to that build's.

## Rebuilding

```bash
brew install cmake ninja      # plus Xcode command line tools and Rust 1.85+ (rustup)
tools/build_encoders.sh /tmp/dinky-encoders Dinky/Resources/bin
```

`tools/build_encoders.sh` downloads the pinned sources, builds them static for arm64 with a
macOS 15.0 deployment target, strips and ad-hoc signs the four binaries, and fails if any of them
links a non-system library. To move to a new version, change the `*_VER` line at the top and
re-check the outputs against the old binaries.

The key configure flags, for reference:

- **libwebp**: `-DBUILD_SHARED_LIBS=OFF -DWEBP_BUILD_{DWEBP,GIF2WEBP,IMG2WEBP,VWEBP,WEBPINFO,WEBPMUX,EXTRAS,ANIM_UTILS}=OFF`, TIFF and GIF not found.
- **libaom**: `-DCMAKE_BUILD_TYPE=Release -DCONFIG_AV1_DECODER=0 -DCONFIG_TUNE_VMAF=0 -DCONFIG_TUNE_BUTTERAUGLI=0 -DENABLE_SVE=0 -DENABLE_SVE2=0 -DBUILD_SHARED_LIBS=0`
- **libavif**: `-DAVIF_CODEC_AOM=SYSTEM -DAVIF_CODEC_AOM_DECODE=OFF -DAVIF_CODEC_DAV1D=OFF -DAVIF_BUILD_APPS=ON -DAVIF_LIBYUV=OFF -DAVIF_LIBSHARPYUV=OFF -DBUILD_SHARED_LIBS=OFF`
- **qpdf**: `-DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=OFF -DBUILD_STATIC_LIBS=ON -DREQUIRE_CRYPTO_NATIVE=ON -DUSE_IMPLICIT_CRYPTO=OFF -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON`
- **oxipng**: `cargo install oxipng --version 10.1.0 --locked --no-default-features --features binary,parallel` with `CARGO_PROFILE_RELEASE_{LTO=fat,CODEGEN_UNITS=1,PANIC=abort,STRIP=symbols}`
- Everything: `-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_EXE_LINKER_FLAGS=-Wl,-dead_strip`

The "Re-sign bundled binaries" build phase ad-hoc signs everything in `Resources` again at build
time, so a binary whose signature was invalidated (for example by `install_name_tool`) still runs.

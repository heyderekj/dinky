#!/bin/zsh
# Builds Dinky's bundled encoders as small, fully static arm64 binaries:
#   cwebp (libwebp), avifenc (libavif + libaom encoder), oxipng, qpdf.
# Only system zlib/libc++ are linked dynamically, so Resources/lib is not needed.
#
# Usage: tools/build_encoders.sh <work-dir> [out-dir]
#   <work-dir> gets src/, build/ and prefix/; binaries land in out-dir (default: <work-dir>/out).
# Needs: Xcode command line tools, cmake, ninja (brew install cmake ninja), Rust 1.85+ (rustup).
# Versions match what Dinky shipped before, so encodes are byte-for-byte the same.
set -euo pipefail

JPEG_VER=3.1.4.1
PNG_VER=1.6.57
WEBP_VER=1.6.0
AOM_VER=3.13.3
AVIF_VER=1.4.1
QPDF_VER=12.3.2
OXIPNG_VER=10.1.0

WORK=${1:?usage: build_encoders.sh <work-dir> [out-dir]}
mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
OUT=${2:-$WORK/out}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
SRC=$WORK/src B=$WORK/build P=$WORK/prefix
mkdir -p "$SRC" "$B" "$P"

export MACOSX_DEPLOYMENT_TARGET=15.0
export PKG_CONFIG_LIBDIR=$P/lib/pkgconfig
CM=(-G Ninja -DCMAKE_EXE_LINKER_FLAGS=-Wl,-dead_strip -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOSX_DEPLOYMENT_TARGET
    -DCMAKE_INSTALL_PREFIX=$P -DCMAKE_PREFIX_PATH=$P -DCMAKE_FIND_FRAMEWORK=NEVER
    "-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew;/usr/local" -DBUILD_SHARED_LIBS=OFF)

fetch() { # name url
  [[ -d $SRC/$1 ]] && return
  curl -fsSL "$2" -o "$SRC/$1.tar.gz"
  mkdir "$SRC/$1" && tar xzf "$SRC/$1.tar.gz" -C "$SRC/$1" --strip-components 1
}
build() { # name source-dir cmake-args...
  local name=$1 dir=$2; shift 2
  cmake -S "$dir" -B "$B/$name" "${CM[@]}" "$@" >/dev/null
  ninja -C "$B/$name" install >/dev/null
  echo "built $name"
}

fetch jpeg https://github.com/libjpeg-turbo/libjpeg-turbo/releases/download/$JPEG_VER/libjpeg-turbo-$JPEG_VER.tar.gz
fetch png  https://download.sourceforge.net/libpng/libpng-$PNG_VER.tar.gz
fetch webp https://github.com/webmproject/libwebp/archive/refs/tags/v$WEBP_VER.tar.gz
fetch avif https://github.com/AOMediaCodec/libavif/archive/refs/tags/v$AVIF_VER.tar.gz
fetch qpdf https://github.com/qpdf/qpdf/releases/download/v$QPDF_VER/qpdf-$QPDF_VER.tar.gz
[[ -d $SRC/aom ]] || git clone -q --depth 1 --branch v$AOM_VER https://aomedia.googlesource.com/aom "$SRC/aom"

build jpeg "$SRC/jpeg" -DCMAKE_BUILD_TYPE=Release -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DWITH_TURBOJPEG=OFF -DWITH_TESTS=OFF
build png  "$SRC/png"  -DCMAKE_BUILD_TYPE=Release -DPNG_SHARED=OFF -DPNG_STATIC=ON -DPNG_TESTS=OFF -DPNG_TOOLS=OFF -DPNG_FRAMEWORK=OFF

# cwebp: PNG/JPEG/WebP input only (Dinky decodes everything else to PNG first).
build webp "$SRC/webp" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_DISABLE_FIND_PACKAGE_TIFF=ON -DCMAKE_DISABLE_FIND_PACKAGE_GIF=ON \
  -DWEBP_BUILD_CWEBP=ON -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
  -DWEBP_BUILD_ANIM_UTILS=OFF

# libaom: encoder only, no VMAF tuning (Dinky never passes --tune vmaf). -O3 (CMake Release) is ~45% faster
# than Homebrew's -Os. Apple Silicon has no SVE, so those kernels would never be picked at runtime.
build aom "$SRC/aom" -DCMAKE_BUILD_TYPE=Release \
  -DCONFIG_AV1_DECODER=0 -DCONFIG_TUNE_VMAF=0 -DCONFIG_TUNE_BUTTERAUGLI=0 \
  -DENABLE_SVE=0 -DENABLE_SVE2=0 \
  -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TESTDATA=0 -DENABLE_TOOLS=0

# avifenc: aom encode only, no dav1d; libyuv/libsharpyuv off as in the build Dinky shipped.
build avif "$SRC/avif" -DCMAKE_BUILD_TYPE=Release \
  -DAVIF_CODEC_AOM=SYSTEM -DAVIF_CODEC_AOM_ENCODE=ON -DAVIF_CODEC_AOM_DECODE=OFF -DAVIF_CODEC_DAV1D=OFF \
  -DAVIF_BUILD_APPS=ON -DAVIF_JPEG=SYSTEM -DAVIF_ZLIBPNG=SYSTEM \
  -DAVIF_LIBYUV=OFF -DAVIF_LIBSHARPYUV=OFF -DAVIF_LIBXML2=OFF

# qpdf: native crypto instead of OpenSSL, one static binary.
build qpdf "$SRC/qpdf" -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_STATIC_LIBS=ON \
  -DREQUIRE_CRYPTO_NATIVE=ON -DUSE_IMPLICIT_CRYPTO=OFF -DBUILD_DOC=OFF -DINSTALL_EXAMPLES=OFF \
  -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON

# oxipng: no zopfli (Dinky never passes --zopfli).
CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1 \
CARGO_PROFILE_RELEASE_PANIC=abort CARGO_PROFILE_RELEASE_STRIP=symbols \
  cargo install oxipng --version $OXIPNG_VER --locked --no-default-features \
    --features binary,parallel --root "$B/oxipng" --force -q
echo "built oxipng"

for t in cwebp avifenc qpdf; do cp "$P/bin/$t" "$OUT/"; done
cp "$B/oxipng/bin/oxipng" "$OUT/"
for t in cwebp avifenc qpdf oxipng; do
  strip -x "$OUT/$t" 2>/dev/null || true
  codesign -s - --force "$OUT/$t" 2>/dev/null
  if otool -L "$OUT/$t" | tail -n +2 | grep -qv '/usr/lib/'; then
    echo "error: $t links a non-system library:" >&2; otool -L "$OUT/$t" >&2; exit 1
  fi
done
ls -l "$OUT"

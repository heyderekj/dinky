#!/bin/bash
# Build universal macOS helper binaries for Dinky from the checked-in arm64
# slices plus Intel Homebrew bottles.
#
# The app copies the files in Dinky/Resources/bin into Contents/Resources and
# the lib folder into Contents/Resources/lib. Homebrew bottles use Cellar paths
# and @loader_path/../lib, so this script patches the Intel slices to Dinky's
# bundle layout before combining them with lipo.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CACHE_DIR="${DINKY_BOTTLE_CACHE:-$ROOT/build/universal-binaries}"
BOTTLES_DIR="$CACHE_DIR/bottles"
EXTRACT_DIR="$CACHE_DIR/extract"
STAGE_DIR="$CACHE_DIR/x86_64-stage"
BOTTLE_PLATFORMS=(${DINKY_BOTTLE_PLATFORMS:-sonoma sequoia ventura tahoe})

require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required tool '$1' not found" >&2
    exit 1
  }
}

for tool in curl jq tar shasum lipo install_name_tool codesign otool; do
  require_tool "$tool"
done

mkdir -p "$BOTTLES_DIR" "$EXTRACT_DIR" "$STAGE_DIR/bin" "$STAGE_DIR/lib"

formula_slug() {
  printf '%s' "$1" | tr '@/' '__'
}

download_formula() {
  local formula="$1"
  local slug api platform url sha repo_path token bottle

  slug="$(formula_slug "$formula")"
  api="$(curl -fsS "https://formulae.brew.sh/api/formula/${formula}.json")"
  platform=""
  for candidate in "${BOTTLE_PLATFORMS[@]}"; do
    if printf '%s' "$api" | jq -e --arg k "$candidate" '.bottle.stable.files | has($k)' >/dev/null; then
      platform="$candidate"
      break
    fi
  done
  if [ -z "$platform" ]; then
    echo "error: no supported Intel bottle for $formula" >&2
    exit 1
  fi

  url="$(printf '%s' "$api" | jq -r --arg k "$platform" '.bottle.stable.files[$k].url')"
  sha="$(printf '%s' "$api" | jq -r --arg k "$platform" '.bottle.stable.files[$k].sha256')"
  repo_path="$(printf '%s' "$url" | sed -E 's#https://ghcr.io/v2/(.*)/blobs/.*#\1#')"
  token="$(curl -fsS "https://ghcr.io/token?scope=repository:${repo_path}:pull&service=ghcr.io" | jq -r .token)"
  bottle="$BOTTLES_DIR/${slug}.tar.gz"

  if [ ! -f "$bottle" ] || [ "$(shasum -a 256 "$bottle" 2>/dev/null | awk '{print $1}')" != "$sha" ]; then
    echo "download $formula ($platform)"
    curl -fsSL -H "Authorization: Bearer $token" "$url" -o "$bottle"
  else
    echo "cached $formula ($platform)"
  fi

  if [ "$(shasum -a 256 "$bottle" | awk '{print $1}')" != "$sha" ]; then
    echo "error: sha256 mismatch for $formula" >&2
    exit 1
  fi

  rm -rf "$EXTRACT_DIR/$slug"
  mkdir -p "$EXTRACT_DIR/$slug"
  tar -xzf "$bottle" -C "$EXTRACT_DIR/$slug"
}

first_match() {
  local root="$1"
  local name="$2"
  find "$root" -type f -name "$name" | head -n 1
}

copy_from_formula() {
  local formula="$1"
  local source_name="$2"
  local dest="$3"
  local slug src

  slug="$(formula_slug "$formula")"
  src="$(first_match "$EXTRACT_DIR/$slug" "$source_name")"
  if [ -z "$src" ]; then
    echo "error: could not find $source_name in $formula bottle" >&2
    exit 1
  fi
  cp "$src" "$dest"
  chmod +w "$dest"
}

change_if_present() {
  local file="$1"
  local old="$2"
  local new="$3"
  if otool -L "$file" | grep -Fq "$old"; then
    install_name_tool -change "$old" "$new" "$file"
  fi
}

id_if_dylib() {
  local file="$1"
  local id="$2"
  install_name_tool -id "$id" "$file"
}

rpath_if_present() {
  local file="$1"
  local old="$2"
  local new="$3"
  if otool -l "$file" | grep -Fq "$old"; then
    install_name_tool -rpath "$old" "$new" "$file"
  fi
}

merge_universal() {
  local arm_file="$1"
  local x86_file="$2"
  local dest="$3"
  local tmp arm_tmp

  tmp="$(mktemp "$CACHE_DIR/lipo.XXXXXX")"
  arm_tmp="$(mktemp "$CACHE_DIR/arm64.XXXXXX")"
  if [ "$(lipo -archs "$arm_file")" = "arm64" ]; then
    cp "$arm_file" "$arm_tmp"
  else
    lipo "$arm_file" -thin arm64 -output "$arm_tmp"
  fi
  lipo -create "$arm_tmp" "$x86_file" -output "$tmp"
  mv "$tmp" "$dest"
  rm -f "$arm_tmp"
}

for formula in webp libavif oxipng qpdf lame jpeg-turbo libpng libtiff xz zstd openssl@3 aom dav1d libvmaf; do
  download_formula "$formula"
done

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/bin" "$STAGE_DIR/lib"

copy_from_formula libavif avifenc "$STAGE_DIR/bin/avifenc"
copy_from_formula webp cwebp "$STAGE_DIR/bin/cwebp"
copy_from_formula lame lame "$STAGE_DIR/bin/lame"
copy_from_formula oxipng oxipng "$STAGE_DIR/bin/oxipng"
copy_from_formula qpdf qpdf "$STAGE_DIR/bin/qpdf"

copy_from_formula aom 'libaom.3.*.dylib' "$STAGE_DIR/lib/libaom.3.dylib"
copy_from_formula libavif 'libavif.16.*.dylib' "$STAGE_DIR/lib/libavif.16.dylib"
copy_from_formula openssl@3 libcrypto.3.dylib "$STAGE_DIR/lib/libcrypto.3.dylib"
copy_from_formula dav1d libdav1d.7.dylib "$STAGE_DIR/lib/libdav1d.7.dylib"
copy_from_formula jpeg-turbo 'libjpeg.8.*.dylib' "$STAGE_DIR/lib/libjpeg.8.3.2.dylib"
cp "$STAGE_DIR/lib/libjpeg.8.3.2.dylib" "$STAGE_DIR/lib/libjpeg.8.dylib"
copy_from_formula xz liblzma.5.dylib "$STAGE_DIR/lib/liblzma.5.dylib"
copy_from_formula libpng libpng16.16.dylib "$STAGE_DIR/lib/libpng16.16.dylib"
copy_from_formula qpdf 'libqpdf.30.*.dylib' "$STAGE_DIR/lib/libqpdf.30.3.2.dylib"
copy_from_formula webp 'libsharpyuv.0.*.dylib' "$STAGE_DIR/lib/libsharpyuv.0.dylib"
copy_from_formula libtiff libtiff.6.dylib "$STAGE_DIR/lib/libtiff.6.dylib"
copy_from_formula libvmaf libvmaf.3.dylib "$STAGE_DIR/lib/libvmaf.3.dylib"
copy_from_formula webp 'libwebp.7.*.dylib' "$STAGE_DIR/lib/libwebp.7.dylib"
copy_from_formula webp 'libwebpdemux.2.*.dylib' "$STAGE_DIR/lib/libwebpdemux.2.dylib"
copy_from_formula zstd 'libzstd.1.*.dylib' "$STAGE_DIR/lib/libzstd.1.dylib"

# Match Dinky's app bundle layout: binaries are copied to Resources/, and
# dylibs live in Resources/lib.
rpath_if_present "$STAGE_DIR/bin/avifenc" "@loader_path/../lib" "@loader_path/lib"
rpath_if_present "$STAGE_DIR/bin/cwebp" "@loader_path/../lib" "@loader_path/lib"
rpath_if_present "$STAGE_DIR/bin/qpdf" "@loader_path/../lib" "@loader_path/lib"

for file in "$STAGE_DIR/bin/"* "$STAGE_DIR/lib/"*.dylib; do
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/aom/lib/libaom.3.dylib" "@rpath/libaom.3.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/dav1d/lib/libdav1d.7.dylib" "@rpath/libdav1d.7.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/jpeg-turbo/lib/libjpeg.8.dylib" "@rpath/libjpeg.8.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/libavif/lib/libavif.16.dylib" "@rpath/libavif.16.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/libpng/lib/libpng16.16.dylib" "@rpath/libpng16.16.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/libtiff/lib/libtiff.6.dylib" "@rpath/libtiff.6.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/libvmaf/lib/libvmaf.3.dylib" "@rpath/libvmaf.3.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/openssl@3/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/qpdf/lib/libqpdf.30.dylib" "@loader_path/lib/libqpdf.30.3.2.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/webp/lib/libsharpyuv.0.dylib" "@rpath/libsharpyuv.0.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/webp/lib/libwebp.7.dylib" "@rpath/libwebp.7.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/webp/lib/libwebpdemux.2.dylib" "@rpath/libwebpdemux.2.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/xz/lib/liblzma.5.dylib" "@rpath/liblzma.5.dylib"
  change_if_present "$file" "@@HOMEBREW_PREFIX@@/opt/zstd/lib/libzstd.1.dylib" "@rpath/libzstd.1.dylib"
done

change_if_present "$STAGE_DIR/bin/qpdf" "@rpath/libqpdf.30.dylib" "@loader_path/lib/libqpdf.30.3.2.dylib"
change_if_present "$STAGE_DIR/lib/libqpdf.30.3.2.dylib" "@rpath/libjpeg.8.dylib" "@loader_path/libjpeg.8.3.2.dylib"
change_if_present "$STAGE_DIR/lib/libqpdf.30.3.2.dylib" "@loader_path/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib"

id_if_dylib "$STAGE_DIR/lib/libaom.3.dylib" "@rpath/libaom.3.dylib"
id_if_dylib "$STAGE_DIR/lib/libavif.16.dylib" "@rpath/libavif.16.dylib"
id_if_dylib "$STAGE_DIR/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib"
id_if_dylib "$STAGE_DIR/lib/libdav1d.7.dylib" "@rpath/libdav1d.7.dylib"
id_if_dylib "$STAGE_DIR/lib/libjpeg.8.3.2.dylib" "@loader_path/libjpeg.8.3.2.dylib"
id_if_dylib "$STAGE_DIR/lib/libjpeg.8.dylib" "@rpath/libjpeg.8.dylib"
id_if_dylib "$STAGE_DIR/lib/liblzma.5.dylib" "@rpath/liblzma.5.dylib"
id_if_dylib "$STAGE_DIR/lib/libpng16.16.dylib" "@rpath/libpng16.16.dylib"
id_if_dylib "$STAGE_DIR/lib/libqpdf.30.3.2.dylib" "@loader_path/libqpdf.30.3.2.dylib"
id_if_dylib "$STAGE_DIR/lib/libsharpyuv.0.dylib" "@rpath/libsharpyuv.0.dylib"
id_if_dylib "$STAGE_DIR/lib/libtiff.6.dylib" "@rpath/libtiff.6.dylib"
id_if_dylib "$STAGE_DIR/lib/libvmaf.3.dylib" "@rpath/libvmaf.3.dylib"
id_if_dylib "$STAGE_DIR/lib/libwebp.7.dylib" "@rpath/libwebp.7.dylib"
id_if_dylib "$STAGE_DIR/lib/libwebpdemux.2.dylib" "@rpath/libwebpdemux.2.dylib"
id_if_dylib "$STAGE_DIR/lib/libzstd.1.dylib" "@rpath/libzstd.1.dylib"

for tool in avifenc cwebp lame oxipng qpdf; do
  merge_universal "Dinky/Resources/bin/$tool" "$STAGE_DIR/bin/$tool" "Dinky/Resources/bin/$tool"
done

for lib in Dinky/Resources/lib/*.dylib; do
  name="$(basename "$lib")"
  merge_universal "$lib" "$STAGE_DIR/lib/$name" "$lib"
done

chmod +x Dinky/Resources/bin/avifenc Dinky/Resources/bin/cwebp Dinky/Resources/bin/lame Dinky/Resources/bin/oxipng Dinky/Resources/bin/qpdf

for file in Dinky/Resources/bin/avifenc Dinky/Resources/bin/cwebp Dinky/Resources/bin/lame Dinky/Resources/bin/oxipng Dinky/Resources/bin/qpdf Dinky/Resources/lib/*.dylib; do
  codesign -s - --force "$file" >/dev/null
done

echo "Universal helper payload ready:"
for file in Dinky/Resources/bin/avifenc Dinky/Resources/bin/cwebp Dinky/Resources/bin/lame Dinky/Resources/bin/oxipng Dinky/Resources/bin/qpdf Dinky/Resources/lib/*.dylib; do
  printf '  %-48s %s\n' "$file" "$(lipo -archs "$file")"
done

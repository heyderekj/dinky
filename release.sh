#!/bin/bash
# release.sh — build, package, and publish a new Dinky release.
#
# Usage:
#   ./release.sh 1.2.3
#
# What it does:
#   1. Bumps MARKETING_VERSION in the Xcode project
#   2. Updates version + download URLs in site/index.html and site/llms.txt
#   3. Builds the Release scheme
#   4. Creates the DMG
#   5. Commits, tags, pushes, and publishes the GitHub release
#
# Prerequisites: create-dmg (brew install create-dmg), gh (brew install gh)

set -e  # exit on any error

# ── Validate ──────────────────────────────────────────────────────────────────

if [ -z "$1" ]; then
  echo "Usage: ./release.sh <version>  (e.g. ./release.sh 1.2.3)"
  exit 1
fi

VERSION="$1"
PREV_VERSION=$(grep "MARKETING_VERSION" Dinky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
PREV_BUILD=$(grep "CURRENT_PROJECT_VERSION" Dinky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')

echo "▶ Releasing Dinky v$VERSION (was $PREV_VERSION, build $PREV_BUILD)"
echo ""

# ── 1. Bump version ───────────────────────────────────────────────────────────

echo "→ Bumping version in project.pbxproj…"
sed -i '' "s/MARKETING_VERSION = $PREV_VERSION/MARKETING_VERSION = $VERSION/g" \
  Dinky.xcodeproj/project.pbxproj
sed -i '' "s/CURRENT_PROJECT_VERSION = $PREV_BUILD/CURRENT_PROJECT_VERSION = $VERSION/g" \
  Dinky.xcodeproj/project.pbxproj

# ── 2. Update site ────────────────────────────────────────────────────────────

echo "→ Updating site/index.html…"
sed -i '' "s/v$PREV_VERSION · Requires/v$VERSION · Requires/g" site/index.html
sed -i '' "s/v$PREV_VERSION\/Dinky-$PREV_VERSION.dmg/v$VERSION\/Dinky-$VERSION.dmg/g" site/index.html
sed -i '' "s/\"softwareVersion\": \"$PREV_VERSION\"/\"softwareVersion\": \"$VERSION\"/g" site/index.html

echo "→ Updating site/llms.txt…"
sed -i '' "s/v$PREV_VERSION/v$VERSION/g" site/llms.txt
sed -i '' "s/Dinky-$PREV_VERSION\.dmg/Dinky-$VERSION.dmg/g" site/llms.txt

if [ -f site/homepage.md ]; then
  echo "→ Updating site/homepage.md…"
  sed -i '' "s/v$PREV_VERSION/v$VERSION/g" site/homepage.md
  sed -i '' "s/Dinky-$PREV_VERSION\.dmg/Dinky-$VERSION.dmg/g" site/homepage.md
fi

# ── 3. Build ──────────────────────────────────────────────────────────────────

echo "→ Building Release…"
xcodebuild -scheme Dinky -configuration Release -derivedDataPath build clean build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# ── 4. Create DMG ─────────────────────────────────────────────────────────────

echo "→ Creating Dinky-$VERSION.dmg…"
rm -f "Dinky-$VERSION.dmg"
create-dmg \
  --volname "Dinky" \
  --volicon "Dinky/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png" \
  --background "dmg-background.tiff" \
  --window-pos 200 120 \
  --window-size 420 520 \
  --icon-size 100 \
  --icon "Dinky.app" 210 160 \
  --hide-extension "Dinky.app" \
  --app-drop-link 210 370 \
  "Dinky-$VERSION.dmg" \
  "build/Build/Products/Release/Dinky.app"

echo "→ Creating Dinky-$VERSION.zip (for in-app updater)…"
rm -f "Dinky-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "build/Build/Products/Release/Dinky.app" \
  "Dinky-$VERSION.zip"

# ── 5. Commit, tag, push, release ────────────────────────────────────────────

echo "→ Committing…"
git add Dinky.xcodeproj/project.pbxproj site/index.html site/llms.txt README.md
[ -f site/homepage.md ] && git add site/homepage.md
git commit -m "Bump to v$VERSION"
git push origin main

echo "→ Tagging and publishing release…"
git tag "v$VERSION"
git push origin "v$VERSION"

# Open editor for release notes, then publish
gh release create "v$VERSION" \
  --title "Dinky $VERSION" \
  --notes-file - \
  "Dinky-$VERSION.dmg" \
  "Dinky-$VERSION.zip" << NOTES
## Dinky $VERSION — files, not just images

Dinky is now a **multi-format compressor** on macOS: **images**, **videos**, and **PDFs** in one small app. Drag in files (or use watch folders and presets) and get smaller outputs back.

### Highlights
- **Images** — WebP, AVIF, or lossless PNG with smart quality and resize options.
- **Video** — export to MP4 with H.264 or HEVC and the same preset workflow as images.
- **PDFs** — shrink while keeping text and links selectable, or flatten pages for maximum savings.
- **One UI** — sidebar presets, batch results, smart quality, and history work across supported types.

## Install

Download \`Dinky-$VERSION.dmg\`, drag Dinky to Applications. Already installed? Click **Install Update** in the banner — Dinky handles the rest.
NOTES

echo ""
echo "✓ Dinky v$VERSION released."
echo "  https://github.com/heyderekj/dinky/releases/tag/v$VERSION"

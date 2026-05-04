#!/bin/bash
# release.sh — build, package, and publish a new Dinky release.
#
# Site + compare pages: step 2 updates DMG URLs and visible version lines. If you ship a GitHub
# release manually (gh release create) without running this script, the marketing site will stay
# on the old version until you run `./release.sh X.Y.Z --bump-only` (then commit) or a full run.
#
# Usage:
#   ./release.sh 1.2.3
#   ./release.sh 1.2.3 --bump-only   # steps 1–2 only (no build, git, or gh)
#
# What it does:
#   1. Bumps MARKETING_VERSION + CURRENT_PROJECT_VERSION in the Xcode project
#   2. Updates version + download URLs in site/index.html, site/llms.txt, site/homepage.md, site/compare/*/index.html
#   3. Builds the Release scheme
#   4. Creates the DMG (+ zip for in-app updater), then updates Casks/dinky.rb (version + sha256 of the zip) for Homebrew
#   5. Runs preflight tests (same targets as CI) before any push/tag/release
#   6. Commits, tags, pushes, and publishes the GitHub release
#
# Release notes are built from `git log $PREV_GIT_TAG..HEAD` (subjects only, chronological),
# excluding the “Bump to v$VERSION” commit, so what ships on GitHub matches the repo. Edit the
# release on GitHub afterward if you want prose or grouping; the list is the source of truth.
#
# Commit all app/source changes before running: the tag must point at a tree that includes the full
# app, not only version-string files.
#
# Prerequisites: create-dmg (brew install create-dmg), gh (brew install gh)

set -e  # exit on any error

# ── Args ──────────────────────────────────────────────────────────────────────

BUMP_ONLY=false
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bump-only) BUMP_ONLY=true; shift ;;
    *)
      if [ -n "$VERSION" ]; then
        echo "Usage: ./release.sh <version> [--bump-only]"
        exit 1
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--bump-only]  (e.g. ./release.sh 2.4.1 --bump-only)"
  exit 1
fi

if git rev-parse "refs/tags/v$VERSION" >/dev/null 2>&1; then
  echo "✗ Git tag v$VERSION already exists locally. Remove it or choose another version."
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Working tree is not clean. Commit or stash all changes first so the v$VERSION tag includes the full app."
  git status -sb
  exit 1
fi

FILE_MARKETING=$(grep "MARKETING_VERSION" Dinky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
FILE_BUILD=$(grep "CURRENT_PROJECT_VERSION" Dinky.xcodeproj/project.pbxproj | head -1 | sed 's/.*= //;s/;//')
OLD_MARKETING="$FILE_MARKETING"

echo "▶ Releasing Dinky v$VERSION (project marketing version is $FILE_MARKETING)"
echo ""

# ── 1. Bump version (skip if project + site already at $VERSION) ─────────────

if [ "$FILE_MARKETING" != "$VERSION" ]; then
  echo "→ Bumping version in project.pbxproj…"
  sed -i '' "s/MARKETING_VERSION = $FILE_MARKETING/MARKETING_VERSION = $VERSION/g" \
    Dinky.xcodeproj/project.pbxproj
  sed -i '' "s/CURRENT_PROJECT_VERSION = $FILE_BUILD/CURRENT_PROJECT_VERSION = $VERSION/g" \
    Dinky.xcodeproj/project.pbxproj
else
  echo "→ Project already at $VERSION (skipping pbxproj bump)"
fi

# ── 2. Update site ────────────────────────────────────────────────────────────

if [ "$OLD_MARKETING" != "$VERSION" ]; then
  echo "→ Updating site/index.html…"
  sed -i '' "s/v$OLD_MARKETING · Requires/v$VERSION · Requires/g" site/index.html
  sed -i '' "s/v$OLD_MARKETING\/Dinky-$OLD_MARKETING.dmg/v$VERSION\/Dinky-$VERSION.dmg/g" site/index.html
  sed -i '' "s/\"softwareVersion\": \"$OLD_MARKETING\"/\"softwareVersion\": \"$VERSION\"/g" site/index.html

  echo "→ Updating site/llms.txt…"
  sed -i '' "s/v$OLD_MARKETING/v$VERSION/g" site/llms.txt
  sed -i '' "s/Dinky-$OLD_MARKETING\.dmg/Dinky-$VERSION.dmg/g" site/llms.txt

  if [ -f site/homepage.md ]; then
    echo "→ Updating site/homepage.md…"
    sed -i '' "s/v$OLD_MARKETING/v$VERSION/g" site/homepage.md
    sed -i '' "s/Dinky-$OLD_MARKETING\.dmg/Dinky-$VERSION.dmg/g" site/homepage.md
  fi

  if compgen -G "site/compare/*/index.html" > /dev/null || [ -f site/compare/index.html ]; then
    echo "→ Updating site/compare/**/index.html…"
    for f in site/compare/*/index.html site/compare/index.html; do
      [ -f "$f" ] || continue
      sed -i '' "s/v$OLD_MARKETING · Requires/v$VERSION · Requires/g" "$f"
      sed -i '' "s/v$OLD_MARKETING\/Dinky-$OLD_MARKETING.dmg/v$VERSION\/Dinky-$VERSION.dmg/g" "$f"
    done
  fi
else
  echo "→ Site strings already match v$VERSION (skipping site sed)"
fi

if [ "$BUMP_ONLY" = true ]; then
  echo ""
  echo "✓ Bump only — updated project + site strings to v$VERSION."
  echo "  Commit those files, then: ./release.sh $VERSION  (full build, tag, gh release)"
  exit 0
fi

PREV_GIT_TAG=$(git tag -l 'v*' --sort=-version:refname | head -1 || true)
if [ -z "$PREV_GIT_TAG" ]; then
  echo "✗ No previous v* tags found. Create at least one release tag first, or edit release.sh for your case."
  exit 1
fi

# ── 3. Build ──────────────────────────────────────────────────────────────────

echo "→ Building Release…"
xcodebuild -scheme Dinky -configuration Release -derivedDataPath build clean build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)"

# ── 4. Preflight tests (match CI targets) ─────────────────────────────────────

echo "→ Running preflight tests (Xcode + SwiftPM)…"
xcodebuild \
  -project Dinky.xcodeproj \
  -scheme Dinky \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  test \
  | grep -E "error:|TEST (SUCCEEDED|FAILED)|BUILD (SUCCEEDED|FAILED)"

(
  cd DinkyCoreImage
  swift build -c debug
  swift test
)

# ── 5. Create DMG ─────────────────────────────────────────────────────────────

echo "→ Creating Dinky-$VERSION.dmg…"
rm -f "Dinky-$VERSION.dmg"
create-dmg \
  --volname "Dinky" \
  --volicon "build/Build/Products/Release/Dinky.app/Contents/Resources/AppIcon.icns" \
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

CASK_SHASUM=$(shasum -a 256 "Dinky-$VERSION.zip" | awk '{print $1}')
echo "→ Updating Casks/dinky.rb (version $VERSION, sha256)…"
sed -i '' "s/version \".*\"/version \"$VERSION\"/" Casks/dinky.rb
sed -i '' "s/sha256 \".*\"/sha256 \"$CASK_SHASUM\"/" Casks/dinky.rb

# ── 6. Optional bump commit, push, tag, release ─────────────────────────────

echo "→ Committing version files (if changed by this run)…"
git add Casks/dinky.rb Dinky.xcodeproj/project.pbxproj site/index.html site/llms.txt README.md
[ -f site/homepage.md ] && git add site/homepage.md
if compgen -G "site/compare/*/index.html" > /dev/null; then
  git add site/compare/*/index.html
fi
[ -f site/compare/index.html ] && git add site/compare/index.html
if git diff --cached --quiet; then
  echo "  (nothing to commit — version already in repo)"
else
  git commit -m "Bump to v$VERSION"
fi
git push origin main

echo "→ Tagging and publishing release…"
git tag "v$VERSION"
git push origin "v$VERSION"

echo "→ Composing release notes from git ($PREV_GIT_TAG..HEAD, excluding version bump)…"
NOTES_FILE=$(mktemp)
{
  echo "## Dinky $VERSION"
  echo ""
  echo "Changes since **$PREV_GIT_TAG** (commit subjects from this repo):"
  echo ""
  if git rev-parse "$PREV_GIT_TAG" >/dev/null 2>&1; then
    LIST=$(git log --no-merges "$PREV_GIT_TAG"..HEAD --pretty=format:'%s' --reverse | grep -vFx "Bump to v$VERSION" || true)
    if [ -n "$LIST" ]; then
      echo "$LIST" | while IFS= read -r subject; do
        [ -n "$subject" ] && echo "- $subject"
      done
    else
      echo "- *(No commits listed besides the version bump — describe this release manually on GitHub if needed.)*"
    fi
  else
    echo "- **Warning:** git tag \`$PREV_GIT_TAG\` not found locally. Run \`git fetch --tags\` or edit release notes on GitHub."
  fi
  echo ""
  echo "## Install"
  echo ""
  echo "**Homebrew (optional):**"
  echo ""
  echo "\`\`\`bash"
  echo "brew tap heyderekj/dinky https://github.com/heyderekj/dinky"
  echo "brew install --cask dinky"
  echo "\`\`\`"
  echo ""
  echo "**Or** download **Dinky-$VERSION.dmg** from the assets below and drag **Dinky** into Applications. Already using Dinky? Choose **Install Update** from the in-app banner when it appears."
  echo ""
  echo "## Finder “Open With” shows two Dinkys"
  echo ""
  echo "macOS lists each **Dinky.app** on disk with its own version. After an upgrade, an older copy is often still around."
  echo ""
  echo "- **Homebrew:** \`brew cleanup dinky\` (or \`brew cleanup\`) removes old cask versions under Caskroom."
  echo '- **List every copy:** `mdfind '\''kMDItemCFBundleIdentifier == "com.dinky.app"'\''` in Terminal; delete extras you do not need (e.g. in Downloads).'
} > "$NOTES_FILE"

gh release create "v$VERSION" \
  "Dinky-$VERSION.dmg" \
  "Dinky-$VERSION.zip" \
  --title "Dinky $VERSION" \
  --notes-file "$NOTES_FILE" \
  --verify-tag

rm -f "$NOTES_FILE"

echo ""
echo "✓ Dinky v$VERSION released."
echo "  https://github.com/heyderekj/dinky/releases/tag/v$VERSION"

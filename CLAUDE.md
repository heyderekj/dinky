# Dinky — Agent Rules

## App Size (Non-negotiable)

Dinky is ~23 MB installed (image/video encoders plus bundled **qpdf** and its dylibs, e.g. OpenSSL). That's still the whole point: before adding **anything** — a framework, dependency, asset, font, or feature — mentally check its bundle size impact first.

**Rules:**
- Prefer Apple frameworks always: SwiftUI, Foundation, AppKit, UserNotifications, AVFoundation, etc. They're free — already in the OS, zero bundle cost.
- Never add an SPM or CocoaPods dependency without explicit approval from Derek AND a clear size justification.
- If a feature would meaningfully grow the binary (>100 KB), find a lighter native implementation or skip it.
- No Electron, no web views, no bundled runtimes, no embedded web engines. Ever.
- Assets (images, fonts) should be SVG/SF Symbols where possible. Raster assets must be justified.

**Current footprint reference:** Dinky ~23 MB vs Optimage 62 MB vs ImageOptim 17.6 MB. Keep it dinky.

## Project Context

- macOS app, SwiftUI + macOS 26 (Tahoe), `.glassEffect()`, `.ultraThinMaterial`
- Built by Derek Castelli — full-time freelance web designer (Webflow/Figma) at heyderekj.com
- Compression engines: `cwebp`, `avifenc`, `oxipng` (CLI tools, not bundled)
- GitHub: https://github.com/heyderekj/dinky

## Releasing


- `./release.sh minor` (or `patch` / `major` / `2.16.0`) from an up-to-date `main`. It bumps the version, updates the site's version lines and `site/ask.json`, builds, runs the CI tests, makes the DMG + zip, updates `Casks/dinky.rb`, then commits, tags, pushes and publishes the GitHub release. `--bump-only` stops after the version and site edits.
- The site deploys from `main` (Cloudflare Pages), so copy for an unreleased feature goes live as soon as it merges. Merge site copy with or after the release.
- New UI strings: `xcodebuild -exportLocalizations -project Dinky.xcodeproj -localizationPath /tmp/loc -exportLanguage en` pulls them into `Localizable.xcstrings`; `python3 tools/fill_xcstrings_translations.py` fills only the missing locales (Google Translate; if it's rate-limited it reports which strings failed). Mark labels that shouldn't change (format names, numbers) `"shouldTranslate": false`. `release.sh` warns about untranslated strings added since the last tag.
- Help: `Dinky/Resources/en.lproj/Help.md` is the source; `tools/translate_help_md.py` rewrites the 12 locale copies. The site's Ask answers come from it via `tools/make_ask_json.py`.

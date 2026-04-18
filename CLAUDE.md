# Dinky — Agent Rules

## App Size (Non-negotiable)

Dinky is ~16 MB installed. That's still the whole point: before adding **anything** — a framework, dependency, asset, font, or feature — mentally check its bundle size impact first.

**Rules:**
- Prefer Apple frameworks always: SwiftUI, Foundation, AppKit, UserNotifications, AVFoundation, etc. They're free — already in the OS, zero bundle cost.
- Never add an SPM or CocoaPods dependency without explicit approval from Derek AND a clear size justification.
- If a feature would meaningfully grow the binary (>100 KB), find a lighter native implementation or skip it.
- No Electron, no web views, no bundled runtimes, no embedded web engines. Ever.
- Assets (images, fonts) should be SVG/SF Symbols where possible. Raster assets must be justified.

**Current footprint reference:** Dinky ~16 MB vs Optimage 62 MB vs ImageOptim 17.6 MB. Keep it dinky.

## Project Context

- macOS app, SwiftUI + macOS 26 (Tahoe), `.glassEffect()`, `.ultraThinMaterial`
- Built by Derek Castelli — full-time freelance web designer (Webflow/Figma) at heyderekj.com
- Compression engines: `cwebp`, `avifenc`, `oxipng` (CLI tools, not bundled)
- GitHub: https://github.com/heyderekj/dinky

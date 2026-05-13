# Future: Universal (Intel + Apple Silicon) Dinky builds

**Status:** Implemented in source — still needs a maintainer release pass on real Intel hardware before public support language changes.

**Context:** Current distributed builds are **Apple Silicon (arm64) only**; Intel users see a **slashed app icon** in Finder (architecture mismatch). Site and README already state Apple Silicon + macOS 15. See [`CLAUDE.md`](../../CLAUDE.md) for bundle-size philosophy before expanding support.

## Implementation checklist

1. **Xcode Release:** `ARCHS = arm64 x86_64`, `ONLY_ACTIVE_ARCH = NO` so the main executable is fat.
2. **Bundled tools in `Dinky/Resources/`:** `tools/vendor_universal_binaries.sh` downloads Intel Homebrew bottles, patches install names/rpaths to Dinky's bundle layout, and `lipo`s the x86_64 slices with the checked-in arm64 slices for `cwebp`, `avifenc`, `oxipng`, `qpdf`, `lame`, and every file under `Resources/lib/`.
3. **Re-sign:** The existing Xcode “Re-sign bundled binaries” run phase (`codesign -s - --force`) still signs those paths after Xcode copies them.
4. **Runtime lookup:** process runners now include bundled `Resources/lib`, `/opt/homebrew/lib`, and `/usr/local/lib` in `DYLD_LIBRARY_PATH` for Apple Silicon and Intel fallback paths.

## Effort / risk (when you pick this up)

- **Ongoing tax:** Every release refreshes **two** arch slices via `tools/vendor_universal_binaries.sh`; installed size is larger than the arm64-only payload.
- **Testing:** The source tree can now be smoke-tested directly on Intel hardware. A real Intel Mac pass before changing public support language is still the gold standard.

## References in-repo

- Vendored tool layout: [`Dinky/Resources/bin/README.md`](../../Dinky/Resources/bin/README.md)
- Release packaging: [`release.sh`](../../release.sh)
- Encoder path resolution (CLI): `DinkyCoreImage/Sources/DinkyCoreImage/DinkyEncoderPath.swift`

When this ships in a release, update marketing (site, README, cask notes) from “Apple Silicon only” to universal language and add release-note boilerplate.

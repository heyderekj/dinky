# Future: Universal (Intel + Apple Silicon) Dinky builds

**Status:** Backlog — not started. Derek has no reliable way to **smoke-test on real Intel hardware**, so shipping a universal DMG would be risky without borrowing a machine or CI on Intel.

**Starting point:** [PR #18](https://github.com/heyderekj/dinky/pull/18) (closed, October 2026) did most of the work: universal `bin/` and `lib/` payloads, `tools/vendor_universal_binaries.sh` to rebuild them from Homebrew bottles, `Resources/lib` lookup before the Homebrew fallbacks, and a `generic/platform=macOS` release build. It was tested on an Intel Mac. It was closed only because of the size cost and the lack of Intel hardware here. Rebase it instead of starting over.

Binky went universal in the same pass, because it ships no helper binaries and only its own executable needed a second slice.

**Context:** Current distributed builds are **Apple Silicon (arm64) only**; Intel users see a **slashed app icon** in Finder (architecture mismatch). Site and README already state Apple Silicon + macOS 15. See [`CLAUDE.md`](../../CLAUDE.md) for bundle-size philosophy before expanding support.

## What it would take (high level)

1. **Xcode Release:** `ARCHS = arm64 x86_64`, `ONLY_ACTIVE_ARCH = NO` for the app target so the main executable is fat.
2. **Bundled tools in `Dinky/Resources/`:** For each of `cwebp`, `avifenc`, `oxipng`, `qpdf`, `lame`, and every file under `Resources/lib/`, produce a **universal** Mach-O: `lipo -create` the current arm64 copy with **x86_64** copies (Intel Homebrew, official release tarballs, or a one-off Intel Mac export). Same `install_name_tool` / `@loader_path` story as today for `qpdf` + dylibs — duplicated for the x86_64 slice, then combined per file.
3. **Re-sign:** Keep the existing Xcode “Re-sign bundled binaries” run phase (`codesign -s - --force` on those paths after any `lipo` / `install_name_tool`).
4. **Optional code:** If relying on user-installed Homebrew on Intel, consider prepending `/usr/local/lib` to `DYLD_LIBRARY_PATH` where code today only mentions `/opt/homebrew/lib` (CLI already resolves `/usr/local/bin` via `DinkyEncoderPath`).

## Effort / risk (when you pick this up)

- **Feasibility:** High for someone comfortable vendoring signed binaries; mostly repetitive `lipo` + qpdf/dylib hygiene, not a rewrite.
- **Ongoing tax:** Every release refreshes **two** arch slices (or scripted universal refresh); installed size likely **~1.5–2×** native-heavy portions (ballpark **~50–70 MB** vs ~35 MB until measured).
- **Testing:** Rosetta (`arch -x86_64`) on Apple Silicon catches some x86_64 regressions; **a real Intel Mac pass** before calling Intel “supported” is still the gold standard.

## References in-repo

- Vendored tool layout: [`Dinky/Resources/bin/README.md`](../../Dinky/Resources/bin/README.md)
- Release packaging: [`release.sh`](../../release.sh)
- Encoder path resolution (CLI): `DinkyCoreImage/Sources/DinkyCoreImage/DinkyEncoderPath.swift`

When this ships, update marketing (site, README, cask notes) from “Apple Silicon only” to universal language and add release-note boilerplate.

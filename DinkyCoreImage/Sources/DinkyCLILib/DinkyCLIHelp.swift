import Foundation

public enum DinkyCLIHelp {
    public static func printHelp() {
        let help = """
        dinky — local Dinky compression (CLI): images, video, PDF

        Tools: set DINKY_BIN to a folder with cwebp, avifenc, oxipng (same as the app Resources layout).
        For PDF preserve-mode qpdf passes, place an executable `qpdf` in that folder; add a sibling `lib/`
        for bundled dylibs (see app `Resources/bin/README.md`). video/flatten-PDF do not require encoders.

        Exit codes: 0 = all files succeeded, 1 = parse error, missing tools, or at least one failure.

        Commands:
          dinky compress-image <files>… [options]   # images
          dinky compress <files>…                   # deprecated alias for compress-image
          dinky compress-video <files>… [options]
          dinky compress-pdf <files>… [options]
          dinky ocr <pdf>… [--languages en-US,fr] [-o dir] [--json]
          dinky make-fixtures [--output-dir <path>] [--types images,video,pdf] [--count 1..20] …   # developer testing
          dinky serve --port <n>
          dinky help | --help
          dinky version

        Presets (all compress-* commands):
          --preset "Name"     --preset-id <UUID>     --preset-file <path>
          Preset JSON order: --preset-file → $DINKY_PRESETS_PATH → ~/.config/dinky/presets.json → app prefs.
          CLI flags override preset fields. Presets must include the command’s media type in scope.

        compress-image options:
          -f, --format auto|webp|avif|png|heic   (default: auto)
          -o, --output-dir <path>
          -w, --max-width <px>      --max-size-kb <k>
          -q, --quality <0-100>    (disables smart quality)
          --smart-quality | --no-smart-quality
          --content-hint auto|photo|graphic|mixed
          --strip-metadata | --no-strip-metadata
          -j, --parallel <n>       (default 3)
          --collision-style …     --collision-pattern …
          --json                   schema: \(dinkyImageCompressResultSchema)

        compress-video options:
          -q, --quality low|medium|high|lossless  (low→medium, lossless→high)
          --codec h264|hevc   (ProRes is not supported)
          --remove-audio  |  --keep-audio
          --max-height <px>
          --smart-quality | --no-smart-quality
          -o, --output-dir <path>   --json
          --collision-style …   --collision-pattern …
          JSON: \(dinkyVideoCompressResultSchema)

        compress-pdf options:
          --mode preserve|flatten
          -q, --quality smallest|low|medium|high
          --grayscale | --no-grayscale
          --strip-metadata | --no-strip-metadata
          --resolution-downsample | --no-resolution-downsample
          --target-kb <k>
          --preserve-experimental none|stripStructure|strongerImages|maximum
          --smart-quality | --no-smart-quality
          --auto-grayscale-mono | --no-auto-grayscale-mono
          -o, --output-dir <path>   --json
          JSON: \(dinkyPdfCompressResultSchema)

        serve (HTTP, local use only):
          --port <n>   (default 17381)
          POST /v1/compress       image body (existing)
          POST /v1/video/compress  video JSON
          POST /v1/pdf/compress    PDF JSON
          GET /v1/health           schema \(dinkyImageServeInfoSchema)

        make-fixtures (developer / local testing only):
          Writes valid sample images (png, jpg, tiff, bmp, heic, optional webp+avif), short synthetic videos (.mov, .mp4),
          and PDFs (text-heavy + scan-like) plus manifest.json. Default output: ./.dinky-fixtures/<iso8601>/ (path-safe).
          --output-dir, -o <dir>   target folder
          --types images,video,pdf   subset (default: all)
          --count 1..20            batches per selected family (default 1)
          --seed <u64>             RNG seed (default: built-in)
          --overwrite              allow reusing existing output dir
          --json                   print manifest JSON to stdout

        """
        print(help, terminator: "")
    }
}

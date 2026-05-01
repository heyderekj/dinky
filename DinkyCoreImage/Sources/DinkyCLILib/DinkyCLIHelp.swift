import Foundation

public enum DinkyCLIHelp {
    public static func printHelp() {
        let help = """
        dinky — local Dinky image compression (CLI)

        Encoders: set DINKY_BIN to a folder with cwebp, avifenc, and oxipng, or use ./bin next to the binary, or install Homebrew webp+libavif+oxipng.

        Exit codes: 0 = all files succeeded, 1 = parse error, missing encoders, or at least one file failed.

        Commands:
          dinky compress <file>... [options]   # optimize images
          dinky serve --port <n>                 # local HTTP (binds all interfaces; use 127.0.0.1 in clients)
          dinky help | --help
          dinky version

        compress options:
          -f, --format auto|webp|avif|png|heic   (default: auto)
          -o, --output-dir <path>
          -w, --max-width <px>
              --max-size-kb <k>
          -q, --quality <0-100>    (disables smart quality)
              --no-smart-quality
              --content-hint auto|photo|graphic|mixed
              --strip-metadata | --no-strip-metadata
          -j, --parallel <n>       (default 3)
              --json               machine-readable (schema: \(dinkyImageCompressResultSchema))

        serve:
          --port <n>   (default 17381)
          POST /v1/compress  JSON body, GET /v1/health
          JSON response uses the same schema as `dinky compress --json` (\(dinkyImageCompressResultSchema))

        """
        print(help, terminator: "")
    }
}

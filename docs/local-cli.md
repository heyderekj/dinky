# Dinky `dinky` CLI and local service (images)

Dinky’s **image** compression pipeline is available as a **local** command-line tool and an optional **loopback HTTP** server. There is still **no public cloud API**; everything runs on the Mac with explicit file paths you supply.

**Source layout:** Swift package at `DinkyCoreImage/` in this repo. Library targets: `DinkyCoreImage` (engine), `DinkyCLILib` (CLI + JSON). Product executable: `dinky`.

## Building

```bash
cd DinkyCoreImage
swift build -c release
# Binary: .build/release/dinky
```

**Encoders:** the CLI must find `cwebp`, `avifenc`, and `oxipng` (same as the app). In order:

1. `DINKY_BIN` — directory containing those three executables (e.g. point at `Dinky.app/Contents/Resources` if you copy/symlink the tools).
2. `bin` next to the `dinky` binary.
3. Homebrew: `/opt/homebrew/bin` or `/usr/local/bin` if all three are installed.

## `dinky compress`

```text
dinky compress <file>... [options]
```

### Exit codes

| Code | Meaning |
|------|--------|
| `0` | All inputs processed successfully |
| `1` | Parse error, encoders not found, no inputs, or at least one file failed |

### Flags (images)

- `-f, --format` `auto|webp|avif|png|heic` (default: `auto`)
- `-o, --output-dir` — output directory (default: next to each input)
- `-w, --max-width` — max width in pixels
- `--max-size-kb` — target max file size (KB)
- `-q, --quality` `0...100` — disables smart quality when set
- `--no-smart-quality`
- `--content-hint` `auto|photo|graphic|mixed`
- `--strip-metadata` / `--no-strip-metadata`
- `-j, --parallel` — concurrency (default: 3)
- `--json` — machine-readable output (see schema below)

### JSON schema (`dinky compress --json`)

**Schema id:** `dinky.image.compress/1.0.0` (field `schema` in the root object)

Root object:

| Field | Type | Description |
|-------|------|-------------|
| `schema` | string | Always `dinky.image.compress/1.0.0` |
| `success` | bool | `true` if exit would be `0` |
| `results` | array | One entry per input path, in order |

Each `results[]` item:

| Field | Type | Description |
|-------|------|-------------|
| `input` | string | Original path |
| `output` | string? | Output path on success |
| `originalBytes` | number | Input size |
| `outputBytes` | number? | Output size on success |
| `savingsPercent` | number? | Approximate % reduction |
| `detectedContent` | string? | When available |
| `error` | string? | Set on failure |

## `dinky serve` (local HTTP)

Binds a TCP listener (default port **17381**). For agents, use **`127.0.0.1`** only in clients.

- `GET /v1/health` — `{"ok":true,"schema":"dinky.image.serve/1.0.0"}`
- `POST /v1/compress` — JSON body, same options as compress; response body matches `dinky compress --json` (schema `dinky.image.compress/1.0.0`). HTTP `200` if all files OK, `422` if any failed.

## For humans and agents

Quirky but straightforward:

- **Human mode:** give Dinky one or more file paths; get smaller files back.
- **Robot mode:** same behavior, but with `--json` so your script/agent can parse results.

For AI agents (Claude/Cursor/etc.), two good patterns:

1. **One-shot CLI**
   - Run `dinky compress ... --json`
   - Parse `schema: dinky.image.compress/1.0.0`
2. **Local server for repeated jobs**
   - Start once with `dinky serve --port 17381`
   - Poll `GET /v1/health`
   - Submit `POST /v1/compress`

Suggested guardrails for agent workflows:

- Use `127.0.0.1` only.
- Use explicit absolute file paths.
- Keep the service local (no public binding/reverse proxy).
- Treat output as local filesystem automation, not a cloud API.

### Example POST body

```json
{
  "inputPaths": ["/path/to/photo.png"],
  "format": "webp",
  "outputDir": "/path/to/out",
  "quality": 80,
  "smartQuality": false,
  "stripMetadata": true
}
```

## Security model

- No upload to Dinky’s website or a hosted API.
- Only files you pass are read; output paths are under your control.
- Prefer loopback and explicit paths when wiring agents or scripts.

## Roadmap (next work)

Suggested order for continuing development:

1. **Harden `serve`** — bind listener to loopback only, cap request size, structured JSON errors, optional path allowlist.
2. **More tests** — HTTP handler unit tests without sockets; snapshot or contract tests for JSON responses.
3. **CLI polish** — `dinky --version`, consistent help/exit codes vs this doc.
4. **App parity** — audit `Dinky/CompressionService.swift` after extraction for dead code or drift vs `DinkyCoreImage`.
5. **Distribution** — decide whether `dinky` ships inside the app bundle, Homebrew, or build-from-source only.

## Testing

```bash
cd DinkyCoreImage
swift test
```

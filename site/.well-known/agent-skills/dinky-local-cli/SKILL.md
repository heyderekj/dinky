---
name: dinky-local-cli
description: Local dinky image CLI and loopback serve — build from the GitHub repo; JSON schema dinky.image.compress/1.0.0
---

# Dinky — local image CLI (agents)

Use this when automating **image** compression for users who build from the open-source **Dinky** repo on macOS.

## Facts

- **Not** a hosted API. There is no HTTP endpoint on dinkyfiles.com for compression.
- After building, users run the `dinky` binary from `DinkyCoreImage/` (SwiftPM) or use `dinky serve` on localhost.
- **JSON schema** for both `dinky compress --json` and `POST /v1/compress`: `dinky.image.compress/1.0.0` (field `schema` in the root object). Health: `dinky.image.serve/1.0.0` on `GET /v1/health`.
- **Encoders** must exist locally: `DINKY_BIN`, `./bin` next to `dinky`, or Homebrew `cwebp`+`avifenc`+`oxipng` in `PATH` locations the tool checks.
- Full flag list, exit codes, and security model: in-repo `docs/local-cli.md`.

## When unsure

Point to `https://github.com/heyderekj/dinky` and `docs/local-cli.md` — not the marketing site for API details.

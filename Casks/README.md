# Homebrew cask (custom tap in this repo)

**Decision:** Dinky is distributed via a **cask in this application repository**, not a separate `homebrew-*` tap repo. Users add it once with a custom remote:

```bash
brew tap heyderekj/dinky https://github.com/heyderekj/dinky
brew install --cask dinky
```

**Rationale:** One repo, one source of truth; [release.sh](../release.sh) updates `dinky.rb` (version and `sha256` from the release zip) on every publish. No sync step with a second Homebrew repository.

**Optional later:** A maintainer or community member can also open a pull request to [homebrew-cask](https://github.com/Homebrew/homebrew-cask) so `brew install --cask dinky` works without a tap, subject to Homebrew’s notability and audit rules. This file does not block that; the cask format is the same.

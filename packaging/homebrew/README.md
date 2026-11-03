# Homebrew packaging

`sprout.rb` is a ready-to-use formula. It is **not published yet**; this folder keeps it versioned
next to the code so a tap can be created in minutes.

## What the formula installs

| File | Location | Purpose |
| --- | --- | --- |
| `sprout.plugin.zsh` | `$(brew --prefix)/share/sprout/` | the plugin, sourced from `~/.zshrc` |
| `install.sh` | `bin/sprout-setup` | guided setup (Jira site, token, base branch); detects the packaged plugin |
| `uninstall.sh` | `bin/sprout-uninstall` | removes the loader, config and token |

## Publish it as a tap (when you are ready)

1. Create a public repository named `homebrew-tap` under your account (the `homebrew-` prefix is required).
2. Tag and release the code, e.g. `git tag v0.1.0 && git push --tags` and create the GitHub release.
3. Compute the checksum of the release tarball and put it in `sha256`:

   ```sh
   curl -fsSL https://github.com/beenjii14/sprout/archive/refs/tags/v0.1.0.tar.gz | shasum -a 256
   ```

4. Copy `sprout.rb` to `Formula/sprout.rb` in the tap repository and push it.
5. Validate and try it:

   ```sh
   brew tap beenjii14/tap
   brew audit --strict --new --formula beenjii14/tap/sprout
   brew install --build-from-source beenjii14/tap/sprout
   brew test beenjii14/tap/sprout
   ```

Users then install with:

```sh
brew install beenjii14/tap/sprout
sprout-setup
```

## Releasing a new version

1. Bump `SPROUT_VERSION` in `sprout.plugin.zsh` and add a `CHANGELOG.md` entry.
2. Tag `vX.Y.Z` and create the GitHub release.
3. Update `url` and `sha256` in the formula (in this folder and in the tap).

## Homebrew core

A formula in `homebrew-core` requires notable usage (stars/forks/watchers) and no name clashes. The name
`sprout` is currently free there. Start with the personal tap and revisit once the project has traction.

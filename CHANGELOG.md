# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-11-03

### Added
- `-b`/`--base <branch>` starts the new branch from another base for a single run (also `--base=<branch>`).
- `-r`/`--remote <name>` pulls from another remote for a single run.
- `--no-pull` skips the pull for a single run.
- Tab completion for the new options.

## [0.2.0] - 2026-11-02

First public release.

### Added
- `sprout` command: create a Git branch from a Jira issue key or URL (or from the clipboard).
- Title, issue type and description lookup through the Jira Cloud REST API v3.
- Short branch names written by the Claude Code CLI, in English by default (`SPROUT_LANG` selects another
  language or keeps the ticket's), with a local rule as a fallback.
- Configurable branch format, allowed types, base branch, remote and command name.
- Stash offer for uncommitted changes and reuse of an existing branch for the same ticket.
- Guided setup for macOS and Linux (`sprout-setup` / `install.sh`, `sprout-uninstall` / `uninstall.sh`) with the token
  stored in the Keychain, libsecret or a `600`-mode file.
- Homebrew formula (`brew install beenjii14/tap/sprout`).
- Zsh tab completion, `--dry-run`, `--help` and `--version`.
- Offline test suite, GitHub Actions CI on macOS and Ubuntu, and a project website.

[0.3.0]: https://github.com/beenjii14/sprout/releases/tag/v0.3.0
[0.2.0]: https://github.com/beenjii14/sprout/releases/tag/v0.2.0

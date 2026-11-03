# Contributing to sprout

Thanks for your interest! Bug reports, ideas and pull requests are all welcome.

## Quick start

```sh
git clone https://github.com/beenjii14/sprout.git
cd sprout
zsh tests/run.zsh        # offline test suite
```

The project has no build step. The tool is a single file, [`sprout.plugin.zsh`](sprout.plugin.zsh); the installers
are plain bash ([`install.sh`](install.sh), [`uninstall.sh`](uninstall.sh)); the website is a static page in [`docs/`](docs).

## Guidelines

- **Add or update tests** in `tests/run.zsh` for any behavior change. Tests must stay offline: no Jira, no AI, no network.
- **Keep it portable**: macOS and Linux, zsh 5.0+. Use `emulate -L zsh` in functions and avoid GNU-only flags.
- **Never put secrets on a command line**; pass credentials over stdin as `_sprout_jira_fetch` does.
- **Keep installers `bash` 3.2 compatible** (the macOS default): no associative arrays or `${var,,}`.
- **Document** new options in the README configuration table and in `docs/index.html`, and add a line to `CHANGELOG.md`.
- Keep commits focused and write messages in the imperative mood (`Add X`, `Fix Y`).

## Reporting bugs

Open an issue with your OS, zsh version (`zsh --version`), the command you ran with `--dry-run` if relevant and
what you expected. **Never paste API tokens or private ticket content.**

## Ideas welcome

Jira Server / Data Center support, other trackers (GitHub, GitLab, Linear), fish support, a Homebrew tap.
Open an issue first for larger changes so we can agree on the approach.

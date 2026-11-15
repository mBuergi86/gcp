# gcp

Stage, commit and push all changes in one step, with safety checks.

```console
$ gcp "fix(api): handle empty response"
Branch:  feature/api
Remote:  origin
Message: fix(api): 🐛 handle empty response

Changes:
 M src/api.js

Commit and push these changes? [y/N] y
```

`gcp` makes sure every commit message follows [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/), adds a matching [gitmoji](https://gitmoji.dev), and checks the staged files for secrets and oversized files before anything is committed. On `release/X.Y` branches it also creates patch version tags automatically.

## Features

- **Conventional Commits:** the commit header is validated and limited to 72 characters.
- **Automatic gitmoji:** the emoji is chosen from the commit type, and one you write yourself is kept.
- **Secret protection:** files like `.env` or `id_rsa` are blocked by name, and [gitleaks](https://github.com/gitleaks/gitleaks) scans the staged content.
- **Large file check:** files of 100 MiB or more are rejected, because GitHub would reject them.
- **Safe on failure:** when a check fails after staging, all changes are unstaged again and nothing in the working tree is lost.
- **Rebase before push:** if the branch has an upstream, `gcp` runs `git pull --rebase` first.
- **Release tagging:** a `fix` on `release/X.Y` creates and pushes the next patch tag.

## Requirements

- bash >= 4
- git >= 2.22
- [gitleaks](https://github.com/gitleaks/gitleaks) >= 8.19 (or run with `SKIP_GITLEAKS=1`)

## Installation

From a clone:

```sh
git clone https://github.com/mBuergi86/gcp.git
cd gcp
./install.sh
```

Or in one line, without cloning:

```sh
curl -fsSL https://raw.githubusercontent.com/mBuergi86/gcp/main/install.sh | bash
```

This installs `gcp` to `~/.local/bin` and the man page to `~/.local/share/man/man1`, so no root is needed. The installer checks the requirements and warns if `~/.local/bin` is not in your `PATH`. Afterwards `man gcp` shows the full manual.

| Option | Effect |
| --- | --- |
| `--prefix DIR` | Install to `DIR/bin` and `DIR/share/man/man1` instead, e.g. `sudo ./install.sh --prefix /usr/local` |
| `--zshrc` | Add `unalias gcp` to `~/.zshrc` (see below) |
| `--uninstall` | Remove `gcp` and its man page again |

With the one-line install, pass options after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/mBuergi86/gcp/main/install.sh | bash -s -- --zshrc
```

### oh-my-zsh users

The oh-my-zsh `git` plugin defines `gcp` as an alias for `git cherry-pick`, which hides the script. The installer detects this and warns you. Run it with `--zshrc`, or add this line **at the end** of your `~/.zshrc` yourself:

```zsh
unalias gcp 2>/dev/null
```

## Usage

```sh
gcp [-y|--yes] "<type>[(scope)][!]: [gitmoji] <description>"
```

The message must be passed as **one quoted argument**. A body and footers go on further lines inside the same quotes.

| Option / variable | Effect |
| --- | --- |
| `-y`, `--yes`, `GCP_YES=1` | Skip the confirmation prompt (needed without an interactive terminal, e.g. in scripts, editors or AI agents). The summary is still printed. |
| `ALLOW_MAIN=1` | Allow committing directly to `main` or `master`. |
| `SKIP_GITLEAKS=1` | Skip the content secret scan. Not recommended. |

### Commit types and gitmoji

| Type | Gitmoji | | Type | Gitmoji |
| --- | --- | --- | --- | --- |
| `feat` | ✨ | | `test` | ✅ |
| `fix` | 🐛 | | `build` | 📦️ |
| `docs` | 📝 | | `ci` | 👷 |
| `style` | 🎨 | | `chore` | 🔧 |
| `refactor` | ♻️ | | `revert` | ⏪️ |
| `perf` | ⚡️ | | breaking change | 💥 |

A breaking change is marked with `!` before the colon or with a `BREAKING CHANGE:` footer.

### Examples

Fix on a feature branch:

```sh
gcp "fix(api): handle empty response"
# -> fix(api): 🐛 handle empty response
```

Own gitmoji, kept as is:

```sh
gcp "chore: :arrow_up: bump dependencies"
```

Breaking change with footer:

```sh
gcp "refactor: new auth flow

BREAKING CHANGE: login endpoint moved to /v2/login"
```

Direct commit to `main` without a prompt:

```sh
ALLOW_MAIN=1 gcp -y "docs: update README"
```

## Safety checks

`gcp` refuses to run, or stops before committing, when:

- the message is not valid Conventional Commits, or the header is too long
- a rebase, merge or cherry-pick is in progress
- `HEAD` is detached
- the branch is `main` or `master` (unless `ALLOW_MAIN=1`)
- there is no remote, or several remotes and no upstream
- stdin is not an interactive terminal (unless `-y`)
- staged files look like secrets by name (`.env`, `id_rsa`, `id_ed25519`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials.json`). Files ending in `.example`, `.sample`, `.template` or `.dist` are allowed.
- gitleaks finds secrets in the staged content
- a staged file is 100 MiB or larger
- a commit hook rejects the commit

## Release tags

Tags are only created on branches named `release/X.Y`, for example `release/1.4`.

| Type | On `release/X.Y` |
| --- | --- |
| `fix` | Creates and pushes the next patch tag, e.g. `v1.4.3` after `v1.4.2`. |
| `feat` or breaking change | Rejected. New features need a new release branch. |
| all other types | Committed and pushed, no tag. |

The first tag of a release line must be created by hand:

```sh
git switch -c release/1.4
git tag -a v1.4.0 -m "v1.4.0"
git push -u origin release/1.4 --follow-tags
```

After that:

```console
$ gcp "fix: correct timezone in export"
...
Released v1.4.1
```

The tag is created after the rebase and push, so it always points to the commit that is on the remote.

## Exit status

| Code | Meaning |
| --- | --- |
| `0` | Success, nothing to commit, or aborted by the user |
| `1` | A check failed or a git command failed |

## License

[MIT](LICENSE) © 2026 Markus Bürgi

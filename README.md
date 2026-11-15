# gcp

[![test](https://github.com/mBuergi86/gcp/actions/workflows/test.yml/badge.svg)](https://github.com/mBuergi86/gcp/actions/workflows/test.yml)

Stage, commit and push your changes in one step, with safety checks. All changes, or only the files you name.

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
- **Amend and undo:** `gcp amend` adds a forgotten file to the last commit, `gcp undo` undoes it, with `reset` if local and `revert` if already pushed.
- **Status and history:** `gcp status` warns before a commit would be blocked, `gcp history` lists commits, filterable by type.
- **Single files or all changes:** commit everything, only the paths you name, or pick files interactively (`-i`, with fzf if installed).
- **Rebase before push:** if the branch has an upstream, `gcp` runs `git pull --rebase --autostash` first, so other uncommitted changes are kept.
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
gcp [-y|--yes] [-i|--interactive] "<type>[(scope)][!]: [gitmoji] <description>" [--] [path...]
```

The message must be passed as **one quoted argument**, before any paths. A body and footers go on further lines inside the same quotes.

Subcommands for fixing and checking:

```sh
gcp amend [-m "<message>"] [path...]  # add changes to the last commit (if not pushed yet)
gcp undo                              # undo the last commit, safely
gcp status                            # branch, ahead/behind, changes, and what gcp would block
gcp history [n] [type]                # last n commits (default 10), e.g. "gcp history 20 fix"
```

Without paths, `gcp` commits **all** changes. With paths, only those files and directories are staged, checked and committed. Everything else stays as it is, even if it is already staged.

| Option / variable | Effect |
| --- | --- |
| `-i`, `--interactive` | Pick the files to commit from a list (see below). |
| `-y`, `--yes`, `GCP_YES=1` | Skip the confirmation prompt (needed without an interactive terminal, e.g. in scripts, editors or AI agents). The summary is still printed. |
| `ALLOW_MAIN=1` | Allow committing directly to `main` or `master`. |
| `SKIP_GITLEAKS=1` | Skip the content secret scan. Not recommended. |
| `GCP_NO_FZF=1` | Use the numbered list for `-i` even if fzf is installed. |

### gcp amend

```sh
gcp amend [-y] [-i] [-m "<message>"] [--] [path...]
```

Adds changes to the last commit and pushes it. Useful for a forgotten file or a small fix right after committing.

| Command | Effect |
| --- | --- |
| `gcp amend` | add all changes to the last commit, keep the message |
| `gcp amend forgotten.txt` | add only this file |
| `gcp amend -i` | pick the files from a list |
| `gcp amend -m "fix: better message"` | change the message (with gitmoji, validated); with changes, they are added too |

The same safety checks as for a normal commit apply (secret names, gitleaks, file size, `main`).

`gcp amend` only works if the last commit is **not pushed yet**. Changing a pushed commit would rewrite history that others may already have, so `gcp` refuses and suggests a new commit or `gcp undo` instead.

### gcp undo

```sh
gcp undo [-y]
```

Undoes the last commit, and picks the safe way automatically:

| Last commit is… | What happens |
| --- | --- |
| **not pushed yet** | The commit is removed, its changes stay staged (`git reset --soft`). Nothing is lost, you can fix and commit again. |
| **already pushed** | A new commit `revert: ⏪️ <original message>` reverses the changes and is pushed. The history stays intact for everyone. |

```text
$ gcp undo
Branch:  feature/api
Undo:    8af7e58 fix(api): 🐛 handle empty response
         not pushed yet: the commit is removed, its changes stay staged.

Undo the last commit? [y/N] y
Undone. The changes are staged again, see: gcp status
```

Merge commits are refused, they need `git revert -m 1 HEAD` by hand. Whether a commit is pushed is decided from the remote-tracking branches, as of the last fetch.

### gcp status

```sh
gcp status
```

Shows where you are and warns about everything `gcp` would block, **before** you try to commit. It only reads, nothing is changed and nothing is fetched from the network.

```text
Branch:  feature/api → origin/feature/api (2 ahead, 0 behind, as of last fetch)

Changes:
   M src/api.js
  ?? .env
  ?? video.mp4

Warnings:
  ⚠ .env looks like a secret, add it to .gitignore
  ⚠ video.mp4 is 230 MiB, use Git LFS or .gitignore
```

It shows:

- **Branch:** the current branch, its upstream, and how many commits you are ahead or behind. The numbers are as of the last `git fetch`. Without an upstream it says which remote `gcp` would push to.
- **Release:** on a `release/X.Y` branch, which tag the next `fix` would create, e.g. `next fix creates v1.4.3`.
- **Changes:** all changed and untracked files, like `git status --short`.
- **Warnings:** everything that would make `gcp` stop:
  - files that look like secrets (`.env`, `id_rsa`, `*.pem`, …)
  - files of 100 MiB or more
  - `main`/`master` without `ALLOW_MAIN=1`
  - no remote, or several remotes and no upstream
  - a rebase, merge or cherry-pick in progress
  - detached `HEAD`
  - a release branch without base tag, or with a wrong name
  - gitleaks not installed

If there is nothing to warn about, it ends with `✓ Ready for gcp`.

### gcp history

```sh
gcp history [n] [type]
```

Lists the last commits, one per line with short hash, age, message and tags. It only reads, nothing is changed.

| Command | Shows |
| --- | --- |
| `gcp history` | the last 10 commits |
| `gcp history 30` | the last 30 commits |
| `gcp history fix` | the last 10 `fix` commits |
| `gcp history 5 feat` | the last 5 `feat` commits (order of the arguments does not matter) |
| `gcp history breaking` | breaking changes (`!` or a `BREAKING CHANGE:` footer) |

All types from the [table below](#commit-types-and-gitmoji) can be used as a filter. The scope does not matter: `gcp history fix` also finds `fix(api): …`.

```text
$ gcp history 3 fix
8af7e58  2 days ago   fix(api): 🐛 handle empty response  v1.0.2
e44a390  5 days ago   fix: 🐛 correct timezone in export   v1.0.1
c1d2e3f  2 weeks ago  fix: 🐛 typo in README
```

Tags are shown at the end of the line, so on a release branch you can see at a glance which fix went into which version.

### Interactive selection

`gcp -i` lists all changed files and lets you pick the ones to commit.

- **With [fzf](https://github.com/junegunn/fzf):** a fuzzy finder with a diff preview opens. `TAB` selects, `ctrl-a` toggles all, `ENTER` confirms, `ESC` aborts.
- **Without fzf:** a numbered list is shown. Type e.g. `1 3 5-7`, or `a` for all.

```text
Changed files:
    1)  M src/api.js
    2) ?? src/new.js
    3) D  old.txt
Select files (e.g. 1 3 5-7, a = all, empty = abort): 1 3
```

For a renamed file the old path is committed too. `-i` needs an interactive terminal and cannot be combined with paths.

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

Pick files interactively:

```sh
gcp -i "fix: correct typos"
```

Only some files or directories:

```sh
gcp "docs: update install notes" README.md docs/
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

## Development

Tests use [bats](https://github.com/bats-core/bats-core), every test runs in its own temporary repository with a local remote. [shellcheck](https://www.shellcheck.net) checks the scripts.

```sh
sudo pacman -S bats shellcheck   # Arch; Debian/Ubuntu: sudo apt install bats shellcheck
shellcheck gcp install.sh
bats test/
```

GitHub Actions runs both on every push and pull request.

## Exit status

| Code | Meaning |
| --- | --- |
| `0` | Success, nothing to commit, or aborted by the user |
| `1` | A check failed or a git command failed |

## License

[MIT](LICENSE) © 2026 Markus Bürgi

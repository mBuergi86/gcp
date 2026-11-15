#!/usr/bin/env bash
# install.sh - install or uninstall gcp and its man page.
#
# Usage:
#   ./install.sh [--prefix DIR] [--zshrc] [--uninstall]
#   curl -fsSL https://raw.githubusercontent.com/mBuergi86/gcp/main/install.sh | bash
#
# Options:
#   --prefix DIR   install to DIR/bin and DIR/share/man/man1 (default: ~/.local)
#   --zshrc        add "unalias gcp" to ~/.zshrc (oh-my-zsh git plugin conflict)
#   --uninstall    remove gcp and its man page from the prefix
#   -h, --help     show this help
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/mBuergi86/gcp/main"
PREFIX="${PREFIX:-$HOME/.local}"
FIX_ZSHRC=0
UNINSTALL=0
ZSHRC_LINE='unalias gcp 2>/dev/null'

die()  { echo "Error: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "Warning: $*" >&2; }

usage() {
    cat <<'EOF'
Usage: install.sh [--prefix DIR] [--zshrc] [--uninstall]

  --prefix DIR   install to DIR/bin and DIR/share/man/man1 (default: ~/.local)
  --zshrc        add "unalias gcp" to ~/.zshrc (oh-my-zsh git plugin conflict)
  --uninstall    remove gcp and its man page from the prefix
  -h, --help     show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)    [[ $# -ge 2 ]] || die "--prefix needs a directory."
                     PREFIX="$2"; shift 2 ;;
        --prefix=*)  PREFIX="${1#*=}"; shift ;;
        --zshrc)     FIX_ZSHRC=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *)           die "unknown option: $1 (see --help)" ;;
    esac
done

PREFIX="${PREFIX%/}"
BIN_DIR="$PREFIX/bin"
MAN_DIR="$PREFIX/share/man/man1"

# ---------------------------------------------------------------------------
# Uninstall
# ---------------------------------------------------------------------------

if (( UNINSTALL )); then
    for f in "$BIN_DIR/gcp" "$MAN_DIR/gcp.1"; do
        if [[ -e "$f" ]]; then
            rm -f "$f"
            info "Removed $f"
        fi
    done
    if [[ -f "$HOME/.zshrc" ]] && grep -qxF "$ZSHRC_LINE" "$HOME/.zshrc"; then
        echo "Note: ~/.zshrc still contains '$ZSHRC_LINE'. Remove it by hand if you like."
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Requirements
# ---------------------------------------------------------------------------

version_ge() {
    # True if version $1 >= $2
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

(( BASH_VERSINFO[0] >= 4 )) || die "bash >= 4 is required (found $BASH_VERSION)."

command -v git >/dev/null 2>&1 || die "git is not installed."
GIT_VERSION="$(git --version | awk '{print $3}')"
version_ge "$GIT_VERSION" "2.22" || die "git >= 2.22 is required (found $GIT_VERSION)."

if command -v gitleaks >/dev/null 2>&1; then
    if ! gitleaks git --help >/dev/null 2>&1; then
        warn "gitleaks is older than 8.19. Update it, or run gcp with SKIP_GITLEAKS=1."
    fi
else
    warn "gitleaks is not installed. gcp needs it for the secret scan (or SKIP_GITLEAKS=1)."
    echo "         Arch: sudo pacman -S gitleaks   macOS: brew install gitleaks" >&2
    echo "         Others: https://github.com/gitleaks/gitleaks#installing" >&2
fi

# ---------------------------------------------------------------------------
# Source files: local clone, otherwise download from GitHub
# ---------------------------------------------------------------------------

SRC_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "$CANDIDATE/gcp" && -f "$CANDIDATE/gcp.1" ]]; then
        SRC_DIR="$CANDIDATE"
    fi
fi

TMP_DIR=""
cleanup() { if [[ -n "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi; }
trap cleanup EXIT

if [[ -z "$SRC_DIR" ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is needed to download gcp."
    TMP_DIR="$(mktemp -d)"
    info "Downloading gcp from GitHub"
    curl -fsSL "$REPO_RAW/gcp"   -o "$TMP_DIR/gcp"   || die "download of gcp failed."
    curl -fsSL "$REPO_RAW/gcp.1" -o "$TMP_DIR/gcp.1" || die "download of gcp.1 failed."
    head -n1 "$TMP_DIR/gcp" | grep -q '^#!.*bash' || die "downloaded gcp does not look like a bash script."
    SRC_DIR="$TMP_DIR"
fi

bash -n "$SRC_DIR/gcp" || die "gcp has a syntax error, not installing."

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

install -d "$BIN_DIR" "$MAN_DIR"
install -m 755 "$SRC_DIR/gcp"   "$BIN_DIR/gcp"
install -m 644 "$SRC_DIR/gcp.1" "$MAN_DIR/gcp.1"
info "Installed $BIN_DIR/gcp"
info "Installed $MAN_DIR/gcp.1"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in your PATH. Add this to your shell config:"
       echo "         export PATH=\"$BIN_DIR:\$PATH\"" >&2 ;;
esac

# ---------------------------------------------------------------------------
# oh-my-zsh: the git plugin aliases gcp to "git cherry-pick"
# ---------------------------------------------------------------------------

ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]] && ! grep -qxF "$ZSHRC_LINE" "$ZSHRC"; then
    if (( FIX_ZSHRC )); then
        printf '\n# gcp: use the gcp script instead of the oh-my-zsh git alias (git cherry-pick)\n%s\n' \
            "$ZSHRC_LINE" >> "$ZSHRC"
        info "Added '$ZSHRC_LINE' to ~/.zshrc. Run 'exec zsh' to reload."
    elif command -v zsh >/dev/null 2>&1 \
        && [[ "$(zsh -ic 'alias gcp' 2>/dev/null)" == *"cherry-pick"* ]]; then
        warn "in zsh, gcp is an alias for 'git cherry-pick' (oh-my-zsh git plugin)."
        echo "         Re-run with --zshrc, or add this line at the end of ~/.zshrc:" >&2
        echo "         $ZSHRC_LINE" >&2
    fi
fi

echo
echo "Done. Read 'man gcp' for the full manual."

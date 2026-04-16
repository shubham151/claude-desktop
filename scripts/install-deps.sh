#!/usr/bin/env bash
# Install build dependencies for claude-desktop packaging.
# Usage: ./scripts/install-deps.sh [ci]
#   ci  — non-interactive; skip sudo prompts if possible.

set -euo pipefail

MODE="${1:-local}"
SUDO="sudo"
[[ $EUID -eq 0 ]] && SUDO=""

log() { printf '\033[1;34m[deps]\033[0m %s\n' "$*"; }

install_appimagetool() {
  if command -v appimagetool >/dev/null 2>&1; then
    log "appimagetool already installed"
    return
  fi
  log "installing appimagetool"
  local arch url
  arch="$(uname -m)"
  url="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${arch}.AppImage"
  curl -fL -o /tmp/appimagetool "$url"
  chmod +x /tmp/appimagetool
  $SUDO mv /tmp/appimagetool /usr/local/bin/appimagetool
}

install_debian() {
  log "detected Debian/Ubuntu"
  $SUDO apt-get update
  $SUDO apt-get install -y --no-install-recommends \
    p7zip-full curl fakeroot dpkg-dev rpm \
    imagemagick file desktop-file-utils \
    shellcheck
  # libfuse2 was renamed to libfuse2t64 on Ubuntu 24.04+; install whichever exists.
  if apt-cache show libfuse2t64 >/dev/null 2>&1; then
    $SUDO apt-get install -y --no-install-recommends libfuse2t64
  else
    $SUDO apt-get install -y --no-install-recommends libfuse2 || true
  fi
  install_appimagetool
}

install_fedora() {
  log "detected Fedora/RHEL"
  $SUDO dnf install -y \
    p7zip curl fakeroot dpkg rpm-build \
    ImageMagick fuse-libs file desktop-file-utils \
    ShellCheck
  install_appimagetool
}

install_arch() {
  log "detected Arch"
  $SUDO pacman -Sy --needed --noconfirm \
    p7zip curl fakeroot dpkg rpm-tools \
    imagemagick fuse2 file desktop-file-utils \
    shellcheck
  install_appimagetool
}

check_node() {
  if ! command -v node >/dev/null 2>&1; then
    log "WARNING: node not found. Install Node.js 18+ (setup-node in CI, or nvm locally)."
    return
  fi
  local v
  v="$(node -v | sed 's/^v//' | cut -d. -f1)"
  if [[ "$v" -lt 18 ]]; then
    log "WARNING: node $(node -v) is too old; need >= 18"
  fi
}

main() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
      *debian*|*ubuntu*) install_debian ;;
      *fedora*|*rhel*|*centos*) install_fedora ;;
      *arch*) install_arch ;;
      *)
        log "unknown distro ($ID); install these manually: node npm 7z curl fakeroot dpkg-deb rpmbuild appimagetool imagemagick"
        exit 1
        ;;
    esac
  else
    log "no /etc/os-release; cannot auto-detect distro"
    exit 1
  fi

  check_node
  log "all build dependencies installed"
  [[ "$MODE" == "ci" ]] && log "(ci mode)"
}

main "$@"

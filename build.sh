#!/usr/bin/env bash
set -euo pipefail

# Claude Desktop Linux — build script
# Produces .deb, .rpm, and AppImage from the official macOS DMG.

# ----- Configurable -----
# The DMG redirect URL on claude.ai is session-scoped (token rotates), so we
# discover it fresh on each build by scraping claude.com/download.
# Override with DMG_URL_UNIVERSAL=<url> to pin a specific download.
DOWNLOAD_PAGE_URL="${DOWNLOAD_PAGE_URL:-https://claude.com/download}"
DMG_URL_UNIVERSAL="${DMG_URL_UNIVERSAL:-}"
DMG_URL_AMD64="${DMG_URL_AMD64:-}"
DMG_URL_ARM64="${DMG_URL_ARM64:-}"
MAINTAINER="${MAINTAINER:-shubham151 <shubham.cmishra@gmail.com>}"
PKG_NAME="claude-desktop"

# ----- Paths -----
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
WORK_DIR="${BUILD_DIR}/work"
STAGE_DIR="${BUILD_DIR}/stage"
OUT_DIR="${ROOT_DIR}/dist"

log() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ----- Compile TS shims -----
compile_ts() {
  log "compiling TypeScript shims"
  ( cd "$ROOT_DIR" && npm install --no-audit --no-fund --silent && npx tsc -p tsconfig.json )
  [[ -f "$ROOT_DIR/build-ts/claude-native-bindings.js" ]] || die "TS compile failed: claude-native-bindings.js missing"
  [[ -f "$ROOT_DIR/build-ts/frame-fix-wrapper.js" ]] || die "TS compile failed: frame-fix-wrapper.js missing"
}

# ----- Dependency check -----
check_deps() {
  local missing=()
  local deps=(node npm 7z curl fakeroot dpkg-deb rpmbuild appimagetool convert)
  for d in "${deps[@]}"; do
    command -v "$d" >/dev/null 2>&1 || missing+=("$d")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "missing dependencies: ${missing[*]}"
  fi
}

# ----- Arch detection -----
detect_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "unsupported arch: $m" ;;
  esac
}

resolve_dmg_url() {
  # Scrape the public download page for the current macOS DMG redirect URL.
  # The redirect endpoint uses a session-scoped token that changes per request,
  # but the path shape is stable: /redirect/<token>/api/desktop/darwin/universal/dmg/latest/redirect
  local ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
  local html
  html="$(curl -fsSL -A "$ua" "$DOWNLOAD_PAGE_URL")" || die "failed to fetch $DOWNLOAD_PAGE_URL"

  local url
  url="$(printf '%s' "$html" \
    | grep -oE 'https://claude\.ai/[^"'"'"']*api/desktop/darwin/universal/dmg/latest/redirect' \
    | head -n1)"

  # Fallback: relative path variant.
  if [[ -z "$url" ]]; then
    local rel
    rel="$(printf '%s' "$html" \
      | grep -oE '/redirect/[^"'"'"']*api/desktop/darwin/universal/dmg/latest/redirect' \
      | head -n1)"
    [[ -n "$rel" ]] && url="https://claude.ai$rel"
  fi

  [[ -n "$url" ]] || die "could not find DMG URL on $DOWNLOAD_PAGE_URL (upstream HTML changed?)"
  echo "$url"
}

dmg_url_for_arch() {
  local arch="$1" override=""
  case "$arch" in
    amd64) override="$DMG_URL_AMD64" ;;
    arm64) override="$DMG_URL_ARM64" ;;
    *) die "unknown arch: $arch" ;;
  esac
  if [[ -n "$override" ]]; then
    echo "$override"
    return
  fi
  if [[ -z "${DMG_URL_UNIVERSAL}" ]]; then
    DMG_URL_UNIVERSAL="$(resolve_dmg_url)"
    log "resolved DMG URL: $DMG_URL_UNIVERSAL"
  fi
  echo "$DMG_URL_UNIVERSAL"
}

# ----- Steps -----
download_dmg() {
  local url="$1" out="$2"
  log "downloading DMG: $url"
  curl -fL --retry 3 \
    -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15" \
    -o "$out" "$url"
}

extract_dmg() {
  local dmg="$1" dest="$2"
  log "extracting DMG"
  mkdir -p "$dest"
  7z x -y -o"$dest" "$dmg" >/dev/null
  # DMG usually exposes one partition; find Claude.app
  local app
  app="$(find "$dest" -maxdepth 4 -name 'Claude.app' -type d | head -n1)"
  [[ -n "$app" ]] || die "Claude.app not found in DMG extraction"
  echo "$app"
}

extract_asar() {
  local resources="$1" dest="$2"
  log "extracting app.asar"
  npx --yes @electron/asar extract "$resources/app.asar" "$dest"
}

patch_native_bindings() {
  local extracted="$1"
  local target="$extracted/node_modules/claude-native/index.js"
  [[ -f "$target" ]] || die "claude-native/index.js not found at $target"
  log "replacing native bindings shim"
  cp "$ROOT_DIR/build-ts/claude-native-bindings.js" "$target"
  # Remove any prebuilt .node binaries packaged alongside
  find "$extracted/node_modules/claude-native" -name '*.node' -delete || true
}

inject_frame_patch() {
  local extracted="$1"
  log "injecting frame-fix-wrapper as main entry"
  local pkg="$extracted/package.json"
  [[ -f "$pkg" ]] || die "package.json missing in asar"

  local orig_main
  orig_main="$(node -e "console.log(require('$pkg').main || 'index.js')")"

  cp "$ROOT_DIR/build-ts/frame-fix-wrapper.js" "$extracted/frame-fix-wrapper.js"

  # Record original main for the wrapper to require.
  node -e "
    const fs = require('fs');
    const p = '$pkg';
    const j = JSON.parse(fs.readFileSync(p, 'utf8'));
    j._originalMain = j.main || 'index.js';
    j.main = 'frame-fix-wrapper.js';
    fs.writeFileSync(p, JSON.stringify(j, null, 2));
  "
  log "original main was: $orig_main"
}

verify_shim() {
  local extracted="$1"
  log "verifying native shim loads"
  node -e "
    const b = require('$extracted/node_modules/claude-native/index.js');
    console.log('exports:', Object.keys(b).join(', '));
  "
}

repack_asar() {
  local extracted="$1" out="$2"
  log "repacking app.asar"
  npx --yes @electron/asar pack "$extracted" "$out"
}

extract_icons() {
  local resources="$1" dest="$2"
  log "extracting icons"
  mkdir -p "$dest"
  local icns
  icns="$(find "$resources" -maxdepth 2 -name '*.icns' | head -n1)"
  if [[ -z "$icns" ]]; then
    log "no .icns found, skipping icon extraction"
    return 0
  fi
  for size in 16 32 48 64 128 256; do
    convert "$icns[0]" -resize "${size}x${size}" "$dest/${size}x${size}.png" 2>/dev/null || \
      convert "$icns" -resize "${size}x${size}" "$dest/${size}x${size}.png"
  done
}

get_version() {
  local extracted="$1"
  node -e "console.log(require('$extracted/package.json').version)"
}

# ----- Stage layout (shared across deb/rpm/AppImage) -----
prepare_stage() {
  local arch="$1" version="$2" asar="$3" icons_dir="$4"
  log "preparing staging tree"
  rm -rf "$STAGE_DIR"
  mkdir -p \
    "$STAGE_DIR/usr/lib/$PKG_NAME" \
    "$STAGE_DIR/usr/bin" \
    "$STAGE_DIR/usr/share/applications"

  cp "$asar" "$STAGE_DIR/usr/lib/$PKG_NAME/app.asar"

  # Launcher
  cat > "$STAGE_DIR/usr/bin/$PKG_NAME" <<'LAUNCHER'
#!/usr/bin/env bash
ELECTRON=$(command -v electron || echo /usr/lib/claude-desktop/electron)

WAYLAND_FLAGS=""
if [[ -n "${WAYLAND_DISPLAY:-}" && "${CLAUDE_USE_WAYLAND:-}" == "1" ]]; then
  WAYLAND_FLAGS="--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland"
fi

exec "${ELECTRON}" /usr/lib/claude-desktop/app.asar ${WAYLAND_FLAGS} "$@"
LAUNCHER
  chmod +x "$STAGE_DIR/usr/bin/$PKG_NAME"

  # .desktop file
  cp "$ROOT_DIR/packaging/appimage/$PKG_NAME.desktop" \
     "$STAGE_DIR/usr/share/applications/$PKG_NAME.desktop"

  # Icons
  if [[ -d "$icons_dir" ]]; then
    for size in 16 32 48 64 128 256; do
      local src="$icons_dir/${size}x${size}.png"
      [[ -f "$src" ]] || continue
      local dst="$STAGE_DIR/usr/share/icons/hicolor/${size}x${size}/apps"
      mkdir -p "$dst"
      cp "$src" "$dst/$PKG_NAME.png"
    done
  fi
}

# ----- Build .deb -----
build_deb() {
  local arch="$1" version="$2"
  log "building .deb"
  local root="$BUILD_DIR/deb-root"
  rm -rf "$root"
  mkdir -p "$root/DEBIAN"
  cp -a "$STAGE_DIR"/. "$root/"

  sed -e "s/^Version:.*/Version: $version/" \
      -e "s/^Architecture:.*/Architecture: $arch/" \
      -e "s/^Maintainer:.*/Maintainer: $MAINTAINER/" \
      "$ROOT_DIR/packaging/deb/control" > "$root/DEBIAN/control"

  mkdir -p "$OUT_DIR"
  local out="$OUT_DIR/${PKG_NAME}_${version}_${arch}.deb"
  fakeroot dpkg-deb --build "$root" "$out"
  log "wrote $out"
}

# ----- Build .rpm -----
build_rpm() {
  local arch="$1" version="$2"
  log "building .rpm"
  local topdir="$BUILD_DIR/rpmbuild"
  rm -rf "$topdir"
  mkdir -p "$topdir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}

  local buildroot="$topdir/BUILDROOT/${PKG_NAME}-${version}-1.${arch}"
  mkdir -p "$buildroot"
  cp -a "$STAGE_DIR"/. "$buildroot/"

  local rpm_arch
  case "$arch" in
    amd64) rpm_arch="x86_64" ;;
    arm64) rpm_arch="aarch64" ;;
  esac

  sed -e "s/^Version:.*/Version:        $version/" \
      "$ROOT_DIR/packaging/rpm/${PKG_NAME}.spec" > "$topdir/SPECS/${PKG_NAME}.spec"

  rpmbuild --define "_topdir $topdir" \
           --define "_binary_payload w2.xzdio" \
           --buildroot "$buildroot" \
           --target "$rpm_arch" \
           -bb "$topdir/SPECS/${PKG_NAME}.spec"

  mkdir -p "$OUT_DIR"
  cp "$topdir/RPMS/$rpm_arch/"*.rpm "$OUT_DIR/"
  log "wrote rpm to $OUT_DIR"
}

# ----- Build AppImage -----
build_appimage() {
  local arch="$1" version="$2"
  log "building AppImage"
  local appdir="$BUILD_DIR/${PKG_NAME}.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir"
  cp -a "$STAGE_DIR"/. "$appdir/"

  cp "$ROOT_DIR/packaging/appimage/$PKG_NAME.desktop" "$appdir/$PKG_NAME.desktop"
  local icon="$appdir/usr/share/icons/hicolor/256x256/apps/$PKG_NAME.png"
  [[ -f "$icon" ]] && cp "$icon" "$appdir/$PKG_NAME.png" || true

  cat > "$appdir/AppRun" <<'APPRUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
ELECTRON=$(command -v electron || true)
if [[ -z "$ELECTRON" ]]; then
  echo "claude-desktop: electron not found in PATH; install the 'electron' package." >&2
  exit 1
fi
exec "$ELECTRON" --no-sandbox "$HERE/usr/lib/claude-desktop/app.asar" "$@"
APPRUN
  chmod +x "$appdir/AppRun"

  mkdir -p "$OUT_DIR"
  local out="$OUT_DIR/${PKG_NAME}-${version}-${arch}.AppImage"
  ARCH="$arch" appimagetool "$appdir" "$out"
  log "wrote $out"
}

main() {
  check_deps
  local arch="${ARCH_OVERRIDE:-$(detect_arch)}"
  log "target arch: $arch"

  rm -rf "$BUILD_DIR"
  mkdir -p "$WORK_DIR" "$OUT_DIR"

  compile_ts

  local dmg="$WORK_DIR/claude.dmg"
  download_dmg "$(dmg_url_for_arch "$arch")" "$dmg"

  local app_root
  app_root="$(extract_dmg "$dmg" "$WORK_DIR/dmg")"
  local resources="$app_root/Contents/Resources"
  [[ -d "$resources" ]] || die "Resources dir missing: $resources"

  local extracted="$WORK_DIR/app-extracted"
  extract_asar "$resources" "$extracted"

  patch_native_bindings "$extracted"
  inject_frame_patch "$extracted"
  verify_shim "$extracted"

  local new_asar="$WORK_DIR/app.asar"
  repack_asar "$extracted" "$new_asar"

  local icons_dir="$WORK_DIR/icons"
  extract_icons "$resources" "$icons_dir"

  local version
  version="$(get_version "$extracted")"
  log "version: $version"

  prepare_stage "$arch" "$version" "$new_asar" "$icons_dir"

  build_deb "$arch" "$version"
  build_rpm "$arch" "$version"
  build_appimage "$arch" "$version"

  log "done. artifacts in $OUT_DIR"
}

main "$@"

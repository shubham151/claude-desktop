# Claude Desktop for Linux (unofficial)

Repackages Anthropic's official Claude Desktop macOS `.dmg` as `.deb`, `.rpm`, and `AppImage` for `amd64` / `arm64`. Runs the original Electron app on system Electron with a small Linux-compatible native-bindings shim — no custom UI, no Tauri.

## How it works

The macOS app ships `app.asar` (the full frontend) plus a macOS-only `claude-native-bindings.node`. The build pipeline:

1. Download the official DMG
2. Extract `app.asar`
3. Replace the native bindings module with a pure-JS Linux shim
4. Inject a small `BrowserWindow` wrapper to fix Linux window decorations + register `Ctrl+Alt+Space`
5. Repack and emit `.deb`, `.rpm`, and `AppImage`

## Build locally

```bash
make deps     # install build dependencies (apt / dnf / pacman auto-detected)
make build    # ARCH=amd64|arm64, defaults to host arch
```

Artifacts land in `dist/`.

## Install

```bash
# Debian/Ubuntu
sudo apt install ./dist/claude-desktop_*_amd64.deb

# Fedora/RHEL
sudo dnf install ./dist/claude-desktop-*.x86_64.rpm

# AppImage
chmod +x ./dist/claude-desktop-*.AppImage && ./dist/claude-desktop-*.AppImage
```

Installs to `/usr/lib/claude-desktop/` with launcher at `/usr/bin/claude-desktop`. Config: `~/.config/Claude/claude_desktop_config.json`.

## Wayland

```bash
CLAUDE_USE_WAYLAND=1 claude-desktop
```

## Automatic releases

GitHub Actions (`.github/workflows/build.yml`) checks upstream weekly (Mon 06:00 UTC) and on manual dispatch. When a new version is detected it builds `amd64` + `arm64` in parallel and publishes a GitHub Release tagged `vX.Y.Z` with all six artifacts attached. Use **Run workflow → force** to rebuild an existing tag.

Download the latest packages from the [Releases page](https://github.com/shubham151/claude-desktop/releases).

## License

Claude Desktop itself is proprietary (© Anthropic). This repo contains only the repackaging scripts and Linux shims — see [LICENSE](LICENSE).

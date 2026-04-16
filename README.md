# Claude Desktop for Linux (unofficial)

Repackages Anthropic's official Claude Desktop macOS `.dmg` as `.deb`, `.rpm`, and `AppImage` for `amd64` / `arm64` Linux. No custom UI — the original Electron app runs on system Electron with a Linux-compatible native bindings shim.

See [IMPLEMENTATION.md](IMPLEMENTATION.md) for design notes.

## Build

```bash
./build.sh
```

Outputs land in `dist/`. Requires: `node`, `npm`, `7z`, `curl`, `fakeroot`, `dpkg-deb`, `rpmbuild`, `appimagetool`, `imagemagick`.

Override architecture via `ARCH_OVERRIDE=amd64|arm64`. Override DMG URLs via `DMG_URL_AMD64` / `DMG_URL_ARM64`.

## Install

```bash
# Debian/Ubuntu
sudo apt install ./dist/claude-desktop_*_amd64.deb

# Fedora/RHEL
sudo dnf install ./dist/claude-desktop-*.x86_64.rpm

# Or run the AppImage directly
chmod +x ./dist/claude-desktop-*.AppImage
./dist/claude-desktop-*.AppImage
```

All install paths install to `/usr/lib/claude-desktop/` with launcher at `/usr/bin/claude-desktop`. Config lives at `~/.config/Claude/claude_desktop_config.json`.

## Wayland

```bash
CLAUDE_USE_WAYLAND=1 claude-desktop
```

## License

Claude Desktop itself is proprietary (© Anthropic). This repo contains only the repackaging scripts and Linux shims — see [LICENSE](LICENSE).

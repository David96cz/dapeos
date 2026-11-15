# WhiskerMenu without the "Run" search action

WhiskerMenu adds a generated "Run <command>" entry to search results whenever
the query matches an executable in PATH. Upstream has no option to disable it.

This patch removes that entry. Everything else (categories, favorites, recent,
application search) is unchanged.

## Build (on Debian trixie, native architecture)

```bash
sudo packages/whiskermenu-no-run/build.sh
```

The script installs build dependencies, enables `deb-src` if needed, downloads
the current trixie source, applies `no-run.patch`, bumps the version to
`<debian-version>+dapeos1`, builds the package, and copies the `.deb` here.

For ARM64, run the same script on an ARM64 Debian machine/VM.

## Install

```bash
sudo apt-get install -y packages/whiskermenu-no-run/xfce4-whiskermenu-plugin_*_<arch>.deb
sudo apt-mark hold xfce4-whiskermenu-plugin
```

The DapeOS installer installs a matching `.deb` automatically when present and
holds the package; otherwise it keeps the stock WhiskerMenu.

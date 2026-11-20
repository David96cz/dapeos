# Thunar without the "File System" device

Thunar always adds a root/File System device to the sidebar; there is no
xfconf setting for it. This patch removes only that hardcoded entry.

## Build (Debian trixie, native architecture)

```bash
sudo packages/thunar-no-root/build.sh
```

Outputs `thunar_*_<arch>.deb` and `thunar-data_*_<arch>.deb` here.

## Install

```bash
sudo apt-get install -y packages/thunar-no-root/thunar_*_<arch>.deb \
  packages/thunar-no-root/thunar-data_*_<arch>.deb
sudo apt-mark hold thunar thunar-data
```

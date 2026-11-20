# DapeOS status panel plugin — handoff for Claude

## Goal

Replace the Python `dapeos-status` + XFCE GenMon combination with a **single C XFCE panel plugin** that:

- draws the existing network + battery + volume composite (same look/size),
- updates **event-driven**, with no polling timer,
- is light enough for old Intel Atom hardware,
- opens `dapeos-quicksettings-toggle` on left click,
- keeps a tooltip with network / volume / battery.

Target: Debian 13 trixie, XFCE 4.20.4, ARM64 VM for testing, later amd64 Lenovo L460.

## Repository

- `https://github.com/David96cz/dapeos`, branch `dev`
- Working tree on the user's Mac: `~/dapeos`
- Safe tag before the C work: `safe/pre-status-c` (`c484b98`)
- Latest relevant work: `cea755f` (event GenMon fallback), C plugin code is in `packages/dapeos-status-plugin/`

## Current C plugin

Files:

- `packages/dapeos-status-plugin/src/dapeos-status.c`
- `packages/dapeos-status-plugin/build.sh`
- `packages/dapeos-status-plugin/dapeos-status.desktop`

Builds a shared object `libdapeos-status.so`, installs it to:

```
/usr/lib/<multiarch>/xfce4/panel/plugins/libdapeos-status.so
/usr/share/xfce4/panel/plugins/dapeos-status.desktop
```

Descriptor (this exact structure was required):

```ini
[Xfce Panel]
Type=X-XFCE-PanelPlugin
Name=DapeOS Status
Comment=Network, battery and volume status
Icon=dapeos-logo
X-XFCE-Module=dapeos-status
X-XFCE-Internal=false
X-XFCE-API=2.0
```

`X-XFCE-Module` must be `dapeos-status`, **not** `libdapeos-status.so`. The `[Xfce Panel]` group is required. `X-XFCE-API=2.0` is required, otherwise the panel assumes Gtk2 API v1.0.

Build:

```bash
sudo packages/dapeos-status-plugin/build.sh
sudo apt-get install -y --reinstall ./packages/dapeos-status-plugin/dapeos-status-plugin_1.0_arm64.deb
```

## Symptom

The panel loads the plugin and calls `construct`, but the plugin has **zero/near-zero width** and nothing is visible.

Observed log from `xfce4-panel`:

```
DAPEOS: construct
DAPEOS: pixbuf 74x22
DAPEOS: now plugin=1 child=1 area=1 parent=0x... children=1 visible=1 mapped=0
DAPEOS: pixbuf 74x22
DAPEOS: pixbuf 74x22
```

There is **no** `DAPEOS: alloc plugin=...` and **no** `DAPEOS: force size done`, so the `g_idle_add()` / `g_timeout_add()` callbacks never run after `construct`.

Historically also seen:

```
Gtk-CRITICAL gtk_widget_destroy: assertion 'GTK_IS_WIDGET (widget)' failed
```

and the panel had `plugin-ids` without `12`, so the item disappeared entirely after switching plugin type. Adding GenMon back restores the icon.

## What was already tried

- `GtkDrawingArea` with `draw` signal → no `draw` callback.
- `GtkImage` + `gdk_pixbuf_get_from_surface()` → pixbuf is correctly 74x22, but widget still 1x1.
- `xfce_panel_create_button()` wrapper → no change.
- `GtkEventBox` + `xfce_panel_plugin_add_action_widget()` + box, copied from GenMon → no change.
- `size-changed` returning `TRUE`/`FALSE`; setting size request on plugin, button, eventbox, and parent `GtkPlug` → no change.
- `xfce_panel_plugin_set_small(plugin, TRUE)` → no change.
- `update_image()` is called in `construct`, so SVG rendering works.

The plugin runs in the **external plugin wrapper** (`xfce4-panel-wrapper` / `GtkPlug` + `GtkSocket`), not directly in the panel process. The provider is allocated 1x1 and never mapped, and idle/timeout callbacks don't fire.

## Strong hypotheses for Claude

1. **Try `X-XFCE-Internal=true`** instead of `false`. `clock.desktop` is internal (`TRUE`) and works. Internal may load the module in the panel process and avoid the external `GtkPlug`/wrapper sizing entirely. This is probably the first thing to test.
2. Inspect `xfce4-panel` source `panel/panel-plugin-external-wrapper.c`, `wrapper/main.c`, `wrapper/wrapper-plug-x11.c`, and `libxfce4panel/xfce-panel-plugin.c`:
   - `xfce_panel_plugin_set_size()` sets `real_size x real_size` unless `size-changed` is handled.
   - The wrapper creates a `GtkPlug`, packs the provider into it, and shows only the provider.
3. Compare with `xfce4-genmon-plugin` `main.c` `genmon_construct()` and `genmon_set_size()` — that plugin works in this panel.
4. Determine why `g_idle_add`/`g_timeout_add` callbacks never run. Maybe the module is unloaded after construct, or the provider is destroyed/unmapped. Check module residency (`g_module_make_resident`) and the `Gtk-CRITICAL gtk_widget_destroy`.
5. If external plugin cannot be made to work, alternative: write the C code as a **patched GenMon** plugin (same panel plugin, C event handling, C-rendered SVG/pixbuf) instead of a new external plugin.

## Event sources intended

- Volume/mute: `pactl subscribe` (child process, read lines via `GIOChannel`).
- Network: NetworkManager D-Bus (`org.freedesktop.NetworkManager`) or `nmcli monitor`.
- Battery: UPower D-Bus (`org.freedesktop.UPower.Device`) or `/sys/class/power_supply`.
- Panel dark mode: xfconf `/panels/*/dark-mode`.

No periodic timer. Initial read once, then events only.

## Existing Python reference

`contents/xfce/scripts/dapeos-status` contains the exact SVG geometry/colors and tray settings. The C `build_svg()` in `dapeos-status.c` is a first-pass port; compare output.

## Current fallback

Stock GenMon + Python `dapeos-status` is installed (or event-patched GenMon `4.1.1-1+dapeos1`), but the user explicitly does **not** want GenMon/Python for the final status. Use it only as a visual/reference fallback.

## Test procedure

```bash
cd ~/dapeos
git pull
sudo packages/dapeos-status-plugin/build.sh
sudo apt-get install -y --reinstall ./packages/dapeos-status-plugin/dapeos-status-plugin_1.0_arm64.deb

pkill -x xfce4-panel
xfce4-panel 2>&1 | tee /tmp/panel-debug.log
```

Check:

```bash
xfconf-query -c xfce4-panel -p /panels/panel-2/plugin-ids
xfconf-query -c xfce4-panel -p /plugins/plugin-12
```

For the plugin, `plugin-ids` must include `12`; `/plugins/plugin-12` must be `dapeos-status`.

## Constraints

- Keep it light: target <15 MB RSS, ~0% idle CPU, event latency <50 ms.
- Preserve the composite look (three icons, spacing, colors, tooltip).
- Do not break panel Light/Dark independence.
- User has limited patience; give exact commands and check results, don't guess.

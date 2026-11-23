#include <gtk/gtk.h>
#include <glib-unix.h>
#include <signal.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

static gchar *run_cmd (const gchar *cmd);
static void run_async (const gchar *cmd);

static GtkWidget *window;
static GtkWidget *qstack;
static GtkWidget *main_page;
static GtkWidget *wifi_page;
static GtkWidget *wifi_page_toggle;
static GtkWidget *bt_page;
static GtkWidget *bt_list;
static GtkWidget *night_page;
static GtkWidget *night_page_scale;
static GtkWidget *night_page_toggle;
static GtkWidget *night_from_entry;
static GtkWidget *night_to_entry;
static GtkWidget *wifi_password_page;
static GtkWidget *wifi_password_label;
static GtkWidget *wifi_password_entry;
static gchar *wifi_password_ssid;
static gboolean wifi_password_known;
static GtkWidget *wifi_error_label;
static GtkWidget *wifi_confirm_page;
static GtkWidget *wifi_confirm_label;
static gchar *wifi_confirm_ssid;
static gboolean wifi_confirm_connected;
static guint wifi_error_timeout = 0;
static GtkWidget *vol_scale;
static GtkWidget *vol_label;
static GtkWidget *mute_button;
static GtkWidget *battery_label;
static GtkWidget *bt_label;
static GtkWidget *night_label;
static GtkWidget *net_label;
static GtkWidget *net_status_label;
static GtkWidget *bri_row;
static GtkWidget *bri_scale;
static GtkWidget *bri_label;
static gboolean bri_updating = FALSE;
static guint bri_timeout = 0;
static GtkWidget *bt_status_label;
static GtkWidget *night_status_label;
static gboolean updating = FALSE;
static guint vol_timeout = 0;
static guint bg_timeout = 0;
static gboolean night_on = FALSE;
static gboolean window_dark = TRUE;
static void position_window (void);
static gboolean net_connecting = FALSE;
static guint net_anim_id = 0;
static gint net_anim_phase = 0;
static gint net_anim_ticks = 0;

static gchar *night_state_path (const gchar *name)
{
    return g_build_filename (g_get_user_cache_dir (), "dapeos", name, NULL);
}

static gchar *
bt_connected_name (void)
{
    gchar *out = run_cmd ("bluetoothctl devices Connected 2>/dev/null");
    gchar *name = NULL;
    gchar **lines = g_strsplit (out, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        gchar mac[64] = "", n[256] = "";
        if (sscanf (lines[i], "Device %63s %255[^\n]", mac, n) == 2 && *n) {
            name = g_strdup (n);
            break;
        }
    }
    g_strfreev (lines);
    g_free (out);
    return name;
}

static gboolean bt_is_on (void)
{
    gchar *out = run_cmd ("rfkill list bluetooth 2>/dev/null");
    if (strstr (out, "Soft blocked: yes")) { g_free (out); return FALSE; }
    if (strstr (out, "Soft blocked: no")) { g_free (out); return TRUE; }
    g_free (out);
    out = run_cmd ("timeout 1 bluetoothctl show 2>/dev/null");
    gboolean on = strstr (out, "Powered: yes") != NULL;
    g_free (out);
    return on;
}

static void update_volume_ui (void);
static void set_volume_ui (gint vol, gboolean mute);
static gint get_volume (void);
static gboolean get_mute (void);
static gboolean backlight_info (gint *current, gint *maximum);
static void update_tiles (void);
static gboolean wifi_radio_on (void);
static void on_bt_open (GtkButton *button, gpointer data);
static void bt_refresh (GtkWidget *page);
static gboolean bt_refresh_cb (gpointer data);
static void bt_refresh (GtkWidget *page);
static void show_main_page (GtkButton *button, gpointer data);
static void on_night_open (GtkButton *button, gpointer data);

static gboolean update_volume_cb (gpointer data) { (void) data; update_volume_ui (); return FALSE; }
static gboolean update_tiles_cb (gpointer data) { (void) data; update_tiles (); return FALSE; }
static gboolean tiles_tick (gpointer data) { (void) data; update_tiles (); return G_SOURCE_CONTINUE; }

static gchar *
active_wifi_ssid (void)
{
    gchar *out = run_cmd ("nmcli -t -f ACTIVE,SSID device wifi list 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    gchar *ssid = NULL;
    for (guint i = 0; lines[i]; i++) {
        gchar **p = g_strsplit (lines[i], ":", 2);
        if (p[0] && g_strcmp0 (p[0], "yes") == 0 && p[1]) {
            ssid = g_strdup (p[1]);
            g_strfreev (p);
            break;
        }
        g_strfreev (p);
    }
    g_strfreev (lines);
    g_free (out);
    return ssid;
}

static gboolean
has_known_wifi (void)
{
    gchar *out = run_cmd ("nmcli -t -f NAME,TYPE connection show 2>/dev/null");
    gboolean known = strstr (out, "wireless") != NULL || strstr (out, "wifi") != NULL;
    g_free (out);
    return known;
}

static gboolean update_network_label (void)
{
    if (!net_label) return FALSE;
    gchar *out = run_cmd ("nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    gchar *wifi = NULL, *eth = NULL;
    for (guint i = 0; lines[i]; i++) {
        gchar **parts = g_strsplit (lines[i], ":", 3);
        if (parts[1] && g_strcmp0 (parts[1], "connected") == 0) {
            if (g_strcmp0 (parts[0], "wifi") == 0 && wifi == NULL)
                wifi = g_strdup (parts[2] ? parts[2] : "");
            else if (g_strcmp0 (parts[0], "ethernet") == 0 && eth == NULL)
                eth = g_strdup (parts[2] ? parts[2] : "");
        }
        g_strfreev (parts);
    }
    gchar *label;
    if (wifi) {
        gchar *ssid = active_wifi_ssid ();
        label = g_strdup (ssid ? ssid : wifi);
        g_free (ssid);
    }
    else if (eth)
        label = g_strdup_printf ("Ethernet: %s", eth);
    else
        label = g_strdup ("Disconnected");
    if (net_connecting && !wifi && !eth) {
        g_free (label); g_free (wifi); g_free (eth);
        g_strfreev (lines);
        g_free (out);
        return FALSE;
    }
    gboolean connected = (wifi != NULL);
    gtk_label_set_text (GTK_LABEL (net_label), label);
    g_free (label); g_free (wifi); g_free (eth);
    g_strfreev (lines);
    g_free (out);
    return connected;
}

static gboolean
net_anim_tick (gpointer data)
{
    (void) data;
    if (!net_connecting) { net_anim_id = 0; return FALSE; }
    net_anim_ticks++;
    if (net_anim_ticks > 22) {
        net_connecting = FALSE;
        net_anim_id = 0;
        gtk_label_set_text (GTK_LABEL (net_label),
                            has_known_wifi () ? "Disconnected" : "No known Wi-Fi");
        return FALSE;
    }
    if (update_network_label ()) {
        net_connecting = FALSE;
        net_anim_id = 0;
        return FALSE;
    }
    static const gchar *dots[] = { ".", "..", "...", "....", "...", ".." };
    gchar *text = g_strdup_printf ("Connecting%s", dots[net_anim_phase % 6]);
    gtk_label_set_text (GTK_LABEL (net_label), text);
    g_free (text);
    net_anim_phase++;
    return TRUE;
}

static void
start_net_animation (void)
{
    net_connecting = TRUE;
    net_anim_phase = 0;
    net_anim_ticks = 0;
    if (net_anim_id == 0)
        net_anim_id = g_timeout_add (450, net_anim_tick, NULL);
}

static void
stop_net_animation (void)
{
    net_connecting = FALSE;
    if (net_anim_id) { g_source_remove (net_anim_id); net_anim_id = 0; }
}

static gchar *
short_name (const gchar *s)
{
    if (!s) return g_strdup ("");
    if (g_utf8_strlen (s, -1) <= 12) return g_strdup (s);
    const gchar *end = g_utf8_offset_to_pointer (s, 12);
    return g_strdup_printf ("%.*s…", (int) (end - s), s);
}

static void update_tiles (void)
{
    gboolean bt = bt_is_on ();
    gtk_label_set_text (GTK_LABEL (bt_status_label), bt ? "On" : "Off");
    gchar *btdev = bt_connected_name ();
    gchar *shortdev = short_name (btdev);
    gtk_label_set_text (GTK_LABEL (bt_label), shortdev);
    g_free (shortdev);
    g_free (btdev);

    gchar *nightfile = night_state_path ("nightlight_on");
    night_on = g_file_test (nightfile, G_FILE_TEST_EXISTS);
    g_free (nightfile);
    gtk_label_set_text (GTK_LABEL (night_status_label), night_on ? "On" : "Off");
    if (night_on) {
        gchar *state = night_state_path ("nightlight");
        gchar *temp = NULL;
        if (g_file_get_contents (state, &temp, NULL, NULL)) {
            gchar *t = g_strdup_printf ("%d K", atoi (temp));
            gtk_label_set_text (GTK_LABEL (night_label), t);
            g_free (t);
        }
        g_free (temp); g_free (state);
    } else {
        gtk_label_set_text (GTK_LABEL (night_label), "");
    }

    gboolean on = wifi_radio_on ();
    gtk_label_set_text (GTK_LABEL (net_status_label), on ? "On" : "Off");
    if (wifi_page_toggle) gtk_button_set_label (GTK_BUTTON (wifi_page_toggle), on ? "On" : "Off");
    if (!on) {
        gtk_label_set_text (GTK_LABEL (net_label), "");
    } else {
        update_network_label ();
    }
}

static void
volume_cache_changed (GFileMonitor *monitor, GFile *file, GFile *other,
                      GFileMonitorEvent event, gpointer data)
{
    (void) monitor; (void) file; (void) other; (void) data;
    if (event != G_FILE_MONITOR_EVENT_CHANGED &&
        event != G_FILE_MONITOR_EVENT_CREATED &&
        event != G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT)
        return;
    gchar *path = g_build_filename (g_get_user_cache_dir (), "dapeos", "volume", NULL);
    gchar *text = NULL;
    if (g_file_get_contents (path, &text, NULL, NULL)) {
        gchar **p = g_strsplit (text, "\n", -1);
        gint vol = p[0] ? atoi (p[0]) : 0;
        gboolean mute = p[1] ? atoi (p[1]) != 0 : FALSE;
        set_volume_ui (vol, mute);
        g_strfreev (p);
    }
    g_free (text); g_free (path);
}

static void
brightness_cache_changed (GFileMonitor *monitor, GFile *file, GFile *other,
                          GFileMonitorEvent event, gpointer data)
{
    (void) monitor; (void) file; (void) other; (void) data;
    if (event != G_FILE_MONITOR_EVENT_CHANGED &&
        event != G_FILE_MONITOR_EVENT_CREATED &&
        event != G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT)
        return;
    gchar *path = g_build_filename (g_get_user_cache_dir (), "dapeos", "brightness", NULL);
    gchar *text = NULL;
    if (g_file_get_contents (path, &text, NULL, NULL)) {
        gint pct = atoi (text);
        bri_updating = TRUE;
        gtk_range_set_value (GTK_RANGE (bri_scale), pct);
        gchar *t = g_strdup_printf ("%d%%", pct);
        gtk_label_set_text (GTK_LABEL (bri_label), t);
        g_free (t);
        bri_updating = FALSE;
    }
    g_free (text); g_free (path);
}

static void
install_cache_monitors (void)
{
    gchar *dir = g_build_filename (g_get_user_cache_dir (), "dapeos", NULL);
    g_mkdir_with_parents (dir, 0700);

    gchar *vpath = g_build_filename (dir, "volume", NULL);
    if (!g_file_test (vpath, G_FILE_TEST_EXISTS)) {
        gchar *init = g_strdup_printf ("%d\n%d\n", get_volume (), get_mute () ? 1 : 0);
        g_file_set_contents (vpath, init, -1, NULL);
        g_free (init);
    }
    GFile *vf = g_file_new_for_path (vpath);
    GFileMonitor *vm = g_file_monitor_file (vf, G_FILE_MONITOR_NONE, NULL, NULL);
    if (vm) g_signal_connect (vm, "changed", G_CALLBACK (volume_cache_changed), NULL);
    g_object_unref (vf);

    gchar *bpath = g_build_filename (dir, "brightness", NULL);
    if (!g_file_test (bpath, G_FILE_TEST_EXISTS)) {
        gint cur = 0, max = 0;
        gchar *init = NULL;
        if (backlight_info (&cur, &max) && max > 0)
            init = g_strdup_printf ("%d", cur * 100 / max);
        else
            init = g_strdup ("0");
        g_file_set_contents (bpath, init, -1, NULL);
        g_free (init);
    }
    GFile *bf = g_file_new_for_path (bpath);
    GFileMonitor *bm = g_file_monitor_file (bf, G_FILE_MONITOR_NONE, NULL, NULL);
    if (bm) g_signal_connect (bm, "changed", G_CALLBACK (brightness_cache_changed), NULL);
    g_object_unref (bf);

    g_free (vpath); g_free (bpath); g_free (dir);
}

static gboolean
bt_connect_known_cb (gpointer data)
{
    (void) data;
    gchar *out = run_cmd ("bluetoothctl devices Paired 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        gchar mac[64] = "", name[256] = "";
        if (sscanf (lines[i], "Device %63s %255[^\n]", mac, name) == 2) {
            gchar *cmd = g_strdup_printf ("bluetoothctl connect %s >/dev/null 2>&1", mac);
            run_async (cmd);
            g_free (cmd);
        }
    }
    g_strfreev (lines);
    g_free (out);
    return FALSE;
}

static void on_bt_clicked (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gboolean was_on = bt_is_on ();
    if (was_on)
        run_async ("bluetoothctl power off");
    else
        run_async ("rfkill unblock bluetooth; bluetoothctl power on");
    if (bt_page) {
        g_object_ref (bt_page);
        g_timeout_add (800, bt_refresh_cb, bt_page);
    }
    if (!was_on) g_timeout_add (2500, bt_connect_known_cb, NULL);
    g_timeout_add (400, update_tiles_cb, NULL);
}

static void primary_output (gchar *out, gsize len)
{
    gchar *list = run_cmd ("xrandr --query 2>/dev/null");
    gchar **lines = g_strsplit (list, "\n", -1);
    out[0] = 0;
    for (guint i = 0; lines[i]; i++) {
        if (strstr (lines[i], " connected")) {
            g_strlcpy (out, lines[i], len);
            gchar *space = strchr (out, ' ');
            if (space) *space = 0;
            break;
        }
    }
    g_strfreev (lines);
    g_free (list);
}

static void apply_gamma (gint temp)
{
    gchar output[64];
    primary_output (output, sizeof output);
    if (!output[0]) return;
    gdouble r, g, b;
    if (temp <= 0) { r = g = b = 1.0; }
    else {
        gdouble t = temp / 100.0;
        if (t <= 66) {
            r = 255.0;
            g = 99.4708025861 * log (t) - 161.1195681661;
            b = (t <= 19) ? 0.0 : 138.5177312231 * log (t - 10) - 305.0447927307;
        } else {
            r = 329.698727446 * pow (t - 60, -0.1332047592);
            g = 288.1221695283 * pow (t - 60, -0.0755148492);
            b = 255.0;
        }
        r = MAX (0.0, MIN (255.0, r)) / 255.0;
        g = MAX (0.0, MIN (255.0, g)) / 255.0;
        b = MAX (0.0, MIN (255.0, b)) / 255.0;
    }
    gchar *cmd = g_strdup_printf ("xrandr --output %s --gamma %.3f:%.3f:%.3f", output, r, g, b);
    run_async (cmd);
    g_free (cmd);
}

static void on_night_clicked (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gchar *dir = g_build_filename (g_get_user_cache_dir (), "dapeos", NULL);
    gchar *onfile = night_state_path ("nightlight_on");
    g_mkdir_with_parents (dir, 0700);
    if (night_on) {
        g_unlink (onfile);
        apply_gamma (0);
    } else {
        g_file_set_contents (onfile, "", 0, NULL);
        apply_gamma (4000);
    }
    night_on = !night_on;
    gtk_label_set_text (GTK_LABEL (night_status_label), night_on ? "On" : "Off");
    gtk_label_set_text (GTK_LABEL (night_label), night_on ? "4000 K" : "");
    g_free (onfile); g_free (dir);
}

static gchar *run_cmd (const gchar *cmd)
{
    gchar *out = NULL;
    gint status = 0;
    gchar *quoted = g_shell_quote (cmd);
    gchar *shell = g_strdup_printf ("sh -c %s", quoted);
    gboolean ok = g_spawn_command_line_sync (shell, &out, NULL, &status, NULL);
    g_free (shell);
    g_free (quoted);
    if (!ok || out == NULL) return g_strdup ("");
    g_strstrip (out);
    return out;
}

static void run_async (const gchar *cmd)
{
    gchar *quoted = g_shell_quote (cmd);
    gchar *shell = g_strdup_printf ("sh -c %s", quoted);
    g_spawn_command_line_async (shell, NULL);
    g_free (shell);
    g_free (quoted);
}

static gint get_volume (void)
{
    gchar *out = run_cmd ("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null");
    gint vol = 0;
    for (gchar *p = out; *p; p++) {
        if (*p == '%') {
            gchar *start = p;
            while (start > out && g_ascii_isdigit (start[-1])) start--;
            vol = atoi (start);
            break;
        }
    }
    g_free (out);
    return vol;
}

static gboolean get_mute (void)
{
    gchar *out = run_cmd ("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null");
    gboolean mute = strstr (out, "yes") != NULL;
    g_free (out);
    return mute;
}

static gchar *get_battery (void)
{
    const gchar *names[] = { "BAT0", "BAT1", "BAT2" };
    for (guint i = 0; i < G_N_ELEMENTS (names); i++) {
        gchar *base = g_strdup_printf ("/sys/class/power_supply/%s", names[i]);
        gchar *capf = g_build_filename (base, "capacity", NULL);
        gchar *stf = g_build_filename (base, "status", NULL);
        gchar *cap = NULL, *status = NULL;
        if (g_file_get_contents (capf, &cap, NULL, NULL)) {
            g_file_get_contents (stf, &status, NULL, NULL);
            gchar *res = g_strdup_printf ("Battery %s%% (%s)", g_strstrip (cap),
                                          status ? g_strstrip (status) : "");
            g_free (cap); g_free (status); g_free (capf); g_free (stf); g_free (base);
            return res;
        }
        g_free (cap); g_free (status); g_free (capf); g_free (stf); g_free (base);
    }
    return g_strdup ("Battery: no battery");
}

static gboolean is_dark (void)
{
    gchar *out = run_cmd ("xfconf-query -c xfce4-panel -p /panels/dark-mode 2>/dev/null");
    gboolean dark = g_strcmp0 (out, "true") == 0;
    if (!dark && out && *out == 0) {
        gchar *list = run_cmd ("xfconf-query -c xfce4-panel -l 2>/dev/null");
        gchar **lines = g_strsplit (list, "\n", -1);
        for (guint i = 0; lines[i]; i++) {
            if (g_str_has_suffix (lines[i], "/dark-mode")) {
                gchar *cmd = g_strdup_printf ("xfconf-query -c xfce4-panel -p '%s' 2>/dev/null", lines[i]);
                gchar *val = run_cmd (cmd);
                dark = g_strcmp0 (val, "true") == 0;
                g_free (val); g_free (cmd);
                break;
            }
        }
        g_strfreev (lines);
        g_free (list);
    }
    g_free (out);
    return dark;
}

static gint panel_height (void)
{
    gchar *out = run_cmd ("xfconf-query -c xfce4-panel -p /panels/panel-2/size 2>/dev/null");
    gint h = atoi (out);
    g_free (out);
    return h > 0 ? h : 36;
}

static GtkWidget *
volume_icon (const gchar *name)
{
    const gchar *theme_name = is_dark () ? "Papirus-Dark" : "Papirus-Light";
    GtkIconTheme *theme = gtk_icon_theme_new ();
    gtk_icon_theme_set_custom_theme (theme, theme_name);
    GdkPixbuf *pix = gtk_icon_theme_load_icon (theme, name, 24, GTK_ICON_LOOKUP_FORCE_SIZE, NULL);
    g_object_unref (theme);
    if (pix) {
        GtkWidget *img = gtk_image_new_from_pixbuf (pix);
        g_object_unref (pix);
        return img;
    }
    return gtk_image_new_from_icon_name (name, GTK_ICON_SIZE_BUTTON);
}

static void apply_css (void)
{
    window_dark = is_dark ();
    GtkCssProvider *css = gtk_css_provider_new ();
    const gchar *data;
    if (is_dark ()) {
        data =
            "#dapeos-qs { background: transparent; }"
            "#dapeos-qs label, #dapeos-qs button { color: #eaeaea; }"
            "#dapeos-qs button.tile-left { background: #3a3a3a; border: 1px solid #4a4a4a; border-radius: 10px 0 0 10px; padding: 10px; }"
            "#dapeos-qs button.tile-right { background: #3a3a3a; border: 1px solid #4a4a4a; border-left: none; border-radius: 0 10px 10px 0; padding: 0; }"
            "#dapeos-qs button.tile-left:hover, #dapeos-qs button.tile-right:hover { border-color: #2a7fca; }"
            "#dapeos-qs scale trough { background: #151515; border-radius: 3px; min-height: 6px; }"
            "#dapeos-qs scale highlight { background: #2a7fca; }"
            "#dapeos-qs scale slider { background: #2a7fca; border-radius: 8px; min-width: 16px; min-height: 16px; }"
            "#dapeos-qs button.flat { background: transparent; border: none; }"
            "#dapeos-qs scrolledwindow, #dapeos-qs viewport, #dapeos-qs list, #dapeos-qs listbox, #dapeos-qs row { background: transparent; color: #eaeaea; }"
            "#dapeos-qs list row:selected { background: #2a7fca; color: #ffffff; }"
            "#dapeos-qs button { background: #3a3a3a; border: 1px solid #4a4a4a; border-radius: 8px; padding: 6px 10px; }"
            "#dapeos-qs label#wifi-error { color: #ff6b6b; }"
            "#dapeos-qs label#brightness-icon { color: #eaeaea; font-size: 16pt; }";
    } else {
        data =
            "#dapeos-qs { background: transparent; }"
            "#dapeos-qs label, #dapeos-qs button { color: #1a1a1a; }"
            "#dapeos-qs button.tile-left { background: #ffffff; border: 1px solid #dcdcdc; border-radius: 10px 0 0 10px; padding: 10px; }"
            "#dapeos-qs button.tile-right { background: #ffffff; border: 1px solid #dcdcdc; border-left: none; border-radius: 0 10px 10px 0; padding: 0; }"
            "#dapeos-qs button.tile-left:hover, #dapeos-qs button.tile-right:hover { border-color: #2a7fca; }"
            "#dapeos-qs scale trough { background: #d0d0d0; border-radius: 3px; min-height: 6px; }"
            "#dapeos-qs scale highlight { background: #2a7fca; }"
            "#dapeos-qs scale slider { background: #2a7fca; border-radius: 8px; min-width: 16px; min-height: 16px; }"
            "#dapeos-qs button.flat { background: transparent; border: none; }"
            "#dapeos-qs scrolledwindow, #dapeos-qs viewport, #dapeos-qs list, #dapeos-qs listbox, #dapeos-qs row { background: transparent; color: #1a1a1a; }"
            "#dapeos-qs list row:selected { background: #2a7fca; color: #ffffff; }"
            "#dapeos-qs button { background: #ffffff; border: 1px solid #dcdcdc; border-radius: 8px; padding: 6px 10px; }"
            "#dapeos-qs label#wifi-error { color: #c62828; }"
            "#dapeos-qs label#brightness-icon { color: #1a1a1a; font-size: 16pt; }";
    }
    gtk_css_provider_load_from_data (css, data, -1, NULL);
    gtk_style_context_add_provider_for_screen (gdk_screen_get_default (),
        GTK_STYLE_PROVIDER (css), GTK_STYLE_PROVIDER_PRIORITY_USER);
    g_object_unref (css);
}

static void
set_volume_ui (gint vol, gboolean mute)
{
    updating = TRUE;
    gtk_range_set_value (GTK_RANGE (vol_scale), vol);
    gchar *txt = g_strdup_printf ("%d%%", vol);
    gtk_label_set_text (GTK_LABEL (vol_label), txt);
    g_free (txt);
    const gchar *ic = mute ? "audio-volume-muted" : "audio-volume-high";
    gtk_button_set_image (GTK_BUTTON (mute_button), volume_icon (ic));
    updating = FALSE;
}

static void update_volume_ui (void)
{
    set_volume_ui (get_volume (), get_mute ());
}

static gboolean
backlight_info (gint *current, gint *maximum)
{
    gchar *cur_s = run_cmd ("brightnessctl get 2>/dev/null");
    gchar *max_s = run_cmd ("brightnessctl max 2>/dev/null");
    if (*cur_s && *max_s) {
        *current = atoi (cur_s);
        *maximum = atoi (max_s);
        g_free (cur_s); g_free (max_s);
        if (*maximum > 0) return TRUE;
    } else {
        g_free (cur_s); g_free (max_s);
    }

    GDir *dir = g_dir_open ("/sys/class/backlight", 0, NULL);
    if (!dir) return FALSE;
    const gchar *name;
    gboolean found = FALSE;
    while ((name = g_dir_read_name (dir)) != NULL) {
        gchar *base = g_build_filename ("/sys/class/backlight", name, NULL);
        gchar *curf = g_build_filename (base, "brightness", NULL);
        gchar *maxf = g_build_filename (base, "max_brightness", NULL);
        gchar *cur = NULL, *max = NULL;
        if (g_file_get_contents (curf, &cur, NULL, NULL) &&
            g_file_get_contents (maxf, &max, NULL, NULL)) {
            *current = atoi (cur);
            *maximum = atoi (max);
            found = (*maximum > 0);
        }
        g_free (cur); g_free (max); g_free (curf); g_free (maxf); g_free (base);
        if (found) break;
    }
    g_dir_close (dir);
    return found;
}

static void
update_brightness_ui (void)
{
    gint cur = 0, max = 0;
    if (!bri_row) return;
    if (!backlight_info (&cur, &max)) {
        gtk_widget_hide (bri_row);
        return;
    }
    gtk_widget_show (bri_row);
    bri_updating = TRUE;
    gint pct = max > 0 ? (cur * 100 / max) : 0;
    gtk_range_set_value (GTK_RANGE (bri_scale), pct);
    gchar *txt = g_strdup_printf ("%d%%", pct);
    gtk_label_set_text (GTK_LABEL (bri_label), txt);
    g_free (txt);
    bri_updating = FALSE;
}

static gboolean
apply_brightness (gpointer data)
{
    (void) data;
    bri_timeout = 0;
    gint pct = (gint) gtk_range_get_value (GTK_RANGE (bri_scale));
    gchar *cmd = g_strdup_printf ("brightnessctl set %d%%", pct);
    run_async (cmd);
    g_free (cmd);
    gchar *txt = g_strdup_printf ("%d%%", pct);
    gtk_label_set_text (GTK_LABEL (bri_label), txt);
    g_free (txt);
    return FALSE;
}

static void
on_brightness_changed (GtkRange *range, gpointer data)
{
    (void) range; (void) data;
    if (bri_updating) return;
    if (bri_timeout) g_source_remove (bri_timeout);
    bri_timeout = g_timeout_add (120, apply_brightness, NULL);
}

static gboolean apply_volume (gpointer data)
{
    (void) data;
    vol_timeout = 0;
    gint vol = (gint) gtk_range_get_value (GTK_RANGE (vol_scale));
    gchar *cmd = g_strdup_printf ("pactl set-sink-volume @DEFAULT_SINK@ %d%%", vol);
    run_async (cmd);
    g_free (cmd);
    gchar *txt = g_strdup_printf ("%d%%", vol);
    gtk_label_set_text (GTK_LABEL (vol_label), txt);
    g_free (txt);
    return FALSE;
}

static void on_volume_changed (GtkRange *range, gpointer data)
{
    (void) range; (void) data;
    if (updating) return;
    if (vol_timeout) g_source_remove (vol_timeout);
    vol_timeout = g_timeout_add (120, apply_volume, NULL);
}

static void on_mute_clicked (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    run_async ("pactl set-sink-mute @DEFAULT_SINK@ toggle");
    g_timeout_add (80, update_volume_cb, NULL);
}

static void on_settings_clicked (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    run_async ("dapeos-settings");
    gtk_widget_hide (window);
}

static void on_close_clicked (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_widget_hide (window);
}

static gboolean on_key_press (GtkWidget *widget, GdkEventKey *event, gpointer data)
{
    (void) widget; (void) data;
    if (event->keyval == GDK_KEY_Escape) {
        gtk_widget_hide (window);
        return TRUE;
    }
    return FALSE;
}

static gboolean on_focus_out (GtkWidget *widget, GdkEventFocus *event, gpointer data)
{
    (void) widget; (void) event; (void) data;
    gtk_widget_hide (window);
    return FALSE;
}

static GtkWidget *
make_tile (const gchar *title, const gchar *sub, GtkWidget **sub_label,
           GtkWidget **status_label, GtkWidget **toggle_out, GtkWidget **open_out)
{
    GtkWidget *box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 1);

    GtkWidget *toggle = gtk_button_new ();
    gtk_style_context_add_class (gtk_widget_get_style_context (toggle), "tile-left");
    GtkWidget *content = gtk_box_new (GTK_ORIENTATION_VERTICAL, 2);
    GtkWidget *top = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *t = gtk_label_new (title);
    gtk_widget_set_halign (t, GTK_ALIGN_START);
    gtk_widget_set_hexpand (t, TRUE);
    GtkWidget *st = gtk_label_new ("Off");
    gtk_widget_set_halign (st, GTK_ALIGN_END);
    gtk_style_context_add_class (gtk_widget_get_style_context (st), "dim-label");
    gtk_box_pack_start (GTK_BOX (top), t, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (top), st, FALSE, FALSE, 0);
    GtkWidget *s = gtk_label_new (sub);
    gtk_label_set_xalign (GTK_LABEL (s), 0.0);
    gtk_label_set_justify (GTK_LABEL (s), GTK_JUSTIFY_LEFT);
    gtk_widget_set_halign (s, GTK_ALIGN_START);
    gtk_style_context_add_class (gtk_widget_get_style_context (s), "dim-label");
    gtk_box_pack_start (GTK_BOX (content), top, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (content), s, FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (toggle), content);

    GtkWidget *open = gtk_button_new_with_label ("›");
    gtk_style_context_add_class (gtk_widget_get_style_context (open), "tile-right");
    gtk_widget_set_size_request (open, 28, -1);

    gtk_box_pack_start (GTK_BOX (box), toggle, TRUE, TRUE, 0);
    gtk_box_pack_start (GTK_BOX (box), open, FALSE, FALSE, 0);
    if (sub_label) *sub_label = s;
    if (status_label) *status_label = st;
    if (toggle_out) *toggle_out = toggle;
    if (open_out) *open_out = open;
    return box;
}

typedef struct {
    gchar *ssid;
    gboolean secured;
    gboolean connected;
    gboolean known;
    gchar *connection;
    GtkWidget *status_label;
} WifiItem;

static void
wifi_item_free (gpointer data, GClosure *closure)
{
    (void) closure;
    WifiItem *item = data;
    g_free (item->ssid);
    g_free (item->connection);
    g_free (item);
}

static void
wifi_item_destroy (gpointer data)
{
    wifi_item_free (data, NULL);
}

static gboolean connect_wifi (const gchar *ssid, const gchar *password, gboolean was_known);

static void
password_visibility_toggled (GtkToggleButton *button, gpointer data)
{
    GtkWidget *entry = data;
    gtk_entry_set_visibility (GTK_ENTRY (entry), gtk_toggle_button_get_active (button));
}

static void
wifi_row_selected (GtkListBox *list, GtkListBoxRow *row, gpointer data)
{
    (void) list;
    GtkWidget *dialog = data;
    GtkWidget *action = g_object_get_data (G_OBJECT (dialog), "wifi-action");
    WifiItem *item = NULL;
    if (row) item = g_object_get_data (G_OBJECT (row), "wifi-item");
    g_object_set_data (G_OBJECT (dialog), "wifi-selected", item);
    GtkWidget *forget = g_object_get_data (G_OBJECT (dialog), "wifi-forget");
    if (item) {
        gtk_button_set_label (GTK_BUTTON (action), item->connected ? "Disconnect" : "Connect");
        gtk_widget_show (action);
        gtk_widget_set_sensitive (action, TRUE);
        gtk_widget_set_sensitive (forget, item->known || item->connected);
    } else {
        gtk_button_set_label (GTK_BUTTON (action), "Connect");
        gtk_widget_set_sensitive (action, FALSE);
        gtk_widget_set_sensitive (forget, FALSE);
    }
}

static void wifi_start_scan (GtkWidget *dialog);
static void show_wifi_password (const gchar *ssid, gboolean known);

static gboolean
rescan_cb (gpointer data)
{
    GtkWidget *dialog = data;
    wifi_start_scan (dialog);
    g_object_unref (dialog);
    return FALSE;
}

static void
rescan_later (GtkWidget *dialog)
{
    g_object_ref (dialog);
    g_timeout_add (1200, rescan_cb, dialog);
}

static gchar *
wifi_device (void)
{
    gchar *out = run_cmd ("nmcli -t -f DEVICE,TYPE device status 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    gchar *dev = NULL;
    for (guint i = 0; lines[i]; i++) {
        gchar **parts = g_strsplit (lines[i], ":", 2);
        if (parts[0] && parts[1] && g_strcmp0 (parts[1], "wifi") == 0) {
            dev = g_strdup (parts[0]);
            g_strfreev (parts);
            break;
        }
        g_strfreev (parts);
    }
    g_strfreev (lines);
    g_free (out);
    return dev;
}

static gboolean
wifi_is_fresh (const gchar *ssid)
{
    gchar *out = run_cmd ("dapeos-wifi-fresh 2>/dev/null");
    if (!out || !*out) { g_free (out); return TRUE; }
    gboolean found = FALSE;
    gchar **lines = g_strsplit (out, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        if (g_strcmp0 (lines[i], ssid) == 0) { found = TRUE; break; }
    }
    g_strfreev (lines);
    g_free (out);
    return found;
}

static gboolean hide_wifi_error (gpointer data);
static guint connect_anim_id = 0;
static GtkWidget *connect_label = NULL;
static gint connect_phase = 0;

static gboolean
connect_anim_cb (gpointer data)
{
    (void) data;
    if (!connect_label) return G_SOURCE_REMOVE;
    connect_phase = (connect_phase + 1) % 4;
    gchar *text = g_strdup_printf ("Connecting%.*s", connect_phase, "...");
    gtk_label_set_text (GTK_LABEL (connect_label), text);
    g_free (text);
    return G_SOURCE_CONTINUE;
}

static void
start_connect_anim (WifiItem *item)
{
    if (connect_anim_id) g_source_remove (connect_anim_id);
    connect_label = item ? item->status_label : NULL;
    connect_phase = 0;
    if (connect_label) {
        g_object_ref (connect_label);
        gtk_label_set_text (GTK_LABEL (connect_label), "Connecting...");
        connect_anim_id = g_timeout_add (350, connect_anim_cb, NULL);
    }
}

static void
stop_connect_anim (void)
{
    if (connect_anim_id) { g_source_remove (connect_anim_id); connect_anim_id = 0; }
    if (connect_label) { g_object_unref (connect_label); connect_label = NULL; }
}

static gboolean
wifi_gone_error (const gchar *out)
{
    return strstr (out, "not be found") || strstr (out, "No network with SSID") ||
           strstr (out, "not found");
}

typedef struct {
    GtkWidget *dialog;
    gchar *ssid;
} KnownConnect;

static void
known_connect_done (GObject *source, GAsyncResult *res, gpointer data)
{
    KnownConnect *ctx = data;
    GError *error = NULL;
    gchar *out = NULL;
    gchar *errout = NULL;
    g_subprocess_communicate_utf8_finish (G_SUBPROCESS (source), res, &out, &errout, &error);
    if (errout && *errout) {
        gchar *both = g_strconcat (out ? out : "", "\n", errout, NULL);
        g_free (out);
        out = both;
    }
    g_free (errout);
    stop_connect_anim ();
    if (out && wifi_gone_error (out)) {
        if (wifi_error_label) {
            gtk_label_set_text (GTK_LABEL (wifi_error_label), "This connection is no longer available");
            gtk_widget_show (wifi_error_label);
            if (wifi_error_timeout) g_source_remove (wifi_error_timeout);
            wifi_error_timeout = g_timeout_add (1500, hide_wifi_error, NULL);
        }
        rescan_later (ctx->dialog);
    } else if (out && (strstr (out, "Secrets") || strstr (out, "key-mgmt") ||
                       strstr (out, "password") || strstr (out, "Error"))) {
        show_wifi_password (ctx->ssid, TRUE);
    } else {
        g_timeout_add (1500, update_tiles_cb, NULL);
        rescan_later (ctx->dialog);
    }
    if (error) g_error_free (error);
    g_free (out);
    g_object_unref (ctx->dialog);
    g_free (ctx->ssid);
    g_free (ctx);
}

static void
wifi_action (GtkWidget *dialog)
{
    WifiItem *item = g_object_get_data (G_OBJECT (dialog), "wifi-selected");
    if (!item) return;
    if (!item->connected && !item->known && !wifi_is_fresh (item->ssid)) {
        if (wifi_error_label) {
            gtk_label_set_text (GTK_LABEL (wifi_error_label), "This connection is no longer available");
            gtk_widget_show (wifi_error_label);
            if (wifi_error_timeout) g_source_remove (wifi_error_timeout);
            wifi_error_timeout = g_timeout_add (1500, hide_wifi_error, NULL);
        }
        rescan_later (dialog);
        return;
    }
    if (item->connected) {
        gchar *dev = wifi_device ();
        gchar *cmd;
        if (dev)
            cmd = g_strdup_printf ("nmcli device disconnect %s 2>&1", g_shell_quote (dev));
        else
            cmd = g_strdup_printf ("nmcli connection down id %s 2>&1", g_shell_quote (item->ssid));
        run_async (cmd);
        g_free (cmd);
        g_free (dev);
        rescan_later (dialog);
        g_timeout_add (1200, update_tiles_cb, NULL);
        return;
    }
    if (item->known) {
        start_connect_anim (item);
        const gchar *argv[] = { "nmcli", "connection", "up", "id",
                                item->connection ? item->connection : item->ssid, NULL };
        GError *error = NULL;
        GSubprocess *proc = g_subprocess_newv (argv, G_SUBPROCESS_FLAGS_STDOUT_PIPE |
                                               G_SUBPROCESS_FLAGS_STDERR_PIPE, &error);
        if (proc) {
            KnownConnect *ctx = g_new0 (KnownConnect, 1);
            ctx->dialog = g_object_ref (dialog);
            ctx->ssid = g_strdup (item->ssid);
            g_subprocess_communicate_utf8_async (proc, NULL, NULL, known_connect_done, ctx);
            g_object_unref (proc);
        } else {
            stop_connect_anim ();
            if (error) g_error_free (error);
        }
        return;
    }
    if (!item->secured) {
        connect_wifi (item->ssid, NULL, FALSE);
        rescan_later (dialog);
        return;
    }

    show_wifi_password (item->ssid, FALSE);
}

static void
on_wifi_action (GtkButton *button, gpointer data)
{
    (void) button;
    wifi_action (data);
}

static void
on_wifi_forget (GtkButton *button, gpointer data)
{
    (void) button;
    GtkWidget *page = data;
    WifiItem *item = g_object_get_data (G_OBJECT (page), "wifi-selected");
    if (!item) return;
    g_free (wifi_confirm_ssid);
    wifi_confirm_ssid = g_strdup (item->connection ? item->connection : item->ssid);
    wifi_confirm_connected = item->connected;
    gtk_label_set_text (GTK_LABEL (wifi_confirm_label), item->ssid);
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi-confirm");
}

static void
on_wifi_advanced (GtkButton *button, gpointer data)
{
    (void) button;
    GtkWidget *dialog = data;
    (void) dialog;
    if (g_find_program_in_path ("nm-connection-editor"))
        run_async ("nm-connection-editor");
    else
        run_async ("xfce4-settings-manager");
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");
}

static void
on_wifi_refresh (GtkButton *button, gpointer data)
{
    (void) button;
    wifi_start_scan (GTK_WIDGET (data));
}

static gboolean
hide_wifi_error (gpointer data)
{
    (void) data;
    wifi_error_timeout = 0;
    if (wifi_error_label) gtk_widget_hide (wifi_error_label);
    return FALSE;
}

static const gchar *
wifi_error_text (const gchar *out)
{
    if (strstr (out, "Secrets were required") || strstr (out, "key-mgmt") ||
        strstr (out, "password") || strstr (out, "802-11-wireless-security"))
        return "Wrong password or connection failed.";
    if (strstr (out, "No network with SSID"))
        return "Network not found.";
    return "Could not connect to this Wi-Fi network.";
}

static gboolean
connect_wifi (const gchar *ssid, const gchar *password, gboolean was_known)
{
    gchar *qssid = g_shell_quote (ssid);
    gchar *cmd;
    if (password && *password)
        cmd = g_strdup_printf ("nmcli device wifi connect %s password %s 2>&1",
                               qssid, g_shell_quote (password));
    else
        cmd = g_strdup_printf ("nmcli device wifi connect %s 2>&1", qssid);
    gchar *out = run_cmd (cmd);
    gboolean ok = !(g_strrstr (out, "Error") || g_strrstr (out, "error"));

    if (!ok && !was_known) {
        gchar *del = g_strdup_printf ("nmcli connection delete id %s 2>/dev/null", qssid);
        run_async (del);
        g_free (del);
    }
    if (wifi_error_label) {
        if (!ok) {
            gtk_label_set_text (GTK_LABEL (wifi_error_label), wifi_error_text (out));
            gtk_widget_show (wifi_error_label);
            if (wifi_error_timeout) g_source_remove (wifi_error_timeout);
            wifi_error_timeout = g_timeout_add (4000, hide_wifi_error, NULL);
        } else {
            gtk_widget_hide (wifi_error_label);
        }
    }
    g_free (out);
    g_free (cmd);
    g_free (qssid);
    if (ok) {
        start_net_animation ();
        g_timeout_add (1500, update_tiles_cb, NULL);
    }
    return ok;
}

static void
wifi_scan_done (GObject *source, GAsyncResult *res, gpointer data)
{
    GtkWidget *dialog = data;
    GtkWidget *list = g_object_get_data (G_OBJECT (dialog), "wifi-list");
    if (!list || !GTK_IS_LIST_BOX (list)) {
        g_object_unref (dialog);
        return;
    }
    gchar *out = NULL;
    GError *error = NULL;
    GSubprocess *proc = G_SUBPROCESS (source);
    gboolean ok = g_subprocess_communicate_utf8_finish (proc, res, &out, NULL, &error);

    GList *children = gtk_container_get_children (GTK_CONTAINER (list));
    g_list_free_full (children, (GDestroyNotify) gtk_widget_destroy);

    if (!ok || out == NULL) {
        GtkWidget *label = gtk_label_new ("Could not read Wi-Fi networks");
        gtk_list_box_insert (GTK_LIST_BOX (list), label, -1);
        if (error) g_error_free (error);
        g_free (out);
        g_object_unref (dialog);
        return;
    }

    gchar *active = run_cmd ("nmcli -t -f ACTIVE,SSID device wifi list 2>/dev/null");
    GHashTable *active_set = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
    gchar **alines = g_strsplit (active, "\n", -1);
    for (guint i = 0; alines[i]; i++) {
        gchar **ap = g_strsplit (alines[i], ":", 2);
        if (ap[0] && g_strcmp0 (ap[0], "yes") == 0 && ap[1])
            g_hash_table_add (active_set, g_strdup (ap[1]));
        g_strfreev (ap);
    }
    g_strfreev (alines);
    g_free (active);

    if (g_hash_table_size (active_set) == 0) {
        gchar *connections = run_cmd ("nmcli -t -f NAME,TYPE connection show --active 2>/dev/null");
        gchar **clines = g_strsplit (connections, "\n", -1);
        for (guint i = 0; clines[i]; i++) {
            gchar **cp = g_strsplit (clines[i], ":", 2);
            if (cp[0] && cp[1] && strstr (cp[1], "wireless"))
                g_hash_table_add (active_set, g_strdup (cp[0]));
            g_strfreev (cp);
        }
        g_strfreev (clines);
        g_free (connections);
    }

    GHashTable *known_map = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, g_free);
    gchar *profiles = run_cmd ("nmcli -t -f NAME,TYPE connection show 2>/dev/null");
    gchar **plines = g_strsplit (profiles, "\n", -1);
    for (guint i = 0; plines[i]; i++) {
        gchar **pp = g_strsplit (plines[i], ":", 2);
        if (pp[0] && pp[1] && (strstr (pp[1], "wireless") || strstr (pp[1], "wifi"))) {
            gchar *q = g_shell_quote (pp[0]);
            gchar *cmd = g_strdup_printf ("nmcli -g 802-11-wireless.ssid connection show %s 2>/dev/null", q);
            gchar *ssid = run_cmd (cmd);
            g_free (cmd); g_free (q);
            if (ssid && *ssid)
                g_hash_table_insert (known_map, ssid, g_strdup (pp[0]));
            else
                g_free (ssid);
        }
        g_strfreev (pp);
    }
    g_strfreev (plines);
    g_free (profiles);

    GHashTable *fresh = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
    gchar *fresh_raw = run_cmd ("dapeos-wifi-fresh 2>/dev/null");
    gchar **flines = g_strsplit (fresh_raw, "\n", -1);
    for (guint fi = 0; flines[fi]; fi++)
        if (*flines[fi]) g_hash_table_add (fresh, g_strdup (flines[fi]));
    g_strfreev (flines);
    g_free (fresh_raw);

    GHashTable *seen = g_hash_table_new_full (g_str_hash, g_str_equal, g_free, NULL);
    gchar **lines = g_strsplit (out, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        gchar **parts = g_strsplit (lines[i], ":", 3);
        if (parts[0] && *parts[0] && parts[2] &&
            !g_hash_table_contains (seen, parts[0]) &&
            (g_hash_table_size (fresh) == 0 || g_hash_table_contains (fresh, parts[0]))) {
            g_hash_table_add (seen, g_strdup (parts[0]));
            gboolean secured = g_strcmp0 (parts[2], "--") != 0 && *parts[2] != 0;
            gboolean connected = g_hash_table_contains (active_set, parts[0]);
            WifiItem *item = g_new0 (WifiItem, 1);
            item->ssid = g_strdup (parts[0]);
            item->secured = secured;
            item->connected = connected;
            item->connection = g_strdup (g_hash_table_lookup (known_map, parts[0]));
            item->known = (item->connection != NULL);
            GtkWidget *row = gtk_list_box_row_new ();
            GtkWidget *hbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
            GtkWidget *name = gtk_label_new (parts[0]);
            gtk_widget_set_halign (name, GTK_ALIGN_START);
            gtk_widget_set_hexpand (name, TRUE);
            gtk_box_pack_start (GTK_BOX (hbox), name, TRUE, TRUE, 0);
            if (connected || item->known) {
                GtkWidget *state = gtk_label_new (connected ? "✓ Connected" : "Known connection");
                gtk_widget_set_halign (state, GTK_ALIGN_END);
                gtk_style_context_add_class (gtk_widget_get_style_context (state), "dim-label");
                gtk_box_pack_end (GTK_BOX (hbox), state, FALSE, FALSE, 0);
                item->status_label = state;
            }
            gtk_container_add (GTK_CONTAINER (row), hbox);
            g_object_set_data_full (G_OBJECT (row), "wifi-item", item, wifi_item_destroy);
            if (connected) {
                gtk_list_box_insert (GTK_LIST_BOX (list), row, 0);
            } else if (item->known) {
                gint pos = 0, idx = 0;
                GList *kids = gtk_container_get_children (GTK_CONTAINER (list));
                for (GList *k = kids; k; k = k->next, idx++) {
                    if (!GTK_IS_LIST_BOX_ROW (k->data)) continue;
                    WifiItem *ki = g_object_get_data (G_OBJECT (k->data), "wifi-item");
                    if (ki && (ki->connected || ki->known)) {
                        pos = idx + 1;
                        continue;
                    }
                    break;
                }
                g_list_free (kids);
                gtk_list_box_insert (GTK_LIST_BOX (list), row, pos);
            } else {
                gtk_list_box_insert (GTK_LIST_BOX (list), row, -1);
            }
        }
        g_strfreev (parts);
    }
    g_strfreev (lines);
    if (g_hash_table_size (seen) == 0) {
        GtkWidget *empty = gtk_label_new ("No Wi-Fi networks found");
        gtk_list_box_insert (GTK_LIST_BOX (list), empty, -1);
    }
    g_hash_table_destroy (seen);
    g_hash_table_destroy (fresh);
    g_hash_table_destroy (active_set);
    g_hash_table_destroy (known_map);
    g_free (out);
    gtk_widget_show_all (list);

    GList *rows = gtk_container_get_children (GTK_CONTAINER (list));
    for (GList *l = rows; l; l = l->next) {
        if (!GTK_IS_LIST_BOX_ROW (l->data)) continue;
        WifiItem *it = g_object_get_data (G_OBJECT (l->data), "wifi-item");
        if (it && it->connected) {
            GtkWidget *row = GTK_WIDGET (l->data);
            g_object_ref (row);
            gtk_container_remove (GTK_CONTAINER (list), row);
            gtk_list_box_insert (GTK_LIST_BOX (list), row, 0);
            g_object_unref (row);
            gtk_list_box_select_row (GTK_LIST_BOX (list), GTK_LIST_BOX_ROW (row));
            break;
        }
    }
    g_list_free (rows);
    g_object_unref (dialog);
    return;
}

static gboolean
wifi_radio_on (void)
{
    gchar *out = run_cmd ("nmcli -t -f WIFI radio 2>/dev/null");
    gboolean on = strstr (out, "enabled") != NULL;
    g_free (out);
    return on;
}

static void
connect_known_wifi (void)
{
    gchar *out = run_cmd ("nmcli -t -f NAME,TYPE connection show 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    gchar *name = NULL;
    for (guint i = 0; lines[i]; i++) {
        gchar **p = g_strsplit (lines[i], ":", 2);
        if (p[0] && p[1] && (strstr (p[1], "wireless") || strstr (p[1], "wifi"))) {
            name = g_strdup (p[0]);
            g_strfreev (p);
            break;
        }
        g_strfreev (p);
    }
    g_strfreev (lines);
    g_free (out);
    if (name) {
        gchar *cmd = g_strdup_printf ("nmcli connection up id %s 2>&1", g_shell_quote (name));
        run_async (cmd);
        g_free (cmd);
        g_free (name);
        g_timeout_add (1500, update_tiles_cb, NULL);
    } else {
        stop_net_animation ();
        gtk_label_set_text (GTK_LABEL (net_label), "No known Wi-Fi");
    }
}

static gboolean
connect_known_cb (gpointer data)
{
    (void) data;
    connect_known_wifi ();
    return FALSE;
}

static void
on_net_toggle (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    if (wifi_radio_on ()) {
        stop_net_animation ();
        run_async ("nmcli radio wifi off");
        gtk_label_set_text (GTK_LABEL (net_status_label), "Off");
        gtk_label_set_text (GTK_LABEL (net_label), "");
    } else {
        gtk_label_set_text (GTK_LABEL (net_status_label), "On");
        run_async ("nmcli radio wifi on");
        if (has_known_wifi ()) {
            start_net_animation ();
            g_timeout_add (1500, connect_known_cb, NULL);
        } else {
            stop_net_animation ();
            gtk_label_set_text (GTK_LABEL (net_label), "No known Wi-Fi");
        }
    }
    g_timeout_add (1000, update_tiles_cb, NULL);
}

static void
wifi_add_connected_stub (GtkWidget *list)
{
    gchar *active = run_cmd ("nmcli -t -f ACTIVE,SSID device wifi list 2>/dev/null");
    gchar **lines = g_strsplit (active, "\n", -1);
    gchar *ssid = NULL;
    for (guint i = 0; lines[i]; i++) {
        gchar **p = g_strsplit (lines[i], ":", 2);
        if (p[0] && g_strcmp0 (p[0], "yes") == 0 && p[1] && *p[1]) {
            ssid = g_strdup (p[1]);
            g_strfreev (p);
            break;
        }
        g_strfreev (p);
    }
    g_strfreev (lines);
    g_free (active);
    if (!ssid) return;

    WifiItem *item = g_new0 (WifiItem, 1);
    item->ssid = ssid;
    item->connected = TRUE;
    item->known = TRUE;
    item->secured = TRUE;

    GtkWidget *row = gtk_list_box_row_new ();
    GtkWidget *hbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *name = gtk_label_new (item->ssid);
    gtk_label_set_ellipsize (GTK_LABEL (name), PANGO_ELLIPSIZE_END);
    gtk_widget_set_halign (name, GTK_ALIGN_START);
    gtk_widget_set_hexpand (name, TRUE);
    gtk_box_pack_start (GTK_BOX (hbox), name, TRUE, TRUE, 0);
    GtkWidget *state = gtk_label_new ("✓ Connected");
    gtk_widget_set_halign (state, GTK_ALIGN_END);
    gtk_style_context_add_class (gtk_widget_get_style_context (state), "dim-label");
    gtk_box_pack_end (GTK_BOX (hbox), state, FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (row), hbox);
    g_object_set_data_full (G_OBJECT (row), "wifi-item", item, wifi_item_destroy);
    gtk_list_box_insert (GTK_LIST_BOX (list), row, 0);
}

static void
start_wifi_list (GtkWidget *dialog)
{
    GtkWidget *list = g_object_get_data (G_OBJECT (dialog), "wifi-list");
    if (!list) return;
    const gchar *argv[] = { "nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY",
                            "device", "wifi", "list", "--rescan", "yes", NULL };
    GError *error = NULL;
    GSubprocess *proc = g_subprocess_newv (argv, G_SUBPROCESS_FLAGS_STDOUT_PIPE, &error);
    if (proc) {
        g_object_ref (dialog);
        g_subprocess_communicate_utf8_async (proc, NULL, NULL, wifi_scan_done, dialog);
        g_object_unref (proc);
    } else {
        if (error) g_error_free (error);
        GtkWidget *label = gtk_label_new ("NetworkManager is not available");
        gtk_list_box_insert (GTK_LIST_BOX (list), label, -1);
    }
}

static gboolean
wifi_list_cb (gpointer data)
{
    GtkWidget *dialog = data;
    start_wifi_list (dialog);
    g_object_unref (dialog);
    return FALSE;
}

static void
wifi_start_scan (GtkWidget *dialog)
{
    GtkWidget *list = g_object_get_data (G_OBJECT (dialog), "wifi-list");
    if (!list) return;
    stop_connect_anim ();
    GList *children = gtk_container_get_children (GTK_CONTAINER (list));
    g_list_free_full (children, (GDestroyNotify) gtk_widget_destroy);
    wifi_add_connected_stub (list);
    GtkWidget *scanning = gtk_label_new ("Scanning for networks…");
    gtk_list_box_insert (GTK_LIST_BOX (list), scanning, -1);
    gtk_widget_show_all (list);

    gchar *dev = wifi_device ();
    gchar *cmd = dev
        ? g_strdup_printf ("nmcli device wifi rescan ifname %s 2>/dev/null", g_shell_quote (dev))
        : g_strdup ("nmcli device wifi rescan 2>/dev/null");
    run_async (cmd);
    g_free (cmd);
    g_free (dev);

    g_object_ref (dialog);
    g_timeout_add (3000, wifi_list_cb, dialog);
}

static void
on_net_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi");
    wifi_start_scan (wifi_page);
}

static void
log_geometry (const gchar *tag)
{
    gint w = 0, h = 0, x = 0, y = 0;
    gtk_window_get_size (GTK_WINDOW (window), &w, &h);
    gtk_window_get_position (GTK_WINDOW (window), &x, &y);
    FILE *f = fopen ("/tmp/dapeos-qs-geometry.log", "a");
    if (f) {
        fprintf (f, "%s: %dx%d at %d,%d\n", tag, w, h, x, y);
        fclose (f);
    }
}

static gboolean
toggle_wifi_signal (gpointer data)
{
    (void) data;
    {
        FILE *f = fopen ("/tmp/dapeos-qs-signal.log", "a");
        if (f) { fprintf (f, "handler pid=%d\n", (int) getpid ()); fclose (f); }
    }
    gtk_widget_show_all (window);
    gtk_window_present (GTK_WINDOW (window));
    log_geometry ("before toggle");
    on_net_open (NULL, NULL);
    log_geometry ("after toggle");
    return G_SOURCE_CONTINUE;
}

static gboolean
show_bt_signal (gpointer data)
{
    (void) data;
    gtk_widget_show_all (window);
    gtk_window_present (GTK_WINDOW (window));
    on_bt_open (NULL, NULL);
    return G_SOURCE_CONTINUE;
}

static gboolean
show_night_signal (gpointer data)
{
    (void) data;
    gtk_widget_show_all (window);
    gtk_window_present (GTK_WINDOW (window));
    on_night_open (NULL, NULL);
    return G_SOURCE_CONTINUE;
}

static void
on_bt_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "bluetooth");
    bt_refresh (bt_page);
}

static void
night_scale_changed (GtkRange *range, gpointer data)
{
    (void) data;
    gint temp = (gint) gtk_range_get_value (range);
    gchar *dir = g_build_filename (g_get_user_cache_dir (), "dapeos", NULL);
    gchar *state = night_state_path ("nightlight");
    gchar *onfile = night_state_path ("nightlight_on");
    g_mkdir_with_parents (dir, 0700);
    gchar *val = g_strdup_printf ("%d", temp);
    g_file_set_contents (state, val, -1, NULL);
    g_file_set_contents (onfile, "", 0, NULL);
    g_free (val); g_free (state); g_free (onfile); g_free (dir);
    apply_gamma (temp);
    night_on = TRUE;
    if (night_status_label) gtk_label_set_text (GTK_LABEL (night_status_label), "On");
    if (night_label) {
        gchar *t = g_strdup_printf ("%d K", temp);
        gtk_label_set_text (GTK_LABEL (night_label), t);
        g_free (t);
    }
}

static void
on_night_page_toggle (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    on_night_clicked (NULL, NULL);
    gtk_button_set_label (GTK_BUTTON (night_page_toggle), night_on ? "On" : "Off");
}

static void
night_schedule_save (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    const gchar *from = gtk_entry_get_text (GTK_ENTRY (night_from_entry));
    const gchar *to = gtk_entry_get_text (GTK_ENTRY (night_to_entry));
    gchar *fp = night_state_path ("nightlight_from");
    gchar *tp = night_state_path ("nightlight_to");
    g_file_set_contents (fp, from, -1, NULL);
    g_file_set_contents (tp, to, -1, NULL);
    g_free (fp); g_free (tp);
}

static gboolean
night_schedule_tick (gpointer data)
{
    (void) data;
    gchar *fp = night_state_path ("nightlight_from");
    gchar *tp = night_state_path ("nightlight_to");
    gchar *from = NULL, *to = NULL;
    g_file_get_contents (fp, &from, NULL, NULL);
    g_file_get_contents (tp, &to, NULL, NULL);
    g_free (fp); g_free (tp);
    if (!from || !to || !*from || !*to) { g_free (from); g_free (to); return G_SOURCE_CONTINUE; }
    gint fh = 0, fm = 0, th = 0, tm = 0;
    if (sscanf (from, "%d:%d", &fh, &fm) != 2 || sscanf (to, "%d:%d", &th, &tm) != 2) {
        g_free (from); g_free (to); return G_SOURCE_CONTINUE;
    }
    g_free (from); g_free (to);
    time_t now = time (NULL);
    struct tm *lt = localtime (&now);
    gint cur = lt->tm_hour * 60 + lt->tm_min;
    gint start = fh * 60 + fm;
    gint end = th * 60 + tm;
    gboolean should = (start <= end) ? (cur >= start && cur < end)
                                     : (cur >= start || cur < end);
    if (should != night_on) {
        on_night_clicked (NULL, NULL);
        if (night_page_toggle) gtk_button_set_label (GTK_BUTTON (night_page_toggle), night_on ? "On" : "Off");
    }
    return G_SOURCE_CONTINUE;
}

static GtkWidget *
build_night_page (void)
{
    GtkWidget *page = gtk_box_new (GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width (GTK_CONTAINER (page), 16);
    GtkWidget *header = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *back = gtk_button_new_with_label ("‹ Back");
    gtk_style_context_add_class (gtk_widget_get_style_context (back), "flat");
    GtkWidget *title = gtk_label_new ("Night light");
    gtk_widget_set_hexpand (title, TRUE);
    gtk_widget_set_halign (title, GTK_ALIGN_START);
    night_page_toggle = gtk_button_new_with_label (night_on ? "On" : "Off");
    g_signal_connect (back, "clicked", G_CALLBACK (show_main_page), NULL);
    g_signal_connect (night_page_toggle, "clicked", G_CALLBACK (on_night_page_toggle), NULL);
    gtk_box_pack_start (GTK_BOX (header), back, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (header), title, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (header), night_page_toggle, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), header, FALSE, FALSE, 0);

    GtkWidget *label = gtk_label_new ("Color temperature");
    gtk_widget_set_halign (label, GTK_ALIGN_START);
    night_page_scale = gtk_scale_new_with_range (GTK_ORIENTATION_HORIZONTAL, 1000, 6500, 100);
    gtk_range_set_value (GTK_RANGE (night_page_scale), 4000);
    g_signal_connect (night_page_scale, "value-changed", G_CALLBACK (night_scale_changed), NULL);
    gtk_box_pack_start (GTK_BOX (page), label, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), night_page_scale, FALSE, FALSE, 0);

    GtkWidget *sched = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *fl = gtk_label_new ("From");
    GtkWidget *tl = gtk_label_new ("To");
    night_from_entry = gtk_entry_new ();
    night_to_entry = gtk_entry_new ();
    gtk_entry_set_width_chars (GTK_ENTRY (night_from_entry), 6);
    gtk_entry_set_width_chars (GTK_ENTRY (night_to_entry), 6);
    gtk_entry_set_placeholder_text (GTK_ENTRY (night_from_entry), "22:00");
    gtk_entry_set_placeholder_text (GTK_ENTRY (night_to_entry), "07:00");
    gtk_box_pack_start (GTK_BOX (sched), fl, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (sched), night_from_entry, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (sched), tl, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (sched), night_to_entry, FALSE, FALSE, 0);
    GtkWidget *save = gtk_button_new_with_label ("Save schedule");
    g_signal_connect (save, "clicked", G_CALLBACK (night_schedule_save), NULL);
    gtk_box_pack_start (GTK_BOX (sched), save, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), sched, FALSE, FALSE, 0);
    gtk_widget_show_all (page);
    return page;
}

static void
on_night_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "night");
    gchar *path = night_state_path ("nightlight");
    gchar *text = NULL;
    if (g_file_get_contents (path, &text, NULL, NULL)) {
        gtk_range_set_value (GTK_RANGE (night_page_scale), atoi (text));
        g_free (text);
    }
    g_free (path);
    gtk_button_set_label (GTK_BUTTON (night_page_toggle), night_on ? "On" : "Off");
}

static void
on_sound_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    if (g_find_program_in_path ("pavucontrol"))
        run_async ("pavucontrol");
    else
        run_async ("xfce4-settings-manager");
    gtk_widget_hide (window);
}

static gboolean
on_window_draw (GtkWidget *widget, cairo_t *cr, gpointer data)
{
    (void) data;
    gint w = gtk_widget_get_allocated_width (widget);
    gint h = gtk_widget_get_allocated_height (widget);
    double r = 14.0;

    cairo_set_operator (cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_source_rgba (cr, 0, 0, 0, 0);
    cairo_paint (cr);

    cairo_set_operator (cr, CAIRO_OPERATOR_OVER);
    if (window_dark)
        cairo_set_source_rgb (cr, 47.0 / 255.0, 47.0 / 255.0, 47.0 / 255.0);
    else
        cairo_set_source_rgb (cr, 245.0 / 255.0, 245.0 / 255.0, 245.0 / 255.0);
    cairo_new_sub_path (cr);
    cairo_arc (cr, w - r, r, r, -G_PI / 2, 0);
    cairo_arc (cr, w - r, h - r, r, 0, G_PI / 2);
    cairo_arc (cr, r, h - r, r, G_PI / 2, G_PI);
    cairo_arc (cr, r, r, r, G_PI, 3 * G_PI / 2);
    cairo_close_path (cr);
    cairo_fill (cr);
    return FALSE;
}

static void
wifi_row_activated (GtkListBox *list, GtkListBoxRow *row, gpointer data)
{
    (void) list;
    if (!row) return;
    gtk_list_box_select_row (GTK_LIST_BOX (list), row);
    wifi_action (data);
}

static void
show_main_page (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");
}

static void
wifi_password_cancel (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi");
}

static void
wifi_password_connect (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    const gchar *pw = gtk_entry_get_text (GTK_ENTRY (wifi_password_entry));
    if (connect_wifi (wifi_password_ssid, pw, wifi_password_known)) {
        gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi");
        rescan_later (wifi_page);
    }
}

static void
wifi_password_entry_activate (GtkEntry *entry, gpointer data)
{
    (void) entry;
    wifi_password_connect (NULL, data);
}

static void
wifi_confirm_cancel (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi");
}

static void
wifi_confirm_do (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    if (!wifi_confirm_ssid) return;
    gchar *cmd;
    if (wifi_confirm_connected) {
        gchar *dev = wifi_device ();
        if (dev)
            cmd = g_strdup_printf ("nmcli device disconnect %s 2>/dev/null; nmcli connection delete id %s 2>&1",
                                   g_shell_quote (dev), g_shell_quote (wifi_confirm_ssid));
        else
            cmd = g_strdup_printf ("nmcli connection delete id %s 2>&1", g_shell_quote (wifi_confirm_ssid));
        g_free (dev);
    } else {
        cmd = g_strdup_printf ("nmcli connection delete id %s 2>&1", g_shell_quote (wifi_confirm_ssid));
    }
    run_cmd (cmd);
    g_free (cmd);
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi");
    update_tiles_cb (NULL);
    rescan_later (wifi_page);
}

static GtkWidget *
build_wifi_confirm_page (void)
{
    GtkWidget *page = gtk_box_new (GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width (GTK_CONTAINER (page), 16);
    GtkWidget *title = gtk_label_new ("Forget Wi-Fi network?");
    PangoAttrList *attrs = pango_attr_list_new ();
    pango_attr_list_insert (attrs, pango_attr_weight_new (PANGO_WEIGHT_BOLD));
    gtk_label_set_attributes (GTK_LABEL (title), attrs);
    pango_attr_list_unref (attrs);
    gtk_widget_set_halign (title, GTK_ALIGN_START);
    wifi_confirm_label = gtk_label_new ("");
    gtk_widget_set_halign (wifi_confirm_label, GTK_ALIGN_START);
    gtk_box_pack_start (GTK_BOX (page), title, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), wifi_confirm_label, FALSE, FALSE, 0);

    GtkWidget *actions = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *forget = gtk_button_new_with_label ("Forget");
    GtkWidget *cancel = gtk_button_new_with_label ("Cancel");
    g_signal_connect (forget, "clicked", G_CALLBACK (wifi_confirm_do), NULL);
    g_signal_connect (cancel, "clicked", G_CALLBACK (wifi_confirm_cancel), NULL);
    gtk_box_pack_start (GTK_BOX (actions), forget, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), cancel, FALSE, FALSE, 0);
    gtk_box_pack_end (GTK_BOX (page), actions, FALSE, FALSE, 0);
    gtk_widget_show_all (page);
    return page;
}

static GtkWidget *
build_wifi_password_page (void)
{
    GtkWidget *page = gtk_box_new (GTK_ORIENTATION_VERTICAL, 10);
    gtk_container_set_border_width (GTK_CONTAINER (page), 16);

    GtkWidget *title = gtk_label_new ("Wi-Fi password");
    PangoAttrList *attrs = pango_attr_list_new ();
    pango_attr_list_insert (attrs, pango_attr_weight_new (PANGO_WEIGHT_BOLD));
    gtk_label_set_attributes (GTK_LABEL (title), attrs);
    pango_attr_list_unref (attrs);
    gtk_widget_set_halign (title, GTK_ALIGN_START);
    gtk_box_pack_start (GTK_BOX (page), title, FALSE, FALSE, 0);

    wifi_password_label = gtk_label_new ("");
    gtk_widget_set_halign (wifi_password_label, GTK_ALIGN_START);
    gtk_box_pack_start (GTK_BOX (page), wifi_password_label, FALSE, FALSE, 0);

    wifi_password_entry = gtk_entry_new ();
    gtk_entry_set_visibility (GTK_ENTRY (wifi_password_entry), FALSE);
    gtk_entry_set_input_purpose (GTK_ENTRY (wifi_password_entry), GTK_INPUT_PURPOSE_PASSWORD);
    gtk_entry_set_placeholder_text (GTK_ENTRY (wifi_password_entry), "Password");
    gtk_box_pack_start (GTK_BOX (page), wifi_password_entry, FALSE, FALSE, 0);

    GtkWidget *show = gtk_check_button_new_with_label ("Show password");
    g_signal_connect (show, "toggled", G_CALLBACK (password_visibility_toggled), wifi_password_entry);
    gtk_box_pack_start (GTK_BOX (page), show, FALSE, FALSE, 0);
    wifi_error_label = gtk_label_new ("");
    gtk_widget_set_name (wifi_error_label, "wifi-error");
    gtk_label_set_ellipsize (GTK_LABEL (wifi_error_label), PANGO_ELLIPSIZE_END);
    gtk_label_set_lines (GTK_LABEL (wifi_error_label), 1);
    gtk_label_set_max_width_chars (GTK_LABEL (wifi_error_label), 42);
    gtk_widget_set_hexpand (wifi_error_label, FALSE);
    gtk_widget_set_halign (wifi_error_label, GTK_ALIGN_START);
    gtk_box_pack_start (GTK_BOX (page), wifi_error_label, FALSE, FALSE, 0);
    gtk_widget_hide (wifi_error_label);
    g_signal_connect (wifi_password_entry, "activate", G_CALLBACK (wifi_password_entry_activate), NULL);

    GtkWidget *actions = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *connect = gtk_button_new_with_label ("Connect");
    GtkWidget *cancel = gtk_button_new_with_label ("Cancel");
    g_signal_connect (connect, "clicked", G_CALLBACK (wifi_password_connect), NULL);
    g_signal_connect (cancel, "clicked", G_CALLBACK (wifi_password_cancel), NULL);
    gtk_box_pack_start (GTK_BOX (actions), connect, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), cancel, FALSE, FALSE, 0);
    gtk_box_pack_end (GTK_BOX (page), actions, FALSE, FALSE, 0);
    gtk_widget_show_all (page);
    return page;
}

static void
show_wifi_password (const gchar *ssid, gboolean known)
{
    g_free (wifi_password_ssid);
    wifi_password_ssid = g_strdup (ssid);
    wifi_password_known = known;
    if (wifi_error_label) { gtk_label_set_text (GTK_LABEL (wifi_error_label), ""); gtk_widget_hide (wifi_error_label); }
    gtk_label_set_text (GTK_LABEL (wifi_password_label), ssid);
    gtk_entry_set_text (GTK_ENTRY (wifi_password_entry), "");
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "wifi-password");
    gtk_widget_grab_focus (wifi_password_entry);
}

typedef struct {
    gchar *mac;
    gchar *name;
    gboolean connected;
    gboolean paired;
} BtItem;

static void
bt_item_free (gpointer data)
{
    BtItem *it = data;
    g_free (it->mac);
    g_free (it->name);
    g_free (it);
}

static void
bt_row_selected (GtkListBox *list, GtkListBoxRow *row, gpointer data)
{
    (void) list; (void) data;
    GtkWidget *action = g_object_get_data (G_OBJECT (gtk_widget_get_parent (GTK_WIDGET (list))), "noop");
    (void) action;
    BtItem *it = row ? g_object_get_data (G_OBJECT (row), "bt-item") : NULL;
    g_object_set_data (G_OBJECT (bt_page), "bt-selected", it);
    GtkWidget *act = g_object_get_data (G_OBJECT (bt_page), "bt-action");
    GtkWidget *forget = g_object_get_data (G_OBJECT (bt_page), "bt-forget");
    if (it) {
        gtk_button_set_label (GTK_BUTTON (act), it->connected ? "Disconnect" : "Connect");
        gtk_widget_set_sensitive (act, TRUE);
        gtk_widget_set_sensitive (forget, it->paired);
    } else {
        gtk_widget_set_sensitive (act, FALSE);
        gtk_widget_set_sensitive (forget, FALSE);
    }
}

static void bt_refresh (GtkWidget *page);

static gboolean
bt_valid_name (const gchar *name)
{
    if (!name || !*name) return FALSE;
    if (g_str_has_prefix (name, "Device ")) return FALSE;
    gint colons = 0, dashes = 0;
    for (const gchar *p = name; *p; p++) {
        if (*p == ':') colons++;
        else if (*p == '-') dashes++;
    }
    if (colons >= 5 || dashes >= 5) return FALSE;
    return TRUE;
}

static gboolean
bt_list_cb (gpointer data)
{
    GtkWidget *page = data;
    gchar *out = run_cmd ("bluetoothctl devices 2>/dev/null");
    if (!bt_list) { g_free (out); g_object_unref (page); return FALSE; }
    GList *children = gtk_container_get_children (GTK_CONTAINER (bt_list));
    g_list_free_full (children, (GDestroyNotify) gtk_widget_destroy);

    gchar *connected = run_cmd ("bluetoothctl devices Connected 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    gint known_pos = 0;
    for (guint i = 0; lines[i]; i++) {
        gchar mac[64] = "", name[256] = "";
        if (sscanf (lines[i], "Device %63s %255[^\n]", mac, name) != 2) continue;
        if (!bt_valid_name (name)) continue;
        gchar *info = run_cmd (g_strdup_printf ("bluetoothctl info %s 2>/dev/null", mac));
        gboolean paired = strstr (info, "Paired: yes") != NULL;
        gboolean conn = strstr (connected, mac) != NULL;
        g_free (info);

        BtItem *it = g_new0 (BtItem, 1);
        it->mac = g_strdup (mac);
        it->name = g_strdup (name);
        it->connected = conn;
        it->paired = paired;

        GtkWidget *row = gtk_list_box_row_new ();
        GtkWidget *hbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
        GtkWidget *label = gtk_label_new (name);
        gtk_label_set_ellipsize (GTK_LABEL (label), PANGO_ELLIPSIZE_END);
        gtk_widget_set_hexpand (label, TRUE);
        gtk_widget_set_halign (label, GTK_ALIGN_START);
        GtkWidget *state = gtk_label_new (conn ? "✓ Connected" : (paired ? "Paired" : ""));
        gtk_widget_set_halign (state, GTK_ALIGN_END);
        gtk_style_context_add_class (gtk_widget_get_style_context (state), "dim-label");
        gtk_box_pack_start (GTK_BOX (hbox), label, TRUE, TRUE, 0);
        gtk_box_pack_end (GTK_BOX (hbox), state, FALSE, FALSE, 0);
        gtk_container_add (GTK_CONTAINER (row), hbox);
        g_object_set_data_full (G_OBJECT (row), "bt-item", it, bt_item_free);
        if (conn) {
            gtk_list_box_insert (GTK_LIST_BOX (bt_list), row, 0);
        } else if (paired) {
            gtk_list_box_insert (GTK_LIST_BOX (bt_list), row, known_pos + 1);
            known_pos++;
        } else {
            gtk_list_box_insert (GTK_LIST_BOX (bt_list), row, -1);
        }
    }
    g_strfreev (lines);
    g_free (connected);
    g_free (out);
    if (gtk_list_box_get_row_at_index (GTK_LIST_BOX (bt_list), 0) == NULL) {
        GtkWidget *empty = gtk_label_new ("No Bluetooth devices found");
        gtk_list_box_insert (GTK_LIST_BOX (bt_list), empty, -1);
    }
    gtk_widget_show_all (bt_list);
    g_object_unref (page);
    return FALSE;
}

static gboolean
bt_scan_cb (gpointer data)
{
    GtkWidget *page = data;
    bt_list_cb (page);
    return FALSE;
}

static void
bt_add_known_stub (GtkWidget *list)
{
    gchar *out = run_cmd ("bluetoothctl devices 2>/dev/null");
    gchar **lines = g_strsplit (out, "\n", -1);
    for (guint i = 0; lines[i]; i++) {
        gchar mac[64] = "", name[256] = "";
        if (sscanf (lines[i], "Device %63s %255[^\n]", mac, name) != 2) continue;
        if (!bt_valid_name (name)) continue;
        gchar *info = run_cmd (g_strdup_printf ("bluetoothctl info %s 2>/dev/null", mac));
        gboolean paired = strstr (info, "Paired: yes") != NULL;
        gboolean conn = strstr (info, "Connected: yes") != NULL;
        g_free (info);
        if (!paired) continue;

        BtItem *it = g_new0 (BtItem, 1);
        it->mac = g_strdup (mac);
        it->name = g_strdup (name);
        it->paired = TRUE;
        it->connected = conn;

        GtkWidget *row = gtk_list_box_row_new ();
        GtkWidget *hbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
        GtkWidget *label = gtk_label_new (name);
        gtk_label_set_ellipsize (GTK_LABEL (label), PANGO_ELLIPSIZE_END);
        gtk_widget_set_hexpand (label, TRUE);
        gtk_widget_set_halign (label, GTK_ALIGN_START);
        GtkWidget *state = gtk_label_new (conn ? "✓ Connected" : "Paired");
        gtk_widget_set_halign (state, GTK_ALIGN_END);
        gtk_style_context_add_class (gtk_widget_get_style_context (state), "dim-label");
        gtk_box_pack_start (GTK_BOX (hbox), label, TRUE, TRUE, 0);
        gtk_box_pack_end (GTK_BOX (hbox), state, FALSE, FALSE, 0);
        gtk_container_add (GTK_CONTAINER (row), hbox);
        g_object_set_data_full (G_OBJECT (row), "bt-item", it, bt_item_free);
        gtk_list_box_insert (GTK_LIST_BOX (list), row, -1);
    }
    g_strfreev (lines);
    g_free (out);
}

static void
bt_refresh (GtkWidget *page)
{
    if (!bt_list) return;
    GList *children = gtk_container_get_children (GTK_CONTAINER (bt_list));
    g_list_free_full (children, (GDestroyNotify) gtk_widget_destroy);
    bt_add_known_stub (bt_list);
    if (!bt_is_on ()) {
        GtkWidget *off = gtk_label_new ("Bluetooth is off");
        gtk_list_box_insert (GTK_LIST_BOX (bt_list), off, -1);
        gtk_widget_show_all (bt_list);
        return;
    }
    GtkWidget *scanning = gtk_label_new ("Scanning for Bluetooth devices…");
    gtk_list_box_insert (GTK_LIST_BOX (bt_list), scanning, -1);
    gtk_widget_show_all (bt_list);
    run_async ("bluetoothctl --timeout 5 scan on >/dev/null 2>&1");
    g_object_ref (page);
    g_timeout_add (5500, bt_scan_cb, page);
}

static gboolean
bt_refresh_cb (gpointer data)
{
    bt_refresh (GTK_WIDGET (data));
    g_object_unref (data);
    return FALSE;
}

static void
on_bt_refresh (GtkButton *button, gpointer data)
{
    (void) button;
    bt_refresh (GTK_WIDGET (data));
}

static void
on_bt_action (GtkButton *button, gpointer data)
{
    (void) button;
    BtItem *it = g_object_get_data (G_OBJECT (data), "bt-selected");
    if (!it) return;
    gchar *cmd = it->connected
        ? g_strdup_printf ("bluetoothctl disconnect %s 2>/dev/null", it->mac)
        : g_strdup_printf ("bluetoothctl pair %s 2>/dev/null; bluetoothctl trust %s 2>/dev/null; bluetoothctl connect %s 2>/dev/null",
                           it->mac, it->mac, it->mac);
    run_async (cmd);
    g_free (cmd);
    g_object_ref (GTK_WIDGET (data));
    g_timeout_add (3000, bt_scan_cb, data);
}

static void
on_bt_forget (GtkButton *button, gpointer data)
{
    (void) button;
    BtItem *it = g_object_get_data (G_OBJECT (data), "bt-selected");
    if (!it) return;
    gchar *cmd = g_strdup_printf ("bluetoothctl remove %s 2>/dev/null", it->mac);
    run_async (cmd);
    g_free (cmd);
    g_object_ref (GTK_WIDGET (data));
    g_timeout_add (1000, bt_scan_cb, data);
}

static void
on_bt_power (GtkButton *button, gpointer data)
{
    (void) button;
    gboolean on = bt_is_on ();
    if (on)
        run_async ("bluetoothctl power off");
    else
        run_async ("rfkill unblock bluetooth; bluetoothctl power on");
    gtk_button_set_label (GTK_BUTTON (data), on ? "Off" : "On");
    if (bt_page) {
        g_object_ref (bt_page);
        g_timeout_add (800, bt_refresh_cb, bt_page);
    }
}

static GtkWidget *
build_bt_page (void)
{
    GtkWidget *page = gtk_box_new (GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width (GTK_CONTAINER (page), 16);
    GtkWidget *header = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *back = gtk_button_new_with_label ("‹ Back");
    gtk_style_context_add_class (gtk_widget_get_style_context (back), "flat");
    GtkWidget *title = gtk_label_new ("Bluetooth devices");
    gtk_widget_set_hexpand (title, TRUE);
    gtk_widget_set_halign (title, GTK_ALIGN_START);
    GtkWidget *power = gtk_button_new_with_label ("On");
    g_signal_connect (back, "clicked", G_CALLBACK (show_main_page), NULL);
    g_signal_connect (power, "clicked", G_CALLBACK (on_bt_power), power);
    gtk_box_pack_start (GTK_BOX (header), back, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (header), title, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (header), power, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), header, FALSE, FALSE, 0);

    GtkWidget *scroll = gtk_scrolled_window_new (NULL, NULL);
    gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (scroll),
                                    GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_widget_set_vexpand (scroll, TRUE);
    bt_list = gtk_list_box_new ();
    gtk_list_box_set_selection_mode (GTK_LIST_BOX (bt_list), GTK_SELECTION_SINGLE);
    gtk_container_add (GTK_CONTAINER (scroll), bt_list);
    gtk_box_pack_start (GTK_BOX (page), scroll, TRUE, TRUE, 0);

    GtkWidget *actions = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *action = gtk_button_new_with_label ("Connect");
    GtkWidget *forget = gtk_button_new_with_label ("Forget");
    GtkWidget *refresh = gtk_button_new_with_label ("Refresh");
    g_signal_connect (action, "clicked", G_CALLBACK (on_bt_action), page);
    g_signal_connect (forget, "clicked", G_CALLBACK (on_bt_forget), page);
    g_signal_connect (refresh, "clicked", G_CALLBACK (on_bt_refresh), page);
    gtk_box_pack_start (GTK_BOX (actions), action, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), forget, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), refresh, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), actions, FALSE, FALSE, 0);
    g_object_set_data (G_OBJECT (page), "bt-action", action);
    g_object_set_data (G_OBJECT (page), "bt-forget", forget);
    g_signal_connect (bt_list, "row-selected", G_CALLBACK (bt_row_selected), page);
    gtk_widget_set_sensitive (action, FALSE);
    gtk_widget_set_sensitive (forget, FALSE);
    gtk_widget_show_all (page);
    return page;
}

static GtkWidget *
build_wifi_page (void)
{
    GtkWidget *page = gtk_box_new (GTK_ORIENTATION_VERTICAL, 8);
    gtk_container_set_border_width (GTK_CONTAINER (page), 16);

    GtkWidget *header = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *back = gtk_button_new_with_label ("‹ Back");
    gtk_style_context_add_class (gtk_widget_get_style_context (back), "flat");
    GtkWidget *title = gtk_label_new ("Wi-Fi networks");
    PangoAttrList *attrs = pango_attr_list_new ();
    pango_attr_list_insert (attrs, pango_attr_weight_new (PANGO_WEIGHT_BOLD));
    gtk_label_set_attributes (GTK_LABEL (title), attrs);
    pango_attr_list_unref (attrs);
    gtk_widget_set_hexpand (title, TRUE);
    gtk_widget_set_halign (title, GTK_ALIGN_START);
    g_signal_connect (back, "clicked", G_CALLBACK (show_main_page), NULL);
    wifi_page_toggle = gtk_button_new_with_label (wifi_radio_on () ? "On" : "Off");
    g_signal_connect (wifi_page_toggle, "clicked", G_CALLBACK (on_net_toggle), NULL);
    gtk_box_pack_start (GTK_BOX (header), back, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (header), title, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (header), wifi_page_toggle, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), header, FALSE, FALSE, 0);

    GtkWidget *scroll = gtk_scrolled_window_new (NULL, NULL);
    gtk_scrolled_window_set_policy (GTK_SCROLLED_WINDOW (scroll),
                                    GTK_POLICY_NEVER, GTK_POLICY_AUTOMATIC);
    gtk_scrolled_window_set_propagate_natural_width (GTK_SCROLLED_WINDOW (scroll), FALSE);
    gtk_scrolled_window_set_propagate_natural_height (GTK_SCROLLED_WINDOW (scroll), FALSE);
    gtk_widget_set_size_request (scroll, 400, 170);
    gtk_widget_set_vexpand (scroll, TRUE);
    GtkWidget *list = gtk_list_box_new ();
    gtk_list_box_set_selection_mode (GTK_LIST_BOX (list), GTK_SELECTION_SINGLE);
    gtk_list_box_set_activate_on_single_click (GTK_LIST_BOX (list), FALSE);
    gtk_container_add (GTK_CONTAINER (scroll), list);
    gtk_box_pack_start (GTK_BOX (page), scroll, TRUE, TRUE, 0);

    GtkWidget *actions = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget *action = gtk_button_new_with_label ("Connect");
    GtkWidget *forget = gtk_button_new_with_label ("Forget");
    GtkWidget *advanced = gtk_button_new_with_label ("Advanced…");
    GtkWidget *refresh = gtk_button_new_with_label ("Refresh");
    gtk_widget_set_tooltip_text (refresh, "Scan Wi-Fi networks again");
    g_signal_connect (action, "clicked", G_CALLBACK (on_wifi_action), page);
    g_signal_connect (forget, "clicked", G_CALLBACK (on_wifi_forget), page);
    g_signal_connect (advanced, "clicked", G_CALLBACK (on_wifi_advanced), page);
    g_signal_connect (refresh, "clicked", G_CALLBACK (on_wifi_refresh), page);
    gtk_box_pack_start (GTK_BOX (actions), action, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), forget, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), advanced, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (actions), refresh, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (page), actions, FALSE, FALSE, 0);

    g_object_set_data (G_OBJECT (page), "wifi-list", list);
    g_object_set_data (G_OBJECT (page), "wifi-action", action);
    g_object_set_data (G_OBJECT (page), "wifi-forget", forget);
    gtk_widget_set_no_show_all (action, TRUE);
    gtk_widget_set_sensitive (action, FALSE);
    gtk_widget_set_sensitive (forget, FALSE);
    g_signal_connect (list, "row-selected", G_CALLBACK (wifi_row_selected), page);
    g_signal_connect (list, "row-activated", G_CALLBACK (wifi_row_activated), page);
    gtk_widget_show_all (page);
    gtk_widget_hide (action);
    return page;
}

static void
on_window_realize (GtkWidget *widget, gpointer data)
{
    (void) data;
    GdkWindow *gw = gtk_widget_get_window (widget);
    if (gw) {
        gdk_window_set_skip_taskbar_hint (gw, TRUE);
        gdk_window_set_skip_pager_hint (gw, TRUE);
    }
}

static gboolean
on_window_map (GtkWidget *widget, GdkEvent *event, gpointer data)
{
    (void) widget; (void) event; (void) data;
    GdkWindow *gw = gtk_widget_get_window (window);
    if (gw) {
        gdk_window_set_skip_taskbar_hint (gw, TRUE);
        gdk_window_set_skip_pager_hint (gw, TRUE);
    }
    position_window ();
    return FALSE;
}

static void build_ui (void)
{
    window = gtk_window_new (GTK_WINDOW_TOPLEVEL);
    gtk_window_set_decorated (GTK_WINDOW (window), FALSE);
    gtk_widget_set_name (window, "dapeos-qs");
    gtk_window_set_skip_taskbar_hint (GTK_WINDOW (window), TRUE);
    gtk_window_set_skip_pager_hint (GTK_WINDOW (window), TRUE);
    gtk_window_set_type_hint (GTK_WINDOW (window), GDK_WINDOW_TYPE_HINT_DOCK);
    gtk_window_set_keep_above (GTK_WINDOW (window), TRUE);
    gtk_window_set_resizable (GTK_WINDOW (window), FALSE);
    gtk_window_set_default_size (GTK_WINDOW (window), 504, 300);
    GdkGeometry hints = { 0 };
    hints.min_width = 504; hints.max_width = 504;
    hints.min_height = 300; hints.max_height = 300;
    gtk_window_set_geometry_hints (GTK_WINDOW (window), NULL, &hints,
                                   GDK_HINT_MIN_SIZE | GDK_HINT_MAX_SIZE);
    g_signal_connect (window, "key-press-event", G_CALLBACK (on_key_press), NULL);
    g_signal_connect (window, "focus-out-event", G_CALLBACK (on_focus_out), NULL);
    g_signal_connect (window, "map-event", G_CALLBACK (on_window_map), NULL);
    g_signal_connect (window, "realize", G_CALLBACK (on_window_realize), NULL);
    GdkScreen *screen = gtk_widget_get_screen (window);
    GdkVisual *visual = gdk_screen_get_rgba_visual (screen);
    if (visual) gtk_widget_set_visual (window, visual);
    gtk_widget_set_app_paintable (window, TRUE);
    g_signal_connect (window, "draw", G_CALLBACK (on_window_draw), NULL);

    qstack = gtk_stack_new ();
    gtk_stack_set_transition_type (GTK_STACK (qstack), GTK_STACK_TRANSITION_TYPE_NONE);
    gtk_stack_set_hhomogeneous (GTK_STACK (qstack), FALSE);
    gtk_stack_set_vhomogeneous (GTK_STACK (qstack), FALSE);
    gtk_widget_set_size_request (qstack, 504, 300);
    gtk_container_add (GTK_CONTAINER (window), qstack);

    main_page = gtk_box_new (GTK_ORIENTATION_VERTICAL, 12);
    gtk_container_set_border_width (GTK_CONTAINER (main_page), 16);
    GtkWidget *outer = main_page;
    gtk_stack_add_named (GTK_STACK (qstack), main_page, "main");
    wifi_page = build_wifi_page ();
    gtk_stack_add_named (GTK_STACK (qstack), wifi_page, "wifi");
    bt_page = build_bt_page ();
    gtk_stack_add_named (GTK_STACK (qstack), bt_page, "bluetooth");
    night_page = build_night_page ();
    gtk_stack_add_named (GTK_STACK (qstack), night_page, "night");
    wifi_password_page = build_wifi_password_page ();
    gtk_stack_add_named (GTK_STACK (qstack), wifi_password_page, "wifi-password");
    wifi_confirm_page = build_wifi_confirm_page ();
    gtk_stack_add_named (GTK_STACK (qstack), wifi_confirm_page, "wifi-confirm");
    gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");

    GtkWidget *header = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    GtkWidget *title = gtk_label_new ("Quick settings");
    PangoAttrList *attrs = pango_attr_list_new ();
    pango_attr_list_insert (attrs, pango_attr_weight_new (PANGO_WEIGHT_BOLD));
    pango_attr_list_insert (attrs, pango_attr_scale_new (1.25));
    gtk_label_set_attributes (GTK_LABEL (title), attrs);
    pango_attr_list_unref (attrs);
    gtk_widget_set_hexpand (title, TRUE);
    gtk_widget_set_halign (title, GTK_ALIGN_START);
    GtkWidget *close = gtk_button_new_with_label ("×");
    gtk_style_context_add_class (gtk_widget_get_style_context (close), "flat");
    g_signal_connect (close, "clicked", G_CALLBACK (on_close_clicked), NULL);
    gtk_box_pack_start (GTK_BOX (header), title, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (header), close, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (outer), header, FALSE, FALSE, 0);

    GtkWidget *grid = gtk_grid_new ();
    gtk_grid_set_column_homogeneous (GTK_GRID (grid), TRUE);
    gtk_grid_set_column_spacing (GTK_GRID (grid), 8);
    gtk_grid_set_row_spacing (GTK_GRID (grid), 8);
    GtkWidget *net_t, *net_o, *bt_t, *bt_o, *night_t, *night_o;
    GtkWidget *net = make_tile ("Network", "", &net_label, &net_status_label, &net_t, &net_o);
    GtkWidget *bt = make_tile ("Bluetooth", "", &bt_label, &bt_status_label, &bt_t, &bt_o);
    gtk_label_set_ellipsize (GTK_LABEL (bt_label), PANGO_ELLIPSIZE_END);
    gtk_label_set_max_width_chars (GTK_LABEL (bt_label), 12);
    gtk_widget_set_size_request (bt_label, 110, -1);
    GtkWidget *night = make_tile ("Night light", "", &night_label, &night_status_label, &night_t, &night_o);
    g_signal_connect (net_t, "clicked", G_CALLBACK (on_net_toggle), NULL);
    g_signal_connect (net_o, "clicked", G_CALLBACK (on_net_open), NULL);
    g_signal_connect (bt_t, "clicked", G_CALLBACK (on_bt_clicked), NULL);
    g_signal_connect (bt_o, "clicked", G_CALLBACK (on_bt_open), NULL);
    g_signal_connect (night_t, "clicked", G_CALLBACK (on_night_clicked), NULL);
    g_signal_connect (night_o, "clicked", G_CALLBACK (on_night_open), NULL);
    gtk_widget_set_hexpand (net, TRUE);
    gtk_widget_set_hexpand (bt, TRUE);
    gtk_widget_set_hexpand (night, TRUE);
    gtk_grid_attach (GTK_GRID (grid), net, 0, 0, 1, 1);
    gtk_grid_attach (GTK_GRID (grid), bt, 1, 0, 1, 1);
    gtk_grid_attach (GTK_GRID (grid), night, 2, 0, 1, 1);
    gtk_box_pack_start (GTK_BOX (outer), grid, FALSE, FALSE, 0);

    GtkWidget *volrow = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 10);
    vol_scale = gtk_scale_new_with_range (GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
    gtk_scale_set_draw_value (GTK_SCALE (vol_scale), FALSE);
    gtk_widget_set_hexpand (vol_scale, TRUE);
    vol_label = gtk_label_new ("0%");
    gtk_widget_set_size_request (vol_label, 48, -1);
    mute_button = gtk_button_new ();
    gtk_style_context_add_class (gtk_widget_get_style_context (mute_button), "flat");
    gtk_button_set_image (GTK_BUTTON (mute_button),
        gtk_image_new_from_icon_name ("audio-volume-high", GTK_ICON_SIZE_BUTTON));
    gtk_widget_set_size_request (mute_button, 32, -1);
    g_signal_connect (vol_scale, "value-changed", G_CALLBACK (on_volume_changed), NULL);
    g_signal_connect (mute_button, "clicked", G_CALLBACK (on_mute_clicked), NULL);
    gtk_box_pack_start (GTK_BOX (volrow), mute_button, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), vol_scale, TRUE, TRUE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), vol_label, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (outer), volrow, FALSE, FALSE, 0);

    bri_row = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 10);
    GtkWidget *bri_icon = gtk_label_new ("☀");
    gtk_widget_set_name (bri_icon, "brightness-icon");
    gtk_widget_set_size_request (bri_icon, 32, -1);
    bri_scale = gtk_scale_new_with_range (GTK_ORIENTATION_HORIZONTAL, 1, 100, 1);
    gtk_scale_set_draw_value (GTK_SCALE (bri_scale), FALSE);
    gtk_widget_set_hexpand (bri_scale, TRUE);
    bri_label = gtk_label_new ("0%");
    gtk_widget_set_size_request (bri_label, 48, -1);
    g_signal_connect (bri_scale, "value-changed", G_CALLBACK (on_brightness_changed), NULL);
    gtk_box_pack_start (GTK_BOX (bri_row), bri_icon, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (bri_row), bri_scale, TRUE, TRUE, 0);
    gtk_box_pack_start (GTK_BOX (bri_row), bri_label, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (outer), bri_row, FALSE, FALSE, 0);

    GtkSizeGroup *icon_group = gtk_size_group_new (GTK_SIZE_GROUP_HORIZONTAL);
    GtkSizeGroup *value_group = gtk_size_group_new (GTK_SIZE_GROUP_HORIZONTAL);
    gtk_size_group_add_widget (icon_group, mute_button);
    gtk_size_group_add_widget (icon_group, bri_icon);
    gtk_size_group_add_widget (value_group, vol_label);
    gtk_size_group_add_widget (value_group, bri_label);
    g_object_unref (icon_group);
    g_object_unref (value_group);

    GtkWidget *footer = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    battery_label = gtk_label_new ("Battery");
    gtk_widget_set_hexpand (battery_label, TRUE);
    gtk_widget_set_halign (battery_label, GTK_ALIGN_START);
    GtkWidget *soundbtn = gtk_button_new ();
    GtkWidget *mbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_pack_start (GTK_BOX (mbox), volume_icon ("audio-volume-high"), FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (mbox), gtk_label_new ("Sound"), FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (soundbtn), mbox);
    gtk_style_context_add_class (gtk_widget_get_style_context (soundbtn), "flat");
    g_signal_connect (soundbtn, "clicked", G_CALLBACK (on_sound_open), NULL);

    GtkWidget *settings = gtk_button_new ();
    GtkWidget *sbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_pack_start (GTK_BOX (sbox),
        gtk_image_new_from_icon_name ("preferences-system", GTK_ICON_SIZE_BUTTON), FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (sbox), gtk_label_new ("Settings"), FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (settings), sbox);
    gtk_style_context_add_class (gtk_widget_get_style_context (settings), "flat");
    g_signal_connect (settings, "clicked", G_CALLBACK (on_settings_clicked), NULL);
    gtk_box_pack_start (GTK_BOX (footer), battery_label, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (footer), settings, FALSE, FALSE, 0);
    gtk_box_pack_end (GTK_BOX (footer), soundbtn, FALSE, FALSE, 0);
    gtk_box_pack_end (GTK_BOX (outer), footer, FALSE, FALSE, 0);

    apply_css ();
    gtk_label_set_text (GTK_LABEL (vol_label), "--%");
    gtk_label_set_text (GTK_LABEL (bt_label), "--");
    gtk_label_set_text (GTK_LABEL (night_label), "--");
    gchar *bat = get_battery ();
    gtk_label_set_text (GTK_LABEL (battery_label), bat);
    g_free (bat);
    update_brightness_ui ();
    install_cache_monitors ();
}

static gboolean position_done = FALSE;

static void position_window (void)
{
    if (position_done) return;
    GdkDisplay *display = gdk_display_get_default ();
    GdkMonitor *monitor = gdk_display_get_primary_monitor (display);
    if (!monitor) monitor = gdk_display_get_monitor (display, 0);
    GdkRectangle geo;
    gdk_monitor_get_geometry (monitor, &geo);
    gint w = 0, h = 0;
    gtk_window_get_size (GTK_WINDOW (window), &w, &h);
    if (w < 504) w = 504;
    if (h < 300) h = 300;
    gint x = geo.x + geo.width - w - 20;
    gint y = geo.y + geo.height - panel_height () - h - 20;
    if (x < geo.x + 8) x = geo.x + 8;
    if (y < geo.y + 8) y = geo.y + 8;
    gtk_window_move (GTK_WINDOW (window), x, y);
    {
        gint aw = 0, ah = 0, ax = 0, ay = 0;
        gtk_window_get_size (GTK_WINDOW (window), &aw, &ah);
        gtk_window_get_position (GTK_WINDOW (window), &ax, &ay);
        FILE *f = fopen ("/tmp/dapeos-qs-geometry.log", "a");
        if (f) { fprintf (f, "positioned: %dx%d at %d,%d\n", aw, ah, ax, ay); fclose (f); }
    }
}

static gboolean refresh_bg (gpointer data)
{
    (void) data;
    bg_timeout = 0;
    apply_css ();
    return FALSE;
}

static GtkApplication *application;
static gboolean signal_installed = FALSE;

static void
activate (GtkApplication *app, gpointer data)
{
    (void) data;
    if (window == NULL) {
        build_ui ();
        gtk_application_add_window (app, GTK_WINDOW (window));
        gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");
        gtk_window_resize (GTK_WINDOW (window), 504, 300);
        gtk_widget_show_all (window);
        gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");
        log_geometry ("initial show");
        if (!signal_installed) {
            g_unix_signal_add (SIGUSR1, toggle_wifi_signal, NULL);
            g_unix_signal_add (SIGUSR2, show_bt_signal, NULL);
            g_unix_signal_add (SIGHUP, show_night_signal, NULL);
            {
                FILE *f = fopen ("/tmp/dapeos-qs-signal.log", "a");
                if (f) { fprintf (f, "registered pid=%d\n", (int) getpid ()); fclose (f); }
            }
            signal_installed = TRUE;
        }
        g_timeout_add (100, update_volume_cb, NULL);
        g_timeout_add (400, update_tiles_cb, NULL);
        g_timeout_add (1000, refresh_bg, NULL);
        g_timeout_add_seconds (2, tiles_tick, NULL);
        g_timeout_add_seconds (30, night_schedule_tick, NULL);
        gtk_window_present (GTK_WINDOW (window));
        if (g_getenv ("DAPEOS_QS_TOGGLE"))
            toggle_wifi_signal (NULL);
    } else if (gtk_widget_get_visible (window)) {
        gtk_widget_hide (window);
    } else {
        gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");
        gtk_window_resize (GTK_WINDOW (window), 504, 300);
        gtk_widget_show_all (window);
        gtk_stack_set_visible_child_name (GTK_STACK (qstack), "main");
        log_geometry ("initial show");
        if (!signal_installed) {
            g_unix_signal_add (SIGUSR1, toggle_wifi_signal, NULL);
            g_unix_signal_add (SIGUSR2, show_bt_signal, NULL);
            g_unix_signal_add (SIGHUP, show_night_signal, NULL);
            {
                FILE *f = fopen ("/tmp/dapeos-qs-signal.log", "a");
                if (f) { fprintf (f, "registered pid=%d\n", (int) getpid ()); fclose (f); }
            }
            signal_installed = TRUE;
        }
        gtk_window_present (GTK_WINDOW (window));
    }
}

int main (int argc, char **argv)
{
    unsetenv ("GTK_THEME");
    application = gtk_application_new ("cz.dapeos.quicksettings", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect (application, "activate", G_CALLBACK (activate), NULL);
    int status = g_application_run (G_APPLICATION (application), argc, argv);
    g_object_unref (application);
    return status;
}

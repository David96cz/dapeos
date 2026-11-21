#include <gtk/gtk.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static gchar *run_cmd (const gchar *cmd);
static void run_async (const gchar *cmd);

static GtkWidget *window;
static GtkWidget *vol_scale;
static GtkWidget *vol_label;
static GtkWidget *mute_button;
static GtkWidget *battery_label;
static GtkWidget *bt_label;
static GtkWidget *night_label;
static GtkWidget *net_label;
static gboolean updating = FALSE;
static guint vol_timeout = 0;
static guint bg_timeout = 0;
static gboolean night_on = FALSE;
static gboolean window_dark = TRUE;

static gchar *night_state_path (const gchar *name)
{
    return g_build_filename (g_get_user_cache_dir (), "dapeos", name, NULL);
}

static gboolean bt_is_on (void)
{
    gchar *out = run_cmd ("rfkill list bluetooth 2>/dev/null");
    gboolean on = strstr (out, "Soft blocked: no") != NULL;
    g_free (out);
    return on;
}

static void update_volume_ui (void);
static void update_tiles (void);

static gboolean update_volume_cb (gpointer data) { (void) data; update_volume_ui (); return FALSE; }
static gboolean update_tiles_cb (gpointer data) { (void) data; update_tiles (); return FALSE; }

static void update_tiles (void)
{
    gboolean bt = bt_is_on ();
    gtk_label_set_text (GTK_LABEL (bt_label), bt ? "On" : "Off");
    gchar *nightfile = night_state_path ("nightlight_on");
    night_on = g_file_test (nightfile, G_FILE_TEST_EXISTS);
    g_free (nightfile);
    gtk_label_set_text (GTK_LABEL (night_label), night_on ? "On" : "Off");
}

static void on_bt_clicked (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    run_async (bt_is_on () ? "bluetoothctl power off" : "bluetoothctl power on");
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
    gtk_label_set_text (GTK_LABEL (night_label), night_on ? "On" : "Off");
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

static void
apply_panel_icon_theme (void)
{
    const gchar *name = is_dark () ? "Papirus-Light" : "Papirus-Dark";
    GtkIconTheme *theme = gtk_icon_theme_get_default ();
    gtk_icon_theme_set_custom_theme (theme, name);
}

static void apply_css (void)
{
    window_dark = is_dark ();
    apply_panel_icon_theme ();
    GtkCssProvider *css = gtk_css_provider_new ();
    const gchar *data;
    if (is_dark ()) {
        data =
            "window { background: transparent; }"
            "label, button { color: #eaeaea; }"
            "button.tile-left { background: #3a3a3a; border: 1px solid #4a4a4a; border-radius: 10px 0 0 10px; padding: 10px; }"
            "button.tile-right { background: #3a3a3a; border: 1px solid #4a4a4a; border-left: none; border-radius: 0 10px 10px 0; padding: 0; }"
            "button.tile-left:hover, button.tile-right:hover { border-color: #2a7fca; }"
            "scale trough { background: #151515; border-radius: 3px; min-height: 6px; }"
            "scale highlight { background: #2a7fca; }"
            "scale slider { background: #2a7fca; border-radius: 8px; min-width: 16px; min-height: 16px; }"
            "button.flat { background: transparent; border: none; }";
    } else {
        data =
            "window { background: transparent; }"
            "label, button { color: #1a1a1a; }"
            "button.tile-left { background: #ffffff; border: 1px solid #dcdcdc; border-radius: 10px 0 0 10px; padding: 10px; }"
            "button.tile-right { background: #ffffff; border: 1px solid #dcdcdc; border-left: none; border-radius: 0 10px 10px 0; padding: 0; }"
            "button.tile-left:hover, button.tile-right:hover { border-color: #2a7fca; }"
            "scale trough { background: #d0d0d0; border-radius: 3px; min-height: 6px; }"
            "scale highlight { background: #2a7fca; }"
            "scale slider { background: #2a7fca; border-radius: 8px; min-width: 16px; min-height: 16px; }"
            "button.flat { background: transparent; border: none; }";
    }
    gtk_css_provider_load_from_data (css, data, -1, NULL);
    gtk_style_context_add_provider_for_screen (gdk_screen_get_default (),
        GTK_STYLE_PROVIDER (css), GTK_STYLE_PROVIDER_PRIORITY_USER);
    g_object_unref (css);
}

static void update_volume_ui (void)
{
    updating = TRUE;
    gint vol = get_volume ();
    gboolean mute = get_mute ();
    gtk_range_set_value (GTK_RANGE (vol_scale), vol);
    gchar *txt = g_strdup_printf ("%d%%", vol);
    gtk_label_set_text (GTK_LABEL (vol_label), txt);
    g_free (txt);
    const gchar *ic = (mute || vol == 0) ? "audio-volume-muted" : "audio-volume-high";
    GtkWidget *img = gtk_image_new_from_icon_name (ic, GTK_ICON_SIZE_BUTTON);
    gtk_button_set_image (GTK_BUTTON (mute_button), img);
    updating = FALSE;
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
           GtkWidget **toggle_out, GtkWidget **open_out)
{
    GtkWidget *box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 1);

    GtkWidget *toggle = gtk_button_new ();
    gtk_style_context_add_class (gtk_widget_get_style_context (toggle), "tile-left");
    GtkWidget *content = gtk_box_new (GTK_ORIENTATION_VERTICAL, 2);
    GtkWidget *t = gtk_label_new (title);
    gtk_widget_set_halign (t, GTK_ALIGN_START);
    GtkWidget *s = gtk_label_new (sub);
    gtk_widget_set_halign (s, GTK_ALIGN_START);
    gtk_style_context_add_class (gtk_widget_get_style_context (s), "dim-label");
    gtk_box_pack_start (GTK_BOX (content), t, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (content), s, FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (toggle), content);

    GtkWidget *open = gtk_button_new_with_label ("›");
    gtk_style_context_add_class (gtk_widget_get_style_context (open), "tile-right");
    gtk_widget_set_size_request (open, 28, -1);

    gtk_box_pack_start (GTK_BOX (box), toggle, TRUE, TRUE, 0);
    gtk_box_pack_start (GTK_BOX (box), open, FALSE, FALSE, 0);
    if (sub_label) *sub_label = s;
    if (toggle_out) *toggle_out = toggle;
    if (open_out) *open_out = open;
    return box;
}

static void
on_net_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    if (g_find_program_in_path ("nm-connection-editor"))
        run_async ("nm-connection-editor");
    else
        run_async ("xfce4-settings-manager");
    gtk_widget_hide (window);
}

static void
on_bt_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    if (g_find_program_in_path ("blueman-manager"))
        run_async ("blueman-manager");
    else
        run_async ("xfce4-settings-manager");
    gtk_widget_hide (window);
}

static void
on_night_open (GtkButton *button, gpointer data)
{
    (void) button; (void) data;
    run_async ("xfce4-settings-manager");
    gtk_widget_hide (window);
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

static void build_ui (void)
{
    window = gtk_window_new (GTK_WINDOW_TOPLEVEL);
    gtk_window_set_decorated (GTK_WINDOW (window), FALSE);
    gtk_window_set_skip_taskbar_hint (GTK_WINDOW (window), TRUE);
    gtk_window_set_skip_pager_hint (GTK_WINDOW (window), TRUE);
    gtk_window_set_keep_above (GTK_WINDOW (window), TRUE);
    gtk_window_set_resizable (GTK_WINDOW (window), FALSE);
    gtk_window_set_default_size (GTK_WINDOW (window), 440, 300);
    g_signal_connect (window, "key-press-event", G_CALLBACK (on_key_press), NULL);
    GdkScreen *screen = gtk_widget_get_screen (window);
    GdkVisual *visual = gdk_screen_get_rgba_visual (screen);
    if (visual) gtk_widget_set_visual (window, visual);
    gtk_widget_set_app_paintable (window, TRUE);
    g_signal_connect (window, "draw", G_CALLBACK (on_window_draw), NULL);

    GtkWidget *outer = gtk_box_new (GTK_ORIENTATION_VERTICAL, 12);
    gtk_container_set_border_width (GTK_CONTAINER (outer), 16);
    gtk_container_add (GTK_CONTAINER (window), outer);

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
    gtk_grid_set_column_spacing (GTK_GRID (grid), 8);
    gtk_grid_set_row_spacing (GTK_GRID (grid), 8);
    GtkWidget *net_t, *net_o, *bt_t, *bt_o, *night_t, *night_o, *sound_t, *sound_o;
    GtkWidget *net = make_tile ("Network", "Ethernet", &net_label, &net_t, &net_o);
    GtkWidget *bt = make_tile ("Bluetooth", "Off", &bt_label, &bt_t, &bt_o);
    GtkWidget *night = make_tile ("Night light", "Off", &night_label, &night_t, &night_o);
    g_signal_connect (net_t, "clicked", G_CALLBACK (on_net_open), NULL);
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
    gtk_widget_set_size_request (vol_label, 44, -1);
    mute_button = gtk_button_new ();
    gtk_style_context_add_class (gtk_widget_get_style_context (mute_button), "flat");
    gtk_button_set_image (GTK_BUTTON (mute_button),
        gtk_image_new_from_icon_name ("audio-volume-high", GTK_ICON_SIZE_BUTTON));
    g_signal_connect (vol_scale, "value-changed", G_CALLBACK (on_volume_changed), NULL);
    g_signal_connect (mute_button, "clicked", G_CALLBACK (on_mute_clicked), NULL);
    gtk_box_pack_start (GTK_BOX (volrow), mute_button, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), vol_scale, TRUE, TRUE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), vol_label, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (outer), volrow, FALSE, FALSE, 0);

    GtkWidget *footer = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    battery_label = gtk_label_new ("Battery");
    gtk_widget_set_hexpand (battery_label, TRUE);
    gtk_widget_set_halign (battery_label, GTK_ALIGN_START);
    GtkWidget *soundbtn = gtk_button_new ();
    GtkWidget *mbox = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 6);
    gtk_box_pack_start (GTK_BOX (mbox),
        gtk_image_new_from_icon_name ("audio-volume-high", GTK_ICON_SIZE_BUTTON), FALSE, FALSE, 0);
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
    gtk_box_pack_start (GTK_BOX (outer), footer, FALSE, FALSE, 0);

    apply_css ();
    gtk_label_set_text (GTK_LABEL (vol_label), "--%");
    gtk_label_set_text (GTK_LABEL (bt_label), "--");
    gtk_label_set_text (GTK_LABEL (night_label), "--");
    gchar *bat = get_battery ();
    gtk_label_set_text (GTK_LABEL (battery_label), bat);
    g_free (bat);
}

static void position_window (void)
{
    GdkDisplay *display = gdk_display_get_default ();
    GdkMonitor *monitor = gdk_display_get_primary_monitor (display);
    if (!monitor) monitor = gdk_display_get_monitor (display, 0);
    GdkRectangle geo;
    gdk_monitor_get_workarea (monitor, &geo);
    gint w = 0, h = 0;
    gtk_window_get_size (GTK_WINDOW (window), &w, &h);
    if (w <= 0) w = 420;
    if (h <= 0) h = 340;
    gint x = geo.x + geo.width - w - 20;
    gint y = geo.y + geo.height - panel_height () - h - 8;
    if (x < geo.x + 8) x = geo.x + 8;
    if (y < geo.y + 8) y = geo.y + 8;
    gtk_window_move (GTK_WINDOW (window), x, y);
}

static gboolean refresh_bg (gpointer data)
{
    (void) data;
    bg_timeout = 0;
    apply_css ();
    return FALSE;
}

int main (int argc, char **argv)
{
    gtk_init (&argc, &argv);
    build_ui ();
    g_printerr ("DAPEOS-QS: built\n");
    gtk_widget_show_all (window);
    g_printerr ("DAPEOS-QS: shown\n");
    g_timeout_add (100, update_volume_cb, NULL);
    g_timeout_add (400, update_tiles_cb, NULL);
    position_window ();
    gtk_window_present (GTK_WINDOW (window));
    gint dw = 0, dh = 0;
    gtk_window_get_size (GTK_WINDOW (window), &dw, &dh);
    gint px = 0, py = 0;
    gtk_window_get_position (GTK_WINDOW (window), &px, &py);
    g_printerr ("DAPEOS-QS: visible=%d mapped=%d size=%dx%d pos=%d,%d\n",
             gtk_widget_get_visible (window), gtk_widget_get_mapped (window), dw, dh, px, py);
    g_timeout_add (1000, refresh_bg, NULL);
    gtk_main ();
    return 0;
}

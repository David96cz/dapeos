#include <gtk/gtk.h>
#include <gio/gio.h>
#include <stdlib.h>
#include <string.h>

static GtkWidget *window;
static GtkWidget *vol_scale;
static GtkWidget *vol_label;
static GtkWidget *mute_button;
static GtkWidget *battery_label;
static GtkWidget *bt_label;
static GtkWidget *net_label;
static gboolean updating = FALSE;
static guint vol_timeout = 0;
static guint bg_timeout = 0;

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
    gchar *out = run_cmd ("xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null");
    gboolean dark = g_strrstr (out, "dark") != NULL || g_strrstr (out, "Dark") != NULL;
    g_free (out);
    return dark;
}

static void apply_css (void)
{
    GtkCssProvider *css = gtk_css_provider_new ();
    const gchar *data;
    if (is_dark ()) {
        data =
            "window { background: #2b2b2b; border-radius: 14px; }"
            "label, button { color: #eaeaea; }"
            "button.tile { background: #3a3a3a; border: 1px solid #4a4a4a; border-radius: 10px; padding: 10px; }"
            "button.tile:hover { border-color: #2a7fca; }"
            "scale trough { background: #151515; border-radius: 3px; min-height: 6px; }"
            "scale highlight { background: #2a7fca; }"
            "scale slider { background: #2a7fca; border-radius: 8px; min-width: 16px; min-height: 16px; }"
            "button.flat { background: transparent; border: none; }";
    } else {
        data =
            "window { background: #f5f5f5; border-radius: 14px; }"
            "label, button { color: #1a1a1a; }"
            "button.tile { background: #ffffff; border: 1px solid #dcdcdc; border-radius: 10px; padding: 10px; }"
            "button.tile:hover { border-color: #2a7fca; }"
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
    gtk_button_set_label (GTK_BUTTON (mute_button), mute ? "Unmute" : "Mute");
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
    g_timeout_add (80, (GSourceFunc) update_volume_ui, NULL);
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

static GtkWidget *make_tile (const gchar *title, const gchar *sub, GtkWidget **sub_label)
{
    GtkWidget *btn = gtk_button_new ();
    gtk_style_context_add_class (gtk_widget_get_style_context (btn), "tile");
    GtkWidget *box = gtk_box_new (GTK_ORIENTATION_VERTICAL, 2);
    GtkWidget *t = gtk_label_new (title);
    gtk_widget_set_halign (t, GTK_ALIGN_START);
    GtkWidget *s = gtk_label_new (sub);
    gtk_widget_set_halign (s, GTK_ALIGN_START);
    gtk_style_context_add_class (gtk_widget_get_style_context (s), "dim-label");
    gtk_box_pack_start (GTK_BOX (box), t, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (box), s, FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (btn), box);
    if (sub_label) *sub_label = s;
    return btn;
}

static void build_ui (void)
{
    window = gtk_window_new (GTK_WINDOW_TOPLEVEL);
    gtk_window_set_decorated (GTK_WINDOW (window), FALSE);
    gtk_window_set_skip_taskbar_hint (GTK_WINDOW (window), TRUE);
    gtk_window_set_skip_pager_hint (GTK_WINDOW (window), TRUE);
    gtk_window_set_keep_above (GTK_WINDOW (window), TRUE);
    gtk_window_set_resizable (GTK_WINDOW (window), FALSE);
    gtk_window_set_default_size (GTK_WINDOW (window), 420, 340);
    g_signal_connect (window, "key-press-event", G_CALLBACK (on_key_press), NULL);
    g_signal_connect (window, "focus-out-event", G_CALLBACK (on_focus_out), NULL);

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
    GtkWidget *net = make_tile ("Network", "Ethernet", &net_label);
    GtkWidget *bt = make_tile ("Bluetooth", "Off", &bt_label);
    GtkWidget *night = make_tile ("Night light", "Off", NULL);
    gtk_widget_set_hexpand (net, TRUE);
    gtk_widget_set_hexpand (bt, TRUE);
    gtk_widget_set_hexpand (night, TRUE);
    gtk_grid_attach (GTK_GRID (grid), net, 0, 0, 1, 1);
    gtk_grid_attach (GTK_GRID (grid), bt, 1, 0, 1, 1);
    gtk_grid_attach (GTK_GRID (grid), night, 2, 0, 1, 1);
    gtk_box_pack_start (GTK_BOX (outer), grid, FALSE, FALSE, 0);

    GtkWidget *volrow = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 10);
    GtkWidget *vicon = gtk_image_new_from_icon_name ("audio-volume-high", GTK_ICON_SIZE_BUTTON);
    vol_scale = gtk_scale_new_with_range (GTK_ORIENTATION_HORIZONTAL, 0, 100, 1);
    gtk_scale_set_draw_value (GTK_SCALE (vol_scale), FALSE);
    gtk_widget_set_hexpand (vol_scale, TRUE);
    vol_label = gtk_label_new ("0%");
    gtk_widget_set_size_request (vol_label, 44, -1);
    mute_button = gtk_button_new_with_label ("Mute");
    gtk_style_context_add_class (gtk_widget_get_style_context (mute_button), "flat");
    g_signal_connect (vol_scale, "value-changed", G_CALLBACK (on_volume_changed), NULL);
    g_signal_connect (mute_button, "clicked", G_CALLBACK (on_mute_clicked), NULL);
    gtk_box_pack_start (GTK_BOX (volrow), vicon, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), vol_scale, TRUE, TRUE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), vol_label, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (volrow), mute_button, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (outer), volrow, FALSE, FALSE, 0);

    GtkWidget *footer = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 8);
    battery_label = gtk_label_new ("Battery");
    gtk_widget_set_hexpand (battery_label, TRUE);
    gtk_widget_set_halign (battery_label, GTK_ALIGN_START);
    GtkWidget *settings = gtk_button_new_with_label ("Settings");
    gtk_style_context_add_class (gtk_widget_get_style_context (settings), "flat");
    g_signal_connect (settings, "clicked", G_CALLBACK (on_settings_clicked), NULL);
    gtk_box_pack_start (GTK_BOX (footer), battery_label, TRUE, TRUE, 0);
    gtk_box_pack_end (GTK_BOX (footer), settings, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (outer), footer, FALSE, FALSE, 0);

    apply_css ();
    update_volume_ui ();
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
    gint y = geo.y + geo.height - h - 12;
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
    gtk_widget_show_all (window);
    position_window ();
    g_timeout_add (1000, refresh_bg, NULL);
    gtk_main ();
    return 0;
}

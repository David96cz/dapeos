#include <gtk/gtk.h>
#include <gio/gio.h>
#include <libxfce4panel/libxfce4panel.h>
#include <libxfce4util/libxfce4util.h>
#include <librsvg/rsvg.h>

typedef struct {
    gint net_type;          /* 0 none, 1 ethernet, 2 wifi */
    gchar *net_name;
    gint vol;
    gboolean mute;
    gint cap;               /* -1 no battery */
    gchar *bat_status;
    gboolean dark;
    GtkWidget *area;
    GPid pactl_pid, nm_pid, upower_pid;
} DapeosStatus;

static gchar *
run_cmd (const gchar *cmd)
{
    gchar *out = NULL;
    gint status = 0;
    gchar *quoted = g_shell_quote (cmd);
    gchar *shell_cmd = g_strdup_printf ("sh -c %s", quoted);
    gboolean ok = g_spawn_command_line_sync (shell_cmd, &out, NULL, &status, NULL);
    g_free (shell_cmd);
    g_free (quoted);
    if (!ok)
        return g_strdup ("");
    if (out == NULL)
        return g_strdup ("");
    g_strstrip (out);
    return out;
}

static void
read_volume (DapeosStatus *st)
{
    read_volume (st);
}

static void
read_state (DapeosStatus *st)
{
    g_free (st->net_name);
    st->net_name = g_strdup ("");
    st->net_type = 0;

    gchar *nm = run_cmd ("nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null");
    gchar **lines = g_strsplit (nm, "\n", -1);
    for (guint i = 0; lines[i] != NULL; i++) {
        gchar **parts = g_strsplit (lines[i], ":", 3);
        if (parts[0] && parts[1] && g_strcmp0 (parts[1], "connected") == 0) {
            if (g_strcmp0 (parts[0], "ethernet") == 0) st->net_type = 1;
            else if (g_strcmp0 (parts[0], "wifi") == 0) st->net_type = 2;
            g_free (st->net_name);
            st->net_name = g_strdup (parts[2] ? parts[2] : "");
        }
        g_strfreev (parts);
        if (st->net_type != 0) break;
    }
    g_strfreev (lines);
    g_free (nm);

    gchar *v = run_cmd ("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null");
    st->vol = 0;
    for (gchar *p = v; *p; p++) {
        if (*p == '%') {
            gchar *start = p;
            while (start > v && g_ascii_isdigit (start[-1])) start--;
            st->vol = atoi (start);
            break;
        }
    }
    g_free (v);

    gchar *m = run_cmd ("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null");
    st->mute = (strstr (m, "yes") != NULL);
    g_free (m);

    st->cap = -1;
    g_free (st->bat_status);
    st->bat_status = g_strdup ("");
    GDir *dir = g_dir_open ("/sys/class/power_supply", 0, NULL);
    if (dir) {
        const gchar *name;
        while ((name = g_dir_read_name (dir)) != NULL) {
            if (!g_str_has_prefix (name, "BAT")) continue;
            gchar *base = g_build_filename ("/sys/class/power_supply", name, NULL);
            gchar *capf = g_build_filename (base, "capacity", NULL);
            gchar *stf = g_build_filename (base, "status", NULL);
            gchar *cap = NULL, *bat = NULL;
            if (g_file_get_contents (capf, &cap, NULL, NULL)) {
                st->cap = atoi (cap);
                if (g_file_get_contents (stf, &bat, NULL, NULL)) {
                    g_free (st->bat_status);
                    st->bat_status = g_strdup (g_strstrip (bat));
                }
            }
            g_free (cap); g_free (bat);
            g_free (capf); g_free (stf); g_free (base);
            if (st->cap >= 0) break;
        }
        g_dir_close (dir);
    }

    gchar *props = run_cmd ("xfconf-query -c xfce4-panel -l 2>/dev/null");
    st->dark = TRUE;
    gchar **pl = g_strsplit (props, "\n", -1);
    for (guint i = 0; pl[i] != NULL; i++) {
        if (g_str_has_suffix (pl[i], "/dark-mode")) {
            gchar *cmd = g_strdup_printf ("xfconf-query -c xfce4-panel -p '%s' 2>/dev/null", pl[i]);
            gchar *val = run_cmd (cmd);
            st->dark = (g_strcmp0 (val, "true") == 0);
            g_free (val); g_free (cmd);
            break;
        }
    }
    g_strfreev (pl);
    g_free (props);
}

static GString *
build_svg (DapeosStatus *st)
{
    const gint W = 22, H = 22, GAP = 4;
    gint x = 0;
    gchar *color = st->dark ? "#dfdfdf" : "#444444";
    GString *s = g_string_new ("");
    g_string_append_printf (s,
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">",
        3 * W + 2 * GAP, H, 3 * W + 2 * GAP, H);

    if (st->net_type == 1) {
        g_string_append_printf (s, "<g transform=\"translate(%d,1)\" fill=\"%s\">", x, color);
        g_string_append (s, "<rect x=\"4\" y=\"8\" width=\"14\" height=\"8\" rx=\"2\"/>");
        g_string_append (s, "<rect x=\"6\" y=\"4\" width=\"2\" height=\"5\" rx=\"1\"/>");
        g_string_append (s, "<rect x=\"10\" y=\"4\" width=\"2\" height=\"5\" rx=\"1\"/>");
        g_string_append (s, "<rect x=\"14\" y=\"4\" width=\"2\" height=\"5\" rx=\"1\"/>");
        g_string_append (s, "</g>");
    } else {
        gdouble op = st->net_type == 2 ? 1.0 : 0.35;
        g_string_append_printf (s,
            "<g transform=\"translate(%d,0.5)\" opacity=\"%.2f\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.7\" stroke-linecap=\"round\">",
            x, op, color);
        g_string_append_printf (s, "<circle cx=\"11\" cy=\"16.5\" r=\"1.3\" fill=\"%s\" stroke=\"none\"/>", color);
        g_string_append (s, "<path d=\"M6.8 13.4a6.3 6.3 0 0 1 8.4 0\"/>");
        g_string_append (s, "<path d=\"M3.8 10.2a10.6 10.6 0 0 1 14.4 0\"/>");
        g_string_append (s, "</g>");
    }

    x = W + GAP;
    if (st->cap < 0) {
        g_string_append_printf (s, "<g transform=\"translate(%d,0.5)\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.5\" opacity=\"0.35\">", x, color);
        g_string_append (s, "<rect x=\"3\" y=\"7\" width=\"14\" height=\"9\" rx=\"2\"/>");
        g_string_append (s, "</g>");
    } else {
        gint fillw = MAX (2, MIN (10, 10 * st->cap / 100));
        gchar *fill = st->cap > 30 ? "#4caf50" : (st->cap > 15 ? "#ff9800" : "#f44336");
        g_string_append_printf (s, "<g transform=\"translate(%d,-0.5)\">", x);
        g_string_append_printf (s, "<rect x=\"3\" y=\"7\" width=\"14\" height=\"9\" rx=\"2\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.5\"/>", color);
        g_string_append_printf (s, "<rect x=\"5\" y=\"9\" width=\"%d\" height=\"5\" rx=\"1\" fill=\"%s\"/>", fillw, fill);
        g_string_append_printf (s, "<rect x=\"18\" y=\"9.5\" width=\"2\" height=\"4\" rx=\"1\" fill=\"%s\"/>", color);
        g_string_append (s, "</g>");
    }

    x = 2 * (W + GAP);
    g_string_append_printf (s, "<g transform=\"translate(%d,0)\" fill=\"%s\">", x, color);
    g_string_append (s, "<path d=\"M4 8.5h3l4.5-3.5v12L7 13.5H4z\"/>");
    if (st->mute || st->vol == 0) {
        g_string_append (s, "<path d=\"M13.5 8.5l5 5M18.5 8.5l-5 5\" fill=\"none\" stroke=\"#f44336\" stroke-width=\"1.7\" stroke-linecap=\"round\"/>");
    } else {
        if (st->vol >= 34) g_string_append_printf (s, "<path d=\"M13.5 8a4.2 4.2 0 0 1 0 6\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.6\" stroke-linecap=\"round\"/>", color);
        if (st->vol >= 67) g_string_append_printf (s, "<path d=\"M15.8 5.8a8 8 0 0 1 0 10.4\" fill=\"none\" stroke=\"%s\" stroke-width=\"1.6\" stroke-linecap=\"round\"/>", color);
    }
    g_string_append (s, "</g></svg>");
    return s;
}

static void
update_image (DapeosStatus *st)
{
    GString *svg = build_svg (st);
    GError *error = NULL;
    RsvgHandle *handle = rsvg_handle_new_from_data ((const guint8 *) svg->str, svg->len, &error);
    cairo_surface_t *surface = cairo_image_surface_create (CAIRO_FORMAT_ARGB32, 74, 22);
    cairo_t *cr = cairo_create (surface);

    if (handle) {
        rsvg_handle_render_cairo (handle, cr);
        g_object_unref (handle);
    } else {
        cairo_set_source_rgb (cr, 0.9, 0.2, 0.2);
        cairo_rectangle (cr, 0, 0, 22, 22);
        cairo_fill (cr);
    }
    if (error) g_error_free (error);
    cairo_destroy (cr);
    g_string_free (svg, TRUE);

    GdkPixbuf *pix = gdk_pixbuf_get_from_surface (surface, 0, 0, 74, 22);
    cairo_surface_destroy (surface);
    if (pix) {
        gtk_image_set_from_pixbuf (GTK_IMAGE (st->area), pix);
        g_object_unref (pix);
    } else {
    }

    gchar *tip = g_strdup_printf ("%s%s | sound: %d%% | battery: %s",
        st->net_type == 1 ? "Ethernet: " : (st->net_type == 2 ? "Wi-Fi: " : ""),
        st->net_name, st->vol,
        st->cap < 0 ? "none" : st->bat_status);
    gtk_widget_set_tooltip_text (st->area, tip);
    g_free (tip);
}

static gboolean
on_event (GIOChannel *channel, GIOCondition condition, gpointer data)
{
    DapeosStatus *st = data;
    gchar buf[512];
    gsize read = 0;
    g_io_channel_read_chars (channel, buf, sizeof (buf) - 1, &read, NULL);
    read_state (st);
    update_image (st);
    return TRUE;
}

static void
spawn_monitor (DapeosStatus *st, const gchar *cmd, GPid *pid_out)
{
    gchar **argv = NULL;
    if (!g_shell_parse_argv (cmd, NULL, &argv, NULL)) return;
    gint out = -1;
    GPid pid = 0;
    if (g_spawn_async_with_pipes (NULL, argv, NULL,
            G_SPAWN_SEARCH_PATH | G_SPAWN_DO_NOT_REAP_CHILD,
            NULL, NULL, &pid, NULL, &out, NULL, NULL)) {
        GIOChannel *ch = g_io_channel_unix_new (out);
        g_io_add_watch (ch, G_IO_IN | G_IO_HUP, on_event, st);
        *pid_out = pid;
    }
    g_strfreev (argv);
}

static gboolean
on_click (GtkWidget *widget, GdkEventButton *event, gpointer data)
{
    if (event->button == 1) {
        g_spawn_command_line_async ("dapeos-quicksettings-toggle", NULL);
        return TRUE;
    }
    return FALSE;
}

static gboolean
on_size_changed (XfcePanelPlugin *plugin, gint size, gpointer data)
{
    DapeosStatus *st = data;
    gtk_widget_set_size_request (st->area, 74, 22);
    gtk_widget_set_size_request (GTK_WIDGET (plugin), 74, 22);
    update_image (st);
    return TRUE;
}

static void
dapeos_status_construct (XfcePanelPlugin *plugin)
{
    DapeosStatus *st = g_new0 (DapeosStatus, 1);
    read_state (st);

    st->area = gtk_image_new ();
    gtk_widget_set_size_request (st->area, 74, 22);
    gtk_widget_show (st->area);
    gtk_widget_add_events (st->area, GDK_BUTTON_PRESS_MASK);
    g_signal_connect (st->area, "button-press-event", G_CALLBACK (on_click), st);

    GtkWidget *eventbox = gtk_event_box_new ();
    gtk_event_box_set_visible_window (GTK_EVENT_BOX (eventbox), FALSE);
    gtk_widget_show (eventbox);
    gtk_container_add (GTK_CONTAINER (plugin), eventbox);
    xfce_panel_plugin_add_action_widget (plugin, eventbox);

    GtkWidget *box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_show (box);
    gtk_container_add (GTK_CONTAINER (eventbox), box);
    gtk_box_pack_start (GTK_BOX (box), st->area, FALSE, FALSE, 0);
    gtk_widget_set_size_request (eventbox, 74, 22);
    gtk_widget_set_size_request (box, 74, 22);
    update_image (st);

    g_signal_connect (plugin, "size-changed", G_CALLBACK (on_size_changed), st);

    spawn_monitor (st, "pactl subscribe", &st->pactl_pid);

    xfce_panel_plugin_set_small (plugin, TRUE);
    gtk_widget_show_all (GTK_WIDGET (plugin));
}

XFCE_PANEL_PLUGIN_REGISTER (dapeos_status_construct)

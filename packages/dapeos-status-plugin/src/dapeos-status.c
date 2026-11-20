#include <gtk/gtk.h>
#include <libxfce4panel/libxfce4panel.h>

static void
dapeos_status_construct (XfcePanelPlugin *plugin)
{
    GtkWidget *box = gtk_box_new (GTK_ORIENTATION_HORIZONTAL, 4);
    GtkWidget *icon = gtk_image_new_from_icon_name ("network-wired", GTK_ICON_SIZE_BUTTON);
    GtkWidget *label = gtk_label_new ("DapeOS");

    gtk_box_pack_start (GTK_BOX (box), icon, FALSE, FALSE, 0);
    gtk_box_pack_start (GTK_BOX (box), label, FALSE, FALSE, 0);
    gtk_container_add (GTK_CONTAINER (plugin), box);

    xfce_panel_plugin_set_small (plugin, TRUE);
    gtk_widget_show_all (GTK_WIDGET (plugin));
}

XFCE_PANEL_PLUGIN_REGISTER (dapeos_status_construct)

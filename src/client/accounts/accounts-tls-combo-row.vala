/*
 * Copyright 2025 Niels De Graef <nielsdegraef@gmail.com>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/accounts-tls-combo-row.ui")]
internal class Accounts.TlsComboRow : Adw.ComboRow {

    private const string INSECURE_ICON = "channel-insecure-symbolic";
    private const string SECURE_ICON = "channel-secure-symbolic";


    public Geary.TlsNegotiationMethod method {
        get { return ((Adw.EnumListItem) this.selected_item).value; }
        set { this.selected = value; }
    }

    [GtkCallback]
    private void on_factory_setup(Gtk.SignalListItemFactory factory,
                                  GLib.Object object) {
        unowned var item = (Gtk.ListItem) object;

        var image = new Gtk.Image();

        var label = new Gtk.Label(null);
        label.xalign = 1.0f;

        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        box.append(image);
        box.append(label);

        item.child = box;
    }

    [GtkCallback]
    private void on_factory_bind(Gtk.SignalListItemFactory factory,
                                 GLib.Object object) {
        unowned var item = (Gtk.ListItem) object;
        unowned var enum_item = (Adw.EnumListItem) item.item;
        var method = (Geary.TlsNegotiationMethod) enum_item.get_value();

        unowned var box = (Gtk.Box) item.child;

        unowned var image = (Gtk.Image) box.get_first_child();
        if (method == Geary.TlsNegotiationMethod.NONE)
            image.icon_name = "channel-insecure-symbolic";
        else
            image.icon_name = "channel-secure-symbolic";

        unowned var label = (Gtk.Label) image.get_next_sibling();
        label.label = method.to_string();
    }
}

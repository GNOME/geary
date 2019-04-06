/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A window that displays debugging and development information.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-inspector.ui")]
public class Components.Inspector : Gtk.Window {


    [GtkChild]
    private Gtk.HeaderBar header_bar;

    [GtkChild]
    private Hdy.SearchBar search_bar;

    [GtkChild]
    private Gtk.TreeView logs_view;

    [GtkChild]
    private Gtk.CellRendererText log_renderer;

    [GtkChild]
    private Gtk.ListBox detail_list;

    private Gtk.ListStore logs_store = new Gtk.ListStore.newv({
            typeof(string)
    });

    private string details;


    public Inspector(GearyApplication app) {
        this.title = this.header_bar.title = _("Inspector");

        // Log a marker for when the inspector was opened
        debug("---- 8< ---- %s ---- 8< ----", this.header_bar.title);

        Gtk.ListStore logs_store = this.logs_store;
        Geary.Logging.LogRecord? logs = Geary.Logging.get_logs();
        while (logs != null) {
            Gtk.TreeIter iter;
            logs_store.append(out iter);
            logs_store.set_value(iter, 0, logs.format());
            logs = logs.get_next();
        }

        GLib.Settings system = app.config.gnome_interface;
        system.bind(
            "monospace-font-name",
            this.log_renderer, "font",
            SettingsBindFlags.DEFAULT
        );

        this.logs_view.set_model(logs_store);

        StringBuilder details = new StringBuilder();
        foreach (GearyApplication.RuntimeDetail? detail
                 in app.get_runtime_information()) {
            this.detail_list.add(
                new DetailRow("%s:".printf(detail.name), detail.value)
            );
            details.append_printf("%s: %s\n", detail.name, detail.value);
        }
        this.details = details.str;
    }

    [GtkCallback]
    private void on_copy_clicked() {
        get_clipboard(Gdk.SELECTION_CLIPBOARD).set_text(this.details, -1);
    }

    [GtkCallback]
    private void on_search_clicked() {
        this.search_bar.set_search_mode(!this.search_bar.get_search_mode());
    }

    [GtkCallback]
    private void on_destroy() {
        destroy();
    }

}


private class Components.DetailRow : Gtk.ListBoxRow {


    private Gtk.Grid layout { get; private set; default = new Gtk.Grid(); }
    private Gtk.Label label { get; private set; default = new Gtk.Label(""); }
    private Gtk.Label value { get; private set; default = new Gtk.Label(""); }


    public DetailRow(string label, string value) {
        get_style_context().add_class("geary-labelled-row");

        this.label.halign = Gtk.Align.START;
        this.label.valign = Gtk.Align.CENTER;
        this.label.set_text(label);
        this.label.show();

        this.value.halign = Gtk.Align.END;
        this.value.hexpand = true;
        this.value.valign = Gtk.Align.CENTER;
        this.value.xalign = 1.0f;
        this.value.set_text(value);
        this.value.show();

        this.layout.orientation = Gtk.Orientation.HORIZONTAL;
        this.layout.add(this.label);
        this.layout.add(this.value);
        this.layout.show();
        add(this.layout);

        this.activatable = false;
        show();
    }

}

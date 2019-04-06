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


    private const int COL_MESSAGE = 0;


    [GtkChild]
    private Gtk.HeaderBar header_bar;

    [GtkChild]
    private Gtk.Stack stack;

    [GtkChild]
    private Gtk.Button copy_button;

    [GtkChild]
    private Gtk.Widget logs_pane;

    [GtkChild]
    private Gtk.Button search_button;

    [GtkChild]
    private Hdy.SearchBar search_bar;

    [GtkChild]
    private Gtk.SearchEntry search_entry;

    [GtkChild]
    private Gtk.TreeView logs_view;

    [GtkChild]
    private Gtk.CellRendererText log_renderer;

    [GtkChild]
    private Gtk.Widget detail_pane;

    [GtkChild]
    private Gtk.ListBox detail_list;

    private Gtk.ListStore logs_store = new Gtk.ListStore.newv({
            typeof(string)
    });

    private Gtk.TreeModelFilter logs_filter;

    private string[] logs_filter_terms = new string[0];

    private string details;


    public Inspector(GearyApplication app) {
        this.title = this.header_bar.title = _("Inspector");

        this.search_bar.connect_entry(this.search_entry);

        GLib.Settings system = app.config.gnome_interface;
        system.bind(
            "monospace-font-name",
            this.log_renderer, "font",
            SettingsBindFlags.DEFAULT
        );

        StringBuilder details = new StringBuilder();
        foreach (GearyApplication.RuntimeDetail? detail
                 in app.get_runtime_information()) {
            this.detail_list.add(
                new DetailRow("%s:".printf(detail.name), detail.value)
            );
            details.append_printf("%s: %s\n", detail.name, detail.value);
        }
        this.details = details.str;

        // Log a marker for when the inspector was opened
        debug("---- 8< ---- %s ---- 8< ----", this.header_bar.title);

        Gtk.ListStore logs_store = this.logs_store;
        Geary.Logging.LogRecord? logs = Geary.Logging.get_logs();
        while (logs != null) {
            Gtk.TreeIter iter;
            logs_store.append(out iter);
            logs_store.set_value(iter, COL_MESSAGE, logs.format());
            logs = logs.get_next();
        }

        this.logs_filter = new Gtk.TreeModelFilter(logs_store, null);
        this.logs_filter.set_visible_func((model, iter) => {
                bool ret = true;
                if (this.logs_filter_terms.length > 0) {
                    ret = false;
                    Value value;
                    model.get_value(iter, COL_MESSAGE, out value);
                    string? message = (string) value;
                    if (message != null) {
                        foreach (string term in this.logs_filter_terms) {
                            if (term in message) {
                                ret = true;
                                break;
                            }
                        }
                    }
                }
                return ret;
            });

        this.logs_view.set_model(this.logs_filter);
    }

    public override bool key_press_event(Gdk.EventKey event) {
        bool ret = this.search_bar.handle_event(event);
        if (ret == Gdk.EVENT_PROPAGATE) {
            ret = base.key_press_event(event);
        }
        return ret;
    }

    private async void save(string path,
                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.File dest = GLib.File.new_for_path(path);
        GLib.FileIOStream dest_io = yield dest.create_readwrite_async(
            GLib.FileCreateFlags.NONE,
            GLib.Priority.DEFAULT,
            cancellable
        );
        GLib.DataOutputStream out = new GLib.DataOutputStream(
            new GLib.BufferedOutputStream(dest_io.get_output_stream())
        );

        out.put_string(this.details);
        out.put_byte('\n');
        out.put_byte('\n');

        Gtk.TreeModel model = this.logs_view.model;
        Gtk.TreeIter? iter;
        bool valid = model.get_iter_first(out iter);
        while (valid && !cancellable.is_cancelled()) {
            Value value;
            model.get_value(iter, COL_MESSAGE, out value);
            string? message = (string) value;
            if (message != null) {
                out.put_string(message);
                out.put_byte('\n');
            }
            valid = model.iter_next(ref iter);
        }

        yield out.close_async();
        yield dest_io.close_async();
    }

    private void update_ui() {
        bool logs_visible = this.stack.visible_child == this.logs_pane;
        uint logs_selected = this.logs_view.get_selection().count_selected_rows();
        this.copy_button.set_sensitive(!logs_visible || logs_selected > 0);
        this.search_button.set_visible(logs_visible);
    }

    private void update_logs_filter() {
        this.logs_filter_terms = this.search_entry.text.split(" ");
        this.logs_filter.refilter();
    }

    [GtkCallback]
    private void on_visible_child_changed() {
        update_ui();
    }

    [GtkCallback]
    private void on_copy_clicked() {
        string clipboard_value = "";
        if (this.stack.visible_child == this.logs_pane) {
            StringBuilder rows = new StringBuilder();
            Gtk.TreeModel model = this.logs_view.model;
            foreach (Gtk.TreePath path in
                     this.logs_view.get_selection().get_selected_rows(null)) {
                Gtk.TreeIter iter;
                if (model.get_iter(out iter, path)) {
                    Value value;
                    model.get_value(iter, COL_MESSAGE, out value);

                    string? message = (string) value;
                    if (message != null) {
                        rows.append(message);
                        rows.append_c('\n');
                    }
                }
            }
            clipboard_value = rows.str;
        } else if (this.stack.visible_child == this.detail_pane) {
            clipboard_value = this.details;
        }

        if (!Geary.String.is_empty(clipboard_value)) {
            get_clipboard(Gdk.SELECTION_CLIPBOARD).set_text(clipboard_value, -1);
        }
    }

    [GtkCallback]
    private void on_save_as_clicked() {
        Gtk.FileChooserNative chooser = new Gtk.FileChooserNative(
            _("Save As"),
            this,
            Gtk.FileChooserAction.SAVE,
            _("Save As"),
            _("Cancel")
        );
        chooser.set_current_name(
            new GLib.DateTime.now_local().format("Geary Inspector - %F %T.txt")
        );

        if (chooser.run() == Gtk.ResponseType.ACCEPT) {
            this.save.begin(
                chooser.get_filename(),
                null,
                (obj, res) => {
                    try {
                        this.save.end(res);
                    } catch (GLib.Error err) {
                        warning("Failed to save inspector data: %s", err.message);
                    }
                }
            );
        }
    }

    [GtkCallback]
    private void on_search_clicked() {
        this.search_bar.set_search_mode(!this.search_bar.get_search_mode());
    }

    [GtkCallback]
    private void on_logs_selection_changed() {
        update_ui();
    }

    [GtkCallback]
    private void on_logs_search_changed() {
        update_logs_filter();
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

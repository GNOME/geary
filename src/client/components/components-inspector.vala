
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
public class Components.Inspector : Gtk.ApplicationWindow {


    private const int COL_MESSAGE = 0;

    private const string ACTION_CLOSE = "inspector-close";
    private const string ACTION_PLAY_TOGGLE = "toggle-play";
    private const string ACTION_SEARCH_TOGGLE = "toggle-search";
    private const string ACTION_SEARCH_ACTIVATE = "activate-search";

    private const ActionEntry[] action_entries = {
        {GearyApplication.ACTION_CLOSE, on_close },
        {GearyApplication.ACTION_COPY,  on_copy_clicked },
        {ACTION_CLOSE,                  on_close },
        {ACTION_PLAY_TOGGLE,            on_logs_play_toggled, null, "true" },
        {ACTION_SEARCH_TOGGLE,          on_logs_search_toggled, null, "false" },
        {ACTION_SEARCH_ACTIVATE,        on_logs_search_activated },
    };

    public static void add_window_accelerators(GearyApplication app) {
        app.add_window_accelerators(ACTION_CLOSE, { "Escape" } );
        app.add_window_accelerators(ACTION_PLAY_TOGGLE, { "space" } );
        app.add_window_accelerators(ACTION_SEARCH_ACTIVATE, { "<Ctrl>F" } );
    }


    [GtkChild]
    private Gtk.HeaderBar header_bar;

    [GtkChild]
    private Gtk.Stack stack;

    [GtkChild]
    private Gtk.Button copy_button;

    [GtkChild]
    private Gtk.Widget logs_pane;

    [GtkChild]
    private Gtk.ToggleButton play_button;

    [GtkChild]
    private Gtk.ToggleButton search_button;

    [GtkChild]
    private Hdy.SearchBar search_bar;

    [GtkChild]
    private Gtk.SearchEntry search_entry;

    [GtkChild]
    private Gtk.ScrolledWindow logs_scroller;

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

    private bool update_logs = true;
    private Geary.Logging.Record? first_pending = null;

    private bool autoscroll = true;


    public Inspector(GearyApplication app) {
        Object(application: app);
        this.title = this.header_bar.title = _("Inspector");

        add_action_entries(Inspector.action_entries, this);

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

        // Enable updates to get the log marker
        enable_log_updates(true);

        // Install the listener then starting add the backlog
        // (ba-doom-tish) so to avoid the race.
        Geary.Logging.set_log_listener(this.on_log_record);

        Gtk.ListStore logs_store = this.logs_store;
        Geary.Logging.Record? logs = Geary.Logging.get_logs();
        int index = 0;
        while (logs != null) {
            if (should_append(logs)) {
                Gtk.TreeIter iter;
                logs_store.insert(out iter, index++);
                logs_store.set_value(iter, COL_MESSAGE, logs.format());
            }
            logs = logs.next;
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

    public override void destroy() {
        Geary.Logging.set_log_listener(null);
        base.destroy();
    }

    public override bool key_press_event(Gdk.EventKey event) {
        bool ret = Gdk.EVENT_PROPAGATE;

        if (this.search_bar.search_mode_enabled &&
            event.keyval == Gdk.Key.Escape) {
            // Manually deactivate search so the button stays in sync
            this.search_button.set_active(false);
            ret = Gdk.EVENT_STOP;
        }

        if (ret == Gdk.EVENT_PROPAGATE) {
            ret = this.search_bar.handle_event(event);
        }

        if (ret == Gdk.EVENT_PROPAGATE &&
            this.search_bar.search_mode_enabled) {
            // Ensure <Space> and others are passed to the search
            // entry before getting used as an accelerator.
            ret = this.search_entry.key_press_event(event);
        }

        if (ret == Gdk.EVENT_PROPAGATE) {
            ret = base.key_press_event(event);
        }
        return ret;
    }

    private void enable_log_updates(bool enabled) {
        // Log a marker to indicate when it was started/stopped
        debug(
            "---- 8< ---- %s %s ---- 8< ----",
            this.header_bar.title,
            enabled ? "▶" : "■"
        );

        this.update_logs = enabled;

        // Disable autoscroll when not updating as well to stop the
        // tree view jumping to the bottom when changing the filter.
        this.autoscroll = enabled;

        if (enabled) {
            Geary.Logging.Record? logs = this.first_pending;
            while (logs != null) {
                append_record(logs);
                logs = logs.next;
            }
            this.first_pending = null;
        }
    }

    private inline bool should_append(Geary.Logging.Record record) {
        // Blacklist GdkPixbuf since it spams us e.g. when window
        // focus changes, including between MainWindow and the
        // Inspector, which is very annoying.
        return (record.domain != "GdkPixbuf");
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
        this.play_button.set_visible(logs_visible);
        this.search_button.set_visible(logs_visible);
    }

    private void update_scrollbar() {
        Gtk.Adjustment adj = this.logs_scroller.get_vadjustment();
        adj.set_value(adj.upper - adj.page_size);
    }

    private void update_logs_filter() {
        this.logs_filter_terms = this.search_entry.text.split(" ");
        this.logs_filter.refilter();
    }

    private void append_record(Geary.Logging.Record record) {
        if (should_append(record)) {
            Gtk.TreeIter inserted_iter;
            this.logs_store.append(out inserted_iter);
            this.logs_store.set_value(inserted_iter, COL_MESSAGE, record.format());
        }
    }

    [GtkCallback]
    private void on_visible_child_changed() {
        update_ui();
    }

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
    private void on_logs_size_allocate() {
        if (this.autoscroll) {
            update_scrollbar();
        }
    }

    [GtkCallback]
    private void on_logs_selection_changed() {
        update_ui();
    }

    private void on_logs_search_toggled(GLib.SimpleAction action,
                                        GLib.Variant? param) {
        bool enabled = !((bool) action.state);
        this.search_bar.set_search_mode(enabled);
        action.set_state(enabled);
    }

    private void on_logs_search_activated() {
        this.search_button.set_active(true);
        this.search_entry.grab_focus();
    }

    private void on_logs_play_toggled(GLib.SimpleAction action,
                                      GLib.Variant? param) {
        bool enabled = !((bool) action.state);
        enable_log_updates(enabled);
        action.set_state(enabled);
    }

    [GtkCallback]
    private void on_logs_search_changed() {
        update_logs_filter();
    }

    private void on_log_record(Geary.Logging.Record record) {
        if (this.update_logs) {
            GLib.MainContext.default().invoke(() => {
                    append_record(record);
                    return GLib.Source.REMOVE;
                });
        } else if (this.first_pending == null) {
            this.first_pending = record;
        }
    }

    private void on_close() {
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

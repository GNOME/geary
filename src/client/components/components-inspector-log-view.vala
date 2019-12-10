/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A view that displays the contents of the Engine's log.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-inspector-log-view.ui")]
public class Components.InspectorLogView : Gtk.Grid {


    private const int COL_MESSAGE = 0;


    /** Determines if the log record search user interface is shown. */
    public bool search_mode_enabled {
        get { return this.search_bar.search_mode_enabled; }
        set { this.search_bar.search_mode_enabled = value; }
    }

    [GtkChild]
    private Hdy.SearchBar search_bar { get; private set; }

    [GtkChild]
    private Gtk.SearchEntry search_entry { get; private set; }

    [GtkChild]
    private Gtk.ScrolledWindow logs_scroller;

    [GtkChild]
    private Gtk.TreeView logs_view;

    [GtkChild]
    private Gtk.CellRendererText log_renderer;

    private Gtk.ListStore logs_store = new Gtk.ListStore.newv({
            typeof(string)
    });

    private Gtk.TreeModelFilter logs_filter;

    private string[] logs_filter_terms = new string[0];

    private bool update_logs = true;
    private Geary.Logging.Record? first_pending = null;

    private bool autoscroll = true;

    private Geary.AccountInformation? account_filter = null;

    private bool listener_installed = false;


    /** Emitted when the number of selected records changes. */
    public signal void record_selection_changed();


    public InspectorLogView(Application.Configuration config,
                            Geary.AccountInformation? filter_by = null) {
        GLib.Settings system = config.gnome_interface;
        system.bind(
            "monospace-font-name",
            this.log_renderer, "font",
            SettingsBindFlags.DEFAULT
        );

        this.search_bar.connect_entry(this.search_entry);
        this.account_filter = filter_by;
    }

    /** Loads log records from the logging system into the view. */
    public void load(Geary.Logging.Record first, Geary.Logging.Record? last) {
        if (last == null) {
            // Install the listener then start adding the backlog
            // (ba-doom-tish) so to avoid the race.
            Geary.Logging.set_log_listener(this.on_log_record);
            this.listener_installed = true;
        }

        Gtk.ListStore logs_store = this.logs_store;
        Geary.Logging.Record? logs = first;
        int index = 0;
        while (logs != last) {
            if (should_append(logs)) {
                string message = logs.format();
                Gtk.TreeIter iter;
                logs_store.insert(out iter, index++);
                logs_store.set_value(iter, COL_MESSAGE, message);
            }
            logs = logs.next;
        }

        this.logs_filter = new Gtk.TreeModelFilter(logs_store, null);
        this.logs_filter.set_visible_func((model, iter) => {
                bool ret = true;
                if (this.logs_filter_terms.length > 0) {
                    ret = true;
                    Value value;
                    model.get_value(iter, COL_MESSAGE, out value);
                    string? message = (string) value;
                    if (message != null) {
                        message = message.casefold();
                        foreach (string term in this.logs_filter_terms) {
                            if (!message.contains(term)) {
                                ret = false;
                                break;
                            }
                        }
                    }
                }
                return ret;
            });

        this.logs_view.set_model(this.logs_filter);
    }

    /** {@inheritDoc} */
    public override void destroy() {
        if (this.listener_installed) {
            Geary.Logging.set_log_listener(null);
        }
        base.destroy();
    }

    /** Forwards a key press event to the search entry. */
    public bool handle_key_press(Gdk.EventKey event) {
        return this.search_entry.key_press_event(event);
    }

    /** Returns the number of currently selected log records. */
    public int count_selected_records() {
        return this.logs_view.get_selection().count_selected_rows();
    }

    /** Enables and disables updating log records as new ones arrive. */
    public void enable_log_updates(bool enabled) {
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

    /** Saves all log records to the given output stream. */
    public void save(GLib.DataOutputStream out,
                     Inspector.TextFormat format,
                     bool save_all,
                     GLib.Cancellable? cancellable)
        throws GLib.Error {
        if (format == MARKDOWN) {
            out.put_string("```\n");
        }
        string line_sep = format.get_line_separator();
        Gtk.TreeModel model = this.logs_view.model;
        if (save_all) {
            // Save all rows selected
            Gtk.TreeIter? iter;
            bool valid = model.get_iter_first(out iter);
            while (valid && !cancellable.is_cancelled()) {
                save_record(model, iter, @out, cancellable);
                out.put_string(line_sep);
                valid = model.iter_next(ref iter);
            }
        } else {
            // Save only selected
            GLib.Error? inner_err = null;
            this.logs_view.get_selection().selected_foreach(
                (model, path, iter) => {
                    if (inner_err == null) {
                        try {
                            save_record(model, iter, @out, cancellable);
                            out.put_string(line_sep);
                        } catch (GLib.Error err) {
                            inner_err = err;
                        }
                    }
                }
            );
            if (inner_err != null) {
                throw inner_err;
            }
        }
        if (format == MARKDOWN) {
            out.put_string("```\n");
        }
    }

    private inline void save_record(Gtk.TreeModel model,
                                    Gtk.TreeIter iter,
                                    GLib.DataOutputStream @out,
                                    GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.Value value;
        model.get_value(iter, COL_MESSAGE, out value);
        string? message = (string) value;
        if (message != null) {
            out.put_string(message);
        }
    }

    private inline bool should_append(Geary.Logging.Record record) {
        record.fill_well_known_sources();
        return (
            record.account == null ||
            this.account_filter == null ||
            record.account.information == this.account_filter
        );
    }

    private void update_scrollbar() {
        Gtk.Adjustment adj = this.logs_scroller.get_vadjustment();
        adj.set_value(adj.upper - adj.page_size);
    }

    private void update_logs_filter() {
        string cleaned =
            Geary.String.reduce_whitespace(this.search_entry.text).casefold();
        this.logs_filter_terms = cleaned.split(" ");
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
    private void on_logs_size_allocate() {
        if (this.autoscroll) {
            update_scrollbar();
        }
    }

    [GtkCallback]
    private void on_logs_search_changed() {
        update_logs_filter();
    }

    [GtkCallback]
    private void on_logs_selection_changed() {
        record_selection_changed();
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

}

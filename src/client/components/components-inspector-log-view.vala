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
    private const int COL_ACCOUNT = 1;
    private const int COL_DOMAIN = 2;


    private class SidebarRow : Gtk.ListBoxRow {


        public enum RowType { ACCOUNT, INTERNAL_DOMAIN, EXTERNAL_DOMAIN }


        public RowType row_type { get; private set; }

        public string id  { get; private set; }

        public bool enabled {
            get { return this.enabled_toggle.active; }
            set { this.enabled_toggle.active = value; }
        }

        private Gtk.CheckButton enabled_toggle = new Gtk.CheckButton();


        public SidebarRow(RowType type, string label, string id) {
            this.row_type  = type;
            this.id = id;

            var label_widget = new Gtk.Label(label);
            label_widget.hexpand = true;
            label_widget.xalign = 0.0f;

            this.enabled_toggle.toggled.connect(
                () => { notify_property("enabled"); }
            );

            var grid = new Gtk.Grid();
            grid.orientation = HORIZONTAL;
            grid.add(label_widget);
            grid.add(this.enabled_toggle);
            add(grid);

            show_all();
        }

    }


    /** Determines if the log record search user interface is shown. */
    public bool search_mode_enabled {
        get { return this.search_bar.search_mode_enabled; }
        set { this.search_bar.search_mode_enabled = value; }
    }

    [GtkChild] private unowned Hdy.SearchBar search_bar;

    [GtkChild] private unowned Gtk.SearchEntry search_entry;

    [GtkChild] private unowned Gtk.ListBox sidebar;

    [GtkChild] private unowned Gtk.ScrolledWindow logs_scroller;

    [GtkChild] private unowned Gtk.TreeView logs_view;

    [GtkChild] private unowned Gtk.CellRendererText log_renderer;

    private Gtk.ListStore logs_store = new Gtk.ListStore.newv({
            typeof(string),
            typeof(string),
            typeof(string)
    });

    private Gtk.TreeModelFilter logs_filter;

    private string[] logs_filter_terms = new string[0];

    private bool update_logs = true;
    private Geary.Logging.Record? first_pending = null;

    private bool autoscroll = true;

    private Gee.Set<string> seen_accounts = new Gee.HashSet<string>();
    private Gee.Set<string> suppressed_accounts = new Gee.HashSet<string>();

    private Gee.Set<string> seen_domains = new Gee.HashSet<string>();

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

        // Prefill well-known engine logging domains
        add_domain(Geary.App.ConversationMonitor.LOGGING_DOMAIN);
        add_domain(Geary.Imap.ClientService.LOGGING_DOMAIN);
        add_domain(Geary.Imap.ClientService.DESERIALISATION_LOGGING_DOMAIN);
        add_domain(Geary.Imap.ClientService.PROTOCOL_LOGGING_DOMAIN);
        add_domain(Geary.Imap.ClientService.REPLAY_QUEUE_LOGGING_DOMAIN);
        add_domain(Geary.Smtp.ClientService.LOGGING_DOMAIN);
        add_domain(Geary.Smtp.ClientService.PROTOCOL_LOGGING_DOMAIN);

        this.search_bar.connect_entry(this.search_entry);
        this.sidebar.set_header_func(this.sidebar_header_update);
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
            update_record(logs, logs_store, index++);
            logs = logs.next;
        }

        this.logs_filter = new Gtk.TreeModelFilter(this.logs_store, null);
        this.logs_filter.set_visible_func(log_filter_func);

        this.logs_view.set_model(this.logs_filter);
    }

    /** Clears all log records from the view. */
    public void clear() {
        this.logs_store.clear();
        this.first_pending = null;
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
                update_record(logs, this.logs_store, -1);
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

    private void add_account(Geary.AccountInformation account) {
        if (this.seen_accounts.add(account.id)) {
            var row = new SidebarRow(ACCOUNT, account.display_name, account.id);
            row.enabled = (
                this.account_filter == null ||
                this.account_filter.id == account.id
            );
            row.notify["enabled"].connect(this.on_account_enabled_changed);
            for (int i = 0;; i++) {
                var existing = this.sidebar.get_row_at_index(i) as SidebarRow;
                if (existing == null ||
                    existing.row_type != ACCOUNT ||
                    existing.id.collate(row.id) > 0) {
                    this.sidebar.insert(row, i);
                    break;
                }
            }
        }
    }

    private void add_domain(string? domain) {
        var safe_domain = domain ?? "(none)";
        if (this.seen_domains.add(domain)) {
            var type = (
                safe_domain.down().has_prefix(Geary.Logging.DOMAIN.down())
                ? SidebarRow.RowType.INTERNAL_DOMAIN
                : SidebarRow.RowType.EXTERNAL_DOMAIN
            );
            var row = new SidebarRow(type, safe_domain, safe_domain);
            row.enabled = !Geary.Logging.is_suppressed_domain(domain ?? "");
            row.notify["enabled"].connect(this.on_domain_enabled_changed);
            int i = 0;
            for (;; i++) {
                var existing = this.sidebar.get_row_at_index(i) as SidebarRow;
                if (existing == null ||
                    existing.row_type == type) {
                    break;
                }
            }
            for (;; i++) {
                var existing = this.sidebar.get_row_at_index(i) as SidebarRow;
                if (existing == null ||
                    existing.row_type != type ||
                    existing.id.collate(row.id) > 0) {
                    this.sidebar.insert(row, i);
                    break;
                }
            }
        }
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

    private inline void update_record(Geary.Logging.Record record,
                                      Gtk.ListStore store,
                                      int position) {
        record.fill_well_known_sources();
        if (record.account != null) {
            add_account(record.account.information);
        }
        add_domain(record.domain);

        assert(record.format() != null);

        var account = record.account;
        store.insert_with_values(
            null,
            position,
            COL_MESSAGE, record.format(),
            COL_ACCOUNT, account != null ? account.information.id : "",
            COL_DOMAIN, record.domain ?? ""
        );
    }

    private void sidebar_header_update(Gtk.ListBoxRow current_row,
                                       Gtk.ListBoxRow? previous_row) {
        Gtk.Widget? header = null;
        var current = current_row as SidebarRow;
        var previous = previous_row as SidebarRow;
        if (current != null &&
            (previous == null || current.row_type != previous.row_type)) {
            header = new Gtk.Separator(HORIZONTAL);
        }
        current_row.set_header(header);
    }

    private bool log_filter_func(Gtk.TreeModel model, Gtk.TreeIter iter) {
        GLib.Value value;
        model.get_value(iter, COL_ACCOUNT, out value);
        var account = (string) value;
        var show_row = (
            account == "" || !(account in this.suppressed_accounts)
        );

        if (show_row) {
            model.get_value(iter, COL_DOMAIN, out value);
            var domain = (string) value;
            show_row = !Geary.Logging.is_suppressed_domain(domain);
        }

        model.get_value(iter, COL_MESSAGE, out value);
        string message = (string) value;
        if (show_row && this.logs_filter_terms.length > 0) {
            var folded_message = message.casefold();
            foreach (string term in this.logs_filter_terms) {
                if (!folded_message.contains(term)) {
                    show_row = false;
                    break;
                }
            }
        }

        // If the message looks like an inspector mark, show
        // it anyway. There's some whitespace at the end, so
        // just check the last few chars of the message.
        if (!show_row &&
            message.index_of("---- 8< ----", message.length - 15) >= 0) {
            show_row = true;
        }

        return show_row;
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

    [GtkCallback]
    private void on_sidebar_row_activated(Gtk.ListBox list,
                                          Gtk.ListBoxRow activated) {
        var row = activated as SidebarRow;
        if (row != null) {
            row.enabled = !row.enabled;
        }
    }

    private void on_log_record(Geary.Logging.Record record) {
        if (this.update_logs) {
            GLib.MainContext.default().invoke(() => {
                    update_record(record, this.logs_store, -1);
                    return GLib.Source.REMOVE;
                });
        } else if (this.first_pending == null) {
            this.first_pending = record;
        }
    }

    private void on_account_enabled_changed(GLib.Object object,
                                            GLib.ParamSpec param) {
        var row = object as SidebarRow;
        if (row != null) {
            if ((row.enabled && this.suppressed_accounts.remove(row.id)) ||
                (!row.enabled && this.suppressed_accounts.add(row.id))) {
                update_logs_filter();
            }
        }
    }

    private void on_domain_enabled_changed(GLib.Object object,
                                           GLib.ParamSpec param) {
        var row = object as SidebarRow;
        if (row != null) {
            if ((row.enabled && Geary.Logging.unsuppress_domain(row.id)) ||
                (!row.enabled && Geary.Logging.suppress_domain(row.id))) {
                update_logs_filter();
            }
        }
    }

}

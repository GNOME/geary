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
public class Components.InspectorLogView : Gtk.Box {


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

            var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 0);
            box.append(label_widget);
            box.append(this.enabled_toggle);
            this.child = box;
        }

    }


    private class RecordRow : Gtk.Box {

        public Geary.Logging.Record? record {
            get { return this._record; }
            set {
                this._record = value;
                update();
            }
        }
        private Geary.Logging.Record? _record = null;

        private unowned Gtk.Label message_label;

        construct {
            this.orientation = Gtk.Orientation.HORIZONTAL;
            this.spacing = 6;

            var label = new Gtk.Label("");
            label.selectable = true;
            label.add_css_class("monospace");
            append(label);
            this.message_label = label;
        }

        private void update() {
            if (this.record == null) {
                this.message_label.label = "";
            } else {
                this.message_label.label = this.record.format();
            }
        }
    }


    /** Determines if the log record search user interface is shown. */
    public bool search_mode_enabled {
        get { return this.search_bar.search_mode_enabled; }
        set { this.search_bar.search_mode_enabled = value; }
    }

    [GtkChild] private unowned Gtk.SearchBar search_bar;

    [GtkChild] private unowned Gtk.SearchEntry search_entry;

    [GtkChild] private unowned Gtk.ListBox sidebar;

    [GtkChild] private unowned Gtk.ScrolledWindow logs_scroller;

    [GtkChild] private unowned Gtk.ListView logs_view;

    [GtkChild] private unowned Gtk.MultiSelection selection;

    [GtkChild] private unowned GLib.ListStore logs_store;

    [GtkChild] private unowned Gtk.CustomFilter logs_filter;
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


    public InspectorLogView(Geary.AccountInformation? filter_by = null) {
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

        this.logs_filter.set_filter_func(log_filter_func);
    }

    /** Loads log records from the logging system into the view. */
    public void load(Geary.Logging.Record first, Geary.Logging.Record? last) {
        if (last == null) {
            // Install the listener then start adding the backlog
            // (ba-doom-tish) so to avoid the race.
            Geary.Logging.set_log_listener(this.on_log_record);
            this.listener_installed = true;
        }

        Geary.Logging.Record? logs = first;
        int index = 0;
        while (logs != last) {
            update_record(logs, this.logs_store, index++);
            logs = logs.next;
        }
    }

    /** Clears all log records from the view. */
    public void clear() {
        this.logs_store.remove_all();
        this.first_pending = null;
    }

    ~InspectorLogView() {
        if (this.listener_installed) {
            Geary.Logging.set_log_listener(null);
        }
    }

    /** Returns the number of currently selected log records. */
    public uint count_selected_records() {
        return (uint) this.selection.get_selection().get_size();
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

        if (save_all) {
            // Save all rows selected
            for (uint i = 0; i < this.logs_store.get_n_items(); i++) {
                if (cancellable.is_cancelled())
                    break;

                var record = (Geary.Logging.Record) this.logs_store.get_item(i);
                out.put_string(record.format());
                out.put_string(line_sep);
            }
        } else {
            // Save only selected
            Gtk.Bitset selected = this.selection.get_selection();
            for (uint i = 0; i < selected.get_size(); i++) {
                if (cancellable.is_cancelled())
                    break;

                uint position = selected.get_nth(i);
                var record = (Geary.Logging.Record) this.logs_store.get_item(position);
                assert(record != null);

                out.put_string(record.format());
                out.put_string(line_sep);
            }
        }
        if (format == MARKDOWN) {
            out.put_string("```\n");
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
        this.logs_filter.changed(Gtk.FilterChange.DIFFERENT);
    }

    private inline void update_record(Geary.Logging.Record record,
                                      GLib.ListStore store,
                                      int position) {
        record.fill_well_known_sources();
        if (record.account != null) {
            add_account(record.account.information);
        }
        add_domain(record.domain);

        assert(record.format() != null);

        store.insert(position, record);
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

    private bool log_filter_func(GLib.Object object) {
        unowned var record = (Geary.Logging.Record) object;

        var account = record.account;
        bool show_row = (
            account == null || !(account.information.id in this.suppressed_accounts)
        );

        if (show_row) {
            show_row = !Geary.Logging.is_suppressed_domain(record.domain ?? "");
        }

        string message = record.format();
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
    private void on_logs_search_changed() {
        update_logs_filter();
    }

    [GtkCallback]
    private void on_logs_selection_changed(Gtk.SelectionModel selection,
                                           uint position,
                                           uint changed) {
        record_selection_changed();
    }

    [GtkCallback]
    private void on_item_factory_setup(Object object) {
        unowned var item = (Gtk.ListItem) object;

        item.child = new RecordRow();
    }

    [GtkCallback]
    private void on_item_factory_bind(Object object) {
        unowned var item = (Gtk.ListItem) object;
        unowned var record = (Geary.Logging.Record) item.item;
        unowned var row = (RecordRow) item.child;

        row.record = record;
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

/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Displays technical details when a problem has been reported.
 */
[GtkTemplate (ui = "/org/gnome/Geary/problem-details-dialog.ui")]
public class Dialogs.ProblemDetailsDialog : Adw.Dialog {


    private const string ACTION_SEARCH_TOGGLE = "toggle-search";
    private const string ACTION_SEARCH_ACTIVATE = "activate-search";

    private const ActionEntry[] EDIT_ACTIONS = {
        { Action.Edit.COPY,  on_copy_clicked },
    };

    private const ActionEntry[] WINDOW_ACTIONS = {
        { ACTION_SEARCH_TOGGLE, on_logs_search_toggled, null, "false" },
        { ACTION_SEARCH_ACTIVATE, on_logs_search_activated },
    };

    public static void add_accelerators(Application.Client app) {
        app.add_window_accelerators(ACTION_SEARCH_ACTIVATE, { "<Ctrl>F" } );
    }


    [GtkChild] private unowned Gtk.Stack stack;

    [GtkChild] private unowned Gtk.Button copy_button;

    [GtkChild] private unowned Gtk.ToggleButton search_button;

    private Components.InspectorErrorView error_pane;
    private Components.InspectorLogView log_pane;
    private Components.InspectorSystemView system_pane;

    private Geary.ErrorContext error;
    private Geary.AccountInformation? account;
    private Geary.ServiceInformation? service;


    public ProblemDetailsDialog(Application.Client application,
                                Geary.ProblemReport report) {
        Geary.AccountProblemReport? account_report =
            report as Geary.AccountProblemReport;
        Geary.ServiceProblemReport? service_report =
            report as Geary.ServiceProblemReport;

        this.error = report.error;
        this.account = (account_report != null) ? account_report.account : null;
        this.service = (service_report != null) ? service_report.service : null;

        // Edit actions
        GLib.SimpleActionGroup edit_actions = new GLib.SimpleActionGroup();
        edit_actions.add_action_entries(EDIT_ACTIONS, this);
        insert_action_group(Action.Edit.GROUP_NAME, edit_actions);

        // Window actions
        GLib.SimpleActionGroup window_actions = new GLib.SimpleActionGroup();
        window_actions.add_action_entries(WINDOW_ACTIONS, this);
        insert_action_group(Action.Window.GROUP_NAME, window_actions);

        this.error_pane = new Components.InspectorErrorView(
            error, account, service
        );

        this.log_pane = new Components.InspectorLogView(account);
        this.log_pane.load(report.earliest_log, report.latest_log);
        this.log_pane.record_selection_changed.connect(
            on_logs_selection_changed
        );

        this.system_pane = new Components.InspectorSystemView(
            application
        );

        /// Translators: Title for problem report dialog error
        /// information pane
        this.stack.add_titled(this.error_pane, "error_pane", _("Details"));
        /// Translators: Title for problem report dialog logs pane
        this.stack.add_titled(this.log_pane, "log_pane", _("Logs"));
        /// Translators: Title for problem report system information
        /// pane
        this.stack.add_titled(this.system_pane, "system_pane", _("System"));
    }

    [GtkCallback]
    private bool on_key_pressed(Gtk.EventControllerKey controller,
                                uint keyval,
                                uint keycode,
                                Gdk.ModifierType state) {
        bool ret = Gdk.EVENT_PROPAGATE;

        if (this.log_pane.search_mode_enabled &&
            keyval == Gdk.Key.Escape) {
            // Manually deactivate search so the button stays in sync
            this.search_button.set_active(false);
            ret = Gdk.EVENT_STOP;
        }

        if (ret == Gdk.EVENT_PROPAGATE &&
            this.log_pane.search_mode_enabled) {
            // Ensure <Space> and others are passed to the search
            // entry before getting used as an accelerator.
            ret = controller.forward(this.log_pane);
        }

        //XXX GTK4 not sure how to handle this
        // if (ret == Gdk.EVENT_PROPAGATE) {
        //     ret = base.key_press_event(event);
        // }

        if (ret == Gdk.EVENT_PROPAGATE &&
            !this.log_pane.search_mode_enabled) {
            // Nothing has handled the event yet, and search is not
            // active, so see if we want to activate it now.
            ret = controller.forward(this.log_pane);
            if (ret == Gdk.EVENT_STOP) {
                this.search_button.set_active(true);
            }
        }

        return ret;
    }

    private async void save(GLib.File dest,
                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.FileIOStream dest_io = yield dest.replace_readwrite_async(
            null,
            false,
            GLib.FileCreateFlags.NONE,
            GLib.Priority.DEFAULT,
            cancellable
        );
        GLib.DataOutputStream out = new GLib.DataOutputStream(
            new GLib.BufferedOutputStream(dest_io.get_output_stream())
        );

        this.error_pane.save(
            @out, Components.Inspector.TextFormat.PLAIN, cancellable
        );
        out.put_string("\n");
        this.system_pane.save(
            @out, Components.Inspector.TextFormat.PLAIN, cancellable
        );
        out.put_string("\n");
        this.log_pane.save(
            @out, Components.Inspector.TextFormat.PLAIN, true, cancellable
        );

        yield out.close_async();
        yield dest_io.close_async();
    }

    private void update_ui() {
        bool logs_visible = this.stack.visible_child == this.log_pane;
        uint logs_selected = this.log_pane.count_selected_records();
        this.copy_button.set_sensitive(!logs_visible || logs_selected > 0);
        this.search_button.set_visible(logs_visible);
    }

    [GtkCallback]
    private void on_visible_child_changed() {
        update_ui();
    }

    private void on_copy_clicked() {
        GLib.MemoryOutputStream bytes = new GLib.MemoryOutputStream.resizable();
        GLib.DataOutputStream out = new GLib.DataOutputStream(bytes);
        try {
            if (this.stack.visible_child == this.error_pane) {
                this.error_pane.save(
                    @out, Components.Inspector.TextFormat.MARKDOWN, null
                );
            } else if (this.stack.visible_child == this.log_pane) {
                this.log_pane.save(
                    @out, Components.Inspector.TextFormat.MARKDOWN, false, null
                );
            } else if (this.stack.visible_child == this.system_pane) {
                this.system_pane.save(
                    @out, Components.Inspector.TextFormat.MARKDOWN, null
                );
            }

            // Ensure the data is a valid string
            out.put_byte(0, null);
        } catch (GLib.Error err) {
            warning(
                "Error saving inspector data for clipboard: %s",
                err.message
            );
        }

        string clipboard_value = (string) bytes.get_data();
        if (!Geary.String.is_empty(clipboard_value)) {
            get_clipboard().set_text(clipboard_value);
        }
    }

    [GtkCallback]
    private void on_save_as_clicked() {
        save_as.begin();
    }

    private async void save_as() {
        var dialog = new Gtk.FileDialog();
        dialog.title = _("Save As");
        dialog.accept_label = _("Save As");
        dialog.initial_name = new DateTime.now_local().format(
            "Geary Problem Report - %F %T.txt"
        );

        try {
            File? file = yield dialog.save(get_root() as Gtk.Window, null);
            if (file != null)
                yield this.save(file, null);
        } catch (Error err) {
            warning("Failed to save problem report data: %s", err.message);
        }
    }

    private void on_logs_selection_changed() {
        update_ui();
    }

    private void on_logs_search_toggled(GLib.SimpleAction action,
                                        GLib.Variant? param) {
        bool enabled = !((bool) action.state);
        this.log_pane.search_mode_enabled = enabled;
        action.set_state(enabled);
    }

    private void on_logs_search_activated() {
        this.search_button.set_active(true);
    }
}

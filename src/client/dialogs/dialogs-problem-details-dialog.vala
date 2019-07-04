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
public class Dialogs.ProblemDetailsDialog : Hdy.Dialog {


    private const string ACTION_CLOSE = "problem-details-close";
    private const string ACTION_SEARCH_TOGGLE = "toggle-search";
    private const string ACTION_SEARCH_ACTIVATE = "activate-search";

    private const ActionEntry[] action_entries = {
        {GearyApplication.ACTION_CLOSE, on_close },
        {GearyApplication.ACTION_COPY,  on_copy_clicked },
        {ACTION_CLOSE,                  on_close },
        {ACTION_SEARCH_TOGGLE,          on_logs_search_toggled, null, "false" },
        {ACTION_SEARCH_ACTIVATE,        on_logs_search_activated },
    };

    public static void add_window_accelerators(GearyApplication app) {
        app.add_window_accelerators(ACTION_CLOSE, { "Escape" } );
        app.add_window_accelerators(ACTION_SEARCH_ACTIVATE, { "<Ctrl>F" } );
    }


    [GtkChild]
    private Gtk.Stack stack;

    [GtkChild]
    private Gtk.Button copy_button;

    [GtkChild]
    private Gtk.ToggleButton search_button;

    private Components.InspectorErrorView error_pane;
    private Components.InspectorLogView log_pane;
    private Components.InspectorSystemView system_pane;

    private Geary.ErrorContext error;
    private Geary.AccountInformation? account;
    private Geary.ServiceInformation? service;


    public ProblemDetailsDialog(MainWindow parent,
                                Geary.ErrorContext error,
                                Geary.AccountInformation? account,
                                Geary.ServiceInformation? service) {
        Object(
            transient_for: parent,
            use_header_bar: 1
        );
        set_default_size(600, 400);

        this.error = error;
        this.account = account;
        this.service = service;

        GLib.SimpleActionGroup actions = new GLib.SimpleActionGroup();
        actions.add_action_entries(ProblemDetailsDialog.action_entries, this);
        insert_action_group("win", actions);

        this.error_pane = new Components.InspectorErrorView(
            error, account, service
        );

        this.log_pane = new Components.InspectorLogView(
            parent.application.config, account
        );
        this.log_pane.load();
        this.log_pane.record_selection_changed.connect(
            on_logs_selection_changed
        );

        this.system_pane = new Components.InspectorSystemView(
            parent.application
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

    public override bool key_press_event(Gdk.EventKey event) {
        bool ret = Gdk.EVENT_PROPAGATE;

        if (this.log_pane.search_mode_enabled &&
            event.keyval == Gdk.Key.Escape) {
            // Manually deactivate search so the button stays in sync
            this.search_button.set_active(false);
            ret = Gdk.EVENT_STOP;
        }

        if (ret == Gdk.EVENT_PROPAGATE &&
            this.log_pane.search_mode_enabled) {
            // Ensure <Space> and others are passed to the search
            // entry before getting used as an accelerator.
            ret = this.log_pane.handle_key_press(event);
        }

        if (ret == Gdk.EVENT_PROPAGATE) {
            ret = base.key_press_event(event);
        }

        if (ret == Gdk.EVENT_PROPAGATE &&
            !this.log_pane.search_mode_enabled) {
            // Nothing has handled the event yet, and search is not
            // active, so see if we want to activate it now.
            ret = this.log_pane.handle_key_press(event);
            if (ret == Gdk.EVENT_STOP) {
                this.search_button.set_active(true);
            }
        }

        return ret;
    }

    private async void save(string path,
                            GLib.Cancellable? cancellable)
        throws GLib.Error {
        GLib.File dest = GLib.File.new_for_path(path);
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

        this.error_pane.save(@out, cancellable);
        out.put_byte('\n');
        out.put_byte('\n');
        this.system_pane.save(@out, cancellable);
        out.put_byte('\n');
        out.put_byte('\n');
        this.log_pane.save(@out, true, cancellable);

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
                this.error_pane.save(@out, null);
            } else if (this.stack.visible_child == this.log_pane) {
                this.log_pane.save(@out, false, null);
            } else if (this.stack.visible_child == this.system_pane) {
                this.system_pane.save(@out, null);
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
            new GLib.DateTime.now_local().format(
                "Geary Problem Report - %F %T.txt"
            )
        );

        if (chooser.run() == Gtk.ResponseType.ACCEPT) {
            this.save.begin(
                chooser.get_filename(),
                null,
                (obj, res) => {
                    try {
                        this.save.end(res);
                    } catch (GLib.Error err) {
                        warning(
                            "Failed to save problem report data: %s", err.message
                        );
                    }
                }
            );
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

    private void on_close() {
        destroy();
    }

}

/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Displays application-wide or important account-related messages.
 */
[GtkTemplate (ui = "/org/gnome/Geary/main-window-info-bar.ui")]
public class MainWindowInfoBar : Gtk.InfoBar {


    private enum ResponseType { COPY, DETAILS, RETRY; }


    /** If reporting a problem returns, the specific problem else null. */
    public Geary.Account.Problem? problem { get; private set; default = null; }

    /** If reporting a problem for an account, returns the account else null. */
    public Geary.Account? account { get; private set; default = null; }

    /** If reporting a problem, returns the error thrown, if any. */
    public Error error { get; private set; default = null; }


    /** Emitted when the user clicks the Retry button, if any. */
    public signal void retry();


    [GtkChild]
    private Gtk.Label title;

    [GtkChild]
    private Gtk.Label description;

    [GtkChild]
    private Gtk.Grid problem_details;

    [GtkChild]
    private Gtk.TextView detail_text;


    public MainWindowInfoBar.for_problem(Geary.Account.Problem problem,
                                         Geary.Account account,
                                         GLib.Error? error) {
        string name = account.information.display_name;
        Gtk.MessageType type = Gtk.MessageType.WARNING;
        string title = "";
        string descr = "";
        string? retry = null;
        bool show_close = false;
        switch (problem) {
        case Geary.Account.Problem.DATABASE_FAILURE:
            type = Gtk.MessageType.ERROR;
            title = _("A database problem has occurred");
            descr = _("Messages for %s must be downloaded again.").printf(name);
            show_close = true;
            break;

        case Geary.Account.Problem.HOST_UNREACHABLE:
            // XXX should really be displaying the server name here
            title = _("Could not contact server");
            descr = _("Please check %s server names are correct and are working.").printf(name);
            show_close = true;
            break;

        case Geary.Account.Problem.NETWORK_UNAVAILABLE:
            title = _("Not connected to the Internet");
            descr = _("Please check your connection to the Internet.");
            show_close = true;
            break;

        case Geary.Account.Problem.RECV_EMAIL_ERROR:
            type = Gtk.MessageType.ERROR;
            title = _("A problem occurred checking for new mail");
            descr = _("New messages can not be received for %s, try again in a moment").printf(name);
            retry = _("Retry checking for new mail");
            break;

        case Geary.Account.Problem.RECV_EMAIL_LOGIN_FAILED:
            title = _("Incoming mail password required");
            descr = _("Messages cannot be received for %s without the correct password.").printf(name);
            retry = _("Retry receiving email, you will be prompted for a password");
            break;

        case Geary.Account.Problem.SEND_EMAIL_ERROR:
            type = Gtk.MessageType.ERROR;
            title = _("A problem occurred sending mail");
            descr = _("A message was unable to be sent for %s, try again in a moment").printf(name);
            retry = _("Retry sending queued messages");
            break;

        case Geary.Account.Problem.SEND_EMAIL_LOGIN_FAILED:
            title = _("Outgoing mail password required");
            descr = _("Messages cannot be sent for %s without the correct password.").printf(name);
            retry = _("Retry sending queued messages, you will be prompted for a password");
            break;

        default:
            debug("Un-handled problem type for %s: %s".printf(
                      account.information.id, problem.to_string()
                  ));
            break;
        }

        this(type, title, descr, show_close);
        this.problem = problem;
        this.account = account;
        this.error = error;

        if (this.error != null) {
            Gtk.Button details = add_button(_("_Details"), ResponseType.DETAILS);
            details.tooltip_text = _("View technical details about the error");
        }

        if (retry != null) {
            Gtk.Button retry_btn = add_button(_("_Retry"), ResponseType.RETRY);
            retry_btn.tooltip_text = retry;
        }
    }

    protected MainWindowInfoBar(Gtk.MessageType type,
                                string title,
                                string description,
                                bool show_close) {
        this.message_type = type;
        this.title.label = title;
        this.description.label = description;
        this.show_close_button = show_close;
    }

    private string format_details() {
        string type = "";
        if (this.error != null) {
            const string QUARK_SUFFIX = "-quark";
            string ugly_domain = this.error.domain.to_string();
            if (ugly_domain.has_suffix(QUARK_SUFFIX)) {
                ugly_domain = ugly_domain.substring(
                    0, ugly_domain.length - QUARK_SUFFIX.length
                );
            }
            StringBuilder nice_domain = new StringBuilder();
            foreach (string part in ugly_domain.split("_")) {
                nice_domain.append(part.up(1));
                nice_domain.append(part.substring(1));
            }

            type = "%s %i".printf(nice_domain.str, this.error.code);
        }

        return """Geary version: %s
GTK+ version: %u.%u.%u
Desktop: %s
Error type: %s
Message: %s
""".printf(
        GearyApplication.VERSION,
        Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version(),
        Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "Unknown",
        type,
        (this.error != null) ? error.message : ""
    );
    }

    private void show_details() {
        this.detail_text.buffer.text = format_details();

        // Would love to construct the dialog in Builder, but we to
        // construct the dialog manually since we can't adjust the
        // Headerbar setting afterwards. If the user re-clicks on the
        // Details button to re-show it, a whole bunch of GTK
        // criticals are spewed and the dialog appears b0rked, so just
        // do it from scratch ever time anyway.
        bool use_header = Gtk.Settings.get_default().gtk_dialogs_use_header;
        Gtk.DialogFlags flags = Gtk.DialogFlags.MODAL;
        if (use_header) {
            flags |= Gtk.DialogFlags.USE_HEADER_BAR;
        }
        Gtk.Dialog dialog = new Gtk.Dialog.with_buttons(
            _("Details"), // same as the button
            get_toplevel() as Gtk.Window,
            flags
        );
        dialog.set_default_size(600, -1);
        dialog.get_content_area().add(this.problem_details);

        Gtk.HeaderBar? header_bar = dialog.get_header_bar() as Gtk.HeaderBar;
        use_header = (header_bar != null);
        if (use_header) {
            header_bar.show_close_button = true;
        } else {
            dialog.add_button(_("_Close"), Gtk.ResponseType.CLOSE);
        }

        Gtk.Widget copy = dialog.add_button(
            _("Copy to Clipboard"), ResponseType.COPY
        );
        copy.tooltip_text =
            _("Copy technical details to clipboard for pasting into an email or bug report");


        dialog.set_default_response(ResponseType.COPY);
        dialog.response.connect(on_details_response);
        dialog.show();
        copy.grab_focus();
    }

    private void copy_details() {
        get_clipboard(Gdk.SELECTION_CLIPBOARD).set_text(format_details(), -1);
    }

    [GtkCallback]
    private void on_info_bar_response(int response) {
        switch(response) {
        case ResponseType.DETAILS:
            show_details();
            break;

        case ResponseType.RETRY:
            retry();
            this.hide();
            break;

        default:
            this.hide();
            break;
        }
    }

    [GtkCallback]
    private void on_hide() {
        this.parent.remove(this);
    }

    private void on_details_response(Gtk.Dialog dialog, int response) {
        switch(response) {
        case ResponseType.COPY:
            copy_details();
            break;

        default:
            // fml
            dialog.get_content_area().remove(this.problem_details);
            dialog.hide();
            break;
        }
    }


}

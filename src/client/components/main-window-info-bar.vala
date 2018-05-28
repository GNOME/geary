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

    /** If reporting a problem, returns the problem report else null. */
    public Geary.ProblemReport? report { get; private set; default = null; }

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


    public MainWindowInfoBar.for_problem(Geary.ProblemReport report) {
        Gtk.MessageType type = Gtk.MessageType.WARNING;
        string title = "";
        string descr = "";
        string? retry = null;
        bool show_generic = false;
        bool show_close = false;

        if (report is Geary.ServiceProblemReport) {
            Geary.ServiceProblemReport service_report = (Geary.ServiceProblemReport) report;
            Geary.Endpoint endpoint = service_report.service.endpoint;
            string account = service_report.account.display_name;
            string server = endpoint.remote_address.hostname;

            if (report.problem_type == Geary.ProblemType.CONNECTION_ERROR &&
                service_report.service.protocol == Geary.Service.IMAP) {
                // Translators: String substitution is the account name
                title = _("Problem connecting to incoming server for %s".printf(account));
                // Translators: String substitution is the server name
                descr = _("Could not connect to %s, check your Internet access and the server name and try again").printf(server);
                retry = _("Retry connecting now");

            } else if (report.problem_type == Geary.ProblemType.CONNECTION_ERROR &&
                       service_report.service.protocol == Geary.Service.SMTP) {
                // Translators: String substitution is the account name
                title = _("Problem connecting to outgoing server for %s".printf(account));
                // Translators: String substitution is the server name
                descr = _("Could not connect to %s, check your Internet access and the server name and try again").printf(server);
                retry = _("Try reconnecting now");
                retry = _("Retry connecting now");

            } else if (report.problem_type == Geary.ProblemType.NETWORK_ERROR &&
                       service_report.service.protocol == Geary.Service.IMAP) {
                // Translators: String substitution is the account name
                title = _("Problem with connection to incoming server for %s").printf(account);
                // Translators: String substitution is the server name
                descr = _("Network error talking to %s, check your Internet access and try again").printf(server);
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.NETWORK_ERROR &&
                       service_report.service.protocol == Geary.Service.SMTP) {
                // Translators: String substitution is the account name
                title = _("Problem with connection to outgoing server for %s").printf(account);
                // Translators: String substitution is the server name
                descr = _("Network error talking to %s, check your Internet access and try again").printf(server);
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.SERVER_ERROR &&
                       service_report.service.protocol == Geary.Service.IMAP) {
                // Translators: String substitution is the account name
                title = _("Problem communicating with incoming server for %s").printf(account);
                // Translators: String substitution is the server name
                descr = _("Geary did not understand a message from %s or vice versa, please file a bug report").printf(server);
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.SERVER_ERROR &&
                       service_report.service.protocol == Geary.Service.SMTP) {
                title = _("Problem communicating with outgoing mail server");
                // Translators: First string substitution is the server
                // name, second is the account name
                descr = _("Could not communicate with %s for %s, check the server name and try again in a moment").printf(server, account);
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.LOGIN_FAILED &&
                       service_report.service.protocol == Geary.Service.IMAP) {
                // Translators: String substitution is the account name
                title = _("Incoming mail server password required for %s").printf(account);
                descr = _("Messages cannot be received without the correct password.");
                retry = _("Retry receiving email, you will be prompted for a password");

            } else if (report.problem_type == Geary.ProblemType.LOGIN_FAILED &&
                       service_report.service.protocol == Geary.Service.SMTP) {
                // Translators: String substitution is the account name
                title = _("Outgoing mail server password required for %s").printf(account);
                descr = _("Messages cannot be sent without the correct password.");
                retry = _("Retry sending queued messages, you will be prompted for a password");

            } else if (report.problem_type == Geary.ProblemType.GENERIC_ERROR &&
                       service_report.service.protocol == Geary.Service.IMAP) {
                // Translators: String substitution is the account name
                title = _("A problem occurred checking mail for %s").printf(account);
                descr = _("Something went wrong, please file a bug report if the problem persists");
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.GENERIC_ERROR &&
                       service_report.service.protocol == Geary.Service.SMTP) {
                // Translators: String substitution is the account name
                title = _("A problem occurred sending mail for %s").printf(account);
                descr = _("Something went wrong, please file a bug report if the problem persists");
                retry = _("Retry sending queued messages");

            } else {
                debug("Un-handled service problem report: %s".printf(report.to_string()));
                show_generic = true;
            }
        } else if (report is Geary.AccountProblemReport) {
            Geary.AccountProblemReport account_report = (Geary.AccountProblemReport) report;
            string account = account_report.account.display_name;
            if (report.problem_type == Geary.ProblemType.DATABASE_FAILURE) {
                type = Gtk.MessageType.ERROR;
                title = _("A database problem has occurred");
                // Translators: String substitution is the account name
                descr = _("Messages for %s must be downloaded again.").printf(account);
                show_close = true;

            } else {
                debug("Un-handled account problem report: %s".printf(report.to_string()));
                show_generic = true;
            }
        } else {
            debug("Un-handled generic problem report: %s".printf(report.to_string()));
            show_generic = true;
        }

        if (show_generic) {
            title = _("Geary has encountered a problem");
            descr = _("Please check the technical details and report the problem if it persists.");
            show_close = true;
        }

        this(type, title, descr, show_close);
        this.report = report;

        if (this.report.error != null) {
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

        // Set the label and tooltip for the description in case it is
        // long enough to be ellipsized
        this.description.label = description;
        this.description.tooltip_text = description;

        this.show_close_button = show_close;
    }

    private string format_details() {
        Geary.ServiceProblemReport? service_report = this.report as Geary.ServiceProblemReport;
        Geary.AccountProblemReport? account_report = this.report as Geary.AccountProblemReport;

        StringBuilder details = new StringBuilder();
        details.append_printf(
            "Geary version: %s\n",
            GearyApplication.VERSION
        );
        details.append_printf(
            "GTK version: %u.%u.%u\n",
            Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version()
        );
        details.append_printf(
            "Desktop: %s\n",
            Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "Unknown"
        );
        details.append_printf(
            "Problem type: %s\n",
            this.report.problem_type.to_string()
        );
        if (account_report != null) {
            details.append_printf(
                "Account type: %s\n",
                account_report.account.service_provider.to_string()
            );
        }
        if (service_report != null) {
            details.append_printf(
                "Service type: %s\n",
                service_report.service.protocol.to_string()
            );
            details.append_printf(
                "Endpoint: %s\n",
                service_report.service.endpoint.to_string()
            );
        }
        if (this.report.error == null) {
            details.append("No error reported");
        } else {
            details.append_printf("Error type: %s\n", this.report.format_error_type());
            details.append_printf("Message: %s\n", this.report.error.message);
        }
        if (this.report.backtrace != null) {
            details.append("Back trace:\n");
            foreach (Geary.ProblemReport.StackFrame frame in this.report.backtrace) {
                details.append_printf(" - %s\n", frame.to_string());
            }
        }
        return details.str;
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
            flags,
            null
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

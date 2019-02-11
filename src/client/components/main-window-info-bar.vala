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


    private enum ResponseType { DETAILS, RETRY; }

    /** If reporting a problem, returns the problem report else null. */
    public Geary.ProblemReport? report { get; private set; default = null; }

    /** Emitted when the user clicks the Retry button, if any. */
    public signal void retry();


    [GtkChild]
    private Gtk.Label title;

    [GtkChild]
    private Gtk.Label description;


    public MainWindowInfoBar.for_problem(Geary.ProblemReport report) {
        Gtk.MessageType type = Gtk.MessageType.WARNING;
        string title = "";
        string descr = "";
        string? retry = null;
        bool show_generic = false;
        bool show_close = false;

        if (report is Geary.ServiceProblemReport) {
            Geary.ServiceProblemReport service_report = (Geary.ServiceProblemReport) report;
            string account = service_report.account.display_name;
            string server = service_report.service.host;

            if (report.problem_type == Geary.ProblemType.CONNECTION_ERROR &&
                service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: String substitution is the account name
                title = _("Problem connecting to incoming server for %s".printf(account));
                // Translators: String substitution is the server name
                descr = _("Could not connect to %s, check your Internet access and the server name and try again").printf(server);
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.CONNECTION_ERROR &&
                       service_report.service.protocol == Geary.Protocol.SMTP) {
                // Translators: String substitution is the account name
                title = _("Problem connecting to outgoing server for %s".printf(account));
                // Translators: String substitution is the server name
                descr = _("Could not connect to %s, check your Internet access and the server name and try again").printf(server);
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.NETWORK_ERROR &&
                       service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: String substitution is the account name
                title = _("Problem communicating with incoming server for %s").printf(account);
                // Translators: String substitution is the server name
                descr = _("Network error talking to %s, check your Internet access and try again").printf(server);
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.NETWORK_ERROR &&
                       service_report.service.protocol == Geary.Protocol.SMTP) {
                // Translators: String substitution is the account name
                title = _("Problem communicating with outgoing server for %s").printf(account);
                // Translators: String substitution is the server name
                descr = _("Network error talking to %s, check your Internet access and try again").printf(server);
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.SERVER_ERROR &&
                       service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: String substitution is the account name
                title = _("Problem communicating with incoming server for %s").printf(account);
                // Translators: String substitution is the server name
                descr = _("Geary did not understand a message from %s or vice versa, please file a bug report").printf(server);
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.SERVER_ERROR &&
                       service_report.service.protocol == Geary.Protocol.SMTP) {
                title = _("Problem communicating with outgoing mail server");
                // Translators: First string substitution is the server
                // name, second is the account name
                descr = _("Could not communicate with %s for %s, check the server name and try again in a moment").printf(server, account);
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.AUTHENTICATION &&
                       service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: String substitution is the account name
                title = _("Incoming mail server password required for %s").printf(account);
                descr = _("Messages cannot be received without the correct password.");
                // Translators: Tooltip label for Retry button
                retry = _("Retry receiving email, you will be prompted for a password");

            } else if (report.problem_type == Geary.ProblemType.AUTHENTICATION &&
                       service_report.service.protocol == Geary.Protocol.SMTP) {
                // Translators: String substitution is the account name
                title = _("Outgoing mail server password required for %s").printf(account);
                descr = _("Messages cannot be sent without the correct password.");
                // Translators: Tooltip label for Retry button
                retry = _("Retry sending queued messages, you will be prompted for a password");

            } else if (report.problem_type == Geary.ProblemType.UNTRUSTED &&
                       service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: String substitution is the account name
                title = _("Incoming mail server security is not trusted for %s").printf(account);
                descr = _("Messages will not be received until checked.");
                // Translators: Tooltip label for Retry button
                retry = _("Check security details");

            } else if (report.problem_type == Geary.ProblemType.UNTRUSTED &&
                       service_report.service.protocol == Geary.Protocol.SMTP) {
                // Translators: String substitution is the account name
                title = _("Outgoing mail server security is not trusted for %s").printf(account);
                descr = _("Messages cannot be sent until checked.");
                // Translators: Tooltip label for Retry button
                retry = _("Check security details");

            } else if (report.problem_type == Geary.ProblemType.GENERIC_ERROR &&
                       service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: String substitution is the account name
                title = _("A problem occurred checking mail for %s").printf(account);
                descr = _("Something went wrong, please file a bug report if the problem persists");
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (report.problem_type == Geary.ProblemType.GENERIC_ERROR &&
                       service_report.service.protocol == Geary.Protocol.SMTP) {
                // Translators: String substitution is the account name
                title = _("A problem occurred sending mail for %s").printf(account);
                descr = _("Something went wrong, please file a bug report if the problem persists");
                // Translators: Tooltip label for Retry button
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

    private void show_details() {
        Dialogs.ProblemDetailsDialog dialog =
            new Dialogs.ProblemDetailsDialog.for_problem_report(
                get_toplevel() as Gtk.Window, this.report
        );
        dialog.run();
        dialog.destroy();
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

}

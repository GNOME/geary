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

            if (service_report.service.protocol == Geary.Protocol.IMAP) {
                // Translators: Info bar title for an incoming account
                // problem. String substitution is the account name
                title = _("A problem occurred checking email for %s").printf(account);
                // Translators: Info bar sub-title for an incoming account
                // problem.
                descr = _("Email will not be received until re-connected");
                // Translators: Tooltip label for Retry button
                retry = _("Try reconnecting");

            } else if (service_report.service.protocol == Geary.Protocol.SMTP) {
                // Translators: Info bar title for an outgoing account
                // problem. String substitution is the account name
                title = _("A problem occurred sending email for %s").printf(account);
                // Translators: Info bar sub-title for an outgoing
                // account problem.
                descr = _("Email will not be sent until re-connected");
                // Translators: Tooltip label for Retry button
                retry = _("Retry sending queued messages");

            }
        } else if (report is Geary.AccountProblemReport) {
            Geary.AccountProblemReport account_report = (Geary.AccountProblemReport) report;
            string account = account_report.account.display_name;

            // Translators: Info bar title for a generic account
            // problem. String substitution is the account name
            title = _("A problem occurred with account %s").printf(account);
            // Translators: Info bar sub-title for a generic account
            // problem.
            descr = _("Something went wrong, please file a bug report if the problem persists");

        } else {
            debug("Un-handled generic problem report: %s".printf(report.to_string()));
            show_generic = true;
        }

        if (show_generic) {
            // Translators: Info bar title for a generic application
            // problem.
            title = _("Geary has encountered a problem");
            // Translators: Info bar sub-title for a generic
            // application problem.
            descr = _("Please check the technical details and report the problem if it persists.");
            show_close = true;
        }

        this(type, title, descr, show_close);
        this.report = report;

        if (this.report.error != null) {
            // Translators: Button label for viewing technical details
            // for a problem report.
            Gtk.Button details = add_button(_("_Details"), ResponseType.DETAILS);
            // Translators: Tooltip for viewing technical details for
            // a problem report.
            details.tooltip_text = _("View technical details about the error");
        }

        if (retry != null) {
            // Translators: Button label for retrying a server
            // connection
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
        Geary.ServiceProblemReport? service_report =
            this.report as Geary.ServiceProblemReport;
        Geary.AccountProblemReport? account_report =
            this.report as Geary.AccountProblemReport;

        Dialogs.ProblemDetailsDialog dialog =
            new Dialogs.ProblemDetailsDialog(
                get_toplevel() as MainWindow,
                this.report.error,
                account_report != null ? account_report.account : null,
                service_report != null ? service_report.service : null
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

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

        if (report is Geary.AccountProblemReport) {
            Geary.AccountProblemReport account_report =
                (Geary.AccountProblemReport) report;
            string account_name = account_report.account.display_name;

            // Translators: Info bar title for a generic account
            // problem.
            title = _("Account problem");
            // Translators: Info bar sub-title for a generic account
            // problem. String substitution is the account name.
            descr = _(
                "Geary has encountered a problem with %s."
            ).printf(account_name);

            if (report is Geary.ServiceProblemReport) {
                Geary.ServiceProblemReport service_report =
                    (Geary.ServiceProblemReport) report;

                switch (service_report.service.protocol) {
                case IMAP:
                    // Translators: Info bar sub-title for a generic
                    // account problem. String substitution is the
                    // account name.
                    descr = _(
                        "Geary encountered a problem checking mail for %s."
                    ).printf(account_name);

                    // Translators: Tooltip label for Retry button
                    retry = _("Try reconnecting");
                    break;

                case SMTP:
                    // Translators: Info bar title for an outgoing
                    // account problem. String substitution is the
                    // account name
                    descr = _(
                        "Geary encountered a problem sending email for %s."
                    ).printf(account_name);

                    // Translators: Tooltip label for Retry button
                    retry = _("Retry sending queued messages");
                    break;
                }
            }
        } else {
            // Translators: Info bar title for a generic application
            // problem.
            title = _("Geary has encountered a problem");
            // Translators: Info bar sub-title for a generic
            // application problem.
            descr = _(
                "Please report the details if it persists."
            );
        }

        // Only show a close button if retrying not possible
        this(type, title, descr, (retry == null));
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
        var main = get_toplevel() as Application.MainWindow;
        if (main != null) {
            var dialog = new Dialogs.ProblemDetailsDialog(
                main,
                main.application,
                this.report
            );
            dialog.run();
            dialog.destroy();
        }
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

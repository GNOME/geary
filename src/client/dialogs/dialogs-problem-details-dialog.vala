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
public class Dialogs.ProblemDetailsDialog : Gtk.Dialog {


    private Geary.ErrorContext error;
    private Geary.AccountInformation? account;
    private Geary.ServiceInformation? service;

    [GtkChild]
    private Gtk.TextView detail_text;


    public ProblemDetailsDialog(Gtk.Window parent,
                                Geary.ErrorContext error,
                                Geary.AccountInformation? account,
                                Geary.ServiceInformation? service) {
        Object(
            transient_for: parent,
            use_header_bar: 1
        );
        set_default_size(600, -1);

        this.error = error;
        this.account = account;
        this.service = service;

        this.detail_text.buffer.text = format_details();
    }

    public ProblemDetailsDialog.for_problem_report(Gtk.Window parent,
                                                   Geary.ProblemReport report) {
        Geary.ServiceProblemReport? service_report =
            report as Geary.ServiceProblemReport;
        Geary.AccountProblemReport? account_report =
            report as Geary.AccountProblemReport;
        this(
            parent,
            report.error,
            account_report != null ? account_report.account : null,
            service_report != null ? service_report.service : null
        );
    }

    private string format_details() {
        StringBuilder details = new StringBuilder();

        Gtk.ApplicationWindow? parent =
            this.get_toplevel() as Gtk.ApplicationWindow;
        GearyApplication? app = (parent != null)
            ? parent.application as GearyApplication
            : null;
        if (app != null) {
            foreach (GearyApplication.RuntimeDetail? detail
                     in app.get_runtime_information()) {
                details.append_printf("%s: %s", detail.name, detail.value);
            }
        }
        if (this.account != null) {
            details.append_printf(
                "Account id: %s\n",
                this.account.id
            );
            details.append_printf(
                "Account provider: %s\n",
                this.account.service_provider.to_string()
            );
        }
        if (this.service != null) {
            details.append_printf(
                "Service type: %s\n",
                this.service.protocol.to_string()
            );
            details.append_printf(
                "Service host: %s\n",
                this.service.host
            );
        }
        if (this.error == null) {
            details.append("No error reported");
        } else {
            details.append_printf(
                "Error type: %s\n", this.error.format_error_type()
            );
            details.append_printf(
                "Message: %s\n", this.error.thrown.message
            );
            details.append("Back trace:\n");
            foreach (Geary.ErrorContext.StackFrame frame in
                     this.error.backtrace) {
                details.append_printf(" - %s\n", frame.to_string());
            }
        }
        return details.str;
    }

    [GtkCallback]
    private void on_copy_clicked() {
        get_clipboard(Gdk.SELECTION_CLIPBOARD).set_text(format_details(), -1);
    }

}

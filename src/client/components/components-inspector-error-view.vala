/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A view that displays information about an application error.
 */
[GtkTemplate (ui = "/org/gnome/Geary/components-inspector-error-view.ui")]
public class Components.InspectorErrorView : Gtk.Grid {


    [GtkChild]
    private Gtk.TextView problem_text;

    private string details;


    public InspectorErrorView(Geary.ErrorContext error,
                              Geary.AccountInformation? account,
                              Geary.ServiceInformation? service) {
        this.details = format_problem(error, account, service);
        this.problem_text.buffer.text = this.details;
    }

    public void save(GLib.DataOutputStream out, GLib.Cancellable? cancellable)
        throws GLib.Error {
        out.put_string(this.details, cancellable);
    }

    private string format_problem(Geary.ErrorContext error,
                                  Geary.AccountInformation? account,
                                  Geary.ServiceInformation? service) {
        StringBuilder details = new StringBuilder();
        if (account != null) {
            details.append_printf(
                "Account id: %s\n",
                account.id
            );
            details.append_printf(
                "Account provider: %s\n",
                account.service_provider.to_string()
            );
        }
        if (service != null) {
            details.append_printf(
                "Service type: %s\n",
                service.protocol.to_string()
            );
            details.append_printf(
                "Service host: %s\n",
                service.host
            );
        }
        if (error == null) {
            details.append("No error reported");
        } else {
            details.append_printf(
                "Error type: %s\n", error.format_error_type()
            );
            details.append_printf(
                "Message: %s\n", error.thrown.message
            );
            details.append("Back trace:\n");
            foreach (Geary.ErrorContext.StackFrame frame in
                     error.backtrace) {
                details.append_printf(" - %s\n", frame.to_string());
            }
        }
        return details.str;
    }

}

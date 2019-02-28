/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

public class CertificateWarningDialog {
    public enum Result {
        DONT_TRUST,
        TRUST,
        ALWAYS_TRUST
    }

    private const string BULLET = "&#8226; ";

    private Gtk.Dialog dialog;

    public CertificateWarningDialog(Gtk.Window? parent,
                                    Geary.AccountInformation account,
                                    Geary.ServiceInformation service,
                                    Geary.Endpoint endpoint,
                                    bool is_validation) {
        Gtk.Builder builder = GioUtil.create_builder("certificate_warning_dialog.glade");

        dialog = (Gtk.Dialog) builder.get_object("CertificateWarningDialog");
        dialog.transient_for = parent;
        dialog.modal = true;

        Gtk.Label title_label = (Gtk.Label) builder.get_object("untrusted_connection_label");
        Gtk.Label top_label = (Gtk.Label) builder.get_object("top_label");
        Gtk.Label warnings_label = (Gtk.Label) builder.get_object("warnings_label");
        Gtk.Label trust_label = (Gtk.Label) builder.get_object("trust_label");
        Gtk.Label dont_trust_label = (Gtk.Label) builder.get_object("dont_trust_label");
        Gtk.Label contact_label = (Gtk.Label) builder.get_object("contact_label");

        title_label.label = _("Untrusted Connection: %s").printf(account.display_name);

        top_label.label = _("The identity of the %s mail server at %s:%u could not be verified.").printf(
            service.protocol.to_value(), service.host, service.port);

        warnings_label.label = generate_warning_list(
            endpoint.tls_validation_warnings
        );
        warnings_label.use_markup = true;

        trust_label.label =
            "<b>"
            +_("Selecting “Trust This Server” or “Always Trust This Server” may cause your username and password to be transmitted insecurely.")
            + "</b>";
        trust_label.use_markup = true;

        if (is_validation) {
            // could be a new or existing account
            dont_trust_label.label =
                "<b>"
                + _("Selecting “Don’t Trust This Server” will cause Geary not to access this server.")
                + "</b> "
                + _("Geary will not add or update this email account.");
        } else {
            // a registered account
            dont_trust_label.label =
                "<b>"
                + _("Selecting “Don’t Trust This Server” will cause Geary to stop accessing this account.")
                + "</b> ";
        }
        dont_trust_label.use_markup = true;

        contact_label.label =
            _("Contact your system administrator or email service provider if you have any question about these issues.");
    }

    private static string generate_warning_list(TlsCertificateFlags warnings) {
        StringBuilder builder = new StringBuilder();

        if ((warnings & TlsCertificateFlags.UNKNOWN_CA) != 0)
            builder.append(BULLET + _("The server’s certificate is not signed by a known authority") + "\n");

        if ((warnings & TlsCertificateFlags.BAD_IDENTITY) != 0)
            builder.append(BULLET + _("The server’s identity does not match the identity in the certificate") + "\n");

        if ((warnings & TlsCertificateFlags.EXPIRED) != 0)
            builder.append(BULLET + _("The server’s certificate has expired") + "\n");

        if ((warnings & TlsCertificateFlags.NOT_ACTIVATED) != 0)
            builder.append(BULLET + _("The server’s certificate has not been activated") + "\n");

        if ((warnings & TlsCertificateFlags.REVOKED) != 0)
            builder.append(BULLET + _("The server’s certificate has been revoked and is now invalid") + "\n");

        if ((warnings & TlsCertificateFlags.INSECURE) != 0)
            builder.append(BULLET + _("The server’s certificate is considered insecure") + "\n");

        if ((warnings & TlsCertificateFlags.GENERIC_ERROR) != 0)
            builder.append(BULLET + _("An error has occurred processing the server’s certificate") + "\n");

        return builder.str;
    }

    public Result run() {
        dialog.show_all();
        int response = dialog.run();
        dialog.destroy();

        // these values are defined in the Glade file
        switch (response) {
            case 1:
                return Result.TRUST;

            case 2:
                return Result.ALWAYS_TRUST;

            default:
                return Result.DONT_TRUST;
        }
    }
}


/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

[GtkTemplate (ui = "/org/gnome/Geary/certificate-warning-dialog.ui")]
public class CertificateWarningDialog : Adw.AlertDialog {

    public enum Result {
        DONT_TRUST,
        TRUST,
        ALWAYS_TRUST
    }

    private const string BULLET = "&#8226; ";

    [GtkChild] private unowned Gtk.Label top_label;
    [GtkChild] private unowned Gtk.Label warnings_label;
    [GtkChild] private unowned Gtk.Label trust_label;
    [GtkChild] private unowned Gtk.Label dont_trust_label;
    [GtkChild] private unowned Gtk.Label contact_label;

    public CertificateWarningDialog(Geary.AccountInformation account,
                                    Geary.ServiceInformation service,
                                    Geary.Endpoint endpoint,
                                    bool is_validation) {
        this.title = _("Untrusted Connection: %s").printf(account.display_name);

        this.top_label.label = _("The identity of the %s mail server at %s:%u could not be verified.").printf(
            service.protocol.to_value(), service.host, service.port);

        this.warnings_label.label = generate_warning_list(
            endpoint.tls_validation_warnings
        );
        this.warnings_label.use_markup = true;

        this.trust_label.label =
            "<b>"
            +_("Selecting “Trust This Server” or “Always Trust This Server” may cause your username and password to be transmitted insecurely.")
            + "</b>";
        this.trust_label.use_markup = true;

        if (is_validation) {
            // could be a new or existing account
            this.dont_trust_label.label =
                "<b>"
                + _("Selecting “Don’t Trust This Server” will cause Geary not to access this server.")
                + "</b> "
                + _("Geary will not add or update this email account.");
        } else {
            // a registered account
            this.dont_trust_label.label =
                "<b>"
                + _("Selecting “Don’t Trust This Server” will cause Geary to stop accessing this account.")
                + "</b> ";
        }
        this.dont_trust_label.use_markup = true;

        this.contact_label.label =
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

    public async Result run(Gtk.Window? parent) {
        string response = yield choose(parent, null);

        switch (response) {
            case "trust":
                return Result.TRUST;

            case "always-trust":
                return Result.ALWAYS_TRUST;

            default:
                return Result.DONT_TRUST;
        }
    }
}


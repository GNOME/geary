/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* A service implementation using GNOME Online Accounts.
 * This loads IMAP and SMTP settings from GOA.
 */
public class GoaServiceInformation : Geary.ServiceInformation {


    private Goa.Object account;

    public GoaServiceInformation(Geary.Protocol protocol,
                                 GoaMediator mediator,
                                 Goa.Object account) {
        base(protocol, mediator);
        this.account = account;
        update();
    }

    public void update() {
        Goa.Mail? mail = this.account.get_mail();
        if (mail != null) {
            switch (this.protocol) {
            case Geary.Protocol.IMAP:
                parse_host_name(mail.imap_host);
                this.use_ssl = mail.imap_use_ssl;
                this.use_starttls = mail.imap_use_tls;

                if (this.port == 0) {
                    this.port = this.use_ssl
                        ? Geary.Imap.ClientConnection.IMAP_TLS_PORT
                        : Geary.Imap.ClientConnection.IMAP_PORT;
                }

                this.credentials = new Geary.Credentials(
                    ((GoaMediator) this.mediator).method,
                    mail.imap_user_name
                );
                break;

            case Geary.Protocol.SMTP:
                parse_host_name(mail.smtp_host);
                this.use_ssl = mail.smtp_use_ssl;
                this.use_starttls = mail.smtp_use_tls;
                this.smtp_noauth = !(mail.smtp_use_auth);
                this.smtp_use_imap_credentials = false;

                if (this.port == 0) {
                    if (this.use_ssl) {
                        this.port = Geary.Smtp.ClientConnection.SUBMISSION_TLS_PORT;
                    } else if (this.smtp_noauth) {
                        this.port = Geary.Smtp.ClientConnection.SMTP_PORT;
                    } else {
                        this.port = Geary.Smtp.ClientConnection.SUBMISSION_PORT;
                    }
                }

                if (!this.smtp_noauth) {
                    this.credentials = new Geary.Credentials(
                        ((GoaMediator) this.mediator).method,
                        mail.smtp_user_name
                    );
                }
                break;
            }
        }
    }

    public override Geary.ServiceInformation temp_copy() {
        GoaServiceInformation copy = new GoaServiceInformation(
            this.protocol, (GoaMediator) this.mediator, this.account
        );
        copy.copy_from(this);
        return copy;
    }

    private void parse_host_name(string host_name) {
        // Fall back to trying to use the host name as-is.
        // At least the user can see it in the settings if
        // they look.
        this.host = host_name;
        this.port = 0;

        try {
            GLib.NetworkAddress address = GLib.NetworkAddress.parse(
                host_name, this.port
            );

            this.host = address.hostname;
            this.port = (uint16) address.port;
        } catch (GLib.Error err) {
            warning(
                "GOA account \"%s\" %s hostname \"%s\": %",
                this.account.get_account().id,
                this.protocol.to_value(),
                host_name,
                err.message
            );
        }
    }

}

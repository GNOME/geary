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
                this.host = mail.imap_host;
                this.port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL;
                this.use_ssl = mail.imap_use_ssl;
                this.use_starttls = mail.imap_use_tls;
                this.credentials = new Geary.Credentials(
                    ((GoaMediator) this.mediator).method,
                    mail.imap_user_name
                );
                break;

            case Geary.Protocol.SMTP:
                this.host = mail.smtp_host;
                this.port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL;
                this.use_ssl = mail.smtp_use_ssl;
                this.use_starttls = mail.smtp_use_tls;
                this.smtp_noauth = !(mail.smtp_use_auth);
                this.smtp_use_imap_credentials = false;
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

}

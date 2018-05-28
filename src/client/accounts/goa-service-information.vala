/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* A service implementation using GNOME Online Accounts.
 * This loads IMAP and SMTP settings from GOA.
 */
public class GoaServiceInformation : Geary.ServiceInformation {
    private Goa.Mail mail_object;

    public GoaServiceInformation(Geary.Service protocol,
                                 Geary.CredentialsMediator? mediator,
                                 Goa.Mail mail_object) {
        base(protocol);
        this.credentials_method = Geary.CredentialsMethod.PASSWORD;
        this.mediator = mediator;
        this.mail_object = mail_object;

        switch (protocol) {
            case Geary.Service.IMAP:
                this.credentials.user = mail_object.imap_user_name;
                this.host = mail_object.imap_host;
                this.port = Geary.Imap.ClientConnection.DEFAULT_PORT_SSL;
                this.use_ssl = mail_object.imap_use_ssl;
                this.use_starttls = mail_object.imap_use_tls;
                break;
            case Geary.Service.SMTP:
                this.credentials.user = mail_object.smtp_user_name;
                this.host = mail_object.smtp_host;
                this.port = Geary.Smtp.ClientConnection.DEFAULT_PORT_SSL;
                this.use_ssl = mail_object.smtp_use_ssl;
                this.use_starttls = mail_object.smtp_use_tls;
                this.smtp_noauth = !(mail_object.smtp_use_auth);
                if (smtp_noauth)
                    this.credentials = null;
                break;
        }
    }

    public override Geary.ServiceInformation temp_copy() {
        GoaServiceInformation copy = new GoaServiceInformation(
            this.protocol, this.mediator, this.mail_object
        );
        copy.copy_from(this);
        return copy;
    }

}

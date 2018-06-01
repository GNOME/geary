/*
 * Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* GNOME Online Accounts token adapter. */
public class GoaMediator : Geary.CredentialsMediator, Object {


    public bool is_valid {
        get {
            Goa.Account account = this.account.get_account();
            // Goa.Account.mail_disabled doesn't seem to reflect if we
            // get can get a valid mail object or not, so just rely on
            // actually getting one instead.
            Goa.Mail? mail = this.account.get_mail();
            return (
                mail != null &&
                !account.attention_needed &&
                (this.oauth2 != null || this.password != null)
            );
        }
    }

    public Geary.Credentials.Method method {
        get {
            Geary.Credentials.Method method = Geary.Credentials.Method.PASSWORD;
            if (this.oauth2 != null) {
                method = Geary.Credentials.Method.OAUTH2;
            }
            return method;
        }
    }

    private Goa.Object account;
    private Goa.OAuth2Based? oauth2 = null;
    private Goa.PasswordBased? password = null;


    public GoaMediator(Goa.Object account) {
        this.account = account;
    }

    public async void update(Geary.AccountInformation geary_account,
                             GLib.Cancellable? cancellable)
        throws GLib.Error {
        // XXX have to call the sync version of this since the async
        // version seems to be broken
        this.account.get_account().call_ensure_credentials_sync(
            null, cancellable
        );
        this.oauth2 = this.account.get_oauth2_based();
        this.password = this.account.get_password_based();

        GoaServiceInformation imap = (GoaServiceInformation) geary_account.imap;
        imap.update();

        GoaServiceInformation smtp = (GoaServiceInformation) geary_account.smtp;
        smtp.update();
    }

    public virtual async bool load_token(Geary.AccountInformation account,
                                         Geary.ServiceInformation service,
                                         Cancellable? cancellable)
        throws GLib.Error {
        bool loaded = false;
        string? token = null;

        if (this.method == Geary.Credentials.Method.OAUTH2) {
            // XXX have to call the sync version of this since the async
            // version seems to be broken
            this.oauth2.call_get_access_token_sync(
                out token, null, cancellable
            );
        } else {
            // XXX have to call the sync version of these since the
            // async version seems to be broken
            switch (service.protocol) {
            case Geary.Protocol.IMAP:
                this.password.call_get_password_sync(
                    "imap-password", out token, cancellable
                );
                break;

            case Geary.Protocol.SMTP:
                this.password.call_get_password_sync(
                    "smtp-password", out token, cancellable
                );
                break;

            default:
                return false;
            }
        }

        if (token != null) {
            service.credentials = service.credentials.copy_with_token(token);
            loaded = true;
        }
        return loaded;
    }

    public virtual async bool prompt_token(Geary.AccountInformation account,
                                           Geary.ServiceInformation service,
                                           GLib.Cancellable? cancellable)
        throws GLib.Error {
        // Prompt GOA to update the creds. This might involve some
        // user interaction.
        yield update(account, cancellable);

        // XXX now open a dialog that says "Click here to change your
        // GOA password" or "GOA credentials need renewing" or
        // something. Connect to the GOA service and wait until we
        // hear that needs attention is no longer true.

        return this.is_valid;
    }

}

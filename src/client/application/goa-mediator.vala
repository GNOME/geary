/*
 * Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* GNOME Online Accounts token adapter. */
public class GoaMediator : Geary.CredentialsMediator, Object {


    public bool is_valid {
        get { return (this.oauth2 != null || this.password != null); }
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
        this.oauth2 = account.get_oauth2_based();
        this.password = account.get_password_based();
        debug(
            "OAuth2: %s, Password: %s",
            (this.oauth2 != null).to_string(),
            (this.password != null).to_string()
        );
    }

    public virtual async bool load_token(Geary.AccountInformation account,
                                         Geary.ServiceInformation service,
                                         Cancellable? cancellable)
        throws GLib.Error {
        bool loaded = false;
        string? token = null;
        
        if (this.method == Geary.Credentials.Method.OAUTH2) {
            this.oauth2.call_get_access_token_sync(
                out token, null, cancellable
            );
        } else {
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
        // XXX open a dialog that says "Click here to change your GOA
        // password". Connect to the GOA service and wait until we
        // hear that the account has changed.
        return false;
    }

}

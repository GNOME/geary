/* Copyright 2017 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/* GNOME Online Accounts password adapter. */
public class GoaMediator : Geary.CredentialsMediator, Object {
    private Goa.PasswordBased password;

    public GoaMediator(Goa.PasswordBased password) {
        this.password = password;
    }

    public virtual  async bool load_token(Geary.AccountInformation account,
                                          Geary.ServiceInformation service,
                                          Cancellable? cancellable)
        throws GLib.Error {
        string? pass = null;

        switch (service.protocol) {
        case Geary.Protocol.IMAP:
            password.call_get_password_sync(
                "imap-password", out pass, cancellable
            );
            break;

        case Geary.Protocol.SMTP:
            password.call_get_password_sync(
                "smtp-password", out pass, cancellable
            );
            break;

        default:
            return false;
        }

        bool loaded = false;
        if (pass != null) {
            service.credentials = service.credentials.copy_with_token(pass);
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

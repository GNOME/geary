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

    public virtual async string? get_password_async(Geary.Service service,
                                                    Geary.AccountInformation account,
                                                    Cancellable? cancellable = null)
    throws Error {
        string pass;

        switch (service) {
            case Geary.Service.IMAP:
                if (!password.call_get_password_sync("imap-password", out pass, cancellable))
                    return null;
                break;
            case Geary.Service.SMTP:
                if (!password.call_get_password_sync("smtp-password", out pass, cancellable))
                    return null;
                break;
            default:
                return null;
        }
        return pass;
    }

    public virtual async void set_password_async(Geary.Service service,
                                                 Geary.AccountInformation account,
                                                 Cancellable? cancellable = null)
    throws Error {
        return;
    }

    public virtual async void clear_password_async(Geary.Service service,
                                                   Geary.AccountInformation account,
                                                   Cancellable? cancellable = null)
    throws Error {
        return;
    }

    public virtual async bool prompt_passwords_async(Geary.ServiceFlag services,
        Geary.AccountInformation account_information,
        out string? imap_password, out string? smtp_password,
        out bool imap_remember_password, out bool smtp_remember_password) throws Error {

        imap_password = yield get_password_async(Geary.Service.IMAP, account_information, null);
        smtp_password = yield get_password_async(Geary.Service.SMTP, account_information, null);

        imap_remember_password = false;
        smtp_remember_password = false;

        return false;
    }

}

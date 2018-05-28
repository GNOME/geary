/*
 * Copyright 2017 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

public class Geary.MockCredentialsMediator :
    GLib.Object, CredentialsMediator, MockObject {


    protected Gee.Queue<ExpectedCall> expected {
        get; set; default = new Gee.LinkedList<ExpectedCall>();
    }

    public virtual async string?
        get_password_async(ServiceInformation service,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        return object_call<string>(
            "prompt_passwords_async",
            { service, cancellable },
            ""
        );
    }

    /**
     * Add or update the store's password entry for the given service.
     */
    public virtual async void
        set_password_async(ServiceInformation service,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        void_call(
            "prompt_passwords_async",
            { service, cancellable }
        );
    }

    /**
     * Deletes the key store's password entry for the given service.
     *
     * Do nothing (and do *not* throw an error) if the credentials
     * weren't in the key store.
     */
    public virtual async void
        clear_password_async(ServiceInformation service,
                             GLib.Cancellable? cancellable = null)
        throws GLib.Error {
        void_call(
            "prompt_passwords_async",
            { service, cancellable }
        );
    }

    /**
     * Prompt the user to enter passwords for the given services.
     *
     * Set the out parameters for the services to the values entered
     * by the user (out parameters for services not being prompted for
     * are ignored).  Return false if the user tried to cancel the
     * interaction, or true if they tried to proceed.
     */
    public virtual async bool
        prompt_passwords_async(ServiceFlag services,
                               AccountInformation account_information,
                               out string? imap_password,
                               out string? smtp_password,
                               out bool imap_remember_password,
                               out bool smtp_remember_password)
        throws GLib.Error {
        imap_password = null;
        smtp_password = null;
        imap_remember_password = false;
        smtp_remember_password = false;
        return boolean_call(
            "prompt_passwords_async",
            { box_arg(services), account_information },
            false
        );
    }

}

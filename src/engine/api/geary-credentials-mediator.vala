/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Denotes objects that can store and retrieve authentication secrets.
*/
public interface Geary.CredentialsMediator : GLib.Object {

    /**
     * Query the key store for the password for the given service.
     *
     * Return null if the password wasn't in the key store, or the
     * password if it was.
     */
    public abstract async string?
        get_password_async(ServiceInformation service,
                           GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Add or update the store's password entry for the given service.
     */
    public abstract async
    void set_password_async(ServiceInformation service,
                            GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Deletes the key store's password entry for the given service.
     *
     * Do nothing (and do *not* throw an error) if the credentials
     * weren't in the key store.
     */
    public abstract async void
        clear_password_async(ServiceInformation service,
                             GLib.Cancellable? cancellable = null)
        throws GLib.Error;

    /**
     * Prompt the user to enter passwords for the given services.
     *
     * Set the out parameters for the services to the values entered
     * by the user (out parameters for services not being prompted for
     * are ignored).  Return false if the user tried to cancel the
     * interaction, or true if they tried to proceed.
     */
    public abstract async bool
        prompt_passwords_async(ServiceFlag services,
                               AccountInformation account_information,
                               out string? imap_password,
                               out string? smtp_password,
                               out bool imap_remember_password,
                               out bool smtp_remember_password)
        throws GLib.Error;
}

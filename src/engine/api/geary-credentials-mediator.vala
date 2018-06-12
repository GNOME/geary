/*
 * Copyright 2016 Software Freedom Conservancy Inc.
 * Copyright 2018 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * A store for authentication tokens.
 */
public interface Geary.CredentialsMediator : GLib.Object {

    /**
     * Updates the token for a service's credential from the store.
     *
     * Returns true if the token was present and loaded, else false.
     */
    public abstract async bool load_token(AccountInformation account,
                                          ServiceInformation service,
                                          GLib.Cancellable? cancellable)
        throws GLib.Error;

    /**
     * Prompt the user to enter passwords for the given service.
     *
     * Updates authentication-related details for the given service,
     * possibly including user login names, authentication tokens, and
     * the remember password preference.
     *
     * Returns false if the user tried to cancel the interaction, or
     * true if they tried to proceed.
     */
    public abstract async bool prompt_token(AccountInformation account,
                                            ServiceInformation service,
                                            GLib.Cancellable? cancellable)
        throws GLib.Error;

}

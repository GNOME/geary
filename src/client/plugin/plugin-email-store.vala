/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Provides plugins with access to email.
 *
 * Plugins may obtain instances of this object from their context
 * objects, for example {@link
 * Application.NotificationContext.get_email}.
 */
public interface Plugin.EmailStore : Geary.BaseObject {


    /** Emitted when an email message has been sent. */
    public signal void email_sent(Email message);

    /** Returns a read-only set of all known folders. */
    public async abstract Gee.Collection<Email> get_email(
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable
    ) throws GLib.Error;

}

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


    /** Emitted when an email has been displayed in the UI. */
    public signal void email_displayed(Email sent);

    /** Emitted when an email has been sent. */
    public signal void email_sent(Email sent);

    /** Returns the email with the given identifiers. */
    public async abstract Gee.Collection<Email> get_email(
        Gee.Collection<EmailIdentifier> ids,
        GLib.Cancellable? cancellable
    ) throws GLib.Error;

}

/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing a composer for use by plugins.
 */
public interface Plugin.Composer : Geary.BaseObject {


    /**
     * Causes the composer to be made visible.
     *
     * The composer will be shown as either full-pane and in-window if
     * not a reply to a currently displayed conversation, inline and
     * in-window if a reply to an existing conversation being
     * displayed, or detached if there is already an in-window
     * composer being displayed.
     */
    public abstract void show();

    /**
     * Loads an email into the composer to be edited.
     *
     * Loads the given email, and sets it as the email to be edited in
     * this composer. This must be called before calling {@link show},
     * and has no effect if called afterwards.
     */
    public async abstract void edit_email(EmailIdentifier to_load)
        throws GLib.Error;

    /**
     * Sets the folder used to save the message being composed.
     *
     * Ensures email for both automatic and manual saving of the email
     * in the composer is saved to the given folder. This must be
     * called before calling {@link show}, and has no effect if called
     * afterwards.
     */
    public abstract void save_to_folder(Plugin.Folder? location);

}

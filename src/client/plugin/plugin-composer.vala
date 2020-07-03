/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing a composer for use by plugins.
 *
 * Instances of this interface can be obtained by calling {@link
 * Application.compose_blank} or {@link
 * Application.compose_with_context}. A composer instance may not be
 * visible until {@link present} is called, allowing it to be
 * configured via calls to this interface first, if required.
 */
public interface Plugin.Composer : Geary.BaseObject {


    /**
     * Determines the type of the context email passed to the composer
     *
     * @see Application.compose_with_context
     */
    public enum ContextType {
        /** No context mail was provided. */
        NONE,

        /** Context is an email to edited, for example a draft or template. */
        EDIT,

        /** Context is an email being replied to the sender only. */
        REPLY_SENDER,

        /** Context is an email being replied to all recipients. */
        REPLY_ALL,

        /** Context is an email being forwarded. */
        FORWARD
    }

    /**
     * Denotes the account the composed email will be sent from.
     */
    public abstract Plugin.Account? sender_context { get; }

    /**
     * Determines if the email in the composer can be sent.
     */
    public abstract bool can_send { get; set; }

    /**
     * Denotes the folder that the email will be saved to.
     *
     * If non-null, fixes the folder used by the composer for saving
     * the email. If null, the current account's Draft folder will be
     * used.
     *
     * @see save_to_folder
     */
    public abstract Plugin.Folder? save_to { get; }


    /**
     * Presents the composer on screen.
     *
     * The composer is made visible if this has not yet been done so,
     * and the application attempts to ensure that it is presented on
     * the active display.
     */
    public abstract void present();

    /**
     * Sets the folder used to save the message being composed.
     *
     * Ensures email for both automatic and manual saving of the email
     * in the composer is saved to the given folder. This disables
     * changing accounts in the composer's UI since email cannot be
     * saved across accounts.
     */
    public abstract void save_to_folder(Plugin.Folder? location);

}

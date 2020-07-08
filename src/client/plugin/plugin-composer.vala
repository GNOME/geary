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
     * The group name for GLib actions registered against this object.
     *
     * All actions are registered via {@link register_action} will be
     * added to an action group with the name returned by this
     * property.
     *
     * This must be used when using actions with GLib MenuModel items.
     */
    public abstract string action_group_name { get; }

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
     * Inserts text at the current cursor position.
     *
     * The given text is inserted at the current cursor position in
     * the composer. Note that this may be in an address field,
     * subject line, or message body, depending on which component is
     * focused.
     *
     * If the text is inserted into the message body, any HTML markup
     * present in the string will appear as-is.
     */
    public abstract void insert_text(string plain_text);

    /**
     * Sets the folder used to save the message being composed.
     *
     * Ensures email for both automatic and manual saving of the email
     * in the composer is saved to the given folder. This disables
     * changing accounts in the composer's UI since email cannot be
     * saved across accounts.
     */
    public abstract void save_to_folder(Plugin.Folder? location);

    /**
     * Registers a plugin action with this specific composer.
     *
     * Once registered, the action will be available for use in user
     * interface elements such as {@link Actionable}.
     *
     * @see deregister_action
     */
    public abstract void register_action(GLib.Action action);

    /**
     * De-registers a plugin action, removing it from this composer.
     *
     * Makes a previously registered no longer available.
     *
     * @see register_action
     */
    public abstract void deregister_action(GLib.Action action);

    /**
     * Adds a menu item to the composer's menu.
     *
     * The menu item will be added to a section unique to this plugin
     * on the composer's menu. The item's action must be registered
     * either with the application via {@link
     * Application.register_action} if it is a global action, or with
     * the composer via {@link register_action} if it is
     * composer-specific for it to be successfully activated.
     *
     * @see register_action
     * @see Application.register_action
     */
    public abstract void append_menu_item(Actionable menu_item);

    /**
     * Sets an action bar for the plugin on this composer.
     *
     * If any existing action bar for this plugin has previously been
     * set, it is first removed.
     */
    public abstract void set_action_bar(ActionBar action_bar);


}

/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing the client application for use by plugins.
 *
 * Plugins may obtain instances of this object from their context
 * objects, for example {@link
 * Application.NotificationContext.get_application}.
 */
public interface Plugin.Application : Geary.BaseObject {


    /**
     * Registers a plugin action with the application.
     *
     * Once registered, the action will be available for use in user
     * interface elements such as {@see Button}.
     *
     * @see unregister_action
     */
    public abstract void register_action(GLib.Action action);

    /**
     * De-registers a plugin action with the application.
     *
     * Makes a previously registered no longer available.
     *
     * @see register_action
     */
    public abstract void deregister_action(GLib.Action action);

    /** Displays a folder in the most recently used main window. */
    public abstract void show_folder(Folder folder);

}

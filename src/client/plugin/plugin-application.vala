/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing the client application for use by plugins.
 *
 * Plugins may obtain instances of this object from the {@link
 * PluginBase.plugin_application} property.
 */
public interface Plugin.Application : Geary.BaseObject {


    /**
     * Registers a plugin action with the application.
     *
     * Once registered, the action will be available for use in user
     * interface elements such as {@link Button}.
     *
     * @see deregister_action
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

    /**
     * Reversibly deletes all email from a folder.
     *
     * A prompt will be displayed for confirmation before the folder
     * is actually emptied, if declined an exception will be thrown.
     *
     * This method will return once the engine has completed emptying
     * the folder, however it may take additional time for the changes
     * to be fully committed and reflected on the remote server.
     *
     * @throws Error.PERMISSION_DENIED if permission to access the
     * resource was not given
     */
    public abstract async void empty_folder(Folder folder)
        throws Error.PERMISSION_DENIED;

}

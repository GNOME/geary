/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * The base class for objects implementing a client plugin.
 *
 * To implement a new plugin, have it derive from this type and
 * implement any additional extension interfaces (such as {@link
 * NotificationExtension}) as required.
 */
public abstract class Plugin.PluginBase : Geary.BaseObject {

    /**
     * Returns an object for interacting with the client application.
     *
     * No special permissions are required to use access this
     * resource.
     *
     * This will be set during (or just after) plugin construction,
     * before {@link PluginBase.activate} is called.
     */
    public Plugin.Application plugin_application {
        get; construct;
    }

    /** Invoked to activate the plugin, after loading. */
    public abstract void activate();

    /** Invoked to deactivate the plugin, prior to unloading */
    public abstract void deactivate(bool is_shutdown);

}

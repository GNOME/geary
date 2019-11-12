/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A plugin for notifying of new mail being delivered.
 */
public abstract class Plugin.Notification : GLib.Object {

    /** The application instance containing the plugin. */
    public abstract Application.Client application {
        get; construct set;
    }

    /** Context object for notifications. */
    public abstract Application.NotificationContext context {
        get; construct set;
    }

    /* Invoked to activate the plugin, after loading. */
    public abstract void activate();

    /* Invoked to deactivate the plugin, prior to unloading */
    public abstract void deactivate(bool is_shutdown);

}

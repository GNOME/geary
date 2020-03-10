/*
 * Copyright 2019 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A plugin extension point for notifying of mail sending or arriving.
 */
public interface Plugin.Notification : Geary.BaseObject {

    /** Context object for notifications. */
    public abstract global::Application.NotificationContext notifications {
        get; set;
    }

    /* Invoked to activate the plugin, after loading. */
    public abstract void activate();

    /* Invoked to deactivate the plugin, prior to unloading */
    public abstract void deactivate(bool is_shutdown);

}

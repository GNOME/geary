/*
 * Copyright © 2019-2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A plugin extension point for notifying of mail sending or arriving.
 */
public interface Plugin.NotificationExtension : PluginBase {

    /**
     * Context object for notifications.
     *
     * This will be set during (or just after) plugin construction,
     * before {@link PluginBase.activate} is called.
     */
    public abstract NotificationContext notifications {
        get; set construct;
    }

}


// XXX this should be an inner interface of NotificationExtension, but
// GNOME/vala#918 prevents that.

/**
 * Provides a context for notification plugins.
 *
 * The context provides an interface for notification plugins to
 * interface with the Geary client application. Plugins that implement
 * the {@link NotificationExtension} interface will be given an
 * instance of this class.
 *
 * Plugins should register folders they wish to monitor by calling
 * {@link start_monitoring_folder}. The context will then start
 * keeping track of email being delivered to the folder and being seen
 * in a main window updating {@link total_new_messages} and emitting
 * the {@link new_messages_arrived} and {@link new_messages_retired}
 * signals as appropriate.
 *
 * @see Plugin.NotificationExtension.notifications
 */
public interface Plugin.NotificationContext : Geary.BaseObject {


    /**
     * Current total new message count for all monitored folders.
     *
     * This is the sum of the the counts returned by {@link
     * get_new_message_count} for all folders that are being monitored
     * after a call to {@link start_monitoring_folder}.
     */
    public abstract int total_new_messages { get; default = 0; }

    /**
     * Emitted when new messages have been downloaded.
     *
     * This will only be emitted for folders that are being monitored
     * by calling {@link start_monitoring_folder}.
     */
    public signal void new_messages_arrived(
        Plugin.Folder parent,
        int total,
        Gee.Collection<Plugin.EmailIdentifier> added
    );

    /**
     * Emitted when a folder has been cleared of new messages.
     *
     * This will only be emitted for folders that are being monitored
     * after a call to {@link start_monitoring_folder}.
     */
    public signal void new_messages_retired(Plugin.Folder parent, int total);


    /**
     * Returns a store to lookup contacts for notifications.
     *
     * This method may prompt for permission before returning.
     *
     * @throws Error.NOT_FOUND if the given account does
     * not exist
     * @throws Error.PERMISSION_DENIED if permission to access the
     * resource was not given
     */
    public abstract async Plugin.ContactStore get_contacts_for_folder(Plugin.Folder source)
        throws Error.NOT_FOUND, Error.PERMISSION_DENIED;

    /**
     * Determines if notifications should be made for a specific folder.
     *
     * Notification plugins should call this to first before
     * displaying a "new mail" notification for mail in a specific
     * folder. It will return true for any monitored folder that is
     * not currently visible in the currently focused main window, if
     * any.
     */
    public abstract bool should_notify_new_messages(Plugin.Folder target);

    /**
     * Returns the new message count for a specific folder.
     *
     * The context must have already been requested to monitor the
     * folder by a call to {@link start_monitoring_folder}.
     */
    public abstract int get_new_message_count(Plugin.Folder target)
        throws Error.NOT_FOUND;

    /**
     * Starts monitoring a folder for new messages.
     *
     * Notification plugins should call this to start the context
     * recording new messages for a specific folder.
     */
    public abstract void start_monitoring_folder(Plugin.Folder target);

    /** Stops monitoring a folder for new messages. */
    public abstract void stop_monitoring_folder(Plugin.Folder target);

    /** Determines if a folder is currently being monitored. */
    public abstract bool is_monitoring_folder(Plugin.Folder target);

}

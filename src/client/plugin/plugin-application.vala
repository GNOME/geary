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


    public abstract void show_folder(Folder folder);

}

/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * A plugin extension point for working with folders.
 */
public interface Plugin.FolderExtension : PluginBase {

    /**
     * Context object for accessing folders.
     *
     * This will be set during (or just after) plugin construction,
     * before {@link PluginBase.activate} is called.
     */
    public abstract FolderContext folders {
        get; set construct;
    }

}


// XXX this should be an inner interface of FolderExtension, but
// GNOME/vala#918 prevents that.

/**
 * Provides a context for folder plugins.
 *
 * The context provides an interface for folder plugins to
 * interface with the Geary client application. Plugins that implement
 * the plugins will be passed an instance of this class as the
 * `context` property.
 *
 * @see Plugin.FolderExtension.folders
 */
public interface Plugin.FolderContext : Geary.BaseObject {


    /**
     * Returns a store to lookup folders.
     *
     * This method may prompt for permission before returning.
     *
     * @throws Error.PERMISSIONS if permission to access
     * this resource was not given
     */
    public abstract async FolderStore get_folders()
        throws Error.PERMISSION_DENIED;

}

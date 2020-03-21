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
 * The context provides an interface for folder plugins to interface
 * with the Geary client application. Plugins that implement the
 * {@link FolderExtension} interface will be given an instance of this
 * class.
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

    /**
     * Adds an info bar to a folder, if selected.
     *
     * The info bar will be shown for the given folder if it is
     * currently selected in any main window, which can be determined
     * by connecting to the {@link folder_selected} signal. Further,
     * if multiple info bars are added for the same folder, only the
     * one with a higher priority will be shown. If that is closed or
     * removed, the second highest will be shown, and so on. Once the
     * selected folder changes, the info bars will be automatically
     * removed.
     */
    public abstract void add_folder_info_bar(Folder selected,
                                             InfoBar infobar,
                                             uint priority);

    /**
     * Removes an info bar from a folder, if selected.
     *
     * Removes the info bar from the given folder if it is currently
     * selected in any main window.
     */
    public abstract void remove_folder_info_bar(Folder selected,
                                                InfoBar infobar);

}

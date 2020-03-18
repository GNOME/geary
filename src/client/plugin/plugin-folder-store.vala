/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Provides plugins with access to folders.
 *
 * Plugins may obtain instances of this object from their context
 * objects, for example {@link
 * Application.NotificationContext.get_folder_store}.
 */
public interface Plugin.FolderStore : Geary.BaseObject {


    /** Emitted when new folders are available. */
    public signal void folders_available(Gee.Collection<Folder> available);

    /** Emitted when existing folders have become unavailable. */
    public signal void folders_unavailable(Gee.Collection<Folder> unavailable);

    /** Emitted when existing folders have become unavailable. */
    public signal void folders_type_changed(Gee.Collection<Folder> changed);

    /** Emitted when a folder has been selected in any main window. */
    public signal void folder_selected(Folder selected);


    /** Returns a read-only set of all known folders. */
    public abstract Gee.Collection<Folder> get_folders();


}

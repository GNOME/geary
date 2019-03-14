/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Abstract base class for sidebar entries that represent folders.  This covers only
 * the basics needed for any type of folder, and is intended to work with both local
 * and remote folder types.
 */
public abstract class FolderList.AbstractFolderEntry : Geary.BaseObject, Sidebar.Entry, Sidebar.SelectableEntry {
    public Geary.Folder folder { get; private set; }

    protected AbstractFolderEntry(Geary.Folder folder) {
        this.folder = folder;
    }

    public abstract string get_sidebar_name();

    public abstract string? get_sidebar_tooltip();

    public abstract string? get_sidebar_icon();

    public abstract int get_count();

    public virtual string to_string() {
        return "AbstractFolderEntry: " + get_sidebar_name();
    }
}


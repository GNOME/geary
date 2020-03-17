/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * An object representing a folder for use by plugins.
 *
 * Instances of these may be obtained from {@link FolderStore}.
 */
public interface Plugin.Folder : Geary.BaseObject {


    /**
     * Returns a unique identifier for this account and folder.
     *
     * The value returned is persistent across application restarts.
     */
    public abstract string persistent_id { get; }

    /** Returns the human-readable name of this folder. */
    public abstract string display_name { get; }

    /** Returns the type of this folder. */
    public abstract Geary.SpecialFolderType folder_type { get; }

    /** Returns the account the folder belongs to, if any. */
    public abstract Account? account { get; }

    /**
     * Returns a variant identifying this account and folder.
     *
     * This value is suitable to be used as the `show-folder`
     * application action parameter.
     */
    public abstract GLib.Variant to_variant();

}

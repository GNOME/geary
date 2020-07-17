/*
 * Copyright © 2020 Michael Gratton <mike@vee.net>
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later). See the COPYING file in this distribution.
 */

/**
 * Provides plugins with access to folders.
 *
 * Plugins that implement the {@link FolderExtension} interface may
 * obtain instances of this object by calling {@link
 * FolderContext.get_folder_store} on their {@link
 * FolderExtension.folders} property.
 */
public interface Plugin.FolderStore : Geary.BaseObject {


    /**
     * The type of variant folder identifiers.
     *
     * @see Folder.to_variant
     * @see get_folder_for_variant
     */
    public abstract GLib.VariantType folder_variant_type { get; }

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

    /** Returns the set of folders that contains the given email. */
    public abstract async Gee.Collection<Folder> list_containing_folders(
        EmailIdentifier target,
        GLib.Cancellable? cancellable
    ) throws GLib.Error;

    /**
     * Creates a folder in the root of an account's personal name space.
     */
    public abstract async Folder create_personal_folder(
        Account target,
        string name,
        GLib.Cancellable? cancellable
    ) throws GLib.Error;

    /**
     * Returns the folder specified by the given variant, if any.
     *
     * @see Folder.to_variant
     * @see folder_variant_type
     */
    public abstract Folder? get_folder_for_variant(GLib.Variant id);


}

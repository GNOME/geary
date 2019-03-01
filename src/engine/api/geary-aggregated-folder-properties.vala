/* Copyright 2016 Software Freedom Conservancy Inc.
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution.
 */

/**
 * Aggregates multiple FolderProperties into one.  This way a Geary.Folder can
 * present one stable FolderProperties object that the client can register
 * change listeners on, etc. despite most Geary.Folders having both a local
 * and remote version of FolderProperties.
 *
 * The class relies on GObject bindings and the fact that FolderProperties
 * contains only propertiess.
 */
private class Geary.AggregatedFolderProperties : Geary.FolderProperties {
    // Map of child FolderProperties to their bindings.
    private Gee.Map<FolderProperties, Gee.List<Binding>> child_bindings
        = new Gee.HashMap<FolderProperties, Gee.List<Binding>>();

    /**
     * Creates an aggregate FolderProperties.
     */
    public AggregatedFolderProperties(bool is_local_only, bool is_virtual) {
        // Set defaults.
        base(0, 0, Trillian.UNKNOWN, Trillian.UNKNOWN, Trillian.UNKNOWN, is_local_only, is_virtual, false);
    }

    /**
     * Adds a child FolderProperties.  The child's property values will overwrite
     * this class's property values.
     */
    public void add(FolderProperties child) {
        // Create a binding for all properties.
        Gee.List<Binding>? bindings = Geary.ObjectUtils.mirror_properties(child, this);
        assert(bindings != null);
        child_bindings.set(child, bindings);
    }

    /**
     * Removes a child FolderProperties.
     */
    public bool remove(FolderProperties child) {
        Gee.List<Binding> bindings;
        if (child_bindings.unset(child, out bindings)) {
            Geary.ObjectUtils.unmirror_properties(bindings);

            return true;
        }

        return false;
    }
}

